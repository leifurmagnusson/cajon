// Hold It — una estantería flotante para arrastrar y soltar (inspirada en Yoink).
// App nativa de macOS 13+, un solo archivo, sin dependencias.

import AppKit
import ServiceManagement
import QuickLookThumbnailing

// MARK: - Preferencias

enum Prefs {
    private static let d = UserDefaults.standard
    static var alwaysVisible: Bool {
        get { d.bool(forKey: "alwaysVisible") }
        set { d.set(newValue, forKey: "alwaysVisible") }
    }
    static var removeAfterDrag: Bool {
        get { d.object(forKey: "removeAfterDrag") as? Bool ?? true }
        set { d.set(newValue, forKey: "removeAfterDrag") }
    }
    static var leftEdge: Bool {
        get { d.bool(forKey: "leftEdge") }
        set { d.set(newValue, forKey: "leftEdge") }
    }
}

// MARK: - Modelo

final class ShelfItem {
    let id = UUID()
    let isClip: Bool               // true = lo creó Hold It (texto, imagen, enlace pegado)
    private(set) var bookmark: Data?
    private var fallback: URL

    /// Siempre resuelve el marcador: si mueves el archivo en Finder, Hold It lo sigue.
    var url: URL {
        if let b = bookmark {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: b, options: [.withoutUI, .withoutMounting],
                                relativeTo: nil, bookmarkDataIsStale: &stale) {
                if stale { bookmark = try? u.bookmarkData() }
                fallback = u
                return u
            }
        }
        return fallback
    }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    init(url: URL, isClip: Bool) {
        self.fallback = url
        self.isClip = isClip
        self.bookmark = try? url.bookmarkData()
    }

    init?(bookmark b: Data, isClip: Bool) {
        var stale = false
        guard let u = try? URL(resolvingBookmarkData: b, options: [.withoutUI, .withoutMounting],
                               relativeTo: nil, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: u.path) else { return nil }
        self.fallback = u
        self.isClip = isClip
        self.bookmark = stale ? (try? u.bookmarkData()) : b
    }
}

final class Store {
    static let shared = Store()
    private(set) var items: [ShelfItem] = []
    var onChange: (() -> Void)?
    let clipsDir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HoldIt", isDirectory: true)
        clipsDir = base.appendingPathComponent("Recortes", isDirectory: true)
        try? FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true)
        load()
        cleanOrphanClips()
    }

    func add(_ urls: [URL], isClip: Bool = false) {
        var changed = false
        for u in urls where !items.contains(where: { $0.url.path == u.path }) {
            items.append(ShelfItem(url: u, isClip: isClip))
            changed = true
        }
        if changed { save(); onChange?() }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        save(); onChange?()
    }

    func removeAll() {
        items.removeAll()
        save(); onChange?()
    }

    /// Quita los elementos cuyo archivo ya no existe (borrado, vaciado de papelera…).
    func prune() {
        let before = items.count
        items.removeAll { !$0.exists }
        if items.count != before { save(); onChange?() }
    }

    private func save() {
        let arr: [[String: Any]] = items.compactMap { i in
            guard let b = i.bookmark else { return nil }
            return ["b": b, "c": i.isClip]
        }
        UserDefaults.standard.set(arr, forKey: "items")
    }

    private func load() {
        guard let arr = UserDefaults.standard.array(forKey: "items") as? [[String: Any]] else { return }
        items = arr.compactMap { d in
            guard let b = d["b"] as? Data else { return nil }
            return ShelfItem(bookmark: b, isClip: d["c"] as? Bool ?? false)
        }
    }

    /// Borra recortes que ya no están en el cajón (se hace al arrancar, nunca en caliente,
    /// para no pisar a una app que aún esté leyendo un archivo que acabas de soltarle).
    private func cleanOrphanClips() {
        let base = clipsDir.standardizedFileURL.path + "/"
        var keep = Set<String>()
        for i in items where i.isClip {
            let p = i.url.standardizedFileURL.path
            if p.hasPrefix(base) {
                keep.insert(String(p.dropFirst(base.count)).components(separatedBy: "/").first ?? "")
            }
        }
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: clipsDir.path)) ?? []
        for e in entries where !keep.contains(e) {
            try? FileManager.default.removeItem(at: clipsDir.appendingPathComponent(e))
        }
    }

    // MARK: Recortes (lo que no es un archivo se convierte en archivo)

    private func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: Date())
    }

    private func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "-")
         .replacingOccurrences(of: ":", with: "-")
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func uniqueURL(_ base: String, ext: String) -> URL {
        var u = clipsDir.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: u.path) {
            u = clipsDir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return u
    }

    func clip(text: String) -> URL? {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let name = sanitize(String(first.prefix(40)))
        let u = uniqueURL(name.isEmpty ? "Texto \(stamp())" : name, ext: "txt")
        do { try text.write(to: u, atomically: true, encoding: .utf8); return u } catch { return nil }
    }

    func clip(image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let u = uniqueURL("Imagen \(stamp())", ext: "png")
        do { try png.write(to: u); return u } catch { return nil }
    }

    func clip(webURL: URL) -> URL? {
        let name = sanitize(webURL.host ?? "Enlace")
        let u = uniqueURL(name.isEmpty ? "Enlace" : name, ext: "webloc")
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: ["URL": webURL.absoluteString], format: .xml, options: 0) else { return nil }
        do { try data.write(to: u); return u } catch { return nil }
    }
}

