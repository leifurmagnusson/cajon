// Bolitas — estilo «Monos en la oficina»: abajo a la derecha hay una puerta de madera.
// Cada chat es un mono distinto. Al llegar uno nuevo la puerta se abre de golpe (¡PLAM!),
// sale andando con su portátil, se saca un escritorio del bolsillo y se pone a trabajar.
// Cuando te espera, echa humo, y el humo sube hasta arriba de la pantalla.

import AppKit

struct MonkeyLook {
    var fur, skin, shirt, shirt2, sticker: NSColor
    var hat: Int        // 0 nada · 1 gorro de lana · 2 gorra · 3 auriculares · 4 gorro de fiesta · 5 sombrero vaquero · 6 lazo · 7 gorro de chef · 8 corona de flores · 9 boina
    var eyes: Int       // 0 normales · 1 gafas redondas · 2 gafas de sol · 3 ojos grandes · 4 gafas de pasta
    var mouth: Int      // 0 sonrisa · 1 dientes · 2 lengua · 3 bigote
    var outfit: Int     // 0 camiseta · 1 sudadera · 2 traje con corbata · 3 rayas · 4 camisa de flores
    var earring: Bool

    init(_ key: String) {
        var d = Dice(key)
        let furs: [UInt32] = [0x8B5A2B, 0x6B4423, 0xA0522D, 0x5C4033, 0x3B2F2F, 0xC68E4E, 0x9E9E9E, 0xD8C3A0, 0x7B5EA7, 0x4A6FA5, 0xB5651D, 0x2F2F3A, 0xE07B39, 0x6D8B4E]
        let skins: [UInt32] = [0xF2C9A0, 0xE8B88A, 0xD9A877, 0xF5D7B5, 0xEFC3B3, 0xE2B07E]
        let shirts: [UInt32] = [0xE5484D, 0x3E8ED0, 0x46A758, 0xFFB224, 0x8E4EC6, 0xF76808, 0x12A594, 0xD6409F, 0x1F2937, 0xF5F5F5, 0x0091FF, 0xA18072]
        let stick: [UInt32] = [0xFFD60A, 0xFF5D8F, 0x34C759, 0x5AC8FA, 0xFF9F0A, 0xBF5AF2]
        fur = Palette.rgb(d.pick(furs)); skin = Palette.rgb(d.pick(skins))
        shirt = Palette.rgb(d.pick(shirts)); shirt2 = Palette.rgb(d.pick(shirts)); sticker = Palette.rgb(d.pick(stick))
        hat = Int(d.next() % 10); eyes = Int(d.next() % 5); mouth = Int(d.next() % 4); outfit = Int(d.next() % 5)
        earring = d.chance(0.25)
    }
}

final class MonosView: StageView {
    static let cellW: CGFloat = 104, H: CGFloat = 214, ground: CGFloat = 188, doorW: CGFloat = 78, doorH: CGFloat = 152, pad: CGFloat = 10
    private var looks: [String: MonkeyLook] = [:]
    var usageLines: [String] = []
    var onDoorClick: (() -> Void)?

    override class func size(for count: Int) -> NSSize {
        NSSize(width: pad + CGFloat(count) * cellW + doorW + 30, height: H)
    }
    private func look(_ c: Chat) -> MonkeyLook {
        if let l = looks[c.key] { return l }
        let l = MonkeyLook(c.key); looks[c.key] = l; return l
    }
    private var doorX: CGFloat { bounds.width - MonosView.doorW - 14 }
    private func slotX(_ i: Int) -> CGFloat {
        // El último en llegar se sienta al lado de la puerta.
        doorX - 12 - CGFloat(chats.count - i) * MonosView.cellW + MonosView.cellW / 2
    }
    private var doorRect: CGRect { CGRect(x: doorX, y: MonosView.ground - MonosView.doorH, width: MonosView.doorW, height: MonosView.doorH) }

    override func actorIndex(at p: NSPoint) -> Int? {
        for i in chats.indices where abs(p.x - slotX(i)) < MonosView.cellW / 2 && p.y > 40 { return i }
        return nil
    }
    override func smokeSource(_ i: Int) -> NSPoint? {
        guard i < chats.count, chats[i].mood == .needsYou || chats[i].mood == .done, age(chats[i]) > 2.6 else { return nil }
        return NSPoint(x: slotX(i), y: 58)
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if doorRect.insetBy(dx: -6, dy: -6).contains(p) && actorIndex(at: p) == nil {
            if chats.isEmpty && needsPermission { onPlaceholderClick?() } else { onDoorClick?() }
            return
        }
        super.mouseUp(with: event)
    }

