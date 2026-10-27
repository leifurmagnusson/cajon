// Bolitas — «Club del billar»: gorilas trajeados con su portátil sobre una mesa de billar,
// cada uno bajo su lámpara verde. Abajo a la derecha está la puerta del club, con tu uso de Claude.
//   trabajando → la lámpara alumbra fuerte y teclea concentrado
//   te espera   → se recuesta y se enciende un puro; el humo sube despacio y se queda arriba de la pantalla
//   parado      → duerme con el sombrero tapándole los ojos

import AppKit

struct GorillaLook {
    var fur, face, vest, shirt, tie, hatColor, laptop: NSColor
    var hat: Int        // 0 nada · 1 fedora · 2 gorra plana · 3 bombín · 4 visera de crupier · 5 boina
    var neck: Int       // 0 pajarita · 1 corbata · 2 tirantes · 3 camisa abierta con cadena
    var shades: Bool
    var earring: Bool
    var toothpick: Bool
    var scar: Bool

    init(_ key: String) {
        var d = Dice(key + "gorila")
        let furs: [UInt32] = [0x2B2B30, 0x3A3A40, 0x4A4A52, 0x23232A, 0x5C4A3D, 0x6E6E78, 0x4E3B31, 0x2E3A4F, 0x51404F, 0x8A8A94, 0x3F4A3C]
        let faces: [UInt32] = [0x5A5560, 0x4A4048, 0x6B5E5A, 0x5D5258, 0x7A6A62, 0x4D4A55]
        let vests: [UInt32] = [0x7A1F2B, 0x1F3A5F, 0x2F4F3A, 0x3B2E5A, 0x5A4632, 0x1E1E24, 0x8C6D1F, 0x6B2D5C, 0x2B5F6B]
        let shirts: [UInt32] = [0xF4F1EA, 0xE8E2D0, 0xD9E4F5, 0xF5E1E1, 0xFFFFFF, 0x1E1E24]
        let ties: [UInt32] = [0xC1121F, 0x0F4C81, 0xE9C46A, 0x2A9D8F, 0x111111, 0x9D4EDD, 0xF77F00]
        let hats: [UInt32] = [0x1E1E24, 0x5A4632, 0x3B3B45, 0x7A1F2B, 0x2F4F3A, 0xC9B79C, 0x1F3A5F]
        let laps: [UInt32] = [0xC9CDD6, 0x2F2F36, 0xE8D9C0, 0x8FA8C8]
        fur = Palette.rgb(d.pick(furs)); face = Palette.rgb(d.pick(faces)); vest = Palette.rgb(d.pick(vests))
        shirt = Palette.rgb(d.pick(shirts)); tie = Palette.rgb(d.pick(ties)); hatColor = Palette.rgb(d.pick(hats)); laptop = Palette.rgb(d.pick(laps))
        hat = Int(d.next() % 6); neck = Int(d.next() % 4)
        shades = d.chance(0.3); earring = d.chance(0.2); toothpick = d.chance(0.3); scar = d.chance(0.18)
    }
}

final class GorilasView: StageView {
    static let cellW: CGFloat = 110, H: CGFloat = 220, floor: CGFloat = 204, doorW: CGFloat = 80, doorH: CGFloat = 160
    static let tableTop: CGFloat = 146
    override class var drawScale: CGFloat { 0.62 }
    private var looks: [String: GorillaLook] = [:]
    var usageLines: [String] = []
    var onDoorClick: (() -> Void)?

    override class func size(for count: Int) -> NSSize {
        let s = drawScale
        return NSSize(width: (30 + 130 + CGFloat(count + 1) * cellW + doorW + 54) * s, height: H * s)   // +1: siempre hay una silla libre
    }
    private func look(_ c: Chat) -> GorillaLook {
        if let l = looks[c.key] { return l }
        let l = GorillaLook(c.key); looks[c.key] = l; return l
    }
    private var W: CGFloat { bounds.width / GorilasView.drawScale }
    /// La puerta, de frente y cerrada, en la pared del fondo (a la derecha).
    private var doorRect: CGRect {
        let back = GorilasView.tableTop + 6
        return CGRect(x: W - GorilasView.doorW - 30, y: back - 140, width: GorilasView.doorW, height: 140)
    }
    private func slotX(_ i: Int) -> CGFloat {
        doorRect.minX - 22 - CGFloat(chats.count - i) * GorilasView.cellW + GorilasView.cellW / 2
    }

    /// Dónde cuelga cada lámpara (x en puntos de la ventana), para que Hold It dibuje sus anclajes en el techo.
    func lampXs() -> [CGFloat] {
        ([-1] + chats.indices.filter { age(chats[$0]) >= 1.6 }).map { slotX($0) * GorilasView.drawScale }
    }

    override func cabinets() -> [(Provider, CGRect)] {
        let x0 = slotX(-1) - GorilasView.cellW / 2 - 126
        let bottom = GorilasView.tableTop + 40
        return [(.claude, CGRect(x: x0, y: bottom - 84, width: 54, height: 84)),
                (.chatgpt, CGRect(x: x0 + 62, y: bottom - 84, width: 54, height: 84))]
    }

    override func actorIndex(at p: NSPoint) -> Int? {
        for i in chats.indices where abs(p.x - slotX(i)) < GorilasView.cellW / 2 && p.y > 30 { return i }
        return nil
    }
    /// Sale humo de la punta del puro.
    override func smokeSource(_ i: Int) -> NSPoint? {
        guard i < chats.count, chats[i].mood == .needsYou || chats[i].mood == .done, age(chats[i]) > 2.4 else { return nil }
        let k = GorilasView.drawScale
        return NSPoint(x: (slotX(i) + 36) * k, y: (headY(chats[i]) + 12) * k)
    }
    private func headY(_ c: Chat) -> CGFloat {
        switch c.mood {
        case .working: return 84 + sin(t * 4 + ph(c)) * 1.2
        case .needsYou, .done: return 80
        case .idle: return 94
        }
    }
    private func ph(_ c: Chat) -> CGFloat { CGFloat(seed(c.key) % 100) / 15 }

