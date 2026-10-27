// Bolitas — mira dentro de las apps de Claude y ChatGPT con la Accesibilidad de macOS
// (lo mismo que usa VoiceOver) para saber qué chats están trabajando o esperándote.
// No lee el contenido de los mensajes: solo botones, enlaces del lateral y títulos.

import AppKit
import ApplicationServices

struct AXNode {
    var role = "", subrole = "", title = "", desc = "", value = "", help = "", url = "", ident = ""
    var selected = false
    var parent = -1
    var depth = 0
    var el: AXUIElement?

    /// Lo que la app "dice" de este elemento (sin el texto de los mensajes).
    var labels: String { [title, desc, help].filter { !$0.isEmpty }.joined(separator: " ") }
    var allText: String { [title, desc, value, help].filter { !$0.isEmpty }.joined(separator: " · ") }
}

struct Obs {
    var key: String
    var title: String
    var provider: Provider
    var chatID: String?
    var working = false
    var needs = false
    var current = false
}

enum Rx {
    static func m(_ s: String, _ p: String) -> Bool {
        !s.isEmpty && s.range(of: p, options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func first(_ s: String, _ p: String) -> String? {
        guard let r = s.range(of: p, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(s[r])
    }
    // Botón de parar la respuesta = está trabajando.
    static let stop = "^(stop|detener|parar|interrumpir|aturar)( (response|generating|streaming|responding|la respuesta|respuesta|generación))?$"
    // Botones de permiso = te necesita.
    static let allow = "^(allow|permitir|aprobar|approve|always allow|permitir siempre|allow once|permitir una vez|allow for this chat|permitir en este chat|deny|denegar|rechazar)\\b"
    // Indicadores junto a un chat del lateral.
    static let busy = "(thinking|pensando|running|en curso|ejecutando|working|trabajando|generating|generando|respondiendo|responding|loading|cargando|in progress|en progreso|streaming)"
    static let wait = "(needs (your )?(input|approval|attention|response)|waiting (for|on) (you|input|approval)|necesita (tu|que)|esperando (tu|aprobaci)|requires (your )?approval|awaiting)"
    static let uuid = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
}

enum AX {
    static let attrs: [String] = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
                                  kAXValueAttribute, kAXHelpAttribute, kAXChildrenAttribute, "AXURL",
                                  kAXSelectedAttribute, kAXIdentifierAttribute]

    static var trusted: Bool { AXIsProcessTrusted() }
    static func askPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func str(_ v: AnyObject?) -> String {
        guard let v = v else { return "" }
        let t = CFGetTypeID(v)
        if t == CFStringGetTypeID() { return String((v as! String).prefix(200)) }
        if t == CFURLGetTypeID() { return (v as! NSURL).absoluteString ?? "" }
        if t == CFNumberGetTypeID() { return "\(v)" }
        return ""
    }

    static func bool(_ v: AnyObject?) -> Bool {
        guard let v = v, CFGetTypeID(v) == CFBooleanGetTypeID() else { return false }
        return CFBooleanGetValue((v as! CFBoolean))
    }

    static func children(_ v: AnyObject?) -> [AXUIElement] {
        guard let v = v, CFGetTypeID(v) == CFArrayGetTypeID() else { return [] }
        return (v as? [AXUIElement]) ?? []
    }

    /// Foto plana del árbol de accesibilidad de una app (todas sus ventanas).
    static func snapshot(pid: pid_t, budget: Int = 9000) -> [AXNode] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.8)
        // Las apps hechas con Electron (Claude) solo enseñan su contenido si se lo pides así.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var winsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &winsRef) == .success else { return [] }
        let wins = children(winsRef as AnyObject?)
        var nodes: [AXNode] = []
        var stack: [(AXUIElement, Int, Int)] = wins.reversed().map { ($0, -1, 0) }
        while nodes.count < budget, let item = stack.popLast() {
            let (el, parent, depth) = item
            var valsRef: CFArray?
            let err = AXUIElementCopyMultipleAttributeValues(el, attrs as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &valsRef)
            guard err == .success, let vals = valsRef as? [AnyObject], vals.count == attrs.count else { continue }
            var n = AXNode()
            n.role = str(vals[0]); n.subrole = str(vals[1]); n.title = str(vals[2]); n.desc = str(vals[3])
            n.value = str(vals[4]); n.help = str(vals[5]); n.url = str(vals[7]); n.selected = bool(vals[8])
            n.ident = str(vals[9]); n.parent = parent; n.depth = depth; n.el = el
            let me = nodes.count
            nodes.append(n)
            if depth < 90 {
                for c in children(vals[6]).reversed() { stack.append((c, me, depth + 1)) }
            }
        }
        return nodes
    }

