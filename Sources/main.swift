// Hold It — una mano de camarero que te aguanta lo que arrastras.
// Sueltas archivos sobre la mano y se apilan como cajas; si las tocas, se tambalean
// y la mano hace equilibrio hasta que se quedan quietas.

import AppKit
import ServiceManagement
import QuickLookThumbnailing

// MARK: - Utilidades de dibujo

/// Convierte un trazado tipo SVG (solo M, L, C, Z con coordenadas absolutas) en CGPath.
/// Así la mano se diseña en SVG y aquí se dibuja exactamente igual.
func svgPath(_ d: String) -> CGPath {
    let p = CGMutablePath()
    var tokens: [String] = []
    var cur = ""
    for ch in d {
        if "MLCZ".contains(ch) {
            if !cur.isEmpty { tokens.append(cur); cur = "" }
            tokens.append(String(ch))
        } else if ch == " " || ch == "," || ch == "\n" {
            if !cur.isEmpty { tokens.append(cur); cur = "" }
        } else {
            cur.append(ch)
        }
    }
    if !cur.isEmpty { tokens.append(cur) }
    var i = 0
    var cmd = "M"
    func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
    while i < tokens.count {
        if "MLCZ".contains(tokens[i]) { cmd = tokens[i]; i += 1; if cmd == "Z" { p.closeSubpath() }; continue }
        switch cmd {
        case "M": let x = num(), y = num(); p.move(to: CGPoint(x: x, y: y)); cmd = "L"
        case "L": let x = num(), y = num(); p.addLine(to: CGPoint(x: x, y: y))
        case "C":
            let a = num(), b = num(), c = num(), e = num(), f = num(), g = num()
            p.addCurve(to: CGPoint(x: f, y: g), control1: CGPoint(x: a, y: b), control2: CGPoint(x: c, y: e))
        default: i += 1
        }
    }
    return p
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

enum Art {
    // Mano enguantada, palma hacia arriba, dedos hacia la izquierda. Origen = centro de la palma.
    static let glove = svgPath("""
        M 40 -1 L -50 -1 C -58 -1 -63 -4 -66 -9 C -68 -12 -65 -15 -62 -13 C -59 -11 -57 -8 -50 -7
        C -60 -6 -70 -2 -71 5 C -72 10 -68 13 -63 13 C -66 16 -64 21 -58 21 C -58 25 -53 27 -47 26
        C -45 29 -40 30 -34 29 L 24 25 C 35 24 42 16 42 8 Z
        """)
    static let fingerLines = svgPath("""
        M -63 13 C -55 12 -46 12 -38 11 M -58 21 C -50 20 -42 19 -34 18 M -47 26 C -42 25 -37 24 -32 23
        """)
    static let thumb = svgPath("M 30 2 C 22 -2 10 -8 2 -12 C -4 -15 -9 -10 -5 -6 C 2 0 12 8 22 12 Z")
    static let sleeve = svgPath("M 34 6 L 56 -6 L 190 116 L 150 142 Z")
    static let cuff = svgPath("M 34 8 L 54 -4 L 68 10 L 46 23 Z")

    static let gloveTop = NSColor(hex: 0xFFFFFF).cgColor
    static let gloveBottom = NSColor(hex: 0xE6E4DE).cgColor
    static let gloveStroke = NSColor(hex: 0xBDBAB2).cgColor
    static let lineColor = NSColor(hex: 0xCFCCC4).cgColor
    static let sleeveA = NSColor(hex: 0x2B2F3A).cgColor
    static let sleeveB = NSColor(hex: 0x171A21).cgColor
    static let gold = NSColor(hex: 0xC9A24A).cgColor
    static let kraftTop = NSColor(hex: 0xE2BC84).cgColor
    static let kraftBottom = NSColor(hex: 0xCC9E62).cgColor
    static let kraftStroke = NSColor(hex: 0xA97B45).cgColor
    static let kraftLine = NSColor(hex: 0xB88A55).cgColor
    static let tape = NSColor(hex: 0xEFD9AE, alpha: 0.9).cgColor

    static func gradient(_ a: CGColor, _ b: CGColor) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [a, b] as CFArray, locations: [0, 1])!
    }
    static let gloveGrad = gradient(gloveTop, gloveBottom)
    static let sleeveGrad = gradient(sleeveA, sleeveB)
    static let kraftGrad = gradient(kraftTop, kraftBottom)

    /// Icono de la barra de menús: mano con una caja (plantilla en blanco y negro).
    static func menuBarImage() -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 18), flipped: true) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            cg.translateBy(x: 11, y: 12.5)
            cg.scaleBy(x: 0.135, y: 0.135)
            cg.setFillColor(NSColor.black.cgColor)
            cg.addPath(glove); cg.fillPath()
            cg.addPath(CGPath(roundedRect: CGRect(x: -42, y: -64, width: 64, height: 56), cornerWidth: 8, cornerHeight: 8, transform: nil))
            cg.fillPath()
            return true
        }
        img.isTemplate = true
        return img
    }
}