    override func mouseUp(with event: NSEvent) {
        let p = local(event)
        if doorRect.insetBy(dx: -6, dy: -6).contains(p) && actorIndex(at: p) == nil {
            if chats.isEmpty && needsPermission { onPlaceholderClick?() } else { onDoorClick?() }
            return
        }
        super.mouseUp(with: event)
    }

    // MARK: Escena

    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.clear(bounds)
        let k = GorilasView.drawScale
        cg.saveGState(); cg.scaleBy(x: k, y: k)
        cg.setLineCap(.round); cg.setLineJoin(.round)
        drawRoom(cg)
        drawDropHint(cg, CGRect(x: 2, y: 20, width: W - 4, height: GorilasView.H - 24))

        var open: CGFloat = 0
        for c in chats {
            let a = age(c)
            open = max(open, a < 0 ? 0 : a < 0.2 ? ease(a / 0.2) : a < 1.25 ? 1 : 1 - ease((a - 1.25) / 0.35))
        }
        drawDoor(cg, open: open)
        drawCabinets(cg)

        let seated = chats.enumerated().filter { age($0.element) >= 1.6 }
        // Lámparas (la de la silla libre, apagada)
        drawLamp(cg, x: slotX(-1), on: false, dim: true, ph: 1.3)
        for (i, c) in seated { drawLamp(cg, x: slotX(i), on: c.mood == .working, dim: c.mood == .idle, ph: ph(c)) }
        // Butacas de cuero: una por gorila y siempre una libre
        drawChair(cg, x: slotX(-1), empty: true)
        for (i, _) in chats.enumerated() { drawChair(cg, x: slotX(i), empty: false) }
        // Gorilas sentados (detrás de la mesa)
        for (i, c) in seated { drawGorilla(cg, c, i) }
        // Mesa de billar a lo largo
        if !chats.isEmpty || true { drawTable(cg) }
        for (i, c) in seated { drawFront(cg, c, i) }
        // Los que entran andando
        for (i, c) in chats.enumerated() where age(c) >= 0.25 && age(c) < 1.6 { drawWalking(cg, c, i) }

