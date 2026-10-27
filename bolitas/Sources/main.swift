// Bolitas — tus chats de Claude y ChatGPT como bolitas flotando encima de todo.
// Verde: trabajando (con cronómetro). Amarillo: te necesita. Gris: parada.
// Se oculta y se enseña desde la bolita de la barra de menús.

import AppKit
import ServiceManagement

final class BubblePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: BubblePanel!
    private var view: StageView!
    private var statusItem: NSStatusItem!
    private var anim: Timer?
    private var lastStatusKey = ""
    private let start = Date()
    private let smoke = SmokeOverlay()
    private var lastFrameT: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = BubblePanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu(); menu.delegate = self
        statusItem.menu = menu

        Store.shared.onChange = { [weak self] in self?.modelChanged() }
        Store.shared.onNeedsYou = { _ in
            if Prefs.sound { NSSound(named: NSSound.Name("Pop"))?.play() }
        }
        Usage.shared.onChange = { [weak self] in self?.pushUsage() }
        Usage.shared.start()

        // El aviso de permiso de macOS solo una vez; después, se pide desde la propia app.
        if !AX.trusted && !UserDefaults.standard.bool(forKey: "askedAX") {
            UserDefaults.standard.set(true, forKey: "askedAX")
            AX.askPermission()
        }
        buildStage()
        updateVisibility()
        refreshStatus()

        let watch = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let need = !AX.trusted
            if need != self.view.needsPermission { self.view.needsPermission = need; self.view.needsDisplay = true }
            Watcher.shared.tick()
            Watcher.shared.checkDiagnosticRequest()
            self.refreshStatus()
        }
        RunLoop.main.add(watch, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { Updater.check() }
        let up = Timer(timeInterval: 3 * 3600, repeats: true) { _ in Updater.check() }
        RunLoop.main.add(up, forMode: .common)
    }

    // MARK: Escenario (según el estilo)

    private func stageClass(_ th: Theme) -> StageView.Type {
        switch th {
        case .bolitas: return BubblesView.self
        case .monos: return MonosView.self
        case .enanitos: return ElvesView.self
        }
    }

    private func buildStage() {
        let th = Prefs.theme
        let cls = stageClass(th)
        let size = cls.size(for: Store.shared.chats.count)
        let v = cls.init(frame: NSRect(origin: .zero, size: size))
        v.onClick = { [weak self] c in self?.openChat(c) }
        v.onPlaceholderClick = { [weak self] in self?.placeholderClicked() }
        v.onMoved = { o in Prefs.setOrigin(o, for: Prefs.theme) }
        v.onDrop = { [weak self] s in self?.ingest(s) ?? false }
        v.menuFor = { [weak self] c in self?.chatMenu(c) }
        if let m = v as? MonosView { m.onDoorClick = { [weak self] in self?.usageClicked() } }
        if let e = v as? ElvesView { e.onSignClick = { [weak self] in self?.usageClicked() } }
        v.needsPermission = !AX.trusted
        v.chats = Store.shared.chats
        view = v
        panel.contentView = v
        panel.setFrame(NSRect(origin: Prefs.origin(for: th) ?? defaultOrigin(for: size), size: size), display: true)
        place()
        pushUsage()
        smoke.hide()
    }

    private func pushUsage() {
        (view as? MonosView)?.usageLines = Usage.shared.lines
        (view as? ElvesView)?.usageLines = Usage.shared.lines
        view?.needsDisplay = true
    }

    private func usageClicked() {
        if Usage.shared.loggedIn { Usage.shared.refresh() } else { Usage.shared.showLogin() }
    }

    private func startAnimating() {
        guard anim == nil else { return }
        let a = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.frameTick() }
        RunLoop.main.add(a, forMode: .common)
        anim = a
    }
    private func stopAnimating() { anim?.invalidate(); anim = nil; smoke.hide() }

    private func frameTick() {
        let t = CGFloat(Date().timeIntervalSince(start))
        let dt = t - lastFrameT; lastFrameT = t
        view.t = t
        view.needsDisplay = true
        if Prefs.theme == .monos {
            var src: [NSPoint] = [], names: [String] = []
            let f = panel.frame
            for i in view.chats.indices {
                if let p = view.smokeSource(i) {
                    src.append(NSPoint(x: f.minX + p.x, y: f.maxY - p.y))
                    names.append(view.chats[i].shortTitle)
                }
            }
            smoke.step(t: t, dt: dt, sources: src, names: names, screen: panel.screen)
        }
    }

    private func updateVisibility() {
        if Prefs.hidden { panel.orderOut(nil); stopAnimating() }
        else { panel.orderFrontRegardless(); startAnimating() }
    }

    private func defaultOrigin(for size: NSSize) -> NSPoint {
        let s = NSScreen.main ?? NSScreen.screens.first!
        let v = s.visibleFrame
        switch Prefs.theme {
        case .bolitas: return NSPoint(x: v.midX - size.width / 2, y: v.maxY - size.height - 4)
        case .monos: return NSPoint(x: v.maxX - size.width - 6, y: v.minY + 2)
        case .enanitos: return NSPoint(x: v.minX + 6, y: v.minY + 2)
        }
    }

    /// Coloca el panel al cambiar de tamaño: las bolitas mantienen el centro de arriba,
    /// los monos la esquina de abajo a la derecha y los enanitos la de abajo a la izquierda.
    private func place() {
        let size = type(of: view).size(for: view.chats.count)
        let old = panel.frame
        var frame: NSRect
        switch Prefs.theme {
        case .bolitas: frame = NSRect(x: old.midX - size.width / 2, y: old.maxY - size.height, width: size.width, height: size.height)
        case .monos: frame = NSRect(x: old.maxX - size.width, y: old.minY, width: size.width, height: size.height)
        case .enanitos: frame = NSRect(x: old.minX, y: old.minY, width: size.width, height: size.height)
        }
        let onScreen = NSScreen.screens.contains { $0.frame.intersects(frame) }
        if !onScreen { frame.origin = defaultOrigin(for: size) }
        panel.setFrame(frame, display: true)
        view.frame = NSRect(origin: .zero, size: size)
    }

    private func modelChanged() {
        let before = view.chats.count
        view.chats = Store.shared.chats
        if view.chats.count != before { place(); Prefs.setOrigin(panel.frame.origin, for: Prefs.theme) }
        refreshStatus()
    }

    @objc private func chooseTheme(_ s: NSMenuItem) {
        guard let raw = s.representedObject as? String, let th = Theme(rawValue: raw) else { return }
        Prefs.theme = th
        buildStage()
        if Prefs.hidden { Prefs.hidden = false }
        updateVisibility()
    }

    // MARK: Abrir y añadir chats

    private func openChat(_ c: Chat) {
        Store.shared.markSeen(c.key)
        Watcher.shared.open(c)
    }

    private func placeholderClicked() {
        if !AX.trusted {
            if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(u)
            }
        } else {
            tell("Arrastra aquí un chat",
                 "Desde Claude o ChatGPT, arrastra el enlace de una conversación encima de las bolitas. O usa la bolita de la barra de menús → «Añadir el chat abierto». Las conversaciones que se pongan a trabajar aparecen solas.")
        }
    }

    /// Enlaces arrastrados encima: claude.ai/chat/… o chatgpt.com/c/…
    private func ingest(_ strings: [String]) -> Bool {
        var added = false
        for s in strings {
            if s.contains("claude.ai"), let id = Watcher.claudeID(s) {
                Store.shared.add(provider: .claude, title: "", chatID: id, key: "claude:" + id, pinned: true)
                added = true
            } else if s.contains("chatgpt.com/c/") || s.contains("chat.openai.com/c/"),
                      let r = s.range(of: "/c/") {
                let id = String(s[r.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "-" })
                guard !id.isEmpty else { continue }
                Store.shared.add(provider: .chatgpt, title: "ChatGPT", chatID: id, key: "chatgptid:" + id, pinned: true)
                added = true
            }
        }
        if !added {
            tell("Eso no es un chat", "Arrastra el enlace de una conversación de Claude (claude.ai/chat/…) o de ChatGPT (chatgpt.com/c/…).")
        }
        return added
    }

    @objc private func addCurrentClaude() { addCurrent(.claude) }
    @objc private func addCurrentChatGPT() { addCurrent(.chatgpt) }
    private func addCurrent(_ p: Provider) {
        guard AX.trusted else { placeholderClicked(); return }
        guard let nodes = Watcher.shared.lastNodes[p] else {
            tell("\(p.name) no está abierta", "Abre la conversación en \(p.name) y vuelve a probar."); return
        }
        let obs = p == .claude ? Watcher.claude(nodes) : Watcher.chatgpt(nodes)
        guard let o = obs.first(where: { $0.current }) else {
            tell("No encuentro el chat abierto", "Abre la conversación en \(p.name) y vuelve a probar."); return
        }
        Store.shared.add(provider: p, title: o.title, chatID: o.chatID, key: o.key, pinned: true)
        Watcher.shared.tick()
    }

    // MARK: Menús

    private func chatMenu(_ c: Chat) -> NSMenu {
        let m = NSMenu()
        let head = m.addItem(withTitle: c.title.isEmpty ? c.provider.name : c.title, action: nil, keyEquivalent: "")
        head.isEnabled = false
        m.addItem(.separator())
        let open = m.addItem(withTitle: "Abrir en \(c.provider.name)", action: #selector(menuOpen(_:)), keyEquivalent: "")
        open.representedObject = c.key; open.target = self
        if c.mood == .done || c.mood == .needsYou {
            let s = m.addItem(withTitle: "Ya lo he visto", action: #selector(menuSeen(_:)), keyEquivalent: "")
            s.representedObject = c.key; s.target = self
        }
        let pin = m.addItem(withTitle: c.pinned ? "Dejar de fijar" : "Fijar (que no se vaya sola)", action: #selector(menuPin(_:)), keyEquivalent: "")
        pin.representedObject = c.key; pin.target = self
        let rm = m.addItem(withTitle: "Quitar", action: #selector(menuRemove(_:)), keyEquivalent: "")
        rm.representedObject = c.key; rm.target = self
        return m
    }
    @objc private func menuOpen(_ s: NSMenuItem) {
        if let k = s.representedObject as? String, let i = Store.shared.index(k) { openChat(Store.shared.chats[i]) }
    }
    @objc private func menuSeen(_ s: NSMenuItem) {
        guard let k = s.representedObject as? String else { return }
        Store.shared.dismiss(k)
    }
    @objc private func menuPin(_ s: NSMenuItem) { if let k = s.representedObject as? String { Store.shared.togglePin(k) } }
    @objc private func menuRemove(_ s: NSMenuItem) { if let k = s.representedObject as? String { Store.shared.remove(k) } }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ sel: Selector?, on: Bool? = nil, key: String = "") {
            let it = menu.addItem(withTitle: title, action: sel, keyEquivalent: key)
            it.target = self
            if let on = on { it.state = on ? .on : .off }
            if sel == nil { it.isEnabled = false }
        }
        add(Prefs.hidden ? "Enseñar" : "Ocultar", #selector(toggleHidden), key: "b")
        let st = NSMenuItem(title: "Estilo", action: nil, keyEquivalent: "")
        let sm = NSMenu()
        for th in Theme.allCases {
            let it = sm.addItem(withTitle: th.title, action: #selector(chooseTheme(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = th.rawValue; it.state = th == Prefs.theme ? .on : .off
        }
        st.submenu = sm; menu.addItem(st)
        menu.addItem(.separator())
        if Usage.shared.loggedIn {
            for l in Usage.shared.lines { add(l, nil) }
            add("Actualizar uso de Claude", #selector(refreshUsage))
        } else {
            add("Ver mi uso de Claude…", #selector(loginUsage))
        }
        menu.addItem(.separator())
        let chats = Store.shared.chats
        if chats.isEmpty { add("Aún no hay chats", nil) }
        for c in chats {
            let dot: String
            switch c.mood { case .working: dot = "🟢"; case .needsYou, .done: dot = "🟡"; case .idle: dot = "⚪️" }
            var t = "\(dot)  \(c.title.isEmpty ? c.provider.name : c.title)"
            if c.mood == .working { t += "  · \(elapsed(c.since))" }
            let it = menu.addItem(withTitle: t, action: #selector(menuOpen(_:)), keyEquivalent: "")
            it.representedObject = c.key; it.target = self
        }
        menu.addItem(.separator())
        add("Añadir el chat abierto en Claude", #selector(addCurrentClaude))
        add("Añadir el chat abierto en ChatGPT", #selector(addCurrentChatGPT))
        add("Quitar las que están en gris", #selector(clearIdle))
        menu.addItem(.separator())
        if !AX.trusted { add("⚠️ Dar permiso de Accesibilidad…", #selector(permission)) }
        add("Sonido cuando te necesiten", #selector(toggleSound), on: Prefs.sound)
        add("Volver a su sitio", #selector(recenter))
        add("Abrir al iniciar sesión", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled)
        add("Guardar diagnóstico", #selector(diagnostics))
        add("Buscar actualizaciones", #selector(checkUpdates))
        menu.addItem(.separator())
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        add("Bolitas \(v)", nil)
        add("Salir de Bolitas", #selector(quit), key: "q")
    }

    @objc private func refreshUsage() { Usage.shared.refresh() }
    @objc private func loginUsage() { Usage.shared.showLogin() }
    @objc private func toggleHidden() { Prefs.hidden.toggle(); updateVisibility() }
    @objc private func clearIdle() { Store.shared.removeIdle() }
    @objc private func permission() { placeholderClicked() }
    @objc private func toggleSound() { Prefs.sound.toggle() }
    @objc private func recenter() {
        panel.setFrameOrigin(defaultOrigin(for: panel.frame.size))
        Prefs.setOrigin(panel.frame.origin, for: Prefs.theme)
        if Prefs.hidden { Prefs.hidden = false; updateVisibility() }
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { tell("No he podido cambiarlo", error.localizedDescription) }
    }
    @objc private func diagnostics() {
        Watcher.shared.writeDiagnostics()
        tell("Diagnóstico guardado", "Guardado para afinar la detección.")
    }
    @objc private func checkUpdates() { Updater.check(manual: true) }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Bolita de la barra de menús

    private func refreshStatus() {
        let chats = Store.shared.chats
        let yellow = chats.filter { $0.mood == .needsYou || $0.mood == .done }.count
        let green = chats.filter { $0.mood == .working }.count
        let mood: Mood = yellow > 0 ? .done : (green > 0 ? .working : .idle)
        let key = "\(mood.rawValue)-\(yellow)"
        guard key != lastStatusKey, let b = statusItem.button else { return }
        lastStatusKey = key
        b.image = AppDelegate.statusImage(mood)
        b.imagePosition = .imageLeft
        b.title = yellow > 0 ? " \(yellow)" : ""
        b.toolTip = "Bolitas"
    }

    static func statusImage(_ mood: Mood) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { r in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            let body = r.insetBy(dx: 2, dy: 2)
            cg.setFillColor(Palette.base(mood).cgColor); cg.fillEllipse(in: body)
            cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(1.6); cg.strokeEllipse(in: body)
            cg.setFillColor(Palette.outline.cgColor)
            if mood == .idle {
                cg.setLineWidth(1.2); cg.setLineCap(.round)
                cg.move(to: CGPoint(x: 5.6, y: 8.5)); cg.addLine(to: CGPoint(x: 7.6, y: 8.5))
                cg.move(to: CGPoint(x: 10.4, y: 8.5)); cg.addLine(to: CGPoint(x: 12.4, y: 8.5))
                cg.strokePath()
            } else {
                cg.fillEllipse(in: CGRect(x: 5.8, y: 6.6, width: 2, height: 2.8))
                cg.fillEllipse(in: CGRect(x: 10.2, y: 6.6, width: 2, height: 2.8))
                cg.setLineWidth(1.2); cg.setLineCap(.round)
                cg.move(to: CGPoint(x: 6.6, y: 11.2))
                cg.addQuadCurve(to: CGPoint(x: 11.4, y: 11.2), control: CGPoint(x: 9, y: 13.4))
                cg.strokePath()
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    private func tell(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
