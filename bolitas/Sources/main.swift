// Bolitas — tus chats de Claude y ChatGPT como bolitas flotando encima de todo.
// Verde: trabajando (con cronómetro). Amarillo: te necesita. Gris: parada.
// Se oculta y se enseña desde la bolita de la barra de menús.

import AppKit
import ServiceManagement

final class BubblePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// Se puede esconder por debajo del borde de la pantalla (como el Dock).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: BubblePanel!
    private var view: StageView!
    private var statusItem: NSStatusItem!
    private var anim: Timer?
    private var lastStatusKey = ""
    private let start = Date()
    private let smoke = SmokeOverlay()
    private let confetti = ConfettiOverlay()
    // Casa que se esconde como el Dock (solo en el club)
    private var houseHidden = false
    private var outsideSince: Date?
    private var dockAnimating = false
    private var autoHide: Bool {
        get { UserDefaults.standard.object(forKey: "house.autoHide") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "house.autoHide") }
    }
    private var docks: Bool { Prefs.theme == .billar }

    /// Dónde va la casa: pegada abajo a la derecha; escondida, solo asoma el tejado.
    private func dockFrame(hidden: Bool) -> NSRect {
        let s = panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let size = scaled(type(of: view).size(for: view.chats.count))
        let roof = GorilasView.roofH * GorilasView.drawScale * Prefs.sizeFactor(for: Prefs.theme) + 4
        let y = hidden ? s.frame.minY - (size.height - roof) : s.frame.minY
        return NSRect(x: s.frame.maxX - size.width, y: y, width: size.width, height: size.height)
    }
    private func setHouse(hidden: Bool, animated: Bool = true) {
        houseHidden = hidden
        let f = dockFrame(hidden: hidden)
        guard animated else { panel.setFrame(f, display: true); return }
        dockAnimating = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = hidden ? 0.45 : 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(f, display: true)
        }, completionHandler: { [weak self] in self?.dockAnimating = false })
    }
    /// Cada fotograma: si el ratón está encima, la casa sube; si lleva un rato fuera, baja.
    private func dockTick() {
        guard docks, !dockAnimating else { return }
        let m = NSEvent.mouseLocation
        let s = panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = panel.frame.intersection(s.frame)
        let over = visible.insetBy(dx: -2, dy: -2).contains(m)
        let busy = (NSEvent.pressedMouseButtons & 1) == 1 && over
        if over || busy { outsideSince = nil; if houseHidden { setHouse(hidden: false) }; return }
        guard autoHide else { if houseHidden { setHouse(hidden: false) }; return }
        if outsideSince == nil { outsideSince = Date() }
        if !houseHidden, let o = outsideSince, Date().timeIntervalSince(o) > 6 { setHouse(hidden: true) }
    }
    private var lastFrameT: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SelfInstall.moveIfNeeded() { NSApp.terminate(nil); return }
        // Cuenta a Hold It dónde está el club, para que ponga el techo justo encima (y sus cajas).
        let link = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tellHoldIt() }
        RunLoop.main.add(link, forMode: .common)
        // Una vez: los monos bajan al borde inferior de la pantalla (antes se quedaban encima del Dock).
        if !UserDefaults.standard.bool(forKey: "monosAbajoV1") {
            UserDefaults.standard.removeObject(forKey: "origin." + Theme.monos.rawValue)
            UserDefaults.standard.set(true, forKey: "monosAbajoV1")
        }
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
            self.checkDemoRequest()
            self.refreshStatus()
        }
        RunLoop.main.add(watch, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { Updater.check() }
        let up = Timer(timeInterval: 10 * 60, repeats: true) { _ in Updater.check() }
        RunLoop.main.add(up, forMode: .common)
    }

    // MARK: Escenario (según el estilo)

    private func stageClass(_ th: Theme) -> StageView.Type {
        switch th {
        case .billar: return GorilasView.self
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
        v.onMoved = { [weak self] o in
            guard let self = self else { return }
            if self.docks { self.setHouse(hidden: false) } else { Prefs.setOrigin(o, for: Prefs.theme) }   // la casa vuelve a su esquina
        }
        v.onDrop = { [weak self] s in self?.ingest(s) ?? false }
        v.menuFor = { [weak self] c in self?.chatMenu(c) }
        v.onMicrophone = { [weak self, weak v] at in
            guard let self = self, let v = v else { return }
            let m = NSMenu()
            let h = m.addItem(withTitle: "🎙  Hablar con…", action: nil, keyEquivalent: ""); h.isEnabled = false
            for p in [Provider.claude, .chatgpt] {
                let it = m.addItem(withTitle: p.name, action: #selector(self.cabVoice(_:)), keyEquivalent: "")
                it.target = self; it.representedObject = p.rawValue
            }
            m.popUp(positioning: nil, at: at, in: v)
        }
        v.onCabinet = { [weak self, weak v] p, at in
            guard let self = self, let v = v else { return }
            self.cabinetMenu(p).popUp(positioning: nil, at: at, in: v)
        }
        if let m = v as? MonosView { m.onDoorClick = { [weak self] in self?.usageClicked() } }
        if let g = v as? GorilasView { g.onDoorClick = { [weak self] in self?.usageClicked() } }
        if let e = v as? ElvesView { e.onSignClick = { [weak self] in self?.usageClicked() } }
        v.needsPermission = !AX.trusted
        v.chats = Store.shared.chats
        view = v
        panel.contentView = v
        let fs = scaled(size)
        panel.setFrame(NSRect(origin: Prefs.origin(for: th) ?? defaultOrigin(for: fs), size: fs), display: true)
        place()
        pushUsage()
        smoke.hide()
    }

    private func pushUsage() {
        (view as? MonosView)?.usageLines = Usage.shared.lines
        (view as? GorilasView)?.usageLines = Usage.shared.lines
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
        Frog.shared.step(t: t, dt: dt, mouth: (view as? GorilasView)?.frogMouthScreen())
        dockTick()
        if Int(t * 30) % 10 == 0 { ClipStore.shared.poll() }
        do {
            var src: [NSPoint] = [], names: [String] = []
            let f = panel.frame
            for i in view.chats.indices {
                if let p = view.smokeSource(i) {
                    let k = Prefs.sizeFactor(for: Prefs.theme)
                    src.append(NSPoint(x: f.minX + p.x * k, y: f.maxY - p.y * k))
                    names.append(view.chats[i].shortTitle)
                }
            }
            let g = view as? GorilasView
            smoke.step(t: t, dt: dt, sources: src, names: names, screen: panel.screen,
                       room: g?.roomScreenRect(), chimney: g?.chimneyScreen())
            confetti.step(chimney: g?.chimneyScreen(), active: view.chats.contains { $0.mood == .done }, screen: panel.screen)
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
        case .bolitas: return NSPoint(x: s.frame.midX - size.width / 2, y: s.frame.minY)
        case .monos, .billar: return NSPoint(x: s.frame.maxX - size.width - 4, y: s.frame.minY)   // abajo del todo, a la altura del Dock
        case .enanitos: return NSPoint(x: v.minX + 6, y: v.minY + 2)
        }
    }

    /// Coloca el panel al cambiar de tamaño: las bolitas mantienen el centro de arriba,
    /// los monos la esquina de abajo a la derecha y los enanitos la de abajo a la izquierda.
    /// Tamaño elegido para este estilo (pequeño / mediano / grande).
    private func scaled(_ s: NSSize) -> NSSize {
        let f = Prefs.sizeFactor(for: Prefs.theme)
        return NSSize(width: round(s.width * f), height: round(s.height * f))
    }

    private func place() {
        let base = type(of: view).size(for: view.chats.count)
        let size = scaled(base)
        let old = panel.frame
        var frame: NSRect
        switch Prefs.theme {
        case .bolitas: frame = NSRect(x: old.midX - size.width / 2, y: old.minY, width: size.width, height: size.height)
        case .monos, .billar: frame = NSRect(x: old.maxX - size.width, y: old.minY, width: size.width, height: size.height)
        case .enanitos: frame = NSRect(x: old.minX, y: old.minY, width: size.width, height: size.height)
        }
        let onScreen = NSScreen.screens.contains { $0.frame.intersects(frame) }
        if !onScreen { frame.origin = defaultOrigin(for: size) }
        if docks { frame = dockFrame(hidden: houseHidden) }
        panel.setFrame(frame, display: true)
        view.frame = NSRect(origin: .zero, size: size)
        view.setBoundsSize(base)   // dibuja a su tamaño de siempre y macOS lo escala
    }

    private func modelChanged() {
        let before = view.chats.count
        view.chats = Store.shared.chats
        if view.chats.count != before { place(); Prefs.setOrigin(panel.frame.origin, for: Prefs.theme) }
        refreshStatus()
    }

    /// Si existe ~/Applications/.bolitas/pedir-demo, dibuja una escena de prueba con monos en
    /// todos los estados y la guarda como demo.png (para revisar el diseño sin tocar la pantalla).
    private func checkDemoRequest() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/.bolitas")
        let req = dir.appendingPathComponent("pedir-demo")
        guard FileManager.default.fileExists(atPath: req.path) else { return }
        try? FileManager.default.removeItem(at: req)
        let now = Date()
        func chat(_ k: String, _ title: String, _ m: Mood, _ ago: Double) -> Chat {
            Chat(key: k, provider: .claude, title: title, chatID: nil, pinned: false, mood: m,
                 since: now.addingTimeInterval(-ago), lastConfirmed: now, evidence: .current, lastActive: now)
        }
        let demo = [chat("demo:a", "Nóminas octubre", .working, 95), chat("demo:b", "Carta de vinos", .needsYou, 40),
                    chat("demo:c", "Viaje Japón", .done, 300), chat("demo:d", "Planner", .idle, 900),
                    chat("demo:e", "Hold It", .working, 20)]
        for th in Theme.allCases {
            for (n, tt) in [(1, 10.0), (2, 10.4), (3, 1.0), (4, 2.0)] as [(Int, CGFloat)] {
                let cls = stageClass(th)
                let v = cls.init(frame: NSRect(origin: .zero, size: cls.size(for: demo.count)))
                v.t = tt
                v.chats = demo
                if n >= 3 { v.born["demo:e"] = 0 }
                (v as? MonosView)?.usageLines = ["Claude · 5 horas: 11%", "Claude · semana: 76%"]
                (v as? GorilasView)?.usageLines = ["Claude · 5 horas: 11%", "Claude · semana: 76%"]
                guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("demo-\(th.rawValue)-\(n).png"))
            }
        }
    }

    /// El archivador: conversación nueva (con o sin voz) y la lista de conversaciones de la app.
    private func cabinetMenu(_ p: Provider) -> NSMenu {
        let m = NSMenu()
        let head = m.addItem(withTitle: p == .claude ? "Claude" : "ChatGPT", action: nil, keyEquivalent: ""); head.isEnabled = false
        let n1 = m.addItem(withTitle: "✏️  Conversación nueva", action: #selector(cabNew(_:)), keyEquivalent: "")
        n1.target = self; n1.representedObject = p.rawValue
        let n2 = m.addItem(withTitle: "🎙  Conversación nueva hablando", action: #selector(cabVoice(_:)), keyEquivalent: "")
        n2.target = self; n2.representedObject = p.rawValue
        m.addItem(.separator())
        let rh = m.addItem(withTitle: "Recientes · elige una para traerla a la mesa", action: nil, keyEquivalent: ""); rh.isEnabled = false
        let rec = Watcher.shared.recents[p] ?? []
        if rec.isEmpty {
            let it = m.addItem(withTitle: "Abre \(p.name) con la barra lateral visible para ver aquí tus conversaciones", action: nil, keyEquivalent: "")
            it.isEnabled = false
        }
        for r in rec.prefix(30) {
            let st = Watcher.claudeStatus(r.status)
            let dot = st.working ? "🟢" : (st.needs || st.reply ? "🟡" : "⚪️")
            let it = m.addItem(withTitle: "\(dot)  \(r.title)", action: #selector(cabOpen(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = [p.rawValue, r.title]
            if !r.status.isEmpty { it.toolTip = r.status }
        }
        return m
    }
    @objc private func cabNew(_ s: NSMenuItem) { if let r = s.representedObject as? String, let p = Provider(rawValue: r) { Watcher.shared.newChat(p, voice: false) } }
    @objc private func cabVoice(_ s: NSMenuItem) { if let r = s.representedObject as? String, let p = Provider(rawValue: r) { Watcher.shared.newChat(p, voice: true) } }
    /// Elegir una conversación del archivador: entra un gorila nuevo para ella y se abre en su app.
    @objc private func cabOpen(_ s: NSMenuItem) {
        guard let a = s.representedObject as? [String], a.count == 2, let p = Provider(rawValue: a[0]) else { return }
        let key = (p == .claude ? "claude:t:" : "chatgpt:") + a[1]
        Store.shared.add(provider: p, title: a[1], chatID: nil, key: key, pinned: true)
        Watcher.shared.openTitle(a[1], p)
    }

    @objc private func chooseSize(_ s: NSMenuItem) {
        guard let f = s.representedObject as? CGFloat else { return }
        Prefs.setSizeFactor(f, for: Prefs.theme)
        place()
        Prefs.setOrigin(panel.frame.origin, for: Prefs.theme)
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
        let tm = NSMenuItem(title: "Tamaño", action: nil, keyEquivalent: "")
        let tsm = NSMenu()
        for (name, f) in [("Muy pequeño", 0.75), ("Pequeño", 0.9), ("Mediano", 1.05), ("Grande", 1.2), ("Muy grande", 1.35)] as [(String, CGFloat)] {
            let it = tsm.addItem(withTitle: name, action: #selector(chooseSize(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = f
            it.state = abs(Prefs.sizeFactor(for: Prefs.theme) - f) < 0.01 ? .on : .off
        }
        tm.submenu = tsm; menu.addItem(tm)
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
        // Portapapeles (como CopyClip): lo fijado arriba y lo último copiado debajo
        let cm = NSMenuItem(title: "Portapapeles", action: nil, keyEquivalent: "")
        let csm = NSMenu()
        let clipList = ClipStore.shared.ordered
        if clipList.isEmpty { let e = csm.addItem(withTitle: "Aún no has copiado nada", action: nil, keyEquivalent: ""); e.isEnabled = false }
        for it in clipList.prefix(25) {
            let ci = csm.addItem(withTitle: (it.pinned ? "📌 " : "") + it.preview, action: #selector(clipCopy(_:)), keyEquivalent: "")
            ci.target = self; ci.representedObject = it.id
        }
        if !clipList.isEmpty {
            csm.addItem(.separator())
            let cl = csm.addItem(withTitle: "Borrar los no fijados", action: #selector(clipClear), keyEquivalent: ""); cl.target = self
        }
        cm.submenu = csm; menu.addItem(cm)
        if Prefs.theme == .billar {
            add("Esconder la casa cuando no la uso (se ve el tejado)", #selector(toggleAutoHide), on: autoHide)
            add("Rana del tejado: atrapa lo que arrastras", #selector(toggleFrog), on: Frog.shared.enabled)
            if !ShelfStore.shared.items.isEmpty { add("Vaciar el tejado (\(ShelfStore.shared.items.count))", #selector(clearRoof)) }
        }
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
    @objc private func clipCopy(_ s: NSMenuItem) {
        if let id = s.representedObject as? String, let it = ClipStore.shared.items.first(where: { $0.id == id }) { ClipStore.shared.copy(it) }
    }
    @objc private func clipClear() { ClipStore.shared.clearUnpinned() }
    @objc private func toggleAutoHide() { autoHide.toggle(); if !autoHide { setHouse(hidden: false) } }
    @objc private func toggleFrog() { Frog.shared.enabled.toggle() }
    @objc private func clearRoof() { ShelfStore.shared.removeAll() }
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

    // MARK: Hold It (techo del club)
    private var lastLink = ""
    private var lastLinkAt = Date.distantPast
    private func tellHoldIt() {
        guard let panel = panel, let view = view else { return }
        let f = panel.frame
        let lamps = ((view as? GorilasView)?.lampXs() ?? []).map { String(format: "%.1f", f.minX + $0) }.joined(separator: ";")
        let visible = panel.isVisible && !Prefs.hidden
        let msg = String(format: "%.1f,%.1f,%.1f,%.1f|%d|%@|%@", f.minX, f.minY, f.width, f.height, visible ? 1 : 0, Prefs.theme.rawValue, lamps)
        guard msg != lastLink || Date().timeIntervalSince(lastLinkAt) > 2 else { return }
        lastLink = msg; lastLinkAt = Date()
        DistributedNotificationCenter.default().postNotificationName(Notification.Name("casa.magnusson.bolitas.club"),
                                                                     object: msg, userInfo: nil, deliverImmediately: true)
    }

}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