    static func press(_ el: AXUIElement) -> Bool {
        AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
    }
}

final class Watcher {
    static let shared = Watcher()
    private let queue = DispatchQueue(label: "bolitas.watch", qos: .utility)
    private var busy = false
    /// Últimas fotos, para poder pulsar un chat del lateral y para el diagnóstico.
    private(set) var lastNodes: [Provider: [AXNode]] = [:]

    static func runningApp(_ p: Provider) -> NSRunningApplication? {
        for id in p.bundleIDs {
            if let a = NSRunningApplication.runningApplications(withBundleIdentifier: id).first { return a }
        }
        return nil
    }

    func tick() {
        guard !busy, AX.trusted else { return }
        busy = true
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        queue.async {
            var obs: [Obs] = []
            var frontmost = Set<Provider>(), running = Set<Provider>()
            var snaps: [Provider: [AXNode]] = [:]
            for p in [Provider.claude, .chatgpt] {
                guard let app = Watcher.runningApp(p) else { continue }
                running.insert(p)
                if p.bundleIDs.contains(front) { frontmost.insert(p) }
                let nodes = AX.snapshot(pid: app.processIdentifier)
                snaps[p] = nodes
                obs += (p == .claude) ? Watcher.claude(nodes) : Watcher.chatgpt(nodes)
            }
            DispatchQueue.main.async {
                self.lastNodes = snaps
                Store.shared.apply(obs, frontmost: frontmost, running: running)
                self.busy = false
            }
        }
    }

    // MARK: - Lectura de cada app

    private static func kids(_ n: [AXNode]) -> [[Int]] {
        var k = [[Int]](repeating: [], count: n.count)
        for (i, x) in n.enumerated() where x.parent >= 0 { k[x.parent].append(i) }
        return k
    }
    private static func subtree(_ i: Int, _ k: [[Int]]) -> [Int] {
        var out: [Int] = [], st = [i]
        while let j = st.popLast() { out.append(j); st += k[j] }
        return out
    }
    private static func firstText(_ idx: [Int], _ n: [AXNode]) -> String {
        for j in idx {
            let y = n[j]
            if y.role == "AXStaticText" {
                let t = y.value.isEmpty ? y.title : y.value
                if !t.trimmingCharacters(in: .whitespaces).isEmpty { return t }
            }
        }
        return ""
    }
    /// ¿Hay algún indicador de actividad (no texto de chat) en estos elementos?
    private static func activity(_ idx: [Int], _ n: [AXNode]) -> (busy: Bool, wait: Bool) {
        var b = false, w = false
        for j in idx {
            let y = n[j]
            if y.role == "AXProgressIndicator" || y.role == "AXBusyIndicator" { b = true }
            if y.role == "AXStaticText" { continue }   // el título del chat no cuenta
            let l = [y.desc, y.help, y.role == "AXImage" ? y.title : ""].joined(separator: " ")
            if Rx.m(l, Rx.busy) { b = true }
            if Rx.m(l, Rx.wait) { w = true }
        }
        return (b, w)
    }
    private static func globalButtons(_ n: [AXNode]) -> (stop: Bool, allow: Bool) {
        var s = false, a = false
        for y in n where y.role == "AXButton" {
            let l = y.labels.trimmingCharacters(in: .whitespaces)
            if Rx.m(l, Rx.stop) { s = true }
            if Rx.m(l, Rx.allow) { a = true }
        }
        return (s, a)
    }
    static func cleanTitle(_ t: String) -> String {
        var s = t
        for suf in [" - Claude", " | Claude", " – Claude", " - ChatGPT", " | ChatGPT"] where s.hasSuffix(suf) {
            s = String(s.dropLast(suf.count))
        }
        return (s == "Claude" || s == "ChatGPT") ? "" : s
    }