// MARK: - Física

struct Spring {
    var pos: CGFloat = 0
    var vel: CGFloat = 0
    var target: CGFloat = 0
    let k: CGFloat
    let c: CGFloat
    init(k: CGFloat, c: CGFloat, pos: CGFloat = 0) { self.k = k; self.c = c; self.pos = pos }
    @discardableResult
    mutating func step(_ dt: CGFloat, extra: CGFloat = 0) -> CGFloat {
        let a = -k * (pos - target) - c * vel + extra
        vel += a * dt
        pos += vel * dt
        return a
    }
    var resting: Bool { abs(vel) < 0.003 && abs(pos - target) < 0.003 }
}

/// Cada caja: inclinación, desplazamiento lateral y caída (al soltarla cae desde arriba y rebota).
/// Tarda unos 2–3 segundos en quedarse recta.
final class BoxState {
    var ang = Spring(k: 34, c: 3.0)
    var x = Spring(k: 30, c: 4.5)
    var y = Spring(k: 130, c: 9)
    var lastAccel: CGFloat = 0
}

// MARK: - La mano

final class HandView: NSView, NSDraggingSource {
    override var isFlipped: Bool { true }

    var states: [UUID: BoxState] = [:]
    private var order: [UUID] = []
    private var thumbs: [UUID: NSImage] = [:]
    private var draggingIDs: Set<UUID> = []

    // Mano: inclinación (equilibrio), desplazamiento, hundimiento al recibir y entrada/salida.
    var phi = Spring(k: 16, c: 4.2)
    var shift = Spring(k: 14, c: 4.5)
    var dip = Spring(k: 90, c: 8)
    var slide = Spring(k: 90, c: 11, pos: 1)  // 0 = visible, 1 = fuera de pantalla

    var dragActive = false { didSet { needsDisplay = true } }
    private var dragHover = false { didSet { needsDisplay = true } }

    private var transforms: [CGAffineTransform] = []
    private var handTransform = CGAffineTransform.identity
    private var boxSize = CGSize(width: 86, height: 64)
    private var hovered: Int?
    private var lastMouse: NSPoint?
    private var downPoint: NSPoint?
    private var downTarget: Int?   // índice de caja, o -1 = la mano (todas)
    private var selected: Set<UUID> = []   // cajas seleccionadas con Mayúsculas/⌘ + clic

    override init(frame: NSRect) {
        super.init(frame: frame)
        var types: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string, .tiff, .png]
        types += NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes(types)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    var items: [ShelfItem] { Store.shared.items }

    // MARK: Sincronizar con el modelo

