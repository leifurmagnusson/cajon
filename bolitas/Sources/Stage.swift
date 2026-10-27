// Bolitas — lo común a todos los estilos (bolitas, monos, enanitos):
// ratón, arrastrar la ventana, menú con botón derecho, soltar enlaces de chats y un poco de dibujo.

import AppKit

enum Theme: String, CaseIterable {
    case bolitas, monos, enanitos
    var title: String {
        switch self {
        case .bolitas: return "Bolitas (arriba)"
        case .monos: return "Monos en la oficina (abajo a la derecha)"
        case .enanitos: return "Fábrica de enanitos (abajo a la izquierda)"
        }
    }
}

/// Número estable a partir de un texto: cada chat tiene siempre el mismo mono o enanito.
func seed(_ s: String) -> UInt64 {
    var h: UInt64 = 1469598103934665603
    for b in s.utf8 { h ^= UInt64(b); h = h &* 1099511628211 }
    return h
}

struct Dice {
    var s: UInt64
    init(_ key: String) { s = seed(key) | 1 }
    mutating func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
    mutating func pick<T>(_ a: [T]) -> T { a[Int(next() % UInt64(a.count))] }
    mutating func chance(_ p: Double) -> Bool { Double(next() % 1000) / 1000 < p }
}

func clamp01(_ x: CGFloat) -> CGFloat { min(1, max(0, x)) }
func ease(_ x: CGFloat) -> CGFloat { let t = clamp01(x); return t * t * (3 - 2 * t) }
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

class StageView: NSView {
    var chats: [Chat] = [] { didSet { chatsChanged(from: oldValue) } }
    var needsPermission = false
    var t: CGFloat = 0
    var hoverIndex: Int?
    var hoverPoint: NSPoint?
    var dropHover = false
    /// Cuándo apareció cada chat (para la animación de entrada).
    var born: [String: CGFloat] = [:]
    var firstLoad = true

    var onClick: ((Chat) -> Void)?
    var onPlaceholderClick: (() -> Void)?
    var onMoved: ((NSPoint) -> Void)?
    var onDrop: (([String]) -> Bool)?
    var menuFor: ((Chat) -> NSMenu?)?
    var onBackgroundClick: ((NSPoint) -> Bool)?

