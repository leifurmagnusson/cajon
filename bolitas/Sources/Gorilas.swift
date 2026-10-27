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
        let laps: [UInt32] = [0xC9CDD6]
        fur = Palette.rgb(d.pick(furs)); face = Palette.rgb(d.pick(faces)); vest = Palette.rgb(d.pick(vests))
        shirt = Palette.rgb(d.pick(shirts)); tie = Palette.rgb(d.pick(ties)); hatColor = Palette.rgb(d.pick(hats)); laptop = Palette.rgb(d.pick(laps))
        hat = Int(d.next() % 6); neck = Int(d.next() % 4)
        shades = d.chance(0.3); earring = d.chance(0.2); toothpick = d.chance(0.3); scar = d.chance(0.18)
    }
}

final class GorilasView: StageView, NSDraggingSource {
    static let cellW: CGFloat = 110, H: CGFloat = 220, floor: CGFloat = 204, doorW: CGFloat = 80, doorH: CGFloat = 160
    static let tableTop: CGFloat = 146
    override class var drawScale: CGFloat { 0.62 }
    private var looks: [String: GorillaLook] = [:]
    var usageLines: [String] = []
    var onDoorClick: (() -> Void)?

    static let sideW: CGFloat = 64          // ancho de las paredes laterales en perspectiva
    static let topPad: CGFloat = 46          // fondo de la sala (pasillo por detrás de los gorilas)
    static let backLine: CGFloat = 152       // donde la pared del fondo toca el suelo
    static let roofH: CGFloat = 78           // tejado con la rana y sus cajas
    override var drawOffsetY: CGFloat { GorilasView.topPad + GorilasView.roofH }
    override class func size(for count: Int) -> NSSize {
        let s = drawScale
        return NSSize(width: (40 + 290 + CGFloat(max(1, count)) * cellW + 170) * s, height: (H + topPad + roofH) * s)
    }
    private func look(_ c: Chat) -> GorillaLook {
        if let l = looks[c.key] { return l }
        let l = GorillaLook(c.key); looks[c.key] = l; return l
    }
    private var W: CGFloat { bounds.width / GorilasView.drawScale }
    /// La puerta, al fondo de la sala (más pequeña porque está lejos), cerrada salvo cuando alguien entra o sale.
    private var doorRect: CGRect {
        CGRect(x: W - GorilasView.sideW - 84, y: GorilasView.backLine - 130, width: 64, height: 130)
    }
    private func slotX(_ i: Int) -> CGFloat { slotX(i, count: chats.count) }
    private func slotX(_ i: Int, count: Int) -> CGFloat {
        doorRect.minX - 30 - CGFloat(count - i) * GorilasView.cellW + GorilasView.cellW / 2
    }
    override func seatX(_ i: Int, count: Int) -> CGFloat? { slotX(i, count: count) }

    /// Dónde cuelga cada lámpara (x en puntos de la ventana), para que Hold It dibuje sus anclajes en el techo.
    func lampXs() -> [CGFloat] {
        chats.indices.filter { age(chats[$0]) >= GorilasView.sitAt }.map { slotX($0) * GorilasView.drawScale }
    }

    override func cabinets() -> [(Provider, CGRect)] {
        let x0 = tableRect.minX - 232
        let bottom = GorilasView.tableTop + 40
        return [(.claude, CGRect(x: x0, y: bottom - 84, width: 54, height: 84)),
                (.chatgpt, CGRect(x: x0 + 62, y: bottom - 84, width: 54, height: 84))]
    }

    override func microphone() -> CGRect? {
        CGRect(x: tableRect.minX - 104, y: GorilasView.tableTop - 62, width: 80, height: 102)
    }
    static let sitAt: CGFloat = 2.3      // a partir de aquí ya está sentado

    override func actorIndex(at p: NSPoint) -> Int? {
        for i in chats.indices where abs(p.x - slotX(i)) < GorilasView.cellW / 2 && p.y > 30 { return i }
        return nil
    }
    /// Sale humo de la punta del puro.
    override func smokeSource(_ i: Int) -> NSPoint? {
        guard i < chats.count, chats[i].mood == .needsYou, age(chats[i]) > GorilasView.sitAt + 0.5 else { return nil }
        let k = GorilasView.drawScale
        return NSPoint(x: (slotX(i) + 36) * k, y: (headY(chats[i]) + 12 + drawOffsetY) * k)
    }
    private func headY(_ c: Chat) -> CGFloat {
        switch c.mood {
        case .working: return 84 + sin(t * 4 + ph(c)) * 1.2
        case .needsYou, .done: return 80
        case .idle: return 94
        }
    }
    private func ph(_ c: Chat) -> CGFloat { CGFloat(seed(c.key) % 100) / 15 }


