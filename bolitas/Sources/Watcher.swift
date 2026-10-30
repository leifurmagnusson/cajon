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
    var reply = false        // ha terminado o te ha preguntado algo: espera tu respuesta
    var current = false
    var fromSidebar = false  // el estado lo dice la propia app en su barra lateral
}

/// Una conversación de la barra lateral de una app (para el archivador de chats).
struct Recent { var title: String; var status: String; var provider: Provider }

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
    /// Último error al pedir las ventanas de cada app (para el diagnóstico).
    static var lastError: [pid_t: String] = [:]
    /// Apps a las que ya se les ha pedido que enseñen su accesibilidad (Electron tarda en montarla la primera vez).
    private static var primed = Set<pid_t>()

    static func snapshot(pid: pid_t, budget: Int = 2500) -> [AXNode] {
        let app = AXUIElementCreateApplication(pid)
        // Claude (Electron) en segundo plano contesta despacio: con 0,25 s fallaba a menudo y no veía nada.
        AXUIElementSetMessagingTimeout(app, 1.5)
        // Las apps hechas con Electron (Claude) solo enseñan su contenido si se lo pides así.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        if !primed.contains(pid) { primed.insert(pid); usleep(300_000) }
        var winsRef: CFTypeRef?
        var err = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &winsRef)
        var wins = err == .success ? children(winsRef as AnyObject?) : []
        if wins.isEmpty {
            // Plan B: la ventana principal o la que tiene el foco.
            for a in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
                var w: CFTypeRef?
                let e2 = AXUIElementCopyAttributeValue(app, a as CFString, &w)
                if e2 == .success, let w = w, CFGetTypeID(w) == AXUIElementGetTypeID() { wins = [w as! AXUIElement]; break }
                if err == .success { err = e2 }
            }
        }
        lastError[pid] = wins.isEmpty ? "sin ventanas (AXError \(err.rawValue))" : "ok (\(wins.count) ventanas)"
        guard !wins.isEmpty else { return [] }
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
    /// Conversaciones de la barra lateral de cada app (para el archivador).
    private(set) var recents: [Provider: [Recent]] = [:]

    static func runningApp(_ p: Provider) -> NSRunningApplication? {
        for id in p.bundleIDs {
            if let a = NSRunningApplication.runningApplications(withBundleIdentifier: id).first { return a }
        }
        return nil
    }

    private var lastScan = Date.distantPast
    /// Número del globito rojo de Claude en el Dock (se actualiza aunque Claude esté en segundo plano).
    private(set) var dockBadge: [Provider: String] = [:]
    private var lastBadge: [Provider: String] = [:]
    private var urgentUntil = Date.distantPast

    static func readDockBadges() -> [Provider: String] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [:] }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var out: [Provider: String] = [:]
        var lists: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &lists) == .success else { return [:] }
        for list in AX.children(lists as AnyObject?) {
            var items: CFTypeRef?
            AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &items)
            for it in AX.children(items as AnyObject?) {
                var tRef: CFTypeRef?, bRef: CFTypeRef?
                AXUIElementCopyAttributeValue(it, kAXTitleAttribute as CFString, &tRef)
                AXUIElementCopyAttributeValue(it, "AXStatusLabel" as CFString, &bRef)
                let title = AX.str(tRef as AnyObject?), badge = AX.str(bRef as AnyObject?)
                if title == "Claude" { out[.claude] = badge }
                if title == "ChatGPT" || title == "Codex" { out[.chatgpt] = badge }
            }
        }
        return out
    }

    func tick() {
        // Si Claude pone un aviso en el Dock, se mira enseguida y muy a menudo durante un rato.
        if AX.trusted {
            let b = Watcher.readDockBadges()
            if b != lastBadge { urgentUntil = Date().addingTimeInterval(30); lastScan = .distantPast }
            lastBadge = b; dockBadge = b
        }
        let every: TimeInterval = Date() < urgentUntil ? 1.0 : 2.5
        guard !busy, AX.trusted, Date().timeIntervalSince(lastScan) > every else { return }
        busy = true
        lastScan = Date()
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
            var rec: [Provider: [Recent]] = [:]
            if let cn = snaps[.claude] { rec[.claude] = Watcher.claudeSidebar(cn) }
            if let gn = snaps[.chatgpt] { rec[.chatgpt] = Watcher.chatgptRecents(gn) }
            DispatchQueue.main.async {
                self.lastNodes = snaps
                self.recents = rec
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

    /// Estados que Claude escribe en su barra lateral junto a cada conversación.
    static func claudeStatus(_ s: String) -> (working: Bool, needs: Bool, reply: Bool) {
        let l = s.lowercased()
        if Rx.m(l, "(esperando entrada|waiting for input|needs input|necesita (permiso|aprobaci)|needs (approval|permission)|awaiting (approval|input))") { return (false, true, false) }
        // «Esperando respuesta»: te ha hecho una pregunta → también te pide algo.
        if Rx.m(l, "(esperando respuesta|waiting for (a )?(response|reply|you)|needs (your )?(response|reply)|awaiting (response|reply))") { return (false, true, false) }
        if Rx.m(l, "(en ejecuci|ejecutando|running|working|trabajando|pensando|thinking|generando|generating)") { return (true, false, false) }
        if Rx.m(l, "esperando|waiting") { return (false, true, false) }
        return (false, false, false)
    }

    /// Lee la lista «Recientes» de la barra lateral de Claude: cada conversación es un botón
    /// y, si está haciendo algo, lleva dentro un indicador de estado («En ejecución», «Esperando respuesta»…).
    static func claudeSidebar(_ n: [AXNode]) -> [Recent] {
        let k = kids(n)
        // Títulos: cada conversación tiene un botón «Más opciones para <título>».
        var titles: [String] = []
        for x in n where x.role == "AXPopUpButton" {
            for pre in ["Más opciones para ", "More options for "] where x.desc.hasPrefix(pre) {
                let t = String(x.desc.dropFirst(pre.count))
                if !titles.contains(t) { titles.append(t) }
            }
        }
        var out: [Recent] = []
        for title in titles {
            var status = ""
            if let i = n.indices.first(where: { n[$0].role == "AXButton" && (n[$0].title == title || n[$0].title.hasPrefix(title + " ")) }) {
                for j in subtree(i, k) where n[j].subrole == "AXApplicationStatus" {
                    status = n[j].desc.isEmpty ? n[j].title : n[j].desc
                }
                if status.isEmpty, n[i].title.hasPrefix(title + " ") { status = String(n[i].title.dropFirst(title.count + 1)) }
            }
            out.append(Recent(title: title, status: status, provider: .claude))
        }
        return out
    }

    static func claude(_ n: [AXNode]) -> [Obs] {
        var out: [String: Obs] = [:]
        var currentID: String?, currentTitle = ""
        for x in n where x.role == "AXWebArea" {
            if let id = claudeID(x.url) { currentID = id; currentTitle = cleanTitle(x.title) }
        }
        let side = claudeSidebar(n)
        for r in side {
            let st = claudeStatus(r.status)
            let key = "claude:t:" + r.title
            var o = Obs(key: key, title: r.title, provider: .claude, chatID: nil)
            o.working = st.working; o.needs = st.needs; o.reply = st.reply
            o.fromSidebar = true
            out[key] = o
        }
        // El chat que tienes abierto: si está en la barra lateral, manda lo que dice la barra.
        if !currentTitle.isEmpty || currentID != nil {
            let key = "claude:t:" + currentTitle
            if var o = out[key] {
                o.current = true; o.chatID = currentID; out[key] = o
            } else if side.isEmpty, let id = currentID {
                // Sin barra lateral visible: lo poco que se ve en la ventana.
                let g = globalButtons(n)
                var o = Obs(key: key, title: currentTitle, provider: .claude, chatID: id)
                o.current = true; o.working = g.stop; o.needs = g.allow
                out[key] = o
            }
        }
        return Array(out.values)
    }

    /// Conversaciones de la barra lateral de ChatGPT: botones que llevan dentro «Acciones del chat».
    static func chatgptRecents(_ n: [AXNode]) -> [Recent] {
        let k = kids(n)
        var out: [Recent] = [], seen = Set<String>()
        for (i, x) in n.enumerated() where x.role == "AXButton" && !x.title.isEmpty {
            let sub = subtree(i, k)
            guard sub.count < 30, sub.contains(where: { n[$0].role == "AXPopUpButton" && Rx.m(n[$0].desc + n[$0].title, "^(acciones del chat|chat actions)") }) else { continue }
            guard !seen.contains(x.title), !x.title.hasPrefix("<") else { continue }
            var status = ""
            for j in sub where n[j].subrole == "AXApplicationStatus" || n[j].role == "AXProgressIndicator" || n[j].role == "AXBusyIndicator" {
                status = n[j].desc.isEmpty ? "En ejecución" : n[j].desc
            }
            seen.insert(x.title)
            out.append(Recent(title: x.title, status: status, provider: .chatgpt))
        }
        return out
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
            if c.provider == .claude, x.role == "AXButton", !c.title.isEmpty, x.title == c.title || x.title.hasPrefix(c.title + " ") {
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
        if let app = Watcher.runningApp(c.provider) {
            app.activate(options: [.activateAllWindows])
            queue.async {
                let ok = self.pressInSidebar(c)
                guard !ok else { return }
                DispatchQueue.main.async {
                    if c.provider == .claude, let id = c.chatID, let u = URL(string: "claude://claude.ai/chat/\(id)") { NSWorkspace.shared.open(u) }
                    if c.provider == .chatgpt, let id = c.chatID, let u = URL(string: "https://chatgpt.com/c/\(id)") { NSWorkspace.shared.open(u) }
                }
            }
            return
        }
        if c.provider == .claude, let id = c.chatID, let u = URL(string: "claude://claude.ai/chat/\(id)") {
            NSWorkspace.shared.open(u); return
        }
        // La app no está abierta: la abrimos.
        if let id = c.provider.bundleIDs.first,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        } else if c.provider == .chatgpt, let id = c.chatID, let u = URL(string: "https://chatgpt.com/c/\(id)") {
            NSWorkspace.shared.open(u)
        }
    }

    /// Abre una conversación por su título (desde el archivador).
    func openTitle(_ title: String, _ p: Provider) {
        let c = Chat(key: "x", provider: p, title: title, chatID: nil, pinned: false, mood: .idle,
                     since: Date(), lastConfirmed: Date(), evidence: .none, lastActive: Date())
        open(c)
    }

    /// Conversación nueva en Claude o ChatGPT; con voz, además pulsa el micrófono de la app.
    func newChat(_ p: Provider, voice: Bool) {
        if p == .claude {
            if let u = URL(string: "claude://claude.ai/new") { NSWorkspace.shared.open(u) }
        } else if let app = Watcher.runningApp(p) {
            app.activate(options: [.activateAllWindows])
            queue.async { _ = self.pressButton(p, "^(nuevo chat|new chat)$") }
        } else if let id = p.bundleIDs.first(where: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }),
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        }
        guard voice else { return }
        // Le damos un momento a que se abra el chat nuevo y buscamos el botón del micro.
        for delay in [1.2, 2.2, 3.5] {
            queue.asyncAfter(deadline: .now() + delay) {
                if self.voicePressed { return }
                if self.pressButton(p, "(dictad|dictar|dictation|micr[oó]fono|microphone|mensaje de voz|voice|modo de voz|hablar)") { self.voicePressed = true }
            }
        }
        voicePressed = false
    }
    private var voicePressed = false

    /// Pulsa el primer botón de la app cuya etiqueta encaje con el patrón (con una foto nueva del momento).
    @discardableResult
    func pressButton(_ p: Provider, _ pattern: String) -> Bool {
        guard AX.trusted, let app = Watcher.runningApp(p) else { return false }
        let nodes = AX.snapshot(pid: app.processIdentifier, budget: 4000)
        for x in nodes where x.role == "AXButton" || x.role == "AXCheckBox" {
            if Rx.m(x.labels.trimmingCharacters(in: .whitespaces), pattern), let el = x.el, AX.press(el) { return true }
        }
        return false
    }

    // MARK: - Diagnóstico

    /// Vuelca lo que se ve de cada app a ~/Downloads/Bolitas-diagnostico.txt (para afinar la detección).
    func writeDiagnostics() {
        guard AX.trusted else { return }
        queue.async {
            var text = "Bolitas — diagnóstico \(Date())\n"
            let locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
            text += "permiso de accesibilidad=\(AX.trusted) · pantalla bloqueada=\(locked) · versión \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")\n"
            for p in [Provider.claude, .chatgpt] {
                guard let app = Watcher.runningApp(p) else { text += "\n=== \(p.name): no está abierta\n"; continue }
                let nodes = AX.snapshot(pid: app.processIdentifier, budget: 6000)
                let obs = p == .claude ? Watcher.claude(nodes) : Watcher.chatgpt(nodes)
                text += "\n=== \(p.name) (\(app.bundleIdentifier ?? "")) — \(nodes.count) elementos — \(AX.lastError[app.processIdentifier] ?? "?") — oculta=\(app.isHidden)\n"
                let rec = p == .claude ? Watcher.claudeSidebar(nodes) : Watcher.chatgptRecents(nodes)
                text += "  RECIENTES (\(rec.count)): " + rec.prefix(12).map { "«\($0.title)» \($0.status)" }.joined(separator: " · ") + "\n"
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
            let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/.bolitas", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? text.write(to: dir.appendingPathComponent("diagnostico.txt"), atomically: true, encoding: .utf8)
        }
    }

    /// Si existe ~/Downloads/Bolitas-pedir-diagnostico, escribe el diagnóstico y borra la petición.
    func checkDiagnosticRequest() {
        let f = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/.bolitas/pedir-diagnostico")
        if FileManager.default.fileExists(atPath: f.path) {
            try? FileManager.default.removeItem(at: f)
            writeDiagnostics()
        }
    }
}