    // MARK: Dibujo

    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.clear(bounds)
        drawDropHint(cg, bounds.insetBy(dx: 2, dy: 30))
        cg.setLineCap(.round); cg.setLineJoin(.round)

        // ¿Cuánto está abierta la puerta? La más reciente manda.
        var open: CGFloat = 0
        var plam: CGFloat = -1
        for c in chats {
            let a = age(c)
            let d: CGFloat = a < 0 ? 0 : a < 0.14 ? ease(a / 0.14) : a < 1.15 ? 1 : 1 - ease((a - 1.15) / 0.25)
            open = max(open, d)
            if a >= 0 && a < 0.9 { plam = max(plam, a) }
        }
        drawDoor(cg, open: open)

        for (i, c) in chats.enumerated() { drawMonkey(cg, c, i) }

        if plam >= 0 {
            let s = 0.6 + 0.6 * ease(plam / 0.18)
            let alpha = 1 - clamp01((plam - 0.6) / 0.3)
            cg.saveGState()
            cg.translateBy(x: doorRect.midX - 6, y: doorRect.minY - 6)
            cg.rotate(by: -0.18); cg.scaleBy(x: s, y: s)
            text("¡PLAM!", Fonts.rounded(22, .black), Palette.rgb(0xE5484D, alpha), center: .zero, halo: Palette.rgb(0xFFFFFF, alpha))
            cg.restoreGState()
        }