    // MARK: Escena

    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.clear(bounds)
        let k = GorilasView.drawScale
        cg.saveGState(); cg.scaleBy(x: k, y: k)
        cg.translateBy(x: 0, y: drawOffsetY)
        cg.setLineCap(.round); cg.setLineJoin(.round)
        drawRoom(cg)
        drawRoof(cg)
        drawDropHint(cg, CGRect(x: 2, y: 20 - GorilasView.topPad, width: W - 4, height: GorilasView.H + GorilasView.topPad - 24))

        // La puerta se abre cuando alguien entra o sale, y luego se cierra.
        var open: CGFloat = 0
        for c in chats {
            let a = age(c)
            open = max(open, a < 0 ? 0 : a < 0.25 ? ease(a / 0.25) : a < 0.9 ? 1 : 1 - ease((a - 0.9) / 0.35))
        }
        for l in leaving {
            let a = t - l.start
            open = max(open, a < 1.7 ? 0 : a < 1.95 ? ease((a - 1.7) / 0.25) : a < 2.5 ? 1 : 1 - ease((a - 2.5) / 0.35))
        }
        drawDoor(cg, open: open)
        drawCabinets(cg)

        // Pasillo del fondo: los que entran o salen pasan por detrás de todos.
        for (i, c) in chats.enumerated() where age(c) >= 0 && age(c) < GorilasView.sitAt {
            let a = age(c)
            let k2 = ease((a - 0.3) / 1.6)
            if a >= 0.15 { drawWalking(cg, c, x: lerp(doorRect.midX, slotX(i), k2), walk: a * 8, depth: 0.66, alpha: min(1, (a - 0.15) / 0.2)) }
        }
        for l in leaving {
            let a = t - l.start
            guard a < 2.3 else { continue }
            let k2 = ease((a - 0.2) / 1.6)
            drawWalking(cg, l.chat, x: lerp(l.x, doorRect.midX, k2), walk: a * 8, depth: 0.66, alpha: a > 2.0 ? max(0, 1 - (a - 2.0) / 0.3) : 1)
        }

        let seated = chats.enumerated().filter { age($0.element) >= GorilasView.sitAt }
        drawMicrophone(cg)
        for (i, c) in seated { drawLamp(cg, x: slotX(i), on: c.mood == .working, dim: c.mood == .idle, ph: ph(c)) }
        // Butacas de cuero, una por gorila
        for (i, c) in chats.enumerated() where age(c) >= 0.3 { drawChair(cg, x: slotX(i), empty: false) }
        for (i, c) in seated { drawGorilla(cg, c, i) }
        drawTable(cg)
        for (i, c) in seated { drawFront(cg, c, i) }

