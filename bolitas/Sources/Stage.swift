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
    /// Gramófono con bocina gigante: al tocarlo, hablas con Claude o ChatGPT.
    func drawMicrophone(_ cg: CGContext) {
        guard let r = microphone() else { return }
        let hover = hoverPoint.map { r.insetBy(dx: -6, dy: -6).contains($0) } ?? false
        let wood = Palette.rgb(0x7A4A28), brass = Palette.rgb(0xD4A82A), brassD = Palette.rgb(0x9C7A1C)
        cg.setFillColor(NSColor.black.withAlphaComponent(0.15).cgColor)
        cg.fillEllipse(in: CGRect(x: r.minX + 4, y: r.maxY - 4, width: r.width - 8, height: 8))
        // Caja de madera con patitas
        let box = CGRect(x: r.minX + 10, y: r.maxY - 30, width: r.width - 20, height: 24)
        rrect(cg, CGRect(x: box.minX + 3, y: box.maxY - 2, width: 6, height: 7), 2, wood, line: 1.4)
        rrect(cg, CGRect(x: box.maxX - 9, y: box.maxY - 2, width: 6, height: 7), 2, wood, line: 1.4)
        rrect(cg, box, 4, wood, line: 2)
        rrect(cg, box.insetBy(dx: 5, dy: 6), 2, Palette.rgb(0x5A3A22), line: 1.2)
        ellipse(cg, CGRect(x: box.maxX - 4, y: box.midY - 3, width: 8, height: 6), brass, line: 1.2)   // manivela
        // Disco girando
        let disc = CGRect(x: box.minX + 3, y: box.minY - 7, width: box.width - 6, height: 9)
        ellipse(cg, disc, Palette.rgb(0x151515), line: 1.6)
        ellipse(cg, CGRect(x: disc.midX - 5, y: disc.midY - 2, width: 10, height: 4), Palette.rgb(0xE5484D), line: 0.8)
        let spin = t * (hover ? 6 : 1.5)
        cg.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor); cg.setLineWidth(1)
        cg.move(to: CGPoint(x: disc.midX + cos(spin) * disc.width * 0.4, y: disc.midY + sin(spin) * disc.height * 0.4))
        cg.addLine(to: CGPoint(x: disc.midX + cos(spin) * disc.width * 0.2, y: disc.midY + sin(spin) * disc.height * 0.2)); cg.strokePath()
        // Brazo y cuello de la bocina
        let neckBase = CGPoint(x: disc.maxX - 10, y: disc.minY + 2)
        let mouth = CGPoint(x: r.minX + 26, y: r.minY + 24)       // centro de la boca de la bocina
        let neck = CGMutablePath()
        neck.move(to: neckBase)
        neck.addCurve(to: CGPoint(x: mouth.x + 12, y: mouth.y + 14), control1: CGPoint(x: neckBase.x + 4, y: neckBase.y - 30),
                      control2: CGPoint(x: mouth.x + 30, y: mouth.y + 26))
        cg.addPath(neck); cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(7); cg.strokePath()
        cg.addPath(neck); cg.setStrokeColor(brassD.cgColor); cg.setLineWidth(4.5); cg.strokePath()
        // Bocina enorme (cono que se abre hacia arriba a la izquierda)
        let wob = hover ? sin(t * 14) * 0.03 : 0
        cg.saveGState()
        cg.translateBy(x: mouth.x, y: mouth.y); cg.rotate(by: -0.55 + wob)
        let horn = CGMutablePath()
        horn.move(to: CGPoint(x: 20, y: 34)); horn.addQuadCurve(to: CGPoint(x: -30, y: 0), control: CGPoint(x: -2, y: 30))
        horn.addLine(to: CGPoint(x: 30, y: 0)); horn.addQuadCurve(to: CGPoint(x: 26, y: 34), control: CGPoint(x: 8, y: 30)); horn.closeSubpath()
        fillStroke(cg, horn, brass, line: 2)
        // Pétalos de la bocina
        cg.setStrokeColor(brassD.cgColor); cg.setLineWidth(1.2)
        for k in -2...2 { cg.move(to: CGPoint(x: CGFloat(k) * 11, y: 1)); cg.addLine(to: CGPoint(x: 21 + CGFloat(k) * 1.2, y: 33)) }
        cg.strokePath()
        ellipse(cg, CGRect(x: -31, y: -8, width: 62, height: 16), Palette.rgb(0xF2D16B), line: 2)
        ellipse(cg, CGRect(x: -20, y: -4.5, width: 40, height: 9), Palette.rgb(0x5A4510), line: 1.2)
        cg.restoreGState()
        if hover {
            for n in 0..<3 {
                let q = (t * 0.8 + CGFloat(n) / 3).truncatingRemainder(dividingBy: 1)
                text(["♪", "♫", "♩"][n], Fonts.rounded(13, .black), Palette.outline.withAlphaComponent(1 - q),
                     center: CGPoint(x: mouth.x - 24 - q * 20 + CGFloat(n) * 10, y: mouth.y - 14 - q * 26))
            }
            pill("🎙 hablar", center: CGPoint(x: r.midX, y: r.maxY + 14), maxW: 90)
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

    /// Un solo mueble negro con un cajón para Claude y otro para ChatGPT.
    func drawCabinets(_ cg: CGContext) {
        let cabs = cabinets()
        guard !cabs.isEmpty else { return }
        let all = cabs.map { $0.1 }.reduce(cabs[0].1) { $0.union($1) }
        let body = all.insetBy(dx: -5, dy: -5)
        cg.setFillColor(NSColor.black.withAlphaComponent(0.18).cgColor)
        cg.fillEllipse(in: CGRect(x: body.minX - 4, y: body.maxY - 4, width: body.width + 8, height: 8))
        rrect(cg, CGRect(x: body.minX + 4, y: body.maxY - 2, width: 7, height: 6), 2, Palette.rgb(0x111114), line: 1.4)
        rrect(cg, CGRect(x: body.maxX - 11, y: body.maxY - 2, width: 7, height: 6), 2, Palette.rgb(0x111114), line: 1.4)
        rrect(cg, body, 5, Palette.rgb(0x1E1F24), line: 2.2)
        for (prov, r) in cabs {
            let hover = hoverPoint.map { r.contains($0) } ?? false
            var d = r.insetBy(dx: 1, dy: 2)
            if hover { d = d.offsetBy(dx: 0, dy: 3).insetBy(dx: -3, dy: 0) }
            rrect(cg, d, 3, hover ? Palette.rgb(0x34363E) : Palette.rgb(0x2A2C33), line: 1.8)
            // Placa con el nombre y un punto de color de cada app
            let plate = CGRect(x: d.minX + 6, y: d.minY + 5, width: d.width - 12, height: 13)
            rrect(cg, plate, 2.5, Palette.rgb(0xF2E8CF), line: 1)
            let dot = prov == .claude ? Palette.rgb(0xD97757) : Palette.rgb(0x10A37F)
            ellipse(cg, CGRect(x: plate.minX + 3, y: plate.midY - 3.5, width: 7, height: 7), dot, line: 0.8)
            text(prov == .claude ? "Claude" : "ChatGPT", Fonts.rounded(8, .black), Palette.rgb(0x2A2C33), center: CGPoint(x: plate.midX + 4, y: plate.midY))
            // Tirador
            rrect(cg, CGRect(x: d.midX - 11, y: d.maxY - 13, width: 22, height: 6), 3, Palette.rgb(0xC9A227), line: 1.2)
            if hover {
                for f in 0..<4 {
                    rrect(cg, CGRect(x: d.minX + 8 + CGFloat(f) * 14, y: d.minY - 6 - CGFloat(f % 2) * 2, width: 11, height: 8), 1, Palette.rgb(0xFFF7E2), line: 1)
                }
                pill("conversaciones de \(prov.name)", center: CGPoint(x: r.midX, y: body.maxY + 14), maxW: 190)
            }
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