    static func claudeID(_ url: String) -> String? {
        guard url.contains("/chat/") else { return nil }
        return Rx.first(url, Rx.uuid)?.lowercased()
    }

    static func claude(_ n: [AXNode]) -> [Obs] {
        let k = kids(n)
        var out: [String: Obs] = [:]
        var currentID: String?, currentTitle = ""
        for x in n where x.role == "AXWebArea" {
            if let id = claudeID(x.url) { currentID = id; currentTitle = cleanTitle(x.title) }
        }
        for (i, x) in n.enumerated() where x.role == "AXLink" {
            guard let id = claudeID(x.url), id != "" else { continue }
            let sub = subtree(i, k)
            var title = x.title.isEmpty ? firstText(sub, n) : x.title
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let act = activity(Array(sub.dropFirst()), n)
            let key = "claude:" + id
            var o = out[key] ?? Obs(key: key, title: title, provider: .claude, chatID: id)
            if o.title.isEmpty { o.title = title }
            o.working = o.working || act.busy
            o.needs = o.needs || act.wait
            out[key] = o
        }
        if let id = currentID {
            let g = globalButtons(n)
            let key = "claude:" + id
            var o = out[key] ?? Obs(key: key, title: currentTitle, provider: .claude, chatID: id)
            if !currentTitle.isEmpty { o.title = currentTitle }
            o.current = true
            o.working = o.working || g.stop
            o.needs = o.needs || g.allow
            out[key] = o
        }
        return Array(out.values)
    }

    static func chatgpt(_ n: [AXNode]) -> [Obs] {
        let k = kids(n)
        var out: [String: Obs] = [:]
        // Filas del lateral: el chat seleccionado es el que tienes abierto.
        var currentTitle = ""
        for (i, x) in n.enumerated() where ["AXRow", "AXCell", "AXButton", "AXRadioButton", "AXLink"].contains(x.role) {
            let sub = subtree(i, k)
            guard sub.count < 40 else { continue }            // una fila, no un panel entero
            var title = x.role == "AXButton" || x.role == "AXLink" ? x.title : ""
            if title.isEmpty { title = firstText(sub, n) }
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count < 120 else { continue }
            if x.selected && x.role != "AXButton" && currentTitle.isEmpty { currentTitle = title }
            guard x.role == "AXRow" || x.role == "AXCell" else { continue }
            let act = activity(Array(sub.dropFirst()), n)
            guard act.busy || act.wait else {
                let key = "chatgpt:" + title
                if out[key] == nil { out[key] = Obs(key: key, title: title, provider: .chatgpt, chatID: nil) }
                continue
            }
            let key = "chatgpt:" + title
            var o = out[key] ?? Obs(key: key, title: title, provider: .chatgpt, chatID: nil)
            o.working = o.working || act.busy
            o.needs = o.needs || act.wait
            out[key] = o
        }
        if currentTitle.isEmpty {
            for x in n where x.role == "AXWindow" && x.subrole == "AXStandardWindow" {
                let t = cleanTitle(x.title); if !t.isEmpty { currentTitle = t; break }
            }
        }
        if !currentTitle.isEmpty {
            let g = globalButtons(n)
            let key = "chatgpt:" + currentTitle
            var o = out[key] ?? Obs(key: key, title: currentTitle, provider: .chatgpt, chatID: nil)
            o.current = true
            o.working = o.working || g.stop
            o.needs = o.needs || g.allow
            out[key] = o
        }
        return Array(out.values)
    }

    // MARK: - Abrir un chat