    private var pressIndex: Int?
    private var pressPoint = NSPoint.zero
    private var pressMouse = NSPoint.zero
    private var pressOrigin = NSPoint.zero
    private var dragged = false

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.URL, .string, NSPasteboard.PasteboardType("public.url")])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Tamaño que necesita la escena para n chats.
    class func size(for count: Int) -> NSSize { NSSize(width: 200, height: 120) }
    /// Qué chat hay bajo el ratón.
    func actorIndex(at p: NSPoint) -> Int? { nil }
    /// Punto (en la vista) de donde sale el humo de cada chat, si lo hay.
    func smokeSource(_ i: Int) -> NSPoint? { nil }

    func chatsChanged(from old: [Chat]) {
        let oldKeys = Set(old.map { $0.key })
        for c in chats where !oldKeys.contains(c.key) && born[c.key] == nil {
            born[c.key] = firstLoad ? -100 : t
        }
        firstLoad = false
        needsDisplay = true
    }
    func age(_ c: Chat) -> CGFloat { t - (born[c.key] ?? -100) }

    // MARK: Dibujo de ayuda

    func text(_ s: String, _ font: NSFont, _ color: NSColor, center: CGPoint, halo: NSColor? = nil) {
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if let h = halo {
            let sh = NSShadow(); sh.shadowColor = h; sh.shadowBlurRadius = 3; sh.shadowOffset = .zero
            attrs[.shadow] = sh
        }
        let sz = (s as NSString).size(withAttributes: attrs)
        (s as NSString).draw(at: NSPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2), withAttributes: attrs)
    }

    func pill(_ s: String, center: CGPoint, maxW: CGFloat, fill: NSColor = Palette.rgb(0xFFFFFF, 0.93), color: NSColor = Palette.outline) {
        let font = Fonts.name
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        var s2 = s
        while (s2 as NSString).size(withAttributes: attrs).width > maxW - 14 && s2.count > 2 { s2 = String(s2.dropLast(2)) + "…" }
        let sz = (s2 as NSString).size(withAttributes: attrs)
        let r = NSRect(x: center.x - sz.width / 2 - 7, y: center.y - sz.height / 2 - 2, width: sz.width + 14, height: sz.height + 4)
        let p = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        fill.setFill(); p.fill(); p.lineWidth = 1.5; Palette.outline.setStroke(); p.stroke()
        (s2 as NSString).draw(at: NSPoint(x: r.minX + 7, y: r.minY + 2), withAttributes: attrs)
    }

    func balloon(_ cg: CGContext, _ s: String, center: CGPoint, urgent: Bool, wobble: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: Fonts.balloon]
        let w = (s as NSString).size(withAttributes: attrs).width + 14
        cg.saveGState()
        cg.translateBy(x: center.x, y: center.y)
        cg.rotate(by: wobble)
        let rect = CGRect(x: -w / 2, y: -9, width: w, height: 18)
        let p = CGMutablePath()
        p.addRoundedRect(in: rect, cornerWidth: 9, cornerHeight: 9)
        p.move(to: CGPoint(x: -4, y: 8.5)); p.addLine(to: CGPoint(x: 1, y: 15)); p.addLine(to: CGPoint(x: 5, y: 8.5))
        cg.addPath(p); cg.setFillColor((urgent ? Palette.alert : Palette.balloon).cgColor); cg.fillPath()
        cg.addPath(p); cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(1.8); cg.strokePath()
        cg.restoreGState()
        text(s, Fonts.balloon, urgent ? .white : Palette.outline, center: center)
    }

    func z(_ cg: CGContext, x: CGFloat, y: CGFloat, ph: CGFloat) {
        for k in 0..<2 {
            let p = (t * 0.45 + ph * 0.1 + CGFloat(k) * 0.5).truncatingRemainder(dividingBy: 1)
            let a = sin(p * .pi)
            text("z", Fonts.rounded(9 + p * 6, .heavy), Palette.outline.withAlphaComponent(0.55 * a),
                 center: CGPoint(x: x + p * 12, y: y - p * 22))
        }
    }

    func fillStroke(_ cg: CGContext, _ path: CGPath, _ fill: NSColor, line: CGFloat = 2.2) {
        cg.addPath(path); cg.setFillColor(fill.cgColor); cg.fillPath()
        cg.addPath(path); cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(line); cg.strokePath()
    }
    func ellipse(_ cg: CGContext, _ r: CGRect, _ fill: NSColor, line: CGFloat = 2.2) {
        fillStroke(cg, CGPath(ellipseIn: r, transform: nil), fill, line: line)
    }
    func rrect(_ cg: CGContext, _ r: CGRect, _ rad: CGFloat, _ fill: NSColor, line: CGFloat = 2.2) {
        fillStroke(cg, CGPath(roundedRect: r, cornerWidth: min(rad, r.width / 2), cornerHeight: min(rad, r.height / 2), transform: nil), fill, line: line)
    }

    // MARK: Ratón

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        hoverPoint = p
        let h = actorIndex(at: p)
        if h != hoverIndex { hoverIndex = h }
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { hoverIndex = nil; hoverPoint = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        pressPoint = convert(event.locationInWindow, from: nil)
        pressIndex = actorIndex(at: pressPoint)
        pressMouse = NSEvent.mouseLocation
        pressOrigin = window?.frame.origin ?? .zero
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        let m = NSEvent.mouseLocation
        let dx = m.x - pressMouse.x, dy = m.y - pressMouse.y
        if !dragged && hypot(dx, dy) < 4 { return }
        dragged = true
        window?.setFrameOrigin(NSPoint(x: pressOrigin.x + dx, y: pressOrigin.y + dy))
    }
    override func mouseUp(with event: NSEvent) {
        if dragged { if let o = window?.frame.origin { onMoved?(o) }; return }
        if let i = pressIndex, i < chats.count { onClick?(chats[i]); return }
        if onBackgroundClick?(pressPoint) == true { return }
        if chats.isEmpty || needsPermission { onPlaceholderClick?() }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let i = actorIndex(at: convert(event.locationInWindow, from: nil)), i < chats.count else { return nil }
        return menuFor?(chats[i])
    }

    // MARK: Soltar enlaces de chats

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dropHover = true; needsDisplay = true; return .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropHover = false; needsDisplay = true }
    override func draggingEnded(_ sender: NSDraggingInfo) { dropHover = false; needsDisplay = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropHover = false
        var out: [String] = []
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] { out += urls.map { $0.absoluteString } }
        if let s = pb.string(forType: .string) { out.append(s) }
        return onDrop?(out) ?? false
    }

    func drawDropHint(_ cg: CGContext, _ r: CGRect) {
        guard dropHover else { return }
        let p = NSBezierPath(roundedRect: r, xRadius: 18, yRadius: 18)
        Palette.rgb(0xFFFFFF, 0.35).setFill(); p.fill()
        p.lineWidth = 2.5; p.setLineDash([7, 5], count: 2, phase: t * 20)
        Palette.outline.withAlphaComponent(0.6).setStroke(); p.stroke()
    }
}