let promiseQueue: OperationQueue = {
    let q = OperationQueue()
    q.qualityOfService = .userInitiated
    return q
}()

/// Mete en el cajón lo que haya en un portapapeles (de arrastre o el general).
@discardableResult
func ingest(_ pb: NSPasteboard) -> Bool {
    let store = Store.shared

    // 1. Archivos de verdad (Finder, escritorio…): se guarda una referencia, no una copia.
    if let urls = pb.readObjects(forClasses: [NSURL.self],
                                 options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
        store.add(urls)
        return true
    }
    // 2. Archivos "prometidos" (adjuntos de Mail, Fotos, imágenes de Safari…).
    if let promises = pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil)
        as? [NSFilePromiseReceiver], !promises.isEmpty {
        let dest = store.clipsDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        for p in promises {
            p.receivePromisedFiles(atDestination: dest, options: [:], operationQueue: promiseQueue) { url, error in
                guard error == nil else { return }
                DispatchQueue.main.async { store.add([url], isClip: true) }
            }
        }
        return true
    }
    // 3. Imágenes sueltas.
    if let imgs = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
       let img = imgs.first, let u = store.clip(image: img) {
        store.add([u], isClip: true)
        return true
    }
    // 4. Enlaces web.
    if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
       let w = urls.first(where: { !$0.isFileURL }), let u = store.clip(webURL: w) {
        store.add([u], isClip: true)
        return true
    }
    // 5. Texto.
    if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       let u = store.clip(text: s) {
        store.add([u], isClip: true)
        return true
    }
    return false
}

// MARK: - Vistas

final class FlippedView: NSView { override var isFlipped: Bool { true } }

/// Capa decorativa que no intercepta clics ni arrastres.
final class PassthroughView: NSView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }

final class ItemView: NSView, NSDraggingSource {
    static let height: CGFloat = 84
    let item: ShelfItem
    private let icon = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private let closeBtn = NSButton()
    private var downEvent: NSEvent?
    private var hovering = false { didSet { updateLook() } }