    /// Intenta pulsar el chat en el lateral de la app ya abierta.
    func pressInSidebar(_ c: Chat) -> Bool {
        guard let nodes = lastNodes[c.provider] else { return false }
        for x in nodes {
            guard let el = x.el else { continue }
            if c.provider == .claude, let id = c.chatID, x.role == "AXLink", Watcher.claudeID(x.url) == id {
                if AX.press(el) { return true }
            }
            if c.provider == .chatgpt, ["AXRow", "AXCell", "AXButton", "AXLink"].contains(x.role) {
                let t = x.allText
                if !c.title.isEmpty && (x.title == c.title || t.hasPrefix(c.title)) {
                    if AX.press(el) { return true }
                    // Las filas a veces no se pulsan: se seleccionan.
                    if AXUIElementSetAttributeValue(el, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success { return true }
                }
            }
        }
        return false
    }

    func open(_ c: Chat) {
        if c.provider == .claude, let id = c.chatID, let u = URL(string: "claude://claude.ai/chat/\(id)") {
            NSWorkspace.shared.open(u)
            return
        }
        if let app = Watcher.runningApp(c.provider) {
            app.activate(options: [.activateAllWindows])
            queue.async {
                let ok = self.pressInSidebar(c)
                if !ok, c.provider == .chatgpt, let id = c.chatID, let u = URL(string: "https://chatgpt.com/c/\(id)") {
                    DispatchQueue.main.async { NSWorkspace.shared.open(u) }
                }
            }
            return
        }
        // La app no está abierta: la abrimos.
        if let id = c.provider.bundleIDs.first,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        } else if c.provider == .chatgpt, let id = c.chatID, let u = URL(string: "https://chatgpt.com/c/\(id)") {
            NSWorkspace.shared.open(u)
        }
    }

    // MARK: - Diagnóstico

    /// Vuelca lo que se ve de cada app a ~/Downloads/Bolitas-diagnostico.txt (para afinar la detección).
    func writeDiagnostics() {
        guard AX.trusted else { return }
        queue.async {
            var text = "Bolitas — diagnóstico \(Date())\n"
            for p in [Provider.claude, .chatgpt] {
                guard let app = Watcher.runningApp(p) else { text += "\n=== \(p.name): no está abierta\n"; continue }
                let nodes = AX.snapshot(pid: app.processIdentifier, budget: 20000)
                let obs = p == .claude ? Watcher.claude(nodes) : Watcher.chatgpt(nodes)
                text += "\n=== \(p.name) (\(app.bundleIdentifier ?? "")) — \(nodes.count) elementos\n"
                for o in obs where o.current || o.working || o.needs {
                    text += "  OBS \(o.key) «\(o.title)» actual=\(o.current) trabajando=\(o.working) teNecesita=\(o.needs)\n"
                }
                for x in nodes {
                    let pad = String(repeating: " ", count: min(x.depth, 60))
                    var line = "\(pad)\(x.role)"
                    if !x.subrole.isEmpty { line += "/\(x.subrole)" }
                    // Del texto de los mensajes solo guardamos el principio.
                    let val = x.role == "AXStaticText" ? String(x.value.prefix(40)) : x.value
                    for (k, v) in [("t", x.title), ("d", x.desc), ("v", val), ("h", x.help), ("url", x.url), ("id", x.ident)] where !v.isEmpty {
                        line += " \(k)=\"\(v.replacingOccurrences(of: "\n", with: " "))\""
                    }
                    if x.selected { line += " [sel]" }
                    text += line + "\n"
                }
            }
            let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
            try? text.write(to: dir.appendingPathComponent("Bolitas-diagnostico.txt"), atomically: true, encoding: .utf8)
        }
    }

    /// Si existe ~/Downloads/Bolitas-pedir-diagnostico, escribe el diagnóstico y borra la petición.
    func checkDiagnosticRequest() {
        let f = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/Bolitas-pedir-diagnostico")
        if FileManager.default.fileExists(atPath: f.path) {
            try? FileManager.default.removeItem(at: f)
            writeDiagnostics()
        }
    }
}