    func reload() {
        let newOrder = items.map { $0.id }
        let oldIndex = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        var prevDelta = 0
        for (i, id) in newOrder.enumerated() {
            if let st = states[id], let old = oldIndex[id] {
                // Si se ha quitado una caja de debajo, esta (y las de encima) caen a su sitio.
                let delta = old - i
                if delta > prevDelta { st.y.pos -= CGFloat(delta - prevDelta) * boxSize.height; st.ang.vel += .random(in: -0.6...0.6) }
                prevDelta = delta
            } else {
                let st = BoxState()
                st.ang.pos = .random(in: -0.32...0.32)
                st.x.pos = .random(in: -14...14)
                st.y.pos = -170
                states[id] = st
                dip.vel += 70
                phi.vel += .random(in: -0.5...0.5)
                loadThumb(items[i])
            }
        }
        for id in order where !newOrder.contains(id) { states[id] = nil; thumbs[id] = nil }
        order = newOrder
        selected = selected.intersection(newOrder)
        needsDisplay = true
    }

    private func loadThumb(_ item: ShelfItem) {
        let id = item.id
        thumbs[id] = NSWorkspace.shared.icon(forFile: item.url.path)
        let req = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 48, height: 48),
                                               scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let img = rep?.nsImage else { return }
            DispatchQueue.main.async { self?.thumbs[id] = img; self?.needsDisplay = true }
        }
    }

    // MARK: Animación

    /// Un paso de simulación. Devuelve true si algo se sigue moviendo.
    func step(_ dt: CGFloat) -> Bool {
        var moving = false
        var belowAccel: CGFloat = 0
        var px: CGFloat = 0, acc: CGFloat = 0, com: CGFloat = 0
        let h = boxSize.height
        for id in order {
            guard let st = states[id] else { continue }
            // La caja de encima reacciona al revés que la de abajo: así la torre se balancea.
            let a = st.ang.step(dt, extra: -0.35 * belowAccel)
            st.lastAccel = a
            belowAccel = a
            st.x.step(dt)
            st.y.step(dt)
            if !st.ang.resting || !st.x.resting || !st.y.resting { moving = true }
            px += st.x.pos
            acc += st.ang.pos
            com += px + sin(acc) * h / 2
            px += sin(acc) * h
        }
        // La mano compensa: se inclina y se desplaza hacia el lado contrario al peso.
        if !order.isEmpty { com /= CGFloat(order.count) }
        phi.target = max(-0.22, min(0.22, -com * 0.006))
        shift.target = max(-26, min(26, -com * 0.55))
        phi.step(dt); shift.step(dt); dip.step(dt); slide.step(dt)
        if exitT != nil { advanceGoodbye(dt); moving = true }
        if !phi.resting || !shift.resting || !dip.resting || !slide.resting { moving = true }
        if moving { needsDisplay = true }
        return moving
    }

    // MARK: Despedida
    // Cuando se queda sin cajas: espera un segundo, dice adiós con la mano
    // y se va bajando una escalera a saltitos.

    private(set) var exitT: CGFloat?
    private var exitOffset = CGPoint.zero
    private var exitPhi: CGFloat = 0
    var goodbyeFinished: Bool { (exitT ?? 0) > 2.3 }

    func startGoodbye() {
        guard exitT == nil else { return }
        exitT = 0
        needsDisplay = true
    }

    func cancelGoodbye() {
        guard exitT != nil else { return }
        // Si vuelve a hacer falta a media escalera, sube desde donde esté (sin saltos bruscos).
        slide.pos += exitOffset.x / 300
        dip.pos += exitOffset.y
        phi.pos += exitPhi
        exitT = nil
        exitOffset = .zero
        exitPhi = 0
        needsDisplay = true
    }

    private func advanceGoodbye(_ dt: CGFloat) {
        guard var t = exitT else { return }
        t += dt
        exitT = t
        if t < 0.25 {
            // Un instante, como pensándoselo
            exitOffset = .zero
            exitPhi = 0.025 * sin(t * 12)
        } else if t < 1.1 {
            // ¡Adiós! (tres saludos rápidos con la muñeca, un poco levantada)
            let w = t - 0.25
            let env = sin(min(1, w / 0.85) * .pi)
            exitOffset = CGPoint(x: 0, y: -10 * env)
            exitPhi = 0.34 * sin(w * 2 * .pi * 3.5) * env
        } else {
            // Baja la escalera: 4 escalones, cada uno con su saltito
            let u = (t - 1.1) / 0.24
            let k = floor(u), f = u - k
            let ease = f * f * (3 - 2 * f)
            exitOffset = CGPoint(x: 36 * (k + ease), y: 30 * (k + ease) - 16 * sin(.pi * f))
            exitPhi = 0.16 * sin(.pi * f)
        }
    }

    func nudgeAll(_ amount: CGFloat) {
        for st in states.values { st.ang.vel += .random(in: -amount...amount) }
        phi.vel += CGFloat.random(in: -amount...amount) * 0.4
    }

    // MARK: Geometría

    private var palm: CGPoint { CGPoint(x: bounds.width - 118, y: bounds.height - 74) }

    private func computeLayout() {
        let n = max(order.count, 1)
        let avail = palm.y - 24
        let s = min(1, max(0.45, avail / (CGFloat(n) * 64 + 4)))
        boxSize = CGSize(width: 86 * s, height: 64 * s)
        handTransform = CGAffineTransform(translationX: palm.x + shift.pos + slide.pos * 300 + exitOffset.x,
                                          y: palm.y + dip.pos + exitOffset.y)
            .rotated(by: phi.pos + exitPhi)
        var t = handTransform.translatedBy(x: -10, y: -1)
        transforms = []
        for id in order {
            let st = states[id]!
            t = t.translatedBy(x: st.x.pos, y: st.y.pos).rotated(by: st.ang.pos)
            transforms.append(t)
            t = t.translatedBy(x: 0, y: -boxSize.height)
        }
    }

    /// La X para quitar: esquina superior derecha de la caja (en coordenadas de la caja).
    private var closeRect: CGRect {
        let r = boxRect
        return CGRect(x: r.maxX - 19, y: r.minY + 3, width: 16, height: 16)
    }

    private func hitsClose(_ p: NSPoint, box i: Int) -> Bool {
        closeRect.insetBy(dx: -3, dy: -3).contains(p.applying(transforms[i].inverted()))
    }

    private var boxRect: CGRect {
        CGRect(x: -boxSize.width / 2, y: -boxSize.height, width: boxSize.width, height: boxSize.height)
    }

    private func boxIndex(at p: NSPoint) -> Int? {
        for i in transforms.indices.reversed() where !draggingIDs.contains(order[i]) {
            if boxRect.contains(p.applying(transforms[i].inverted())) { return i }
        }
        return nil
    }

    private func onHand(_ p: NSPoint) -> Bool {
        CGRect(x: -76, y: -16, width: 124, height: 48).contains(p.applying(handTransform.inverted()))
    }

    /// Zona (en coordenadas de la vista) que debe capturar el ratón; el resto deja pasar los clics.
    func interactiveRect() -> CGRect {
        var r = CGRect(x: -80, y: -20, width: 260, height: 170).applying(handTransform)
        for t in transforms { r = r.union(boxRect.insetBy(dx: -4, dy: -4).applying(t)) }
        return r
    }

    // MARK: Dibujo

    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        computeLayout()

        if dragActive {
            let top = CGPoint(x: 0, y: -boxSize.height * CGFloat(order.count) - 40).applying(handTransform)
            let colors = [NSColor.controlAccentColor.withAlphaComponent(dragHover ? 0.38 : 0.16).cgColor,
                          NSColor.controlAccentColor.withAlphaComponent(0).cgColor]
            let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1])!
            cg.drawRadialGradient(g, startCenter: top, startRadius: 0, endCenter: top, endRadius: dragHover ? 130 : 105, options: [])
        }

        cg.saveGState()
        cg.concatenate(handTransform)
        cg.setShadow(offset: CGSize(width: 0, height: -3), blur: 8, color: NSColor(white: 0, alpha: 0.28).cgColor)
        // Manga del camarero
        cg.saveGState()
        cg.addPath(Art.sleeve); cg.clip()
        cg.drawLinearGradient(Art.sleeveGrad, start: CGPoint(x: 40, y: 0), end: CGPoint(x: 160, y: 130), options: [])
        cg.restoreGState()
        // Puño de la camisa con gemelo
        cg.addPath(Art.cuff); cg.setFillColor(.white); cg.fillPath()
        cg.setShadow(offset: .zero, blur: 0, color: nil)
        cg.addPath(Art.cuff); cg.setStrokeColor(NSColor(hex: 0xD4D2CC).cgColor); cg.setLineWidth(1); cg.strokePath()
        cg.setFillColor(Art.gold); cg.fillEllipse(in: CGRect(x: 51.8, y: 7.8, width: 4.4, height: 4.4))
        // Guante
        cg.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: NSColor(white: 0, alpha: 0.22).cgColor)
        cg.addPath(Art.glove); cg.setFillColor(Art.gloveBottom); cg.fillPath()
        cg.setShadow(offset: .zero, blur: 0, color: nil)
        drawGlove(cg, Art.glove)
        cg.addPath(Art.fingerLines); cg.setStrokeColor(Art.lineColor); cg.setLineWidth(1.1); cg.setLineCap(.round); cg.strokePath()
        cg.restoreGState()

        // Cajas
        for (i, t) in transforms.enumerated() where !draggingIDs.contains(order[i]) {
            cg.saveGState()
            cg.concatenate(t)
            drawBox(cg, item: items[i], highlighted: hovered == i, isSelected: selected.contains(order[i]))
            cg.restoreGState()
        }

        // El pulgar va por delante de la primera caja: la sujeta.
        cg.saveGState()
        cg.concatenate(handTransform)
        drawGlove(cg, Art.thumb)
        cg.restoreGState()
    }

    private func drawGlove(_ cg: CGContext, _ path: CGPath) {
        cg.saveGState()
        cg.addPath(path); cg.clip()
        cg.drawLinearGradient(Art.gloveGrad, start: CGPoint(x: 0, y: -16), end: CGPoint(x: 0, y: 30), options: [])
        cg.restoreGState()
        cg.addPath(path); cg.setStrokeColor(Art.gloveStroke); cg.setLineWidth(1.3); cg.setLineJoin(.round); cg.strokePath()
    }

    private func drawBox(_ cg: CGContext, item: ShelfItem, highlighted: Bool, isSelected: Bool) {
        let s = boxSize.height / 64
        let r = boxRect
        let body = CGPath(roundedRect: r, cornerWidth: 5 * s, cornerHeight: 5 * s, transform: nil)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -2), blur: 5, color: NSColor(white: 0, alpha: 0.25).cgColor)
        cg.addPath(body); cg.setFillColor(Art.kraftBottom); cg.fillPath()
        cg.restoreGState()
        cg.saveGState()
        cg.addPath(body); cg.clip()
        cg.drawLinearGradient(Art.kraftGrad, start: CGPoint(x: 0, y: r.minY), end: CGPoint(x: 0, y: r.maxY), options: [])
        cg.setFillColor(Art.tape)
        cg.fill(CGRect(x: -7 * s, y: r.minY, width: 14 * s, height: 22 * s))
        cg.setStrokeColor(Art.kraftLine); cg.setLineWidth(1)
        cg.move(to: CGPoint(x: r.minX, y: r.minY + 12 * s)); cg.addLine(to: CGPoint(x: r.maxX, y: r.minY + 12 * s)); cg.strokePath()
        cg.restoreGState()
        if isSelected {
            cg.addPath(body); cg.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor); cg.fillPath()
        }
        cg.addPath(body)
        cg.setStrokeColor(isSelected || highlighted ? NSColor.controlAccentColor.cgColor : Art.kraftStroke)
        cg.setLineWidth(isSelected ? 3 : (highlighted ? 2 : 1.2))
        cg.strokePath()

        // Etiqueta blanca con la miniatura y el nombre
        let label = CGRect(x: -32 * s, y: r.minY + 17 * s, width: 64 * s, height: 42 * s)
        cg.addPath(CGPath(roundedRect: label, cornerWidth: 4 * s, cornerHeight: 4 * s, transform: nil))
        cg.setFillColor(NSColor(white: 1, alpha: 0.94).cgColor); cg.fillPath()
        if let img = thumbs[item.id] {
            let side = 24 * s
            img.draw(in: NSRect(x: -side / 2, y: label.minY + 3 * s, width: side, height: side),
                     from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingMiddle
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(6.5, 8.5 * s), weight: .medium),
            .foregroundColor: NSColor(hex: 0x3A3027),
            .paragraphStyle: para,
        ]
        (item.url.lastPathComponent as NSString).draw(in: NSRect(x: label.minX + 3 * s, y: label.minY + 28 * s,
                                                                 width: label.width - 6 * s, height: 12 * s),
                                                      withAttributes: attrs)

        if highlighted {
            // Botón X para quitar la caja sin tener que arrastrarla.
            let c = closeRect
            cg.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: NSColor(white: 0, alpha: 0.3).cgColor)
            cg.setFillColor(NSColor(hex: 0x3A3027, alpha: 0.88).cgColor)
            cg.fillEllipse(in: c)
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            cg.setStrokeColor(.white); cg.setLineWidth(1.8); cg.setLineCap(.round)
            let k: CGFloat = 4.2
            cg.move(to: CGPoint(x: c.midX - k, y: c.midY - k)); cg.addLine(to: CGPoint(x: c.midX + k, y: c.midY + k))
            cg.move(to: CGPoint(x: c.midX + k, y: c.midY - k)); cg.addLine(to: CGPoint(x: c.midX - k, y: c.midY + k))
            cg.strokePath()
        }
    }

    // MARK: Ratón: tocar, sacar, abrir

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let dx = lastMouse.map { p.x - $0.x } ?? 0
        lastMouse = p
        let i = boxIndex(at: p)
        if i != hovered {
            if let i = i, let st = states[order[i]] {
                // Al rozar una caja, se tambalea hacia donde la empujas.
                let push = abs(dx) > 0.5 ? max(-1.6, min(1.6, dx * 0.12)) : CGFloat.random(in: -0.8...0.8)
                st.ang.vel += push
                st.x.vel += push * 12
            }
            hovered = i
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil; lastMouse = nil; needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        downPoint = p
        if let i = boxIndex(at: p) {
            let id = order[i]
            if hovered == i && hitsClose(p, box: i) {
                // X: fuera del montón
                downTarget = nil
                Store.shared.remove(items[i])
                return
            }
            downTarget = i
            let flags = event.modifierFlags
            if flags.contains(.shift) || flags.contains(.command) {
                // Mayúsculas o ⌘ + clic: añadir o quitar de la selección
                if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
            } else if !selected.contains(id) {
                selected = [id]
            }
            if event.clickCount == 2 { NSWorkspace.shared.open(items[i].url) }
            if let st = states[id] { st.ang.vel += .random(in: -0.5...0.5) }
            needsDisplay = true
        } else if onHand(p) {
            downTarget = -1
            selected = []
            nudgeAll(0.4)
            needsDisplay = true
        } else {
            downTarget = nil
            if !selected.isEmpty { selected = []; needsDisplay = true }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint, let target = downTarget else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - start.x, p.y - start.y) > 3 else { return }
        downPoint = nil
        let chosen: [(Int, ShelfItem)]
        if target < 0 {
            chosen = items.enumerated().map { ($0.offset, $0.element) }                                // la mano: todo
        } else if selected.contains(order[target]) && selected.count > 1 {
            chosen = items.enumerated().filter { selected.contains($0.element.id) }.map { ($0.offset, $0.element) }
        } else {
            chosen = [(target, items[target])]                                   // solo esa caja
        }
        guard !chosen.isEmpty else { return }
        let dragItems: [NSDraggingItem] = chosen.enumerated().map { (k, pair) in
            let di = NSDraggingItem(pasteboardWriter: pair.1.url as NSURL)
            let img = thumbs[pair.1.id] ?? NSWorkspace.shared.icon(forFile: pair.1.url.path)
            let off = CGFloat(min(k, 6)) * 5
            di.setDraggingFrame(NSRect(x: p.x - 24 + off, y: p.y - 24 + off, width: 48, height: 48), contents: img)
            return di
        }
        draggingIDs = Set(chosen.map { $0.1.id })
        needsDisplay = true
        let session = beginDraggingSession(with: dragItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []   // siempre copia: el original nunca se mueve
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let ids = draggingIDs
        DispatchQueue.main.async {
            self.draggingIDs = []
            if operation != [], Prefs.removeAfterDrag {
                for it in Store.shared.items where ids.contains(it.id) { Store.shared.remove(it) }
            } else {
                self.nudgeAll(0.6)
            }
            self.needsDisplay = true
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = boxIndex(at: p) else { return nil }
        menuItem = items[i]
        let m = NSMenu()
        m.addItem(withTitle: "Abrir", action: #selector(openIt), keyEquivalent: "").target = self
        m.addItem(withTitle: "Mostrar en Finder", action: #selector(reveal), keyEquivalent: "").target = self
        m.addItem(withTitle: "Copiar", action: #selector(copyIt), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Quitar de la mano", action: #selector(removeIt), keyEquivalent: "").target = self
        return m
    }
    private var menuItem: ShelfItem?
    @objc private func openIt() { if let it = menuItem { NSWorkspace.shared.open(it.url) } }
    @objc private func reveal() { if let it = menuItem { NSWorkspace.shared.activateFileViewerSelecting([it.url]) } }
    @objc private func copyIt() {
        guard let it = menuItem else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        if it.isClip, it.url.pathExtension == "txt", let s = try? String(contentsOf: it.url, encoding: .utf8) {
            pb.setString(s, forType: .string)
        } else {
            pb.writeObjects([it.url as NSURL])
        }
    }
    @objc private func removeIt() { if let it = menuItem { Store.shared.remove(it) } }

    // MARK: Soltar encima

    private func isOurs(_ s: NSDraggingInfo) -> Bool { (s.draggingSource as? HandView) === self }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if isOurs(sender) { return [] }
        dragHover = true
        phi.vel += 0.25; dip.vel -= 40   // la mano "se prepara"
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { isOurs(sender) ? [] : .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { dragHover = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { dragHover = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dragHover = false
        return ingest(sender.draggingPasteboard)
    }
}

final class HandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: HandPanel!
    private var hand: HandView!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private let dragPB = NSPasteboard(name: .drag)
    private var baseline = 0
    private var dragActive = false
    private var frameCount = 0
    private var lastTime = CACurrentMediaTime()
    private let width: CGFloat = 250

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = HandPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hand = HandView(frame: NSRect(x: 0, y: 0, width: width, height: 600))
        panel.contentView = hand
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Art.menuBarImage()
        statusItem.button?.toolTip = "Hold It"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        Store.shared.onChange = { [weak self] in self?.modelChanged() }
        baseline = dragPB.changeCount
        place()
        hand.reload()
        updateVisibility()

        timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.frame() }
        RunLoop.main.add(timer!, forMode: .common)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.place() }

        // La primera vez, que se abra sola al encender el Mac.
        if !UserDefaults.standard.bool(forKey: "didSetupLogin") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "didSetupLogin")
        }
        // Actualizaciones automáticas: al arrancar y cada 6 horas.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { Updater.check() }
        let up = Timer(timeInterval: 6 * 3600, repeats: true) { _ in Updater.check() }
        RunLoop.main.add(up, forMode: .common)
    }

    private func frame() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(now - lastTime, 1.0 / 30))
        lastTime = now
        frameCount += 1

        if frameCount % 2 == 0 { watchDrag() }
        if frameCount % 120 == 0 { Store.shared.prune() }
        guard panel.isVisible else { return }

        // Dos sub-pasos por fotograma: física más estable.
        _ = hand.step(dt / 2)
        _ = hand.step(dt / 2)

        if !shouldShow && (hand.slide.pos > 0.97 || hand.goodbyeFinished) && panel.isVisible {
            panel.orderOut(nil)
            hand.cancelGoodbye()
            hand.slide.pos = 1
            hand.slide.vel = 0
            hadItems = false
        }

        // Fuera de la mano y las cajas, los clics pasan a lo que haya debajo.
        if dragActive {
            panel.ignoresMouseEvents = false
        } else {
            let m = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
            let p = hand.convert(m, from: nil)
            panel.ignoresMouseEvents = !hand.interactiveRect().contains(p)
        }
    }

    /// Detecta que estás arrastrando algo en cualquier app: el portapapeles de arrastre
    /// cambia mientras el botón del ratón está pulsado.
    private func watchDrag() {
        let pressed = (NSEvent.pressedMouseButtons & 1) == 1
        let cc = dragPB.changeCount
        if !pressed {
            baseline = cc
            if dragActive {
                dragActive = false
                hand.dragActive = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.updateVisibility() }
            }
        } else if cc != baseline && !dragActive {
            dragActive = true
            hand.dragActive = true
            if !panel.isVisible { place() }
            updateVisibility()
        }
    }

    private func modelChanged() {
        hand.reload()
        updateVisibility()
    }

    private var shouldShow: Bool { dragActive || !Store.shared.items.isEmpty || Prefs.alwaysVisible }

    private var hadItems = false

    private func updateVisibility() {
        if !Store.shared.items.isEmpty { hadItems = true }
        if shouldShow {
            hand.cancelGoodbye()
            if !panel.isVisible {
                hand.slide.pos = 1
                hand.phi.vel += 0.7          // entra con un pequeño "¡aquí estoy!"
                panel.orderFrontRegardless()
            }
            hand.slide.target = 0
        } else if hadItems {
            hand.startGoodbye()               // se despide y baja la escalera
        } else {
            hand.slide.target = 1             // arrastre sin soltar nada: se va sin más
        }
        hand.needsDisplay = true
    }

    private func mouseScreen() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func place() {
        // La mano sale a un tercio de la altura (por encima de los monos de Bolitas, que viven abajo a la derecha).
        let sf = mouseScreen().frame
        let vf = mouseScreen().visibleFrame
        let bottom = sf.minY + sf.height / 3 - 74
        let h = min(vf.maxY - bottom, 900)
        panel.setFrame(NSRect(x: sf.maxX - width, y: bottom, width: width, height: h), display: true)
        hand.needsDisplay = true
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
        let head = menu.addItem(withTitle: n == 0 ? "La mano está libre" : (n == 1 ? "Aguantando 1 cosa" : "Aguantando \(n) cosas"),
                                action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(.separator())
        add("Pegar en la mano", #selector(pasteIn))
        add("Soltarlo todo", #selector(clearAll))
        add("Sacudir", #selector(shake))
        menu.addItem(.separator())
        add("Mostrar siempre la mano", #selector(toggleAlways), on: Prefs.alwaysVisible)
        add("Quitar al arrastrar fuera", #selector(toggleRemove), on: Prefs.removeAfterDrag)
        add("Abrir al iniciar sesión", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled)
        menu.addItem(.separator())
        add("Buscar actualizaciones…", #selector(checkUpdates))
        let ver = menu.addItem(withTitle: Updater.versionText, action: nil, keyEquivalent: "")
        ver.isEnabled = false
        add("Salir de Hold It", #selector(quit), key: "q")
    }

    @objc private func pasteIn() { ingest(NSPasteboard.general) }
    @objc private func clearAll() { Store.shared.removeAll() }
    @objc private func shake() { hand.nudgeAll(1.4) }
    @objc private func toggleAlways() { Prefs.alwaysVisible.toggle(); if Prefs.alwaysVisible { place() }; updateVisibility() }
    @objc private func toggleRemove() { Prefs.removeAfterDrag.toggle() }
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
    @objc private func checkUpdates() { Updater.check(manual: true) }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