    init(item: ShelfItem) {
        self.item = item
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.image = NSWorkspace.shared.icon(forFile: item.url.path)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = item.url.lastPathComponent
        label.font = .systemFont(ofSize: 10.5, weight: .medium)
        label.alignment = .center
        label.textColor = .labelColor
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.cell?.truncatesLastVisibleLine = true
        label.isSelectable = false

        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Quitar")
        closeBtn.isBordered = false
        closeBtn.contentTintColor = .secondaryLabelColor
        closeBtn.target = self
        closeBtn.action = #selector(removeMe)
        closeBtn.isHidden = true
        closeBtn.toolTip = "Quitar de Hold It"

        addSubview(icon); addSubview(label); addSubview(closeBtn)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: ItemView.height),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 46),
            icon.heightAnchor.constraint(equalToConstant: 46),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeBtn.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            closeBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            closeBtn.widthAnchor.constraint(equalToConstant: 16),
            closeBtn.heightAnchor.constraint(equalToConstant: 16),
        ])
        toolTip = item.url.path
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        loadThumbnail()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func loadThumbnail() {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let req = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 46, height: 46),
                                               scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let img = rep?.nsImage else { return }
            DispatchQueue.main.async { self?.icon.image = img }
        }
    }

    private func updateLook() {
        layer?.backgroundColor = hovering ? NSColor.labelColor.withAlphaComponent(0.10).cgColor : NSColor.clear.cgColor
        closeBtn.isHidden = !hovering
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        downEvent = event
        if event.clickCount == 2 { NSWorkspace.shared.open(item.url) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = downEvent else { return }
        let a = d.locationInWindow, b = event.locationInWindow
        guard hypot(a.x - b.x, a.y - b.y) > 3 else { return }
        downEvent = nil
        let di = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        di.setDraggingFrame(icon.frame, contents: icon.image)
        let s = beginDraggingSession(with: [di], event: event, source: self)
        s.animatesToStartingPositionsOnCancelOrFail = true
    }

    // Siempre COPIA: soltar en Finder nunca te mueve (ni te pierde) el original.
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard operation != [], Prefs.removeAfterDrag else { return }
        let it = item
        DispatchQueue.main.async { Store.shared.remove(it) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: "Abrir", action: #selector(openIt), keyEquivalent: "").target = self
        m.addItem(withTitle: "Mostrar en Finder", action: #selector(reveal), keyEquivalent: "").target = self
        m.addItem(withTitle: "Copiar", action: #selector(copyIt), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Quitar de Hold It", action: #selector(removeMe), keyEquivalent: "").target = self
        return m
    }

    @objc private func openIt() { NSWorkspace.shared.open(item.url) }
    @objc private func reveal() { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
    @objc private func copyIt() {
        let pb = NSPasteboard.general
        pb.clearContents()
        if item.isClip, item.url.pathExtension == "txt",
           let s = try? String(contentsOf: item.url, encoding: .utf8) {
            pb.setString(s, forType: .string)       // un texto se copia como texto
        } else {
            pb.writeObjects([item.url as NSURL])    // un archivo se copia como archivo (⌘V en Finder)
        }
    }
    @objc private func removeMe() { Store.shared.remove(item) }
}

/// Cabecera: muestra el recuento y, si la arrastras, te llevas todo el cajón de golpe.
final class HeaderView: NSView, NSDraggingSource {
    private let label = NSTextField(labelWithString: "")
    private let grip = NSImageView()
    private var downEvent: NSEvent?

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        grip.translatesAutoresizingMaskIntoConstraints = false
        grip.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: nil)
        grip.contentTintColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        addSubview(grip); addSubview(label)
        NSLayoutConstraint.activate([
            grip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            grip.centerYAnchor.constraint(equalTo: centerYAnchor),
            grip.widthAnchor.constraint(equalToConstant: 15),
            grip.heightAnchor.constraint(equalToConstant: 15),
            label.leadingAnchor.constraint(equalTo: grip.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(count: Int) {
        label.stringValue = count == 0 ? "Hold It" : (count == 1 ? "1 elemento" : "\(count) elementos")
        toolTip = count > 1 ? "Arrastra aquí para llevarte todo" : nil
    }

    override func mouseDown(with event: NSEvent) { downEvent = event }

    override func mouseDragged(with event: NSEvent) {
        guard let d = downEvent else { return }
        let a = d.locationInWindow, b = event.locationInWindow
        guard hypot(a.x - b.x, a.y - b.y) > 3 else { return }
        downEvent = nil
        let items = Store.shared.items
        guard !items.isEmpty else { return }
        let p = convert(event.locationInWindow, from: nil)
        let dragItems: [NSDraggingItem] = items.enumerated().map { (i, it) in
            let di = NSDraggingItem(pasteboardWriter: it.url as NSURL)
            let img = NSWorkspace.shared.icon(forFile: it.url.path)
            let off = CGFloat(min(i, 6)) * 4
            di.setDraggingFrame(NSRect(x: p.x - 20 + off, y: p.y - 20 - off, width: 40, height: 40), contents: img)
            return di
        }
        beginDraggingSession(with: dragItems, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard operation != [], Prefs.removeAfterDrag else { return }
        DispatchQueue.main.async { Store.shared.removeAll() }
    }
}

final class ShelfView: NSView {
    private let effect = NSVisualEffectView()
    let header = HeaderView()
    private let scroll = NSScrollView()
    private let doc = FlippedView()
    private let stack = NSStackView()
    private let empty = NSStackView()
    private let ring = PassthroughView()
    static let radius: CGFloat = 16

    private var highlighted = false {
        didSet { ring.isHidden = !highlighted }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)

        effect.translatesAutoresizingMaskIntoConstraints = false
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = ShelfView.mask(ShelfView.radius)
        addSubview(effect)

        stack.orientation = .vertical
        stack.spacing = 4
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = doc

        let hint = NSTextField(labelWithString: "Suelta\naquí")
        hint.font = .systemFont(ofSize: 12, weight: .medium)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        hint.maximumNumberOfLines = 2
        let hintIcon = NSImageView(image: NSImage(systemSymbolName: "tray.and.arrow.down",
                                                  accessibilityDescription: nil) ?? NSImage())
        hintIcon.symbolConfiguration = .init(pointSize: 26, weight: .light)
        hintIcon.contentTintColor = .secondaryLabelColor
        empty.orientation = .vertical
        empty.spacing = 8
        empty.addArrangedSubview(hintIcon)
        empty.addArrangedSubview(hint)
        empty.translatesAutoresizingMaskIntoConstraints = false

        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.wantsLayer = true
        ring.layer?.cornerRadius = ShelfView.radius - 3
        ring.layer?.borderWidth = 2
        ring.layer?.borderColor = NSColor.controlAccentColor.cgColor
        ring.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        ring.isHidden = true

        effect.addSubview(header)
        effect.addSubview(scroll)
        effect.addSubview(empty)
        effect.addSubview(ring)

        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),
            effect.topAnchor.constraint(equalTo: topAnchor),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor),

            header.topAnchor.constraint(equalTo: effect.topAnchor, constant: 4),
            header.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 28),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -6),
            scroll.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -6),

            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),

            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),

            empty.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: effect.centerYAnchor, constant: 10),

            ring.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 3),
            ring.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -3),
            ring.topAnchor.constraint(equalTo: effect.topAnchor, constant: 3),
            ring.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -3),
        ])

        var types: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string, .tiff, .png]
        types += NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes(types)
    }
    required init?(coder: NSCoder) { fatalError() }

    static func mask(_ r: CGFloat) -> NSImage {
        let d = r * 2 + 1
        let img = NSImage(size: NSSize(width: d, height: d), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        img.resizingMode = .stretch
        return img
    }

    func reload() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in Store.shared.items {
            let v = ItemView(item: item)
            stack.addArrangedSubview(v)
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        empty.isHidden = !Store.shared.items.isEmpty
        header.update(count: Store.shared.items.count)
    }

    // MARK: Soltar dentro

    private func isOurs(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingSource is ItemView || sender.draggingSource is HeaderView
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if isOurs(sender) { return [] }
        highlighted = true
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isOurs(sender) ? [] : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { highlighted = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlighted = false
        return ingest(sender.draggingPasteboard)
    }
}

final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: ShelfPanel!
    private var shelf: ShelfView!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private let dragPB = NSPasteboard(name: .drag)
    private var baseline = 0
    private var dragActive = false
    private var ticks = 0
    private let width: CGFloat = 112

    func applicationDidFinishLaunching(_ notification: Notification) {
        shelf = ShelfView(frame: NSRect(x: 0, y: 0, width: width, height: 200))
        panel = ShelfPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 200),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.contentView = shelf
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: "Hold It")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        Store.shared.onChange = { [weak self] in self?.refresh() }
        baseline = dragPB.changeCount
        refresh()

        timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.layoutPanel(newScreen: true)
        }
    }

    /// Detecta que has empezado a arrastrar algo en cualquier app: el portapapeles
    /// de arrastre cambia mientras el botón del ratón está pulsado.
    private func tick() {
        let pressed = (NSEvent.pressedMouseButtons & 1) == 1
        let cc = dragPB.changeCount
        if !pressed {
            baseline = cc
            if dragActive {
                dragActive = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.updateVisibility() }
            }
        } else if cc != baseline && !dragActive {
            dragActive = true
            updateVisibility()
        }
        ticks += 1
        if ticks % 20 == 0 { Store.shared.prune() }
    }

    private func refresh() {
        shelf.reload()
        updateVisibility()
        layoutPanel(newScreen: false)
    }

    private var shouldShow: Bool {
        dragActive || !Store.shared.items.isEmpty || Prefs.alwaysVisible
    }

    private func updateVisibility() {
        if shouldShow { show() } else { hide() }
    }

    private func show() {
        guard !panel.isVisible || panel.alphaValue < 1 else { return }
        if !panel.isVisible { layoutPanel(newScreen: true) }
        panel.alphaValue = panel.isVisible ? panel.alphaValue : 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self, !self.shouldShow else { return }
            self.panel.orderOut(nil)
        })
    }

    private func mouseScreen() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func layoutPanel(newScreen: Bool) {
        let screen = (newScreen || panel.screen == nil) ? mouseScreen() : panel.screen!
        let vf = screen.visibleFrame
        let n = Store.shared.items.count
        let content = 32 + CGFloat(max(n, 1)) * (ItemView.height + 4) + 10
        let h = min(max(content, 170), vf.height * 0.8)
        let x = Prefs.leftEdge ? vf.minX + 10 : vf.maxX - width - 10
        let frame = NSRect(x: x, y: vf.midY - h / 2, width: width, height: h)
        panel.setFrame(frame, display: true, animate: panel.isVisible && !newScreen)
        panel.invalidateShadow()
    }

    // MARK: Menú de la barra

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ sel: Selector, on: Bool? = nil, key: String = "") {
            let it = menu.addItem(withTitle: title, action: sel, keyEquivalent: key)
            it.target = self
            if let on = on { it.state = on ? .on : .off }
        }
        let n = Store.shared.items.count
        let head = menu.addItem(withTitle: n == 0 ? "Hold It está vacío" : (n == 1 ? "1 elemento en Hold It" : "\(n) elementos en Hold It"),
                                action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(.separator())
        add("Pegar en Hold It", #selector(pasteIn), key: "")
        add("Vaciar Hold It", #selector(clearAll))
        menu.addItem(.separator())
        add("Mostrar siempre", #selector(toggleAlways), on: Prefs.alwaysVisible)
        add("Quitar al arrastrar fuera", #selector(toggleRemove), on: Prefs.removeAfterDrag)
        add("Colocar a la izquierda", #selector(toggleSide), on: Prefs.leftEdge)
        add("Abrir al iniciar sesión", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled)
        menu.addItem(.separator())
        add("Salir de Hold It", #selector(quit), key: "q")
    }

    @objc private func pasteIn() { ingest(NSPasteboard.general) }
    @objc private func clearAll() { Store.shared.removeAll() }
    @objc private func toggleAlways() { Prefs.alwaysVisible.toggle(); updateVisibility() }
    @objc private func toggleRemove() { Prefs.removeAfterDrag.toggle() }
    @objc private func toggleSide() { Prefs.leftEdge.toggle(); layoutPanel(newScreen: false) }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let a = NSAlert()
            a.messageText = "No se pudo cambiar el inicio automático"
            a.informativeText = error.localizedDescription
            a.runModal()
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