        if chats.isEmpty {
            pill(needsPermission ? "Dame permiso · toca la puerta" : "El club está vacío", center: CGPoint(x: doorRect.minX - 90, y: GorilasView.tableTop - 30), maxW: 240)
        }
        if let hp = hoverPoint, doorRect.contains(hp) { drawUsageCard(cg) }
        cg.restoreGState()
    }

    private var tableRect: CGRect {
        let left = slotX(-1) - GorilasView.cellW / 2 - 6
        return CGRect(x: max(6, left), y: GorilasView.tableTop, width: doorRect.minX - 14 - max(6, left), height: 34)
    }

    private func drawTable(_ cg: CGContext) {
        let r = tableRect
        let F = GorilasView.floor
        // Patas
        for lx in [r.minX + 14, r.maxX - 24] {
            rrect(cg, CGRect(x: lx, y: r.maxY - 4, width: 10, height: F - r.maxY + 2), 3, Palette.rgb(0x5A3A22), line: 2)
        }
        cg.setFillColor(NSColor.black.withAlphaComponent(0.14).cgColor)
        cg.fillEllipse(in: CGRect(x: r.minX, y: F - 4, width: r.width, height: 9))
        // Tapete verde (borde superior) y banda de madera
        rrect(cg, CGRect(x: r.minX, y: r.minY, width: r.width, height: 9), 3, Palette.rgb(0x1F7A4D), line: 2.2)
        rrect(cg, CGRect(x: r.minX - 4, y: r.minY + 8, width: r.width + 8, height: r.height - 8), 5, Palette.rgb(0x7A4A28), line: 2.4)
        // Vetas y troneras
        cg.setStrokeColor(Palette.rgb(0x5A3A22, 0.5).cgColor); cg.setLineWidth(1.2)
        cg.move(to: CGPoint(x: r.minX + 6, y: r.minY + 20)); cg.addLine(to: CGPoint(x: r.maxX - 6, y: r.minY + 20)); cg.strokePath()
        for px in [r.minX + 2, r.midX - 8, r.maxX - 18] {
            let pocket = CGMutablePath(); pocket.addArc(center: CGPoint(x: px + 8, y: r.minY + 8), radius: 7, startAngle: 0, endAngle: .pi, clockwise: false)
            fillStroke(cg, pocket, Palette.rgb(0x111111), line: 1.6)
        }
        // Rombos de nácar
        cg.setFillColor(Palette.rgb(0xF2E8CF).cgColor)
        var dx = r.minX + 40
        while dx < r.maxX - 30 {
            let dm = CGMutablePath(); dm.move(to: CGPoint(x: dx, y: r.minY + 25)); dm.addLine(to: CGPoint(x: dx + 4, y: r.minY + 28)); dm.addLine(to: CGPoint(x: dx, y: r.minY + 31)); dm.addLine(to: CGPoint(x: dx - 4, y: r.minY + 28)); dm.closeSubpath()
            cg.addPath(dm); cg.fillPath(); dx += 70
        }
        // Bolas sobre la mesa entre los gorilas
        let balls: [UInt32] = [0xFFD60A, 0x1D4ED8, 0xC1121F, 0x6A1B9A, 0xF77F00, 0x16A34A, 0x7F1D1D, 0x111111]
        var d = Dice("bolas")
        for i in 0...max(0, chats.count) {
            let bx = (chats.isEmpty ? r.midX : slotX(min(i, chats.count - 1)) + (i == chats.count ? 40 : -48))
            guard bx > r.minX + 10 && bx < r.maxX - 10 else { continue }
            let col = Palette.rgb(d.pick(balls))
            ellipse(cg, CGRect(x: bx - 6, y: r.minY - 11, width: 12, height: 12), col, line: 1.6)
            cg.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            cg.fillEllipse(in: CGRect(x: bx - 3, y: r.minY - 9, width: 4, height: 4))
        }
    }

    private func drawLamp(_ cg: CGContext, x: CGFloat, on: Bool, dim: Bool, ph: CGFloat) {
        let sway = sin(t * 0.7 + ph) * 1.2
        cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(1.6)
        cg.move(to: CGPoint(x: x, y: 0)); cg.addLine(to: CGPoint(x: x + sway, y: 20)); cg.strokePath()
        let lx = x + sway
        // Cono de luz
        let alpha: CGFloat = on ? 0.28 + 0.04 * sin(t * 7 + ph) : (dim ? 0.05 : 0.14)
        let cone = CGMutablePath()
        cone.move(to: CGPoint(x: lx - 14, y: 34)); cone.addLine(to: CGPoint(x: lx + 14, y: 34))
        cone.addLine(to: CGPoint(x: lx + 52, y: GorilasView.tableTop)); cone.addLine(to: CGPoint(x: lx - 52, y: GorilasView.tableTop)); cone.closeSubpath()
        cg.addPath(cone); cg.setFillColor(Palette.rgb(0xFFE7A3, alpha).cgColor); cg.fillPath()
        // Pantalla verde
        let shade = CGMutablePath()
        shade.move(to: CGPoint(x: lx - 8, y: 20)); shade.addLine(to: CGPoint(x: lx + 8, y: 20))
        shade.addLine(to: CGPoint(x: lx + 22, y: 36)); shade.addLine(to: CGPoint(x: lx - 22, y: 36)); shade.closeSubpath()
        fillStroke(cg, shade, Palette.rgb(0x1F6F45), line: 2)
        rrect(cg, CGRect(x: lx - 23, y: 34, width: 46, height: 4), 2, Palette.rgb(0xC9A227), line: 1.4)
        ellipse(cg, CGRect(x: lx - 6, y: 34, width: 12, height: 6), on ? Palette.rgb(0xFFF3C4) : Palette.rgb(0xBFB59A), line: 1.2)
    }

    private func drawDoor(_ cg: CGContext, open: CGFloat) {
        let r = doorRect
        let green = Palette.rgb(0x1E3D2F), greenL = Palette.rgb(0x2C5A45), brass = Palette.rgb(0xC9A227)
        rrect(cg, r.insetBy(dx: -7, dy: -7).offsetBy(dx: 0, dy: 3.5), 4, Palette.rgb(0x4A2E1A), line: 2.5)
        rrect(cg, r, 2, Palette.rgb(0x1A1410), line: 2)
        cg.setFillColor(NSColor.black.withAlphaComponent(0.12).cgColor)
        cg.fillEllipse(in: CGRect(x: r.minX - 10, y: r.maxY - 3, width: r.width + 20, height: 8))
        let w = r.width * (1 - 0.82 * open), skew = 10 * open
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.maxX - w, y: r.minY - skew)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - w, y: r.maxY + skew)); p.closeSubpath()
        fillStroke(cg, p, open > 0.5 ? greenL : green, line: 2.5)
        guard open < 0.35 else { return }
        // Ojo de buey con luz cálida
        let porth = CGRect(x: r.midX - 17, y: r.minY + 16, width: 34, height: 34)
        ellipse(cg, porth.insetBy(dx: -3, dy: -3), brass, line: 2)
        ellipse(cg, porth, Palette.rgb(0xF2C46D, 0.85 + 0.1 * sin(t * 2)), line: 1.6)
        cg.setStrokeColor(Palette.rgb(0x8A6A1F).cgColor); cg.setLineWidth(1.2)
        cg.move(to: CGPoint(x: porth.midX, y: porth.minY)); cg.addLine(to: CGPoint(x: porth.midX, y: porth.maxY))
        cg.move(to: CGPoint(x: porth.minX, y: porth.midY)); cg.addLine(to: CGPoint(x: porth.maxX, y: porth.midY)); cg.strokePath()
        // Placa con el nombre y el uso
        let plate = CGRect(x: r.minX + 11, y: r.minY + 62, width: r.width - 22, height: 18)
        rrect(cg, plate, 3, brass, line: 1.5)
        text("CLUB", Fonts.rounded(10, .black), Palette.rgb(0x2A1F1A), center: CGPoint(x: plate.midX, y: plate.midY))
        let usage = CGRect(x: r.minX + 11, y: r.minY + 88, width: r.width - 22, height: 40)
        rrect(cg, usage, 4, Palette.rgb(0x10241B), line: 1.6)
        let pcts = usageLines.compactMap { Rx.first($0, "[0-9]+ ?%") }
        if pcts.isEmpty {
            text("uso", Fonts.rounded(11, .heavy), Palette.rgb(0xC9A227), center: CGPoint(x: usage.midX, y: usage.midY))
        } else {
            text(pcts[0], Fonts.rounded(15, .black), Palette.rgb(0xF2C46D), center: CGPoint(x: usage.midX, y: usage.minY + 13))
            if pcts.count > 1 { text("sem " + pcts[1], Fonts.rounded(9, .heavy), Palette.rgb(0xC9A227), center: CGPoint(x: usage.midX, y: usage.minY + 30)) }
        }
        ellipse(cg, CGRect(x: r.minX + 7, y: r.midY + 26, width: 9, height: 9), brass, line: 1.8)
    }

    private func drawUsageCard(_ cg: CGContext) {
        let lines = usageLines.isEmpty ? ["Toca la puerta para", "ver tu uso de Claude"] : usageLines
        let font = Fonts.rounded(13, .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let w = (lines.map { ($0 as NSString).size(withAttributes: attrs).width }.max() ?? 80) + 22
        let h = CGFloat(lines.count) * 18 + 12
        let r = CGRect(x: max(4, min(doorRect.midX - w / 2, W - w - 4)), y: max(2, doorRect.minY - h - 8), width: w, height: h)
        rrect(cg, r, 8, Palette.rgb(0xFFF7E2), line: 2)
        for (k, l) in lines.enumerated() { text(l, font, Palette.outline, center: CGPoint(x: r.midX, y: r.minY + 15 + CGFloat(k) * 18)) }
    }

    // MARK: El gorila

    private func drawGorilla(_ cg: CGContext, _ c: Chat, _ i: Int) {
        let L = look(c)
        let x = slotX(i)
        let y = headY(c)
        let lean: CGFloat = (c.mood == .needsYou || c.mood == .done) ? -4 : 0
        drawBody(cg, L, x: x + lean, top: y + 24)
        drawHead(cg, L, x: x + lean, y: y, mood: c.mood, ph: ph(c))
    }

    /// Lo que va por delante de la mesa: portátil, manos, puro, nombre.
    private func drawFront(_ cg: CGContext, _ c: Chat, _ i: Int) {
        let L = look(c)
        let x = slotX(i)
        let y = headY(c)
        let a = age(c)
        let ph = self.ph(c)
        let T = GorilasView.tableTop
        let lidOpen: CGFloat = a < 2.3 ? ease((a - 1.6) / 0.7) : 1
        // Portátil (por detrás)
        let lidH = 30 * lidOpen
        if c.mood == .working && lidOpen > 0.9 {
            cg.setFillColor(Palette.rgb(0x9FD3FF, 0.10 + 0.05 * sin(t * 9 + ph)).cgColor)
            cg.fillEllipse(in: CGRect(x: x - 30, y: y - 10, width: 60, height: 40))
        }
        rrect(cg, CGRect(x: x - 30, y: T - 2 - lidH, width: 60, height: lidH), 5, L.laptop, line: 2.2)
        rrect(cg, CGRect(x: x - 33, y: T - 4, width: 66, height: 5), 2, (L.laptop.blended(withFraction: 0.25, of: .black) ?? L.laptop), line: 1.6)
        if lidOpen > 0.8 {
            // Logo: una bola ocho
            ellipse(cg, CGRect(x: x - 6, y: T - 25, width: 12, height: 12), Palette.rgb(0x111111), line: 1.2)
            ellipse(cg, CGRect(x: x - 3, y: T - 22, width: 6, height: 6), .white, line: 0)
            text("8", Fonts.rounded(5, .black), Palette.rgb(0x111111), center: CGPoint(x: x, y: T - 19))
        }
        let hand = L.face.blended(withFraction: 0.1, of: .black) ?? L.face
        switch c.mood {
        case .working:
            let l: CGFloat = sin(t * 16 + ph) > 0 ? 3 : -2
            let r: CGFloat = sin(t * 16 + ph + 1.7) > 0 ? 3 : -2
            ellipse(cg, CGRect(x: x - 42, y: T - 14 + l, width: 17, height: 13), hand, line: 1.8)
            ellipse(cg, CGRect(x: x + 25, y: T - 14 + r, width: 17, height: 13), hand, line: 1.8)
        case .needsYou, .done:
            // Brazos cruzados sobre la mesa, esperando
            rrect(cg, CGRect(x: x - 38, y: T - 13, width: 76, height: 12), 6, L.vest, line: 1.8)
            ellipse(cg, CGRect(x: x - 42, y: T - 15, width: 15, height: 13), hand, line: 1.6)
            ellipse(cg, CGRect(x: x + 27, y: T - 15, width: 15, height: 13), hand, line: 1.6)
            if c.mood == .needsYou {
                // tamborilea con los dedos, impaciente
                let tap = sin(t * 12 + ph) > 0 ? 2 : 0
                cg.setFillColor(hand.cgColor)
                for k in 0..<3 { cg.fillEllipse(in: CGRect(x: x + 30 + CGFloat(k) * 4, y: T - 4 - CGFloat(k == 1 ? tap : 0), width: 4, height: 4)) }
            }
        case .idle:
            ellipse(cg, CGRect(x: x - 40, y: T - 12, width: 16, height: 12), hand, line: 1.8)
            ellipse(cg, CGRect(x: x + 24, y: T - 12, width: 16, height: 12), hand, line: 1.8)
        }
        // Nombre y reloj en la banda de la mesa
        let waiting = c.mood == .needsYou || c.mood == .done
        pill(c.shortTitle, center: CGPoint(x: x, y: T + 22), maxW: GorilasView.cellW - 6,
             fill: waiting ? Palette.rgb(0xFFCC33) : (c.mood == .working ? Palette.rgb(0xB4F5B9) : Palette.rgb(0xF2E8CF)))
        var sub = ""
        switch c.mood {
        case .working: sub = elapsed(c.since)
        case .needsYou, .done: sub = ago(c.since)
        case .idle: break
        }
        if !sub.isEmpty { text(sub, Fonts.rounded(11, .black), Palette.rgb(0xF2E8CF), center: CGPoint(x: x - 8, y: T + 48), halo: Palette.rgb(0x2A1F1A)) }
        if c.mood == .idle { z(cg, x: x + 28, y: y - 28, ph: ph) }
        let bdg = CGRect(x: x + 40, y: T + 40, width: 16, height: 16)
        ellipse(cg, bdg, Palette.badge(c.provider), line: 1.6)
        text(c.provider.letter, Fonts.rounded(9, .black), .white, center: CGPoint(x: bdg.midX, y: bdg.midY))
    }

    private func drawBody(_ cg: CGContext, _ L: GorillaLook, x: CGFloat, top: CGFloat) {
        let T = GorilasView.tableTop
        // Hombros enormes de gorila
        let body = CGMutablePath()
        body.move(to: CGPoint(x: x - 46, y: T)); body.addCurve(to: CGPoint(x: x, y: top - 2), control1: CGPoint(x: x - 50, y: top + 6), control2: CGPoint(x: x - 30, y: top - 2))
        body.addCurve(to: CGPoint(x: x + 46, y: T), control1: CGPoint(x: x + 30, y: top - 2), control2: CGPoint(x: x + 50, y: top + 6)); body.closeSubpath()
        fillStroke(cg, body, L.shirt)
        cg.saveGState(); cg.addPath(body); cg.clip()
        // Chaleco
        let vl = CGMutablePath(); vl.move(to: CGPoint(x: x - 50, y: top)); vl.addLine(to: CGPoint(x: x - 8, y: top)); vl.addLine(to: CGPoint(x: x - 2, y: T)); vl.addLine(to: CGPoint(x: x - 50, y: T)); vl.closeSubpath()
        let vr = CGMutablePath(); vr.move(to: CGPoint(x: x + 50, y: top)); vr.addLine(to: CGPoint(x: x + 8, y: top)); vr.addLine(to: CGPoint(x: x + 2, y: T)); vr.addLine(to: CGPoint(x: x + 50, y: T)); vr.closeSubpath()
        if L.neck != 3 { fillStroke(cg, vl, L.vest, line: 1.8); fillStroke(cg, vr, L.vest, line: 1.8) }
        // Brazos peludos a los lados
        cg.setFillColor(L.fur.cgColor)
        cg.fillEllipse(in: CGRect(x: x - 62, y: top + 4, width: 26, height: 60)); cg.fillEllipse(in: CGRect(x: x + 36, y: top + 4, width: 26, height: 60))
        cg.restoreGState()
        cg.addPath(body); cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(2.2); cg.strokePath()
        switch L.neck {
        case 0: // pajarita
            let b = CGMutablePath()
            b.move(to: CGPoint(x: x, y: top + 6)); b.addLine(to: CGPoint(x: x - 10, y: top + 1)); b.addLine(to: CGPoint(x: x - 10, y: top + 11)); b.closeSubpath()
            b.move(to: CGPoint(x: x, y: top + 6)); b.addLine(to: CGPoint(x: x + 10, y: top + 1)); b.addLine(to: CGPoint(x: x + 10, y: top + 11)); b.closeSubpath()
            fillStroke(cg, b, L.tie, line: 1.5)
            ellipse(cg, CGRect(x: x - 3, y: top + 3, width: 6, height: 6), L.tie, line: 1.3)
        case 1: // corbata
            let tie = CGMutablePath()
            tie.move(to: CGPoint(x: x - 4, y: top + 2)); tie.addLine(to: CGPoint(x: x + 4, y: top + 2)); tie.addLine(to: CGPoint(x: x + 6, y: top + 30))
            tie.addLine(to: CGPoint(x: x, y: top + 38)); tie.addLine(to: CGPoint(x: x - 6, y: top + 30)); tie.closeSubpath()
            fillStroke(cg, tie, L.tie, line: 1.5)
        case 2: // tirantes
            cg.setStrokeColor(L.tie.cgColor); cg.setLineWidth(4)
            cg.move(to: CGPoint(x: x - 16, y: top + 2)); cg.addLine(to: CGPoint(x: x - 12, y: T))
            cg.move(to: CGPoint(x: x + 16, y: top + 2)); cg.addLine(to: CGPoint(x: x + 12, y: T)); cg.strokePath()
        default: // camisa abierta y cadena de oro
            ellipse(cg, CGRect(x: x - 12, y: top, width: 24, height: 20), L.fur, line: 1.4)
            cg.setStrokeColor(Palette.rgb(0xE9C46A).cgColor); cg.setLineWidth(2.4)
            cg.addArc(center: CGPoint(x: x, y: top + 4), radius: 14, startAngle: 0.3, endAngle: .pi - 0.3, clockwise: false); cg.strokePath()
        }
    }

    private func drawHead(_ cg: CGContext, _ L: GorillaLook, x: CGFloat, y: CGFloat, mood: Mood, ph: CGFloat) {
        // Orejas
        for s in [-1.0, 1.0] as [CGFloat] {
            ellipse(cg, CGRect(x: x + s * 31 - 6, y: y - 4, width: 12, height: 13), L.face)
        }
        if L.earring { ellipse(cg, CGRect(x: x + 30, y: y + 8, width: 6, height: 6), Palette.rgb(0xE9C46A), line: 1.4) }
        // Cráneo con cresta y mandíbula ancha
        let skull = CGMutablePath()
        skull.move(to: CGPoint(x: x - 30, y: y + 4))
        skull.addCurve(to: CGPoint(x: x, y: y - 40), control1: CGPoint(x: x - 31, y: y - 24), control2: CGPoint(x: x - 14, y: y - 42))
        skull.addCurve(to: CGPoint(x: x + 30, y: y + 4), control1: CGPoint(x: x + 14, y: y - 42), control2: CGPoint(x: x + 31, y: y - 24))
        skull.addCurve(to: CGPoint(x: x, y: y + 32), control1: CGPoint(x: x + 33, y: y + 26), control2: CGPoint(x: x + 16, y: y + 33))
        skull.addCurve(to: CGPoint(x: x - 30, y: y + 4), control1: CGPoint(x: x - 16, y: y + 33), control2: CGPoint(x: x - 33, y: y + 26))
        fillStroke(cg, skull, L.fur, line: 2.4)
        // Cara: frente + hocico
        let face = CGMutablePath()
        face.addRoundedRect(in: CGRect(x: x - 21, y: y - 16, width: 42, height: 18), cornerWidth: 9, cornerHeight: 9)
        face.addEllipse(in: CGRect(x: x - 20, y: y - 4, width: 40, height: 32))
        cg.addPath(face); cg.setFillColor(L.face.cgColor); cg.fillPath()
        cg.addPath(CGPath(ellipseIn: CGRect(x: x - 20, y: y - 4, width: 40, height: 32), transform: nil))
        cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(2); cg.strokePath()
        let hl = L.face.blended(withFraction: 0.25, of: .white) ?? L.face

        // Ojos pequeños bajo una ceja enorme
        let ey = y - 6
        let sleeping = mood == .idle
        if !sleeping {
            let lid: CGFloat = mood == .working ? 0.45 : (mood == .needsYou ? 0.15 : 0.55)
            let lookDown: CGFloat = mood == .working ? 1.5 : 0
            let lookSide: CGFloat = mood == .needsYou ? -1.5 : 0
            for s in [-1.0, 1.0] as [CGFloat] {
                let er = CGRect(x: x + s * 10 - 5, y: ey - 3.5, width: 10, height: 7.5)
                ellipse(cg, er, Palette.rgb(0xF2E8CF), line: 1.4)
                cg.setFillColor(Palette.rgb(0x2A1A10).cgColor)
                cg.fillEllipse(in: CGRect(x: x + s * 10 - 2.6 + lookSide, y: ey - 2.4 + lookDown, width: 5.2, height: 5.2))
                cg.saveGState(); cg.addEllipse(in: er); cg.clip()
                cg.setFillColor(L.face.cgColor); cg.fill(CGRect(x: er.minX, y: er.minY, width: er.width, height: er.height * lid))
                cg.restoreGState()
            }
        } else {
            cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(1.8)
            for s in [-1.0, 1.0] as [CGFloat] {
                cg.move(to: CGPoint(x: x + s * 10 - 5, y: ey + 1)); cg.addQuadCurve(to: CGPoint(x: x + s * 10 + 5, y: ey + 1), control: CGPoint(x: x + s * 10, y: ey + 4))
            }
            cg.strokePath()
        }
        // Ceja: un saliente gordo
        let brow = CGMutablePath()
        brow.move(to: CGPoint(x: x - 24, y: ey - 3))
        brow.addQuadCurve(to: CGPoint(x: x, y: ey - 5 + (mood == .needsYou ? 3 : 0)), control: CGPoint(x: x - 12, y: ey - 14))
        brow.addQuadCurve(to: CGPoint(x: x + 24, y: ey - 3), control: CGPoint(x: x + 12, y: ey - 14))
        brow.addQuadCurve(to: CGPoint(x: x - 24, y: ey - 3), control: CGPoint(x: x, y: ey - 9))
        fillStroke(cg, brow, L.fur.blended(withFraction: 0.2, of: .black) ?? L.fur, line: 1.6)
        if L.scar {
            cg.setStrokeColor(hl.cgColor); cg.setLineWidth(1.6)
            cg.move(to: CGPoint(x: x + 12, y: ey - 12)); cg.addLine(to: CGPoint(x: x + 16, y: ey + 6)); cg.strokePath()
        }
        // Nariz ancha y chata
        let nose = CGMutablePath(); nose.addRoundedRect(in: CGRect(x: x - 11, y: y + 1, width: 22, height: 11), cornerWidth: 5.5, cornerHeight: 5.5)
        fillStroke(cg, nose, hl, line: 1.6)
        cg.setFillColor(Palette.rgb(0x1A1418).cgColor)
        cg.fillEllipse(in: CGRect(x: x - 8, y: y + 6, width: 6, height: 4.5)); cg.fillEllipse(in: CGRect(x: x + 2, y: y + 6, width: 6, height: 4.5))
        // Boca
        let my = y + 20
        cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(2)
        cg.move(to: CGPoint(x: x - 13, y: my)); cg.addQuadCurve(to: CGPoint(x: x + 13, y: my), control: CGPoint(x: x, y: my + (mood == .working ? -1 : 2)))
        cg.strokePath()
        if L.toothpick && mood == .working {
            cg.setStrokeColor(Palette.rgb(0xE8D2A6).cgColor); cg.setLineWidth(1.6)
            cg.move(to: CGPoint(x: x - 9, y: my)); cg.addLine(to: CGPoint(x: x - 22, y: my + 4)); cg.strokePath()
        }
        // Gafas de sol
        if L.shades && !sleeping {
            rrect(cg, CGRect(x: x - 21, y: ey - 5, width: 19, height: 10), 3, Palette.rgb(0x111114), line: 1.6)
            rrect(cg, CGRect(x: x + 2, y: ey - 5, width: 19, height: 10), 3, Palette.rgb(0x111114), line: 1.6)
            cg.setFillColor(NSColor.white.withAlphaComponent(0.5).cgColor)
            cg.fill(CGRect(x: x - 17, y: ey - 3, width: 6, height: 1.6)); cg.fill(CGRect(x: x + 6, y: ey - 3, width: 6, height: 1.6))
        }
        // Puro cuando te espera
        if mood == .needsYou || mood == .done {
            cg.saveGState()
            cg.translateBy(x: x + 10, y: my); cg.rotate(by: -0.22)
            rrect(cg, CGRect(x: 0, y: -2.5, width: 26, height: 6), 3, Palette.rgb(0x6B4423), line: 1.4)
            cg.setFillColor(Palette.rgb(0xC9A227).cgColor); cg.fill(CGRect(x: 5, y: -2.5, width: 4, height: 6))
            ellipse(cg, CGRect(x: 23, y: -2.5, width: 6, height: 6), Palette.rgb(0xFF6A1A, 0.75 + 0.25 * sin(t * 3 + ph)), line: 1)
            cg.restoreGState()
        }
        drawHat(cg, L, x: x, y: y, sleeping: sleeping)
    }

    private func drawHat(_ cg: CGContext, _ L: GorillaLook, x: CGFloat, y: CGFloat, sleeping: Bool) {
        // Dormido: el sombrero se le cae sobre los ojos
        let top = y - 38 + (sleeping && L.hat != 0 ? 16 : 0)
        switch L.hat {
        case 1: // fedora
            rrect(cg, CGRect(x: x - 38, y: top + 12, width: 76, height: 8), 4, L.hatColor)
            let crown = CGMutablePath()
            crown.move(to: CGPoint(x: x - 22, y: top + 14)); crown.addLine(to: CGPoint(x: x - 18, y: top - 8))
            crown.addQuadCurve(to: CGPoint(x: x + 18, y: top - 8), control: CGPoint(x: x, y: top + 2))
            crown.addLine(to: CGPoint(x: x + 22, y: top + 14)); crown.closeSubpath()
            fillStroke(cg, crown, L.hatColor)
            cg.setFillColor(L.tie.cgColor); cg.fill(CGRect(x: x - 21, y: top + 6, width: 42, height: 5))
        case 2: // gorra plana
            let cap = CGMutablePath()
            cap.move(to: CGPoint(x: x - 28, y: top + 16)); cap.addQuadCurve(to: CGPoint(x: x + 24, y: top + 6), control: CGPoint(x: x - 6, y: top - 10))
            cap.addLine(to: CGPoint(x: x + 34, y: top + 14)); cap.addQuadCurve(to: CGPoint(x: x - 28, y: top + 16), control: CGPoint(x: x, y: top + 22)); cap.closeSubpath()
            fillStroke(cg, cap, L.hatColor)
        case 3: // bombín
            rrect(cg, CGRect(x: x - 30, y: top + 12, width: 60, height: 7), 3.5, L.hatColor)
            let dome = CGMutablePath(); dome.addArc(center: CGPoint(x: x, y: top + 13), radius: 20, startAngle: .pi, endAngle: 0, clockwise: false); dome.closeSubpath()
            fillStroke(cg, dome, L.hatColor)
        case 4: // visera verde de crupier
            let v = CGMutablePath()
            v.move(to: CGPoint(x: x - 26, y: top + 18)); v.addLine(to: CGPoint(x: x + 26, y: top + 18))
            v.addLine(to: CGPoint(x: x + 32, y: top + 28)); v.addLine(to: CGPoint(x: x - 32, y: top + 28)); v.closeSubpath()
            fillStroke(cg, v, Palette.rgb(0x2E8B57, 0.85))
            cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(2.5)
            cg.move(to: CGPoint(x: x - 26, y: top + 18)); cg.addLine(to: CGPoint(x: x + 26, y: top + 18)); cg.strokePath()
        case 5: // boina
            ellipse(cg, CGRect(x: x - 30, y: top - 2, width: 54, height: 18), L.hatColor)
            ellipse(cg, CGRect(x: x - 3, y: top - 6, width: 5, height: 6), Palette.outline, line: 0)
        default: break
        }
    }

    private func drawWalking(_ cg: CGContext, _ c: Chat, _ i: Int) {
        let L = look(c)
        let a = age(c)
        let k = ease((a - 0.25) / 1.35)
        let x = lerp(doorRect.midX - 14, slotX(i), k)
        let walk = a * 8
        // Sale del fondo de la puerta: empieza pequeño y crece al acercarse
        let depth = 0.72 + 0.28 * k
        cg.saveGState()
        cg.translateBy(x: x, y: GorilasView.floor); cg.scaleBy(x: depth, y: depth); cg.translateBy(x: -x, y: -GorilasView.floor)
        defer { cg.restoreGState() }
        let bob = abs(sin(walk)) * 3
        let F = GorilasView.floor
        cg.setFillColor(NSColor.black.withAlphaComponent(0.14).cgColor)
        cg.fillEllipse(in: CGRect(x: x - 26, y: F - 4, width: 52, height: 8))
        // Piernas cortas, nudillos al suelo (como los gorilas de verdad)
        let sw = sin(walk) * 6
        rrect(cg, CGRect(x: x - 20 + sw, y: 160 - bob, width: 16, height: F - 160 + bob - 2), 7, Palette.rgb(0x2A2A30))
        rrect(cg, CGRect(x: x + 4 - sw, y: 160 - bob, width: 16, height: F - 160 + bob - 2), 7, Palette.rgb(0x2A2A30))
        drawBody(cg, L, x: x, top: 112 - bob)
        rrect(cg, CGRect(x: x - 46, y: 112 - bob, width: 92, height: 50), 20, L.vest, line: 2.2)
        drawHead(cg, L, x: x, y: 90 - bob, mood: .working, ph: 0)
        // portátil bajo el brazo
        rrect(cg, CGRect(x: x + 40, y: 128 - bob, width: 12, height: 34), 3, L.laptop, line: 1.8)
        pill(c.shortTitle, center: CGPoint(x: x, y: GorilasView.tableTop + 22), maxW: GorilasView.cellW - 6)
    }

    // MARK: El salón (pared, suelo en perspectiva y butacas)

    private func drawRoom(_ cg: CGContext) {
        let F = GorilasView.floor, H = GorilasView.H
        let back: CGFloat = GorilasView.tableTop + 6      // donde la pared toca el suelo
        let left = max(0, slotX(-1) - GorilasView.cellW / 2 - 140)
        // Pared del fondo: papel pintado verde oscuro con rayas y zócalo de madera
        let wall = CGRect(x: left, y: 0, width: W - left, height: back)
        cg.setFillColor(Palette.rgb(0x1E3A2C).cgColor); cg.fill(wall)
        cg.setFillColor(Palette.rgb(0x24473A).cgColor)
        var sx = left + 6
        while sx < W { cg.fill(CGRect(x: sx, y: 0, width: 7, height: back)); sx += 18 }
        cg.setFillColor(Palette.rgb(0x5A3A22).cgColor); cg.fill(CGRect(x: left, y: back - 30, width: W - left, height: 30))
        cg.setFillColor(Palette.rgb(0x7A4A28).cgColor); cg.fill(CGRect(x: left, y: back - 32, width: W - left, height: 4))
        // Pared de la derecha en perspectiva (donde está la puerta)
        let sideX = doorRect.maxX + 12
        let side = CGMutablePath()
        side.move(to: CGPoint(x: sideX, y: 0)); side.addLine(to: CGPoint(x: W, y: 0))
        side.addLine(to: CGPoint(x: W, y: H)); side.addLine(to: CGPoint(x: sideX, y: back)); side.closeSubpath()
        cg.addPath(side); cg.setFillColor(Palette.rgb(0x183024).cgColor); cg.fillPath()
        // Suelo de tablones en perspectiva
        let floor = CGMutablePath()
        floor.move(to: CGPoint(x: left, y: back)); floor.addLine(to: CGPoint(x: sideX, y: back))
        floor.addLine(to: CGPoint(x: W, y: H)); floor.addLine(to: CGPoint(x: max(0, left - 30), y: H)); floor.closeSubpath()
        cg.addPath(floor); cg.setFillColor(Palette.rgb(0x8A5A33).cgColor); cg.fillPath()
        cg.saveGState(); cg.addPath(floor); cg.clip()
        cg.setStrokeColor(Palette.rgb(0x5A3A22, 0.55).cgColor); cg.setLineWidth(1.2)
        let vp = CGPoint(x: (left + sideX) / 2, y: back - 120)       // punto de fuga
        var fx = left - 200
        while fx < W + 200 {
            cg.move(to: CGPoint(x: fx, y: H)); cg.addLine(to: vp); fx += 34
        }
        cg.strokePath()
        for (k, yy) in [back + 10, back + 26, back + 48].enumerated() where yy < H {
            cg.setStrokeColor(Palette.rgb(0x5A3A22, 0.25 + 0.1 * CGFloat(k)).cgColor)
            cg.move(to: CGPoint(x: 0, y: yy)); cg.addLine(to: CGPoint(x: W, y: yy)); cg.strokePath()
        }
        cg.restoreGState()
        // Alfombra granate bajo la mesa
        let rug = CGMutablePath()
        let rl = tableRect.minX - 10, rr = tableRect.maxX + 10
        rug.move(to: CGPoint(x: rl + 12, y: back + 4)); rug.addLine(to: CGPoint(x: rr - 4, y: back + 4))
        rug.addLine(to: CGPoint(x: rr + 10, y: F + 8)); rug.addLine(to: CGPoint(x: rl - 6, y: F + 8)); rug.closeSubpath()
        cg.addPath(rug); cg.setFillColor(Palette.rgb(0x6B1E24, 0.85).cgColor); cg.fillPath()
        cg.addPath(rug); cg.setStrokeColor(Palette.rgb(0xC9A227, 0.6).cgColor); cg.setLineWidth(1.6); cg.strokePath()
        _ = F
    }

    /// Butaca de cuero (respaldo capitoné que asoma por detrás de los hombros).
    private func drawChair(_ cg: CGContext, x: CGFloat, empty: Bool) {
        let T = GorilasView.tableTop
        let back = CGRect(x: x - 40, y: T - 78, width: 80, height: 78)
        rrect(cg, back, 18, Palette.rgb(empty ? 0x7A3B1E : 0x6A3219), line: 2.2)
        cg.setFillColor(Palette.rgb(0x4A2210, 0.7).cgColor)
        for row in 0..<2 { for col in 0..<3 {
            cg.fillEllipse(in: CGRect(x: x - 24 + CGFloat(col) * 22 + (row == 1 ? 11 : 0) - (row == 1 && col == 2 ? 44 : 0), y: T - 64 + CGFloat(row) * 18, width: 4, height: 4))
        } }
        // Brazos
        rrect(cg, CGRect(x: x - 50, y: T - 36, width: 18, height: 36), 8, Palette.rgb(0x5A2A15), line: 2)
        rrect(cg, CGRect(x: x + 32, y: T - 36, width: 18, height: 36), 8, Palette.rgb(0x5A2A15), line: 2)
        if empty {
            pill("libre", center: CGPoint(x: x, y: T + 22), maxW: GorilasView.cellW - 20, fill: Palette.rgb(0xF2E8CF))
        }
    }

}