        if chats.isEmpty {
            pill(needsPermission ? "Dame permiso · toca la puerta" : "El club está vacío", center: CGPoint(x: doorRect.minX - 90, y: GorilasView.tableTop - 30), maxW: 240)
        }
        if let hp = hoverPoint, doorRect.contains(hp) { drawUsageCard(cg) }
        cg.restoreGState()
    }

    private var tableRect: CGRect {
        let left = chats.isEmpty ? doorRect.minX - 30 - GorilasView.cellW - 6 : slotX(0) - GorilasView.cellW / 2 - 6
        return CGRect(x: left, y: GorilasView.tableTop, width: doorRect.minX - 24 - left, height: 34)
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
        cg.move(to: CGPoint(x: x, y: -GorilasView.topPad)); cg.addLine(to: CGPoint(x: x + sway, y: 20)); cg.strokePath()
        let lx = x + sway
        // Cono de luz
        let alpha: CGFloat = on ? 0.42 + 0.04 * sin(t * 7 + ph) : (dim ? 0.05 : 0.14)
        if on {
            // Mesa bien iluminada bajo la lámpara
            let cs = CGColorSpaceCreateDeviceRGB()
            if let g = CGGradient(colorsSpace: cs, colors: [Palette.rgb(0xFFE7A3, 0.55).cgColor, Palette.rgb(0xFFE7A3, 0).cgColor] as CFArray, locations: [0, 1]) {
                cg.drawRadialGradient(g, startCenter: CGPoint(x: lx, y: GorilasView.tableTop - 30), startRadius: 0,
                                      endCenter: CGPoint(x: lx, y: GorilasView.tableTop - 30), endRadius: 70, options: [])
            }
        }
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
        let lidOpen: CGFloat = a < GorilasView.sitAt + 0.6 ? ease((a - GorilasView.sitAt) / 0.6) : 1
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
        case .done:
            // Ya ha terminado: te saluda y juega con una bola de billar para que lo veas
            ellipse(cg, CGRect(x: x - 42, y: T - 14, width: 17, height: 13), hand, line: 1.8)
            drawHello(cg, handX: x + 38, handY: y - 14, ballX: x - 30, floorY: T, ph: ph, hand: hand)
        case .needsYou:
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
        if mood == .needsYou {
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

    /// Gorila andando por el pasillo del fondo (más pequeño porque está lejos), con el portátil bajo el brazo.
    private func drawWalking(_ cg: CGContext, _ c: Chat, x: CGFloat, walk: CGFloat, depth: CGFloat, alpha: CGFloat) {
        let L = look(c)
        let F = GorilasView.floor
        cg.saveGState()
        cg.setAlpha(alpha)
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        cg.translateBy(x: x, y: GorilasView.backLine); cg.scaleBy(x: depth, y: depth); cg.translateBy(x: -x, y: -F)
        let bob = abs(sin(walk)) * 3
        cg.setFillColor(NSColor.black.withAlphaComponent(0.14).cgColor)
        cg.fillEllipse(in: CGRect(x: x - 26, y: F - 4, width: 52, height: 8))
        let sw = sin(walk) * 6
        rrect(cg, CGRect(x: x - 20 + sw, y: 160 - bob, width: 16, height: F - 160 + bob - 2), 7, Palette.rgb(0x2A2A30))
        rrect(cg, CGRect(x: x + 4 - sw, y: 160 - bob, width: 16, height: F - 160 + bob - 2), 7, Palette.rgb(0x2A2A30))
        drawBody(cg, L, x: x, top: 112 - bob)
        rrect(cg, CGRect(x: x - 46, y: 112 - bob, width: 92, height: 50), 20, L.vest, line: 2.2)
        drawHead(cg, L, x: x, y: 90 - bob, mood: .working, ph: 0)
        rrect(cg, CGRect(x: x + 40, y: 128 - bob, width: 12, height: 34), 3, L.laptop, line: 1.8)
        cg.endTransparencyLayer()
        cg.restoreGState()
    }

    // MARK: El salón (pared, suelo en perspectiva y butacas)

    // MARK: Tejado con la rana

    private var roomLeft: CGFloat { max(0, tableRect.minX - 254) }
    private var roofTop: CGFloat { -GorilasView.topPad - GorilasView.roofH + 26 }
    private var frogX: CGFloat { W - 62 }
    private var items: [ShelfItem] { ShelfStore.shared.items }
    private func boxRect(_ i: Int) -> CGRect {
        CGRect(x: roomLeft + 74 + CGFloat(i) * 40, y: roofTop - 30, width: 34, height: 30)
    }
    private func boxIndex(at p: NSPoint) -> Int? {
        let n = min(items.count, maxBoxes)
        return (0..<n).first { boxRect($0).insetBy(dx: -2, dy: -2).contains(p) }
    }
    private var maxBoxes: Int { max(1, Int((frogX - 50 - roomLeft - 74) / 40)) }

    /// Boca de la rana en coordenadas de pantalla (para la lengua).
    func frogMouthScreen() -> NSPoint? {
        guard let w = window else { return nil }
        let k = GorilasView.drawScale
        let p = NSPoint(x: (frogX - 16) * k, y: (roofTop - 14 + drawOffsetY) * k)
        return w.convertPoint(toScreen: convert(p, to: nil))
    }

    private func drawRoof(_ cg: CGContext) {
        let left = roomLeft, base = -GorilasView.topPad, top = roofTop
        let roof = CGMutablePath()
        roof.move(to: CGPoint(x: left - 6, y: base)); roof.addLine(to: CGPoint(x: W + 2, y: base))
        roof.addLine(to: CGPoint(x: W - 26, y: top)); roof.addLine(to: CGPoint(x: left + 24, y: top)); roof.closeSubpath()
        fillStroke(cg, roof, Palette.rgb(0xB5562F), line: 2.2)
        // Tejas
        cg.saveGState(); cg.addPath(roof); cg.clip()
        cg.setStrokeColor(Palette.rgb(0x8A3A1C).cgColor); cg.setLineWidth(1.6)
        var row = top + 10
        var shift: CGFloat = 0
        while row < base + 4 {
            var x = left - 20 + shift
            while x < W + 20 {
                cg.addArc(center: CGPoint(x: x + 9, y: row), radius: 9, startAngle: 0, endAngle: .pi, clockwise: false)
                cg.strokePath(); x += 18
            }
            row += 11; shift = shift == 0 ? 9 : 0
        }
        cg.restoreGState()
        // Chimenea
        let ch = CGRect(x: left + 34, y: top - 30, width: 26, height: 34)
        rrect(cg, ch, 2, Palette.rgb(0x8A4A2F), line: 2)
        rrect(cg, CGRect(x: ch.minX - 4, y: ch.minY - 4, width: ch.width + 8, height: 7), 2, Palette.rgb(0x6B3A24), line: 1.8)
        // Cajas que se ha tragado la rana
        let n = min(items.count, maxBoxes)
        for i in 0..<n { drawBox(cg, items[i], boxRect(i), hover: hoverPoint.map { boxRect(i).contains($0) } ?? false) }
        if items.count > n { pill("+\(items.count - n)", center: CGPoint(x: boxRect(n).minX + 16, y: boxRect(n).midY), maxW: 50) }
        drawFrogOnRoof(cg)
    }

    private func drawBox(_ cg: CGContext, _ it: ShelfItem, _ r: CGRect, hover: Bool) {
        let rr = hover ? r.offsetBy(dx: 0, dy: -3) : r
        rrect(cg, rr, 2, Palette.rgb(0xC9935A), line: 1.8)
        cg.setFillColor(Palette.rgb(0xE8C27A, 0.9).cgColor); cg.fill(CGRect(x: rr.midX - 3, y: rr.minY, width: 6, height: rr.height))
        cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(1)
        cg.move(to: CGPoint(x: rr.minX, y: rr.minY + 7)); cg.addLine(to: CGPoint(x: rr.maxX, y: rr.minY + 7)); cg.strokePath()
        // Icono del archivo y nombre
        let icon = NSWorkspace.shared.icon(forFile: it.url.path)
        icon.draw(in: CGRect(x: rr.midX - 8, y: rr.minY + 9, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if hover {
            pill(it.url.lastPathComponent, center: CGPoint(x: rr.midX, y: rr.minY - 12), maxW: 180)
        }
    }

    private func drawFrogOnRoof(_ cg: CGContext) {
        let x = frogX, y = roofTop
        let st = Frog.shared.state
        let gulp = st == .swallowing ? sin(CGFloat(Date().timeIntervalSinceReferenceDate - Double(Frog.shared.swallowStart)) * 12) * 3 : 0
        let green = Palette.rgb(0x5DBB63), dark = Palette.rgb(0x2E7D32)
        // Patas y cuerpo
        ellipse(cg, CGRect(x: x - 30, y: y - 10, width: 20, height: 10), green, line: 1.8)
        ellipse(cg, CGRect(x: x + 10, y: y - 10, width: 20, height: 10), green, line: 1.8)
        ellipse(cg, CGRect(x: x - 26 - gulp, y: y - 36 - gulp, width: 52 + gulp * 2, height: 34 + gulp), green, line: 2.2)
        ellipse(cg, CGRect(x: x - 16, y: y - 22, width: 32, height: 16), Palette.rgb(0xC8E6A0), line: 0)
        // Ojos saltones que miran al cursor
        let m = window.map { NSEvent.mouseLocation.x - $0.frame.midX } ?? 0
        for s in [-1.0, 1.0] as [CGFloat] {
            let e = CGRect(x: x + s * 12 - 9, y: y - 50, width: 18, height: 18)
            ellipse(cg, e, green, line: 2)
            ellipse(cg, e.insetBy(dx: 3, dy: 3), .white, line: 1.2)
            let blink = st == .resting && (t.truncatingRemainder(dividingBy: 5.3)) < 0.12
            if blink {
                cg.setFillColor(green.cgColor); cg.fill(e.insetBy(dx: 3, dy: 3))
            } else {
                let px = max(-2.5, min(2.5, m / 300))
                cg.setFillColor(Palette.outline.cgColor)
                cg.fillEllipse(in: CGRect(x: e.midX - 3 + px, y: e.midY - 3, width: 6, height: 7))
            }
        }
        // Boca: abierta cuando caza
        if st == .catching {
            ellipse(cg, CGRect(x: x - 20, y: y - 22, width: 14, height: 9), Palette.rgb(0x8E2C3B), line: 1.6)
        } else {
            cg.setStrokeColor(dark.cgColor); cg.setLineWidth(1.8)
            cg.move(to: CGPoint(x: x - 18, y: y - 20)); cg.addQuadCurve(to: CGPoint(x: x + 18, y: y - 20), control: CGPoint(x: x, y: y - 13)); cg.strokePath()
        }
        cg.setFillColor(Palette.cheek.cgColor)
        cg.fillEllipse(in: CGRect(x: x - 24, y: y - 26, width: 8, height: 5)); cg.fillEllipse(in: CGRect(x: x + 16, y: y - 26, width: 8, height: 5))
        if !Frog.shared.enabled {
            z(cg, x: x + 20, y: y - 52, ph: 0)
        } else if st == .letGo {
            balloon(cg, "¡vale, vale!", center: CGPoint(x: x - 20, y: y - 66), urgent: false, wobble: 0)
        }
    }

    // MARK: Sacar cajas del tejado

    private var boxPress: (index: Int, at: NSPoint)?
    override func mouseDown(with event: NSEvent) {
        let p = local(event)
        if let i = boxIndex(at: p) {
            boxPress = (i, p)
            if event.clickCount == 2, i < items.count { NSWorkspace.shared.open(items[i].url); boxPress = nil }
            return
        }
        boxPress = nil
        super.mouseDown(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let bp = boxPress else { super.mouseDragged(with: event); return }
        let p = local(event)
        guard hypot(p.x - bp.at.x, p.y - bp.at.y) > 4, bp.index < items.count else { return }
        let it = items[bp.index]
        boxPress = nil
        let di = NSDraggingItem(pasteboardWriter: it.url as NSURL)
        let k = GorilasView.drawScale
        let r = boxRect(bp.index)
        di.setDraggingFrame(NSRect(x: r.minX * k, y: (r.minY + drawOffsetY) * k, width: r.width * k, height: r.height * k),
                            contents: NSWorkspace.shared.icon(forFile: it.url.path))
        Frog.shared.draggingOut = true
        draggedItem = it
        beginDraggingSession(with: [di], event: event, source: self)
    }
    override func mouseUp(with event: NSEvent) {
        if boxPress != nil { boxPress = nil; return }
        let p = local(event)
        if doorRect.insetBy(dx: -6, dy: -6).contains(p) && actorIndex(at: p) == nil {
            if chats.isEmpty && needsPermission { onPlaceholderClick?() } else { onDoorClick?() }
            return
        }
        super.mouseUp(with: event)
    }
    private var draggedItem: ShelfItem?
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .generic] : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        Frog.shared.draggingOut = false
        if operation != [], let it = draggedItem { ShelfStore.shared.remove(it) }   // te lo llevas: la caja desaparece
        draggedItem = nil
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let p = local(event)
        if let i = boxIndex(at: p), i < items.count {
            let it = items[i]
            let m = NSMenu()
            let h = m.addItem(withTitle: it.url.lastPathComponent, action: nil, keyEquivalent: ""); h.isEnabled = false
            m.addItem(withTitle: "Abrir", action: #selector(boxOpen(_:)), keyEquivalent: "").representedObject = it
            m.addItem(withTitle: "Mostrar en Finder", action: #selector(boxReveal(_:)), keyEquivalent: "").representedObject = it
            m.addItem(withTitle: "Quitar del tejado", action: #selector(boxRemove(_:)), keyEquivalent: "").representedObject = it
            m.addItem(.separator())
            m.addItem(withTitle: "Vaciar el tejado", action: #selector(boxClear), keyEquivalent: "")
            for x in m.items { x.target = self }
            return m
        }
        return super.menu(for: event)
    }
    @objc private func boxOpen(_ s: NSMenuItem) { if let it = s.representedObject as? ShelfItem { NSWorkspace.shared.open(it.url) } }
    @objc private func boxReveal(_ s: NSMenuItem) { if let it = s.representedObject as? ShelfItem { NSWorkspace.shared.activateFileViewerSelecting([it.url]) } }
    @objc private func boxRemove(_ s: NSMenuItem) { if let it = s.representedObject as? ShelfItem { ShelfStore.shared.remove(it) } }
    @objc private func boxClear() { ShelfStore.shared.removeAll() }

    private func drawRoom(_ cg: CGContext) {
        let F = GorilasView.floor, H = GorilasView.H
        let back: CGFloat = GorilasView.backLine          // donde la pared del fondo toca el suelo
        let left = max(0, tableRect.minX - 254)
        let top = -GorilasView.topPad
        let sw = GorilasView.sideW
        let bl = left + sw, br = W - sw                   // esquinas de la pared del fondo
        let wallTop = top + 22
        // Techo
        let ceil = CGMutablePath()
        ceil.move(to: CGPoint(x: left, y: top)); ceil.addLine(to: CGPoint(x: W, y: top))
        ceil.addLine(to: CGPoint(x: br, y: wallTop)); ceil.addLine(to: CGPoint(x: bl, y: wallTop)); ceil.closeSubpath()
        cg.addPath(ceil); cg.setFillColor(Palette.rgb(0x2A1F18).cgColor); cg.fillPath()
        // Pared del fondo: papel pintado verde con rayas y zócalo
        cg.setFillColor(Palette.rgb(0x1E3A2C).cgColor); cg.fill(CGRect(x: bl, y: wallTop, width: br - bl, height: back - wallTop))
        cg.setFillColor(Palette.rgb(0x24473A).cgColor)
        var sx = bl + 6
        while sx < br - 4 { cg.fill(CGRect(x: sx, y: wallTop, width: 7, height: back - wallTop)); sx += 18 }
        cg.setFillColor(Palette.rgb(0x5A3A22).cgColor); cg.fill(CGRect(x: bl, y: back - 30, width: br - bl, height: 30))
        cg.setFillColor(Palette.rgb(0x7A4A28).cgColor); cg.fill(CGRect(x: bl, y: back - 32, width: br - bl, height: 4))
        // Paredes laterales en perspectiva (más oscuras), con su zócalo
        let zf = 30 * (H - top) / (back - wallTop)
        for (outer, inner) in [(left, bl), (W, br)] {
            let wall = CGMutablePath()
            wall.move(to: CGPoint(x: outer, y: top)); wall.addLine(to: CGPoint(x: inner, y: wallTop))
            wall.addLine(to: CGPoint(x: inner, y: back)); wall.addLine(to: CGPoint(x: outer, y: H)); wall.closeSubpath()
            cg.addPath(wall); cg.setFillColor(Palette.rgb(0x173024).cgColor); cg.fillPath()
            cg.saveGState(); cg.addPath(wall); cg.clip()
            cg.setStrokeColor(Palette.rgb(0x1E3A2C).cgColor); cg.setLineWidth(5)
            for k in 1..<4 {
                let f = CGFloat(k) / 4
                let x = lerp(outer, inner, f)
                cg.move(to: CGPoint(x: x, y: lerp(top, wallTop, f))); cg.addLine(to: CGPoint(x: x, y: lerp(H, back, f))); cg.strokePath()
            }
            let z = CGMutablePath()
            z.move(to: CGPoint(x: inner, y: back - 30)); z.addLine(to: CGPoint(x: inner, y: back))
            z.addLine(to: CGPoint(x: outer, y: H)); z.addLine(to: CGPoint(x: outer, y: H - zf)); z.closeSubpath()
            cg.addPath(z); cg.setFillColor(Palette.rgb(0x4A2F1C).cgColor); cg.fillPath()
            cg.restoreGState()
            cg.setStrokeColor(Palette.rgb(0x0E1F17).cgColor); cg.setLineWidth(1.5)
            cg.move(to: CGPoint(x: inner, y: wallTop)); cg.addLine(to: CGPoint(x: inner, y: back)); cg.strokePath()
        }
        // Suelo de tablones en perspectiva
        let floor = CGMutablePath()
        floor.move(to: CGPoint(x: bl, y: back)); floor.addLine(to: CGPoint(x: br, y: back))
        floor.addLine(to: CGPoint(x: W, y: H)); floor.addLine(to: CGPoint(x: left, y: H)); floor.closeSubpath()
        cg.addPath(floor); cg.setFillColor(Palette.rgb(0x8A5A33).cgColor); cg.fillPath()
        cg.saveGState(); cg.addPath(floor); cg.clip()
        cg.setStrokeColor(Palette.rgb(0x5A3A22, 0.55).cgColor); cg.setLineWidth(1.2)
        let vp = CGPoint(x: (bl + br) / 2, y: back - 160)       // punto de fuga
        var fx = left - 300
        while fx < W + 300 { cg.move(to: CGPoint(x: fx, y: H)); cg.addLine(to: vp); fx += 34 }
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
