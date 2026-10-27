// Bolitas — lo común a todos los estilos (bolitas, monos, enanitos):
// ratón, arrastrar la ventana, menú con botón derecho, soltar enlaces de chats y un poco de dibujo.

import AppKit

enum Theme: String, CaseIterable {
    case billar, monos, bolitas, enanitos
    var title: String {
        switch self {
        case .billar: return "Club del billar (abajo a la derecha)"
        case .bolitas: return "Bolitas (abajo, botan cuando te necesitan)"
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
    /// Escala del dibujo (los monos se dibujan a su tamaño "de diseño" y se encogen con esto).
    class var drawScale: CGFloat { 1 }
    /// Margen de arriba del dibujo (en coordenadas de dibujo), para escenas con fondo.
    var drawOffsetY: CGFloat { 0 }
    func local(_ e: NSEvent) -> NSPoint {
        let p = convert(e.locationInWindow, from: nil)
        let k = type(of: self).drawScale
        return NSPoint(x: p.x / k, y: p.y / k - drawOffsetY)
    }
    /// Los que se han ido: siguen dibujándose un rato mientras salen por la puerta.
    var leaving: [(chat: Chat, x: CGFloat, start: CGFloat)] = []
    /// Posición x de un chat (para saber desde dónde se va). Las escenas con sitios lo dicen.
    func seatX(_ i: Int, count: Int) -> CGFloat? { nil }
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
    /// Archivadores de conversaciones (uno de Claude y otro de ChatGPT) con una grabadora encima.
    var onCabinet: ((Provider, NSPoint) -> Void)?
    var onCassette: ((Provider) -> Void)?
    /// Dónde está cada archivador, en coordenadas de dibujo (las subclases que lo tengan lo dicen).
    func cabinets() -> [(Provider, CGRect)] { [] }
    /// Mira si el clic ha sido en un archivador o en su grabadora.
    /// Micrófono que cuelga del techo (las escenas que lo tengan dicen dónde).
    func microphone() -> CGRect? { nil }
    var onMicrophone: ((NSPoint) -> Void)?
    func furnitureClick(_ p: NSPoint) -> Bool {
        let k = type(of: self).drawScale
        if let m = microphone(), m.insetBy(dx: -6, dy: -6).contains(p) {
            onMicrophone?(NSPoint(x: m.midX * k, y: (m.maxY + drawOffsetY) * k)); return true
        }
        for (prov, r) in cabinets() where r.contains(p) {
            onCabinet?(prov, NSPoint(x: r.midX * k, y: (r.minY + drawOffsetY) * k)); return true
        }
        return false
    }
    func drawMicrophone(_ cg: CGContext) {
        guard let m = microphone() else { return }
        let hover = hoverPoint.map { m.insetBy(dx: -6, dy: -6).contains($0) } ?? false
        let sway = sin(t * 0.9) * 1.5
        cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(1.6)
        cg.move(to: CGPoint(x: m.midX, y: -drawOffsetY)); cg.addLine(to: CGPoint(x: m.midX + sway, y: m.minY)); cg.strokePath()
        let x = m.midX + sway
        // Micro de radio antiguo: rejilla redondeada con anillo dorado
        let head = CGRect(x: x - m.width / 2, y: m.minY, width: m.width, height: m.height - 8)
        rrect(cg, head, m.width / 2, Palette.rgb(0xB8BCC6), line: 2)
        cg.saveGState(); cg.addPath(CGPath(roundedRect: head, cornerWidth: m.width / 2, cornerHeight: m.width / 2, transform: nil)); cg.clip()
        cg.setStrokeColor(Palette.rgb(0x6B7080).cgColor); cg.setLineWidth(1)
        var yy = head.minY + 4
        while yy < head.maxY { cg.move(to: CGPoint(x: head.minX, y: yy)); cg.addLine(to: CGPoint(x: head.maxX, y: yy)); yy += 4 }
        cg.strokePath(); cg.restoreGState()
        rrect(cg, CGRect(x: x - m.width / 2 - 2, y: head.midY - 3, width: m.width + 4, height: 6), 3, Palette.rgb(0xC9A227), line: 1.4)
        rrect(cg, CGRect(x: x - 4, y: head.maxY, width: 8, height: 8), 2, Palette.rgb(0x2B2B30), line: 1.4)
        if hover {
            ellipse(cg, CGRect(x: x - 4, y: head.minY - 12, width: 8, height: 8), Palette.rgb(0xE5484D, 0.6 + 0.4 * abs(sin(t * 5))), line: 1.2)
            pill("🎙 hablar", center: CGPoint(x: x, y: m.maxY + 16), maxW: 90)
        }
    }
    /// «¡Hola!»: saluda con la mano y juega con una pelota para que veas que ya ha terminado.
    func drawHello(_ cg: CGContext, handX: CGFloat, handY: CGFloat, ballX: CGFloat, floorY: CGFloat, ph: CGFloat, hand: NSColor) {
        let wave = sin(t * 9 + ph) * 6
        ellipse(cg, CGRect(x: handX - 8 + wave, y: handY - 8, width: 16, height: 16), hand, line: 1.8)
        cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(1.4)
        for k in 0..<3 {   // dedos
            cg.move(to: CGPoint(x: handX - 5 + CGFloat(k) * 5 + wave, y: handY - 7))
            cg.addLine(to: CGPoint(x: handX - 6 + CGFloat(k) * 6 + wave * 1.2, y: handY - 13))
        }
        cg.strokePath()
        if sin(t * 1.3 + ph) > -0.2 {
            balloon(cg, "¡hola!", center: CGPoint(x: handX + 6, y: handY - 30), urgent: false, wobble: sin(t * 4 + ph) * 0.08)
        }
        // pelota botando
        let h = abs(sin(t * 4.2 + ph))
        let r: CGFloat = 7
        let by = floorY - r - h * 30
        let squash: CGFloat = h < 0.12 ? 1.25 : 1
        let lift: CGFloat = squash > 1 ? 2 : 0
        let br = CGRect(x: ballX - r * squash, y: by - r / squash + lift, width: r * 2 * squash, height: r * 2 / squash)
        ellipse(cg, br, Palette.rgb(0xE5484D), line: 1.6)
        cg.saveGState(); cg.addEllipse(in: br); cg.clip()
        cg.setFillColor(NSColor.white.cgColor); cg.fill(CGRect(x: br.minX, y: br.midY - 2, width: br.width, height: 4))
        cg.restoreGState()
        cg.setFillColor(NSColor.black.withAlphaComponent(0.15 * (1 - h)).cgColor)
        cg.fillEllipse(in: CGRect(x: ballX - 8, y: floorY - 2, width: 16, height: 4))
    }

    func drawCabinets(_ cg: CGContext) {
        for (prov, r) in cabinets() {
            let hover = hoverPoint.map { r.contains($0) } ?? false
            let body = prov == .claude ? Palette.rgb(0xC96A4A) : Palette.rgb(0x3A3D44)
            let dark = body.blended(withFraction: 0.3, of: .black) ?? body
            cg.setFillColor(NSColor.black.withAlphaComponent(0.15).cgColor)
            cg.fillEllipse(in: CGRect(x: r.minX - 4, y: r.maxY - 4, width: r.width + 8, height: 8))
            rrect(cg, r, 4, body, line: 2.2)
            // Tres cajones; el de arriba se abre un poco al pasar el ratón
            for k in 0..<3 {
                let dh = (r.height - 12) / 3
                var d = CGRect(x: r.minX + 5, y: r.minY + 4 + CGFloat(k) * (dh + 2), width: r.width - 10, height: dh)
                if k == 0 && hover { d = d.offsetBy(dx: 0, dy: 3).insetBy(dx: -3, dy: 0) }
                rrect(cg, d, 3, k == 0 && hover ? (body.blended(withFraction: 0.15, of: .white) ?? body) : body, line: 1.8)
                rrect(cg, CGRect(x: d.midX - 9, y: d.minY + 6, width: 18, height: 5), 2, Palette.rgb(0xD9D9D9), line: 1.2)
                if k == 0 {
                    rrect(cg, CGRect(x: d.minX + 4, y: d.maxY - 12, width: d.width - 8, height: 9), 2, Palette.rgb(0xF2E8CF), line: 1)
                    text(prov == .claude ? "CLAUDE" : "CHATGPT", Fonts.rounded(6.5, .black), dark, center: CGPoint(x: d.midX, y: d.maxY - 7.5))
                }
                if k == 0 && hover {
                    // fichas asomando
                    for f in 0..<4 {
                        rrect(cg, CGRect(x: d.minX + 5 + CGFloat(f) * 9, y: d.minY - 6 - CGFloat(f % 2) * 2, width: 8, height: 8), 1, Palette.rgb(0xFFF7E2), line: 1)
                    }
                }
            }
            if hover { pill("conversaciones", center: CGPoint(x: r.midX, y: r.minY - 12), maxW: 120) }
        }
    }

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
        let newKeys = Set(chats.map { $0.key })
        if !firstLoad {
            for (i, c) in old.enumerated() where !newKeys.contains(c.key) {
                // Se calcula con la lista vieja: es donde estaba sentado.
                if let x = seatX(i, count: old.count) { leaving.append((c, x, t)) }
            }
        }
        leaving.removeAll { t - $0.start > 4 }
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
        let p = local(event)
        hoverPoint = p
        let h = actorIndex(at: p)
        if h != hoverIndex { hoverIndex = h }
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { hoverIndex = nil; hoverPoint = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        pressPoint = local(event)
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
        if furnitureClick(pressPoint) { return }
        if let i = pressIndex, i < chats.count { onClick?(chats[i]); return }
        if onBackgroundClick?(pressPoint) == true { return }
        if chats.isEmpty || needsPermission { onPlaceholderClick?() }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let i = actorIndex(at: local(event)), i < chats.count else { return nil }
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