        if chats.isEmpty {
            pill(needsPermission ? "Dame permiso · toca la puerta" : "Arrastra aquí un chat", center: CGPoint(x: doorRect.midX - 40, y: doorRect.minY - 14), maxW: 220)
        }
        // Al pasar por la puerta: el uso.
        if let hp = hoverPoint, doorRect.contains(hp), !chats.isEmpty || !needsPermission {
            drawUsageCard(cg)
        }
    }

    private func drawUsageCard(_ cg: CGContext) {
        let lines = usageLines.isEmpty ? ["Toca la puerta para", "ver tu uso de Claude"] : usageLines
        let font = Fonts.rounded(11, .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let w = (lines.map { ($0 as NSString).size(withAttributes: attrs).width }.max() ?? 80) + 20
        let h = CGFloat(lines.count) * 15 + 12
        let r = CGRect(x: min(doorRect.midX - w / 2, bounds.width - w - 4), y: doorRect.minY - h - 8, width: w, height: h)
        rrect(cg, r, 8, Palette.rgb(0xFFF7E2), line: 2)
        for (k, l) in lines.enumerated() {
            text(l, font, Palette.outline, center: CGPoint(x: r.midX, y: r.minY + 13 + CGFloat(k) * 15))
        }
    }

    private func drawDoor(_ cg: CGContext, open: CGFloat) {
        let r = doorRect
        let wood = Palette.rgb(0xA8683A), woodDark = Palette.rgb(0x7A4522), woodLight = Palette.rgb(0xC98A55)
        // Marco
        rrect(cg, r.insetBy(dx: -7, dy: -7).offsetBy(dx: 0, dy: 3.5), 4, woodDark, line: 2.5)
        // Hueco oscuro
        rrect(cg, r, 2, Palette.rgb(0x2A1F1A), line: 2)
        // Suelo bajo la puerta
        cg.setFillColor(NSColor.black.withAlphaComponent(0.12).cgColor)
        cg.fillEllipse(in: CGRect(x: r.minX - 10, y: r.maxY - 3, width: r.width + 20, height: 8))

        // La hoja de la puerta gira sobre la bisagra derecha.
        let w = r.width * (1 - 0.82 * open)
        let skew = 10 * open
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.maxX - w, y: r.minY - skew))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - w, y: r.maxY + skew))
        p.closeSubpath()
        fillStroke(cg, p, open > 0.5 ? woodLight : wood, line: 2.5)
        if open < 0.35 {
            // Cuarterones, cartel y pomo.
            let inset = CGRect(x: r.minX + 10, y: r.minY + 12, width: r.width - 20, height: 50)
            rrect(cg, inset, 4, woodDark.withAlphaComponent(0.35), line: 1.5)
            rrect(cg, CGRect(x: r.minX + 10, y: r.minY + 74, width: r.width - 20, height: 64), 4, woodDark.withAlphaComponent(0.35), line: 1.5)
            let plate = CGRect(x: r.minX + 13, y: r.minY + 26, width: r.width - 26, height: 22)
            rrect(cg, plate, 3, Palette.rgb(0xE9C46A), line: 1.5)
            text("MONOS S.A.", Fonts.rounded(9, .black), Palette.outline, center: CGPoint(x: plate.midX, y: plate.midY))
            ellipse(cg, CGRect(x: r.minX + 8, y: r.midY + 4, width: 9, height: 9), Palette.rgb(0xF4D35E), line: 1.8)
            // Mini indicador de uso en la puerta.
            if let first = usageLines.first, let pct = Rx.first(first, "[0-9]+ ?%") {
                text(pct, Fonts.rounded(11, .black), Palette.rgb(0xFFF7E2), center: CGPoint(x: r.midX, y: r.minY + 106), halo: woodDark)
            }
        }
    }

    // MARK: El mono

    private func drawMonkey(_ cg: CGContext, _ c: Chat, _ i: Int) {
        let L = look(c)
        let a = age(c)
        let ph = CGFloat(seed(c.key) % 100) / 15
        let sx = slotX(i)
        let G = MonosView.ground

        // Fases de la entrada.
        let walking = a >= 0.22 && a < 1.5
        let pulling = a >= 1.5 && a < 2.15
        let opening = a >= 2.15 && a < 2.6
        if a < 0.22 { return }   // aún dentro
        if walking || pulling {
            let k = walking ? ease((a - 0.22) / 1.28) : 1
            let x = lerp(doorRect.midX, sx, k)
            var deskScale: CGFloat = 0
            if pulling {
                let q = (a - 1.5) / 0.65
                deskScale = q < 0.7 ? ease(q / 0.7) * 1.12 : lerp(1.12, 1, ease((q - 0.7) / 0.3))
            }
            if deskScale > 0 { drawDesk(cg, x: sx, scale: deskScale) }
            drawStanding(cg, L, x: x, walk: walking ? a * 9 : 0, pulling: pulling)
            pill(c.shortTitle, center: CGPoint(x: x, y: G + 14), maxW: MonosView.cellW - 4)
            return
        }
        let lid: CGFloat = opening ? ease((a - 2.15) / 0.45) : 1
        let hover = hoverIndex == i

        // Sombra y escritorio (patas)
        cg.setFillColor(NSColor.black.withAlphaComponent(0.14).cgColor)
        cg.fillEllipse(in: CGRect(x: sx - 50, y: G - 4, width: 100, height: 9))

        var headY: CGFloat = 84
        var lookDown = false
        switch c.mood {
        case .working: headY += sin(t * 4 + ph) * 1.2; lookDown = true
        case .needsYou: headY -= 5 + abs(sin(t * 5 + ph)) * 4
        case .done: headY -= 2
        case .idle: headY = 108
        }
        if hover && c.mood != .idle { headY -= 3 }

        // Cuerpo (camisa) detrás del portátil
        drawTorso(cg, L, x: sx, top: headY + 18)
        drawHead(cg, L, x: sx, y: headY, mood: c.mood, lookDown: lookDown, ph: ph)

        // Portátil (lo vemos por detrás) y escritorio
        drawDesk(cg, x: sx, scale: 1)
        let lidH = 38 * lid
        let lidR = CGRect(x: sx - 31, y: 140 - lidH, width: 62, height: lidH)
        if c.mood == .working && lid > 0.9 {
            // brillo de la pantalla en la cara
            cg.setFillColor(Palette.rgb(0x9FD3FF, 0.22 + 0.06 * sin(t * 9 + ph)).cgColor)
            cg.fillEllipse(in: CGRect(x: sx - 26, y: headY - 6, width: 52, height: 30))
        }
        rrect(cg, lidR, 5, Palette.rgb(0xC9CDD6), line: 2.2)
        if lid > 0.8 {
            // pegatina con forma de plátano
            let b = CGMutablePath()
            b.move(to: CGPoint(x: sx - 9, y: 116)); b.addQuadCurve(to: CGPoint(x: sx + 9, y: 114), control: CGPoint(x: sx - 1, y: 128))
            b.addQuadCurve(to: CGPoint(x: sx - 9, y: 116), control: CGPoint(x: sx, y: 122))
            fillStroke(cg, b, L.sticker, line: 1.4)
        }
        rrect(cg, CGRect(x: sx - 34, y: 138, width: 68, height: 5), 2, Palette.rgb(0x9AA0AC), line: 1.6)

        // Manos
        switch c.mood {
        case .working:
            let l = sin(t * 14 + ph) > 0 ? 2.5 : -1.5
            let r = sin(t * 14 + ph + 1.6) > 0 ? 2.5 : -1.5
            ellipse(cg, CGRect(x: sx - 38, y: 128 + l, width: 12, height: 10), L.skin, line: 1.8)
            ellipse(cg, CGRect(x: sx + 26, y: 128 + r, width: 12, height: 10), L.skin, line: 1.8)
            if Int(t * 7 + ph) % 3 == 0 { text("tac", Fonts.rounded(8, .heavy), Palette.outline.withAlphaComponent(0.5), center: CGPoint(x: sx + 40, y: 118)) }
        case .needsYou:
            let wave = sin(t * 10 + ph) * 6
            cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(2)
            ellipse(cg, CGRect(x: sx + 30 + wave, y: headY - 14, width: 13, height: 13), L.skin, line: 1.8)
            ellipse(cg, CGRect(x: sx - 38, y: 130, width: 12, height: 10), L.skin, line: 1.8)
        case .done:
            ellipse(cg, CGRect(x: sx - 44, y: headY - 10 + sin(t * 3) * 2, width: 13, height: 13), L.skin, line: 1.8)
            ellipse(cg, CGRect(x: sx + 31, y: headY - 10 - sin(t * 3) * 2, width: 13, height: 13), L.skin, line: 1.8)
        case .idle:
            ellipse(cg, CGRect(x: sx - 30, y: 98, width: 13, height: 10), L.skin, line: 1.8)
            ellipse(cg, CGRect(x: sx + 17, y: 98, width: 13, height: 10), L.skin, line: 1.8)
        }

        // Encima de la cabeza
        switch c.mood {
        case .needsYou: balloon(cg, "¡Permiso!", center: CGPoint(x: sx, y: headY - 52), urgent: true, wobble: sin(t * 14 + ph) * 0.06)
        case .done: balloon(cg, "¡Te toca!", center: CGPoint(x: sx, y: headY - 50), urgent: false, wobble: sin(t * 3 + ph) * 0.04)
        case .idle: z(cg, x: sx + 22, y: headY - 22, ph: ph)
        case .working: break
        }

        // Nombre y reloj
        pill(c.shortTitle, center: CGPoint(x: sx, y: G + 14), maxW: MonosView.cellW - 4)
        var sub = ""
        switch c.mood {
        case .working: sub = elapsed(c.since)
        case .needsYou, .done: sub = ago(c.since)
        case .idle: sub = ""
        }
        if !sub.isEmpty, lid > 0.9 {
            text(sub, Fonts.time, Palette.outline, center: CGPoint(x: sx, y: 108), halo: NSColor.white)
        }
        // Insignia de la app
        let bdg = CGRect(x: sx + 36, y: 150, width: 16, height: 16)
        ellipse(cg, bdg, Palette.badge(c.provider), line: 1.6)
        text(c.provider.letter, Fonts.rounded(9, .black), .white, center: CGPoint(x: bdg.midX, y: bdg.midY))
    }

    private func drawDesk(_ cg: CGContext, x: CGFloat, scale s: CGFloat) {
        let G = MonosView.ground
        cg.saveGState()
        cg.translateBy(x: x, y: G); cg.scaleBy(x: s, y: s); cg.translateBy(x: -x, y: -G)
        let wood = Palette.rgb(0xD9A066)
        rrect(cg, CGRect(x: x - 42, y: 146, width: 7, height: G - 146), 2, Palette.rgb(0xB07A45), line: 1.8)
        rrect(cg, CGRect(x: x + 35, y: 146, width: 7, height: G - 146), 2, Palette.rgb(0xB07A45), line: 1.8)
        rrect(cg, CGRect(x: x - 48, y: 141, width: 96, height: 9), 3, wood, line: 2.2)
        cg.restoreGState()
    }

    private func drawTorso(_ cg: CGContext, _ L: MonkeyLook, x: CGFloat, top: CGFloat) {
        let r = CGRect(x: x - 25, y: top, width: 50, height: 150 - top)
        rrect(cg, r, 16, L.shirt, line: 2.2)
        cg.saveGState(); cg.addPath(CGPath(roundedRect: r, cornerWidth: 16, cornerHeight: 16, transform: nil)); cg.clip()
        switch L.outfit {
        case 1: // sudadera: capucha y cordones
            cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(1.5)
            cg.move(to: CGPoint(x: x - 5, y: top + 4)); cg.addLine(to: CGPoint(x: x - 5, y: top + 16))
            cg.move(to: CGPoint(x: x + 5, y: top + 4)); cg.addLine(to: CGPoint(x: x + 5, y: top + 16)); cg.strokePath()
        case 2: // traje con corbata
            cg.setFillColor(NSColor.white.cgColor)
            cg.fill(CGRect(x: x - 7, y: top, width: 14, height: 30))
            let tie = CGMutablePath()
            tie.move(to: CGPoint(x: x - 3, y: top + 2)); tie.addLine(to: CGPoint(x: x + 3, y: top + 2))
            tie.addLine(to: CGPoint(x: x + 5, y: top + 24)); tie.addLine(to: CGPoint(x: x, y: top + 30)); tie.addLine(to: CGPoint(x: x - 5, y: top + 24)); tie.closeSubpath()
            fillStroke(cg, tie, L.shirt2, line: 1.4)
        case 3: // rayas
            cg.setFillColor(L.shirt2.withAlphaComponent(0.8).cgColor)
            var y = top + 6
            while y < 150 { cg.fill(CGRect(x: x - 26, y: y, width: 52, height: 4)); y += 9 }
        case 4: // flores
            var d = Dice(L.shirt.description)
            for _ in 0..<7 {
                let px = x - 22 + CGFloat(d.next() % 44), py = top + 4 + CGFloat(d.next() % 30)
                cg.setFillColor(L.shirt2.cgColor); cg.fillEllipse(in: CGRect(x: px, y: py, width: 6, height: 6))
            }
        default: break
        }
        cg.restoreGState()
    }

    private func drawHead(_ cg: CGContext, _ L: MonkeyLook, x: CGFloat, y: CGFloat, mood: Mood, lookDown: Bool, ph: CGFloat) {
        // Orejas
        for s in [-1.0, 1.0] as [CGFloat] {
            let e = CGRect(x: x + s * 25 - 9, y: y - 9, width: 18, height: 18)
            ellipse(cg, e, L.fur)
            ellipse(cg, e.insetBy(dx: 4.5, dy: 4.5), L.skin, line: 0)
        }
        if L.earring { ellipse(cg, CGRect(x: x - 33, y: y + 6, width: 6, height: 6), Palette.rgb(0xF4D35E), line: 1.4) }
        // Cabeza
        ellipse(cg, CGRect(x: x - 24, y: y - 24, width: 48, height: 46), L.fur)
        // Cara (corazón + hocico)
        let face = CGMutablePath()
        face.addEllipse(in: CGRect(x: x - 17, y: y - 15, width: 18, height: 20))
        face.addEllipse(in: CGRect(x: x - 1, y: y - 15, width: 18, height: 20))
        cg.addPath(face); cg.setFillColor(L.skin.cgColor); cg.fillPath()
        ellipse(cg, CGRect(x: x - 15, y: y - 1, width: 30, height: 20), L.skin, line: 2)
        // Nariz
        cg.setFillColor(Palette.outline.cgColor)
        cg.fillEllipse(in: CGRect(x: x - 4, y: y + 3, width: 2.6, height: 2.2))
        cg.fillEllipse(in: CGRect(x: x + 1.4, y: y + 3, width: 2.6, height: 2.2))

        // Ojos
        let ey = y - 6
        let sleeping = mood == .idle
        let happy = mood == .done
        let blink = (t + ph).truncatingRemainder(dividingBy: 4.2) < 0.12
        for s in [-1.0, 1.0] as [CGFloat] {
            let ex = x + s * 8
            if sleeping || happy {
                cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(2)
                cg.move(to: CGPoint(x: ex - 4, y: ey))
                cg.addQuadCurve(to: CGPoint(x: ex + 4, y: ey), control: CGPoint(x: ex, y: happy ? ey - 5 : ey + 4))
                cg.strokePath()
            } else if blink {
                cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(2)
                cg.move(to: CGPoint(x: ex - 4, y: ey)); cg.addLine(to: CGPoint(x: ex + 4, y: ey)); cg.strokePath()
            } else {
                let big: CGFloat = L.eyes == 3 || mood == .needsYou ? 1.3 : 1
                let er = CGRect(x: ex - 4.5 * big, y: ey - 5 * big, width: 9 * big, height: 10 * big)
                ellipse(cg, er, .white, line: 1.6)
                let py: CGFloat = lookDown ? 2.2 : 0
                let px: CGFloat = lookDown ? 0 : sin(t * 0.8 + ph) * 1.2
                cg.setFillColor(Palette.outline.cgColor)
                cg.fillEllipse(in: CGRect(x: ex - 2.4 + px, y: ey - 2.4 + py, width: 4.8, height: 5.2))
            }
        }
        // Gafas
        if !sleeping {
            switch L.eyes {
            case 1:
                cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(1.8)
                cg.strokeEllipse(in: CGRect(x: x - 15, y: ey - 7, width: 14, height: 14))
                cg.strokeEllipse(in: CGRect(x: x + 1, y: ey - 7, width: 14, height: 14))
            case 2:
                rrect(cg, CGRect(x: x - 17, y: ey - 5, width: 15, height: 10), 4, Palette.rgb(0x1C1C24), line: 1.6)
                rrect(cg, CGRect(x: x + 2, y: ey - 5, width: 15, height: 10), 4, Palette.rgb(0x1C1C24), line: 1.6)
                cg.setFillColor(NSColor.white.withAlphaComponent(0.6).cgColor)
                cg.fill(CGRect(x: x - 14, y: ey - 3, width: 4, height: 2)); cg.fill(CGRect(x: x + 5, y: ey - 3, width: 4, height: 2))
            case 4:
                cg.setStrokeColor(L.shirt2.cgColor); cg.setLineWidth(3)
                cg.stroke(CGRect(x: x - 16, y: ey - 6, width: 14, height: 11)); cg.stroke(CGRect(x: x + 2, y: ey - 6, width: 14, height: 11))
            default: break
            }
            if mood == .needsYou {
                cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(2)
                cg.move(to: CGPoint(x: x - 13, y: ey - 11)); cg.addLine(to: CGPoint(x: x - 4, y: ey - 13))
                cg.move(to: CGPoint(x: x + 13, y: ey - 11)); cg.addLine(to: CGPoint(x: x + 4, y: ey - 13)); cg.strokePath()
            }
        }
        // Boca
        let my = y + 11
        cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(2)
        if mood == .needsYou {
            ellipse(cg, CGRect(x: x - 4, y: my - 2, width: 8, height: 7), Palette.rgb(0x8E2C3B), line: 1.6)
        } else if sleeping {
            cg.move(to: CGPoint(x: x - 3, y: my + 1)); cg.addLine(to: CGPoint(x: x + 3, y: my + 1)); cg.strokePath()
        } else {
            switch L.mouth {
            case 1:
                let m = CGMutablePath(); m.move(to: CGPoint(x: x - 8, y: my - 1)); m.addQuadCurve(to: CGPoint(x: x + 8, y: my - 1), control: CGPoint(x: x, y: my + 9)); m.closeSubpath()
                fillStroke(cg, m, .white, line: 1.6)
            case 2:
                cg.move(to: CGPoint(x: x - 7, y: my)); cg.addQuadCurve(to: CGPoint(x: x + 7, y: my), control: CGPoint(x: x, y: my + 6)); cg.strokePath()
                ellipse(cg, CGRect(x: x + 1, y: my + 1, width: 6, height: 6), Palette.rgb(0xFF7FA0), line: 1.3)
            case 3:
                cg.move(to: CGPoint(x: x - 6, y: my + 1)); cg.addQuadCurve(to: CGPoint(x: x + 6, y: my + 1), control: CGPoint(x: x, y: my + 5)); cg.strokePath()
                let mus = CGMutablePath()
                mus.move(to: CGPoint(x: x, y: my - 4)); mus.addQuadCurve(to: CGPoint(x: x - 11, y: my - 3), control: CGPoint(x: x - 6, y: my + 2))
                mus.addQuadCurve(to: CGPoint(x: x, y: my - 4), control: CGPoint(x: x - 6, y: my - 6))
                mus.move(to: CGPoint(x: x, y: my - 4)); mus.addQuadCurve(to: CGPoint(x: x + 11, y: my - 3), control: CGPoint(x: x + 6, y: my + 2))
                mus.addQuadCurve(to: CGPoint(x: x, y: my - 4), control: CGPoint(x: x + 6, y: my - 6))
                fillStroke(cg, mus, Palette.outline, line: 1)
            default:
                cg.move(to: CGPoint(x: x - 7, y: my)); cg.addQuadCurve(to: CGPoint(x: x + 7, y: my), control: CGPoint(x: x, y: my + 6)); cg.strokePath()
            }
        }
        drawHat(cg, L, x: x, y: y)
    }

    private func drawHat(_ cg: CGContext, _ L: MonkeyLook, x: CGFloat, y: CGFloat) {
        let top = y - 24
        switch L.hat {
        case 1: // gorro de lana
            let p = CGMutablePath(); p.addArc(center: CGPoint(x: x, y: top + 10), radius: 22, startAngle: .pi, endAngle: 0, clockwise: false)
            p.closeSubpath(); fillStroke(cg, p, L.shirt2)
            rrect(cg, CGRect(x: x - 24, y: top + 6, width: 48, height: 9), 4, L.shirt2.blended(withFraction: 0.3, of: .white) ?? L.shirt2)
            ellipse(cg, CGRect(x: x - 6, y: top - 20, width: 12, height: 12), .white)
        case 2: // gorra
            let p = CGMutablePath(); p.addArc(center: CGPoint(x: x, y: top + 9), radius: 21, startAngle: .pi, endAngle: 0, clockwise: false); p.closeSubpath()
            fillStroke(cg, p, L.shirt2)
            rrect(cg, CGRect(x: x - 4, y: top + 4, width: 34, height: 7), 3, L.shirt2)
        case 3: // auriculares
            cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(4.5)
            cg.addArc(center: CGPoint(x: x, y: y - 2), radius: 27, startAngle: .pi * 1.05, endAngle: .pi * 1.95, clockwise: false); cg.strokePath()
            cg.setStrokeColor(L.shirt2.cgColor); cg.setLineWidth(2.5)
            cg.addArc(center: CGPoint(x: x, y: y - 2), radius: 27, startAngle: .pi * 1.05, endAngle: .pi * 1.95, clockwise: false); cg.strokePath()
            rrect(cg, CGRect(x: x - 33, y: y - 8, width: 10, height: 18), 4, L.shirt2)
            rrect(cg, CGRect(x: x + 23, y: y - 8, width: 10, height: 18), 4, L.shirt2)
        case 4: // gorro de fiesta
            let p = CGMutablePath(); p.move(to: CGPoint(x: x - 12, y: top + 6)); p.addLine(to: CGPoint(x: x + 3, y: top - 26)); p.addLine(to: CGPoint(x: x + 14, y: top + 6)); p.closeSubpath()
            fillStroke(cg, p, L.shirt2)
            ellipse(cg, CGRect(x: x - 1, y: top - 32, width: 9, height: 9), Palette.rgb(0xFFD60A))
        case 5: // sombrero vaquero
            rrect(cg, CGRect(x: x - 34, y: top + 2, width: 68, height: 8), 4, Palette.rgb(0xA0703C))
            rrect(cg, CGRect(x: x - 16, y: top - 18, width: 32, height: 24), 8, Palette.rgb(0xA0703C))
            cg.setFillColor(Palette.outline.cgColor); cg.fill(CGRect(x: x - 16, y: top - 1, width: 32, height: 3))
        case 6: // lazo
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x + 12, y: top + 2)); p.addLine(to: CGPoint(x: x + 2, y: top - 8)); p.addLine(to: CGPoint(x: x + 2, y: top + 10)); p.closeSubpath()
            p.move(to: CGPoint(x: x + 12, y: top + 2)); p.addLine(to: CGPoint(x: x + 22, y: top - 8)); p.addLine(to: CGPoint(x: x + 22, y: top + 10)); p.closeSubpath()
            fillStroke(cg, p, L.shirt2, line: 1.8)
            ellipse(cg, CGRect(x: x + 8, y: top - 2, width: 8, height: 8), L.shirt2, line: 1.6)
        case 7: // gorro de chef
            ellipse(cg, CGRect(x: x - 22, y: top - 26, width: 22, height: 22), .white)
            ellipse(cg, CGRect(x: x - 2, y: top - 28, width: 24, height: 24), .white)
            ellipse(cg, CGRect(x: x - 12, y: top - 34, width: 24, height: 22), .white)
            rrect(cg, CGRect(x: x - 18, y: top - 10, width: 36, height: 16), 3, .white)
        case 8: // corona de flores
            for k in 0..<5 {
                let ang = CGFloat.pi * (1.1 + 0.2 * CGFloat(k))
                let fx = x + cos(ang) * 21, fy = y - 3 + sin(ang) * 21
                ellipse(cg, CGRect(x: fx - 5, y: fy - 5, width: 10, height: 10), k % 2 == 0 ? L.shirt2 : Palette.rgb(0xFFD60A), line: 1.4)
            }
        case 9: // boina
            ellipse(cg, CGRect(x: x - 26, y: top - 6, width: 46, height: 16), L.shirt2)
            ellipse(cg, CGRect(x: x - 3, y: top - 10, width: 5, height: 6), Palette.outline, line: 0)
        default: break
        }
    }

    /// Mono de pie (andando con el portátil bajo el brazo, o sacando el escritorio del bolsillo).
    private func drawStanding(_ cg: CGContext, _ L: MonkeyLook, x: CGFloat, walk: CGFloat, pulling: Bool) {
        let G = MonosView.ground
        let bob = abs(sin(walk)) * 3
        let headY: CGFloat = 92 - bob
        cg.setFillColor(NSColor.black.withAlphaComponent(0.14).cgColor)
        cg.fillEllipse(in: CGRect(x: x - 20, y: G - 4, width: 40, height: 8))
        // Piernas
        let sw = sin(walk) * 7
        rrect(cg, CGRect(x: x - 13 + sw, y: 150 - bob, width: 11, height: G - 150 + bob - 2), 5, L.fur)
        rrect(cg, CGRect(x: x + 2 - sw, y: 150 - bob, width: 11, height: G - 150 + bob - 2), 5, L.fur)
        // Cola
        cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(5)
        cg.move(to: CGPoint(x: x + 20, y: 145 - bob)); cg.addCurve(to: CGPoint(x: x + 36, y: 120), control1: CGPoint(x: x + 40, y: 150), control2: CGPoint(x: x + 22, y: 118)); cg.strokePath()
        cg.setStrokeColor(L.fur.cgColor); cg.setLineWidth(2.5)
        cg.move(to: CGPoint(x: x + 20, y: 145 - bob)); cg.addCurve(to: CGPoint(x: x + 36, y: 120), control1: CGPoint(x: x + 40, y: 150), control2: CGPoint(x: x + 22, y: 118)); cg.strokePath()
        drawTorso(cg, L, x: x, top: headY + 18)
        drawHead(cg, L, x: x, y: headY, mood: .working, lookDown: false, ph: 0)
        if pulling {
            // mano en el bolsillo sacando algo
            ellipse(cg, CGRect(x: x + 12, y: 134, width: 12, height: 11), L.skin, line: 1.8)
            text("✨", Fonts.rounded(12, .bold), Palette.outline, center: CGPoint(x: x + 30, y: 128 - sin(t * 12) * 3))
        } else {
            // portátil cerrado bajo el brazo
            rrect(cg, CGRect(x: x - 34, y: 122 - bob, width: 14, height: 30), 3, Palette.rgb(0xC9CDD6), line: 1.8)
            ellipse(cg, CGRect(x: x - 30, y: 126 - bob, width: 12, height: 11), L.skin, line: 1.8)
        }
    }
}
