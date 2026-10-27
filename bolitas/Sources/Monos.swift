// Bolitas — «Monos en la oficina»: abajo a la derecha hay una puerta de madera.
// Cada chat es un simio distinto, con cara de aburrido. Al llegar uno nuevo la puerta se abre de golpe (¡PLAM!),
// sale andando con su portátil, se saca un escritorio del bolsillo y se pone a teclear.
//   trabajando → teclea a toda prisa, la pantalla le ilumina la cara y salen trocitos de código
//   te espera   → se cabrea y echa humo; el humo invade la pantalla hasta que le haces caso
//   parado      → duerme sobre el portátil

import AppKit

struct ApeLook {
    var fur, furDark, skin, shirt, shirt2, sticker: NSColor
    var hat: Int        // 0 nada · 1 gorro de lana · 2 gorra · 3 auriculares · 4 gorro de fiesta · 5 sombrero vaquero · 6 lazo · 7 gorro de chef · 8 corona de flores · 9 boina · 10 pañuelo pirata
    var eyes: Int       // 0 normales · 1 gafas redondas · 2 gafas de sol · 3 monóculo · 4 gafas de pasta
    var mouth: Int      // 0 recta · 1 media sonrisa · 2 dientes · 3 lengua · 4 bigote
    var outfit: Int     // 0 camiseta · 1 sudadera · 2 traje con corbata · 3 rayas · 4 camisa de flores · 5 sin camiseta
    var earring: Bool
    var lid: CGFloat    // cuánto le pesan los párpados (cara de aburrido)

    init(_ key: String) {
        var d = Dice(key)
        let furs: [UInt32] = [0x6B4423, 0x5C4033, 0x3B2F2F, 0x8B5A2B, 0x2F2F3A, 0x7A5C45, 0x9E9E9E, 0xC9A77C, 0xB5651D, 0x4E3B31,
                              0x6D6875, 0xD4C5A9, 0x2E4057, 0x8D6E63, 0xE07B39, 0x5B7553, 0x7B5EA7, 0x3D5A80]
        let skins: [UInt32] = [0xC9A68A, 0xB89279, 0xD8B89A, 0xA77F66, 0xE2C4A6, 0x9C7A63, 0xCDB4A0]
        let shirts: [UInt32] = [0xE5484D, 0x3E8ED0, 0x46A758, 0xFFB224, 0x8E4EC6, 0xF76808, 0x12A594, 0xD6409F, 0x1F2937, 0xF5F5F5, 0x0091FF, 0xA18072, 0x6E56CF, 0x30A46C]
        let stick: [UInt32] = [0xFFD60A, 0xFF5D8F, 0x34C759, 0x5AC8FA, 0xFF9F0A, 0xBF5AF2]
        let f = Palette.rgb(d.pick(furs))
        fur = f; furDark = f.blended(withFraction: 0.35, of: .black) ?? f
        skin = Palette.rgb(d.pick(skins))
        shirt = Palette.rgb(d.pick(shirts)); shirt2 = Palette.rgb(d.pick(shirts)); sticker = Palette.rgb(d.pick(stick))
        hat = Int(d.next() % 11); eyes = Int(d.next() % 5); mouth = Int(d.next() % 5); outfit = Int(d.next() % 6)
        if d.chance(0.35) { hat = 0 }
        if d.chance(0.45) { eyes = 0 }
        earring = d.chance(0.25)
        lid = 0.38 + CGFloat(d.next() % 20) / 100
    }
}

final class MonosView: StageView {
    static let cellW: CGFloat = 104, H: CGFloat = 214, ground: CGFloat = 188, doorW: CGFloat = 78, doorH: CGFloat = 152, pad: CGFloat = 10
    override class var drawScale: CGFloat { 0.66 }
    private var looks: [String: ApeLook] = [:]
    var usageLines: [String] = []
    var onDoorClick: (() -> Void)?

    override class func size(for count: Int) -> NSSize {
        let s = drawScale
        return NSSize(width: (pad + 130 + CGFloat(count) * cellW + doorW + 30) * s, height: H * s)
    }
    private func look(_ c: Chat) -> ApeLook {
        if let l = looks[c.key] { return l }
        let l = ApeLook(c.key); looks[c.key] = l; return l
    }
    private var W: CGFloat { bounds.width / MonosView.drawScale }
    private var doorX: CGFloat { W - MonosView.doorW - 14 }
    private func slotX(_ i: Int) -> CGFloat {
        doorX - 12 - CGFloat(chats.count - i) * MonosView.cellW + MonosView.cellW / 2
    }
    private var doorRect: CGRect { CGRect(x: doorX, y: MonosView.ground - MonosView.doorH, width: MonosView.doorW, height: MonosView.doorH) }

    override func cabinets() -> [(Provider, CGRect)] {
        let x0 = doorX - 12 - CGFloat(chats.count) * MonosView.cellW - 130
        let G = MonosView.ground
        return [(.claude, CGRect(x: x0, y: G - 88, width: 54, height: 86)),
                (.chatgpt, CGRect(x: x0 + 62, y: G - 88, width: 54, height: 86))]
    }

    override func actorIndex(at p: NSPoint) -> Int? {
        for i in chats.indices where abs(p.x - slotX(i)) < MonosView.cellW / 2 && p.y > 40 { return i }
        return nil
    }
    /// De dónde sale el humo (en puntos de la vista, ya escalados).
    override func smokeSource(_ i: Int) -> NSPoint? {
        guard i < chats.count, chats[i].mood == .needsYou || chats[i].mood == .done, age(chats[i]) > 2.6 else { return nil }
        let k = MonosView.drawScale
        return NSPoint(x: slotX(i) * k, y: 50 * k)
    }

    override func mouseUp(with event: NSEvent) {
        let p = local(event)
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
        let k = MonosView.drawScale
        cg.saveGState()
        cg.scaleBy(x: k, y: k)
        drawDropHint(cg, CGRect(x: 2, y: 30, width: W - 4, height: MonosView.H - 40))
        cg.setLineCap(.round); cg.setLineJoin(.round)

        var open: CGFloat = 0
        var plam: CGFloat = -1
        for c in chats {
            let a = age(c)
            let d: CGFloat = a < 0 ? 0 : a < 0.14 ? ease(a / 0.14) : a < 1.15 ? 1 : 1 - ease((a - 1.15) / 0.25)
            open = max(open, d)
            if a >= 0 && a < 0.9 { plam = max(plam, a) }
        }
        drawDoor(cg, open: open)
        drawCabinets(cg)
        for (i, c) in chats.enumerated() { drawApe(cg, c, i) }

        if plam >= 0 {
            let s = 0.6 + 0.6 * ease(plam / 0.18)
            let alpha = 1 - clamp01((plam - 0.6) / 0.3)
            cg.saveGState()
            cg.translateBy(x: doorRect.midX - 6, y: doorRect.minY - 6)
            cg.rotate(by: -0.18); cg.scaleBy(x: s, y: s)
            text("¡PLAM!", Fonts.rounded(24, .black), Palette.rgb(0xE5484D, alpha), center: .zero, halo: Palette.rgb(0xFFFFFF, alpha))
            cg.restoreGState()
        }
        if chats.isEmpty {
            pill(needsPermission ? "Dame permiso · toca la puerta" : "Aún no hay monos", center: CGPoint(x: doorRect.midX - 40, y: doorRect.minY - 14), maxW: 240)
        }
        if let hp = hoverPoint, doorRect.contains(hp), !(chats.isEmpty && needsPermission) { drawUsageCard(cg) }
        cg.restoreGState()
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

    private func drawDoor(_ cg: CGContext, open: CGFloat) {
        let r = doorRect
        let wood = Palette.rgb(0xA8683A), woodDark = Palette.rgb(0x7A4522), woodLight = Palette.rgb(0xC98A55)
        rrect(cg, r.insetBy(dx: -7, dy: -7).offsetBy(dx: 0, dy: 3.5), 4, woodDark, line: 2.5)
        rrect(cg, r, 2, Palette.rgb(0x2A1F1A), line: 2)
        cg.setFillColor(NSColor.black.withAlphaComponent(0.12).cgColor)
        cg.fillEllipse(in: CGRect(x: r.minX - 10, y: r.maxY - 3, width: r.width + 20, height: 8))
        let w = r.width * (1 - 0.82 * open)
        let skew = 10 * open
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.maxX - w, y: r.minY - skew)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - w, y: r.maxY + skew)); p.closeSubpath()
        fillStroke(cg, p, open > 0.5 ? woodLight : wood, line: 2.5)
        if open < 0.35 {
            rrect(cg, CGRect(x: r.minX + 10, y: r.minY + 12, width: r.width - 20, height: 50), 4, woodDark.withAlphaComponent(0.35), line: 1.5)
            rrect(cg, CGRect(x: r.minX + 10, y: r.minY + 74, width: r.width - 20, height: 64), 4, woodDark.withAlphaComponent(0.35), line: 1.5)
            let plate = CGRect(x: r.minX + 13, y: r.minY + 26, width: r.width - 26, height: 22)
            rrect(cg, plate, 3, Palette.rgb(0xE9C46A), line: 1.5)
            text("MONOS S.A.", Fonts.rounded(7.5, .black), Palette.outline, center: CGPoint(x: plate.midX, y: plate.midY))
            ellipse(cg, CGRect(x: r.minX + 8, y: r.midY + 4, width: 9, height: 9), Palette.rgb(0xF4D35E), line: 1.8)
            if let first = usageLines.first, let pct = Rx.first(first, "[0-9]+ ?%") {
                text(pct, Fonts.rounded(15, .black), Palette.rgb(0xFFF7E2), center: CGPoint(x: r.midX, y: r.minY + 106), halo: woodDark)
            }
        }
    }

    // MARK: El simio

    private func drawApe(_ cg: CGContext, _ c: Chat, _ i: Int) {
        let L = look(c)
        let a = age(c)
        let ph = CGFloat(seed(c.key) % 100) / 15
        let sx = slotX(i)
        let G = MonosView.ground

        let walking = a >= 0.22 && a < 1.5
        let pulling = a >= 1.5 && a < 2.15
        let opening = a >= 2.15 && a < 2.6
        if a < 0.22 { return }
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
        let lidOpen: CGFloat = opening ? ease((a - 2.15) / 0.45) : 1
        let hover = hoverIndex == i
        let waiting = c.mood == .needsYou || c.mood == .done

        cg.setFillColor(NSColor.black.withAlphaComponent(0.14).cgColor)
        cg.fillEllipse(in: CGRect(x: sx - 50, y: G - 4, width: 100, height: 9))

        var headY: CGFloat = 80
        var shake: CGFloat = 0
        switch c.mood {
        case .working: headY += sin(t * 5 + ph) * 1.4
        case .needsYou: headY -= 6; shake = sin(t * 30 + ph) * 1.6
        case .done: headY -= 4; shake = sin(t * 22 + ph) * 0.8
        case .idle: headY = 106
        }
        if hover && c.mood != .idle { headY -= 3 }
        let hx = sx + shake

        drawTorso(cg, L, x: sx, top: headY + 20)
        drawHead(cg, L, x: hx, y: headY, mood: c.mood, ph: ph)

        // Portátil (por detrás) y escritorio
        drawDesk(cg, x: sx, scale: 1)
        let lidH = 40 * lidOpen
        let lidR = CGRect(x: sx - 32, y: 140 - lidH, width: 64, height: lidH)
        if c.mood == .working && lidOpen > 0.9 {
            cg.setFillColor(Palette.rgb(0x9FD3FF, 0.12 + 0.06 * sin(t * 9 + ph)).cgColor)
            cg.fillEllipse(in: CGRect(x: hx - 28, y: headY - 10, width: 56, height: 36))
        }
        rrect(cg, lidR, 5, Palette.rgb(0xC9CDD6), line: 2.2)
        if lidOpen > 0.8 {
            let b = CGMutablePath()
            b.move(to: CGPoint(x: sx - 7, y: 124)); b.addQuadCurve(to: CGPoint(x: sx + 7, y: 122.5), control: CGPoint(x: sx - 1, y: 133))
            b.addQuadCurve(to: CGPoint(x: sx - 7, y: 124), control: CGPoint(x: sx, y: 128.5))
            fillStroke(cg, b, L.sticker, line: 1.4)
        }
        rrect(cg, CGRect(x: sx - 35, y: 138, width: 70, height: 5), 2, Palette.rgb(0x9AA0AC), line: 1.6)

        // Manos (de simio)
        let hand = L.skin.blended(withFraction: 0.15, of: .black) ?? L.skin
        switch c.mood {
        case .working:
            let l: CGFloat = sin(t * 18 + ph) > 0 ? 3 : -2
            let r: CGFloat = sin(t * 18 + ph + 1.6) > 0 ? 3 : -2
            ellipse(cg, CGRect(x: sx - 41, y: 127 + l, width: 15, height: 12), hand, line: 1.8)
            ellipse(cg, CGRect(x: sx + 26, y: 127 + r, width: 15, height: 12), hand, line: 1.8)
            // trocitos de código saliendo del portátil
            for n in 0..<3 {
                let q = (t * 0.9 + CGFloat(n) / 3 + ph).truncatingRemainder(dividingBy: 1)
                let sym = ["</>", "{ }", "01", "✓", "#"][(Int(t * 0.9 + ph) + n) % 5]
                text(sym, Fonts.rounded(9, .heavy), Palette.rgb(0x1E7A33, 1 - q),
                     center: CGPoint(x: sx + 40 + q * 10 + CGFloat(n) * 4, y: 120 - q * 46))
            }
            // indicador verde de trabajando
            let dot = CGRect(x: sx - 38, y: 100, width: 10, height: 10)
            ellipse(cg, dot, Palette.rgb(0x5BD16B, 0.6 + 0.4 * abs(sin(t * 4))), line: 1.6)
        case .needsYou, .done:
            // golpea la mesa con el puño
            let bang: CGFloat = abs(sin(t * (c.mood == .needsYou ? 9 : 5) + ph)) * 10
            ellipse(cg, CGRect(x: sx + 28, y: 124 - bang, width: 16, height: 14), hand, line: 1.8)
            ellipse(cg, CGRect(x: sx - 42, y: 128, width: 15, height: 12), hand, line: 1.8)
            if bang < 1.5 { text("¡pum!", Fonts.rounded(10, .black), Palette.alert, center: CGPoint(x: sx + 46, y: 118), halo: .white) }
        case .idle:
            ellipse(cg, CGRect(x: sx - 32, y: 96, width: 15, height: 11), hand, line: 1.8)
            ellipse(cg, CGRect(x: sx + 17, y: 96, width: 15, height: 11), hand, line: 1.8)
            z(cg, x: hx + 26, y: headY - 24, ph: ph)
        }
        if waiting {
            // vapor saliendo por las orejas
            for s in [-1.0, 1.0] as [CGFloat] {
                for n in 0..<2 {
                    let q = (t * 1.6 + CGFloat(n) * 0.5 + ph).truncatingRemainder(dividingBy: 1)
                    let r = 4 + q * 7
                    cg.setFillColor(NSColor(white: 0.95, alpha: 0.85 * (1 - q)).cgColor)
                    cg.fillEllipse(in: CGRect(x: hx + s * (30 + q * 14) - r, y: headY - 4 - q * 18 - r, width: r * 2, height: r * 2))
                    cg.setStrokeColor(Palette.outline.withAlphaComponent(0.35 * (1 - q)).cgColor); cg.setLineWidth(1.2)
                    cg.strokeEllipse(in: CGRect(x: hx + s * (30 + q * 14) - r, y: headY - 4 - q * 18 - r, width: r * 2, height: r * 2))
                }
            }
        }

        pill(c.shortTitle, center: CGPoint(x: sx, y: G + 14), maxW: MonosView.cellW - 4,
             fill: waiting ? Palette.rgb(0xFFCC33) : (c.mood == .working ? Palette.rgb(0xB4F5B9) : Palette.rgb(0xFFFFFF, 0.93)))
        var sub = ""
        switch c.mood {
        case .working: sub = elapsed(c.since)
        case .needsYou, .done: sub = ago(c.since)
        case .idle: sub = ""
        }
        if !sub.isEmpty, lidOpen > 0.9 {
            text(sub, Fonts.rounded(12, .black), Palette.outline, center: CGPoint(x: sx, y: 111), halo: NSColor.white)
        }
        let bdg = CGRect(x: sx + 38, y: 150, width: 17, height: 17)
        ellipse(cg, bdg, Palette.badge(c.provider), line: 1.6)
        text(c.provider.letter, Fonts.rounded(9, .black), .white, center: CGPoint(x: bdg.midX, y: bdg.midY))
    }

    private func drawDesk(_ cg: CGContext, x: CGFloat, scale s: CGFloat) {
        let G = MonosView.ground
        cg.saveGState()
        cg.translateBy(x: x, y: G); cg.scaleBy(x: s, y: s); cg.translateBy(x: -x, y: -G)
        rrect(cg, CGRect(x: x - 42, y: 146, width: 7, height: G - 146), 2, Palette.rgb(0xB07A45), line: 1.8)
        rrect(cg, CGRect(x: x + 35, y: 146, width: 7, height: G - 146), 2, Palette.rgb(0xB07A45), line: 1.8)
        rrect(cg, CGRect(x: x - 48, y: 141, width: 96, height: 9), 3, Palette.rgb(0xD9A066), line: 2.2)
        cg.restoreGState()
    }

    private func drawTorso(_ cg: CGContext, _ L: ApeLook, x: CGFloat, top: CGFloat) {
        // Hombros anchos de simio
        let r = CGRect(x: x - 33, y: top, width: 66, height: 150 - top)
        let fill = L.outfit == 5 ? L.fur : L.shirt
        rrect(cg, r, 20, fill, line: 2.2)
        cg.saveGState(); cg.addPath(CGPath(roundedRect: r, cornerWidth: 20, cornerHeight: 20, transform: nil)); cg.clip()
        switch L.outfit {
        case 1:
            cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(1.5)
            cg.move(to: CGPoint(x: x - 6, y: top + 4)); cg.addLine(to: CGPoint(x: x - 6, y: top + 18))
            cg.move(to: CGPoint(x: x + 6, y: top + 4)); cg.addLine(to: CGPoint(x: x + 6, y: top + 18)); cg.strokePath()
        case 2:
            cg.setFillColor(NSColor.white.cgColor); cg.fill(CGRect(x: x - 8, y: top, width: 16, height: 30))
            let tie = CGMutablePath()
            tie.move(to: CGPoint(x: x - 3, y: top + 2)); tie.addLine(to: CGPoint(x: x + 3, y: top + 2))
            tie.addLine(to: CGPoint(x: x + 5, y: top + 24)); tie.addLine(to: CGPoint(x: x, y: top + 30)); tie.addLine(to: CGPoint(x: x - 5, y: top + 24)); tie.closeSubpath()
            fillStroke(cg, tie, L.shirt2, line: 1.4)
        case 3:
            cg.setFillColor(L.shirt2.withAlphaComponent(0.8).cgColor)
            var y = top + 6
            while y < 150 { cg.fill(CGRect(x: x - 34, y: y, width: 68, height: 4)); y += 9 }
        case 4:
            var d = Dice(L.shirt.description + L.shirt2.description)
            for _ in 0..<9 {
                let px = x - 30 + CGFloat(d.next() % 60), py = top + 4 + CGFloat(d.next() % 30)
                cg.setFillColor(L.shirt2.cgColor); cg.fillEllipse(in: CGRect(x: px, y: py, width: 6, height: 6))
            }
        case 5:
            ellipse(cg, CGRect(x: x - 18, y: top + 8, width: 36, height: 30), L.skin.withAlphaComponent(0.6), line: 0)
        default: break
        }
        cg.restoreGState()
    }

    private func drawHead(_ cg: CGContext, _ L: ApeLook, x: CGFloat, y: CGFloat, mood: Mood, ph: CGFloat) {
        // Orejas pequeñas
        for s in [-1.0, 1.0] as [CGFloat] {
            let e = CGRect(x: x + s * 27 - 7, y: y - 4, width: 14, height: 15)
            ellipse(cg, e, L.fur)
            ellipse(cg, e.insetBy(dx: 3.5, dy: 3.5), L.skin, line: 0)
        }
        if L.earring { ellipse(cg, CGRect(x: x - 31, y: y + 9, width: 6, height: 6), Palette.rgb(0xF4D35E), line: 1.4) }
        // Cráneo con cresta de pelo
        let skull = CGMutablePath()
        skull.move(to: CGPoint(x: x - 26, y: y + 8))
        skull.addCurve(to: CGPoint(x: x, y: y - 30), control1: CGPoint(x: x - 30, y: y - 20), control2: CGPoint(x: x - 16, y: y - 31))
        skull.addCurve(to: CGPoint(x: x + 26, y: y + 8), control1: CGPoint(x: x + 16, y: y - 31), control2: CGPoint(x: x + 30, y: y - 20))
        skull.addCurve(to: CGPoint(x: x - 26, y: y + 8), control1: CGPoint(x: x + 20, y: y + 30), control2: CGPoint(x: x - 20, y: y + 30))
        fillStroke(cg, skull, L.fur)
        // mechones
        cg.setStrokeColor(L.furDark.cgColor); cg.setLineWidth(1.6)
        for k in -1...1 {
            cg.move(to: CGPoint(x: x + CGFloat(k) * 7, y: y - 29)); cg.addLine(to: CGPoint(x: x + CGFloat(k) * 9, y: y - 22))
        }
        cg.strokePath()

        // Máscara de la cara: zona de ojos + hocico grande
        let face = CGMutablePath()
        face.addEllipse(in: CGRect(x: x - 21, y: y - 16, width: 22, height: 19))
        face.addEllipse(in: CGRect(x: x - 1, y: y - 16, width: 22, height: 19))
        face.addEllipse(in: CGRect(x: x - 19, y: y - 4, width: 38, height: 28))
        cg.addPath(face); cg.setFillColor(L.skin.cgColor); cg.fillPath()
        cg.addPath(CGPath(ellipseIn: CGRect(x: x - 19, y: y - 4, width: 38, height: 28), transform: nil))
        cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(2); cg.strokePath()

        // Ojos con párpados pesados
        let ey = y - 6
        let lid: CGFloat
        switch mood {
        case .working: lid = max(0.25, L.lid - 0.1)
        case .needsYou: lid = 0.05
        case .done: lid = 0.15
        case .idle: lid = 1
        }
        let blink = mood != .idle && (t + ph).truncatingRemainder(dividingBy: 4.6) < 0.12
        for s in [-1.0, 1.0] as [CGFloat] {
            let ex = x + s * 9.5
            let er = CGRect(x: ex - 6, y: ey - 5, width: 12, height: 10)
            if mood == .idle || blink {
                cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(2)
                cg.move(to: CGPoint(x: ex - 5, y: ey + 1)); cg.addQuadCurve(to: CGPoint(x: ex + 5, y: ey + 1), control: CGPoint(x: ex, y: ey + 4)); cg.strokePath()
                continue
            }
            ellipse(cg, er, .white, line: 1.6)
            let py: CGFloat = mood == .working ? 2.5 : 0.5
            let px: CGFloat = mood == .working ? 0 : (mood == .needsYou ? 0 : sin(t * 0.7 + ph) * 1.5)
            cg.setFillColor(Palette.outline.cgColor)
            cg.fillEllipse(in: CGRect(x: ex - 2.8 + px, y: ey - 2.8 + py, width: 5.6, height: 5.8))
            // párpado
            cg.saveGState(); cg.addEllipse(in: er); cg.clip()
            cg.setFillColor((L.skin.blended(withFraction: 0.2, of: .black) ?? L.skin).cgColor)
            cg.fill(CGRect(x: er.minX, y: er.minY, width: er.width, height: er.height * lid))
            cg.restoreGState()
            cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(1.6)
            cg.move(to: CGPoint(x: er.minX + 0.5, y: er.minY + er.height * lid)); cg.addLine(to: CGPoint(x: er.maxX - 0.5, y: er.minY + er.height * lid)); cg.strokePath()
        }
        // Ceja de simio (enfadada cuando te espera)
        let angry: CGFloat = mood == .needsYou ? 5 : (mood == .done ? 3 : 0)
        cg.setStrokeColor(L.furDark.cgColor); cg.setLineWidth(4.5); cg.setLineCap(.round)
        cg.move(to: CGPoint(x: x - 19, y: ey - 9 - angry * 0.4))
        cg.addQuadCurve(to: CGPoint(x: x, y: ey - 8 + angry), control: CGPoint(x: x - 10, y: ey - 14))
        cg.addQuadCurve(to: CGPoint(x: x + 19, y: ey - 9 - angry * 0.4), control: CGPoint(x: x + 10, y: ey - 14))
        cg.strokePath()

        // Gafas
        if mood != .idle {
            switch L.eyes {
            case 1:
                cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(1.8)
                cg.strokeEllipse(in: CGRect(x: x - 18, y: ey - 7, width: 16, height: 14)); cg.strokeEllipse(in: CGRect(x: x + 2, y: ey - 7, width: 16, height: 14))
            case 2:
                rrect(cg, CGRect(x: x - 20, y: ey - 5, width: 18, height: 11), 4, Palette.rgb(0x1C1C24), line: 1.6)
                rrect(cg, CGRect(x: x + 2, y: ey - 5, width: 18, height: 11), 4, Palette.rgb(0x1C1C24), line: 1.6)
                cg.setFillColor(NSColor.white.withAlphaComponent(0.6).cgColor)
                cg.fill(CGRect(x: x - 16, y: ey - 3, width: 5, height: 2)); cg.fill(CGRect(x: x + 6, y: ey - 3, width: 5, height: 2))
            case 3:
                cg.setStrokeColor(Palette.rgb(0xE9C46A).cgColor); cg.setLineWidth(2)
                cg.strokeEllipse(in: CGRect(x: x + 2, y: ey - 7, width: 15, height: 14))
                cg.move(to: CGPoint(x: x + 16, y: ey + 3)); cg.addLine(to: CGPoint(x: x + 20, y: ey + 22)); cg.strokePath()
            case 4:
                cg.setStrokeColor(L.shirt2.cgColor); cg.setLineWidth(3)
                cg.stroke(CGRect(x: x - 19, y: ey - 6, width: 16, height: 12)); cg.stroke(CGRect(x: x + 3, y: ey - 6, width: 16, height: 12))
            default: break
            }
        }

        // Nariz (orificios grandes)
        cg.setFillColor(Palette.outline.cgColor)
        cg.fillEllipse(in: CGRect(x: x - 6, y: y + 3, width: 4.5, height: 3.4))
        cg.fillEllipse(in: CGRect(x: x + 1.5, y: y + 3, width: 4.5, height: 3.4))

        // Boca ancha
        let my = y + 14
        cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(2)
        if mood == .needsYou {
            let m = CGMutablePath(); m.addRoundedRect(in: CGRect(x: x - 10, y: my - 3, width: 20, height: 9), cornerWidth: 4, cornerHeight: 4)
            fillStroke(cg, m, Palette.rgb(0x5A1E28), line: 1.8)
            cg.setFillColor(NSColor.white.cgColor)
            cg.fill(CGRect(x: x - 8, y: my - 2, width: 16, height: 2.5))
        } else if mood == .idle {
            cg.move(to: CGPoint(x: x - 7, y: my + 1)); cg.addQuadCurve(to: CGPoint(x: x + 7, y: my + 1), control: CGPoint(x: x, y: my + 4)); cg.strokePath()
        } else {
            switch L.mouth {
            case 1:
                cg.move(to: CGPoint(x: x - 11, y: my + 1)); cg.addQuadCurve(to: CGPoint(x: x + 11, y: my - 2), control: CGPoint(x: x + 4, y: my + 5)); cg.strokePath()
            case 2:
                let m = CGMutablePath(); m.addRoundedRect(in: CGRect(x: x - 10, y: my - 2, width: 20, height: 6), cornerWidth: 2, cornerHeight: 2)
                fillStroke(cg, m, .white, line: 1.6)
                cg.setLineWidth(1)
                for k in -1...1 { cg.move(to: CGPoint(x: x + CGFloat(k) * 5, y: my - 2)); cg.addLine(to: CGPoint(x: x + CGFloat(k) * 5, y: my + 4)) }
                cg.strokePath()
            case 3:
                cg.move(to: CGPoint(x: x - 11, y: my)); cg.addLine(to: CGPoint(x: x + 11, y: my)); cg.strokePath()
                ellipse(cg, CGRect(x: x + 1, y: my, width: 7, height: 7), Palette.rgb(0xFF7FA0), line: 1.3)
            case 4:
                cg.move(to: CGPoint(x: x - 9, y: my + 2)); cg.addLine(to: CGPoint(x: x + 9, y: my + 2)); cg.strokePath()
                let mus = CGMutablePath()
                mus.move(to: CGPoint(x: x, y: my - 3)); mus.addQuadCurve(to: CGPoint(x: x - 13, y: my - 1), control: CGPoint(x: x - 7, y: my + 3))
                mus.addQuadCurve(to: CGPoint(x: x, y: my - 3), control: CGPoint(x: x - 7, y: my - 5))
                mus.move(to: CGPoint(x: x, y: my - 3)); mus.addQuadCurve(to: CGPoint(x: x + 13, y: my - 1), control: CGPoint(x: x + 7, y: my + 3))
                mus.addQuadCurve(to: CGPoint(x: x, y: my - 3), control: CGPoint(x: x + 7, y: my - 5))
                fillStroke(cg, mus, L.furDark, line: 1)
            default:
                cg.move(to: CGPoint(x: x - 11, y: my)); cg.addQuadCurve(to: CGPoint(x: x + 11, y: my), control: CGPoint(x: x, y: my - 1.5)); cg.strokePath()
            }
        }
        drawHat(cg, L, x: x, y: y)
    }

    private func drawHat(_ cg: CGContext, _ L: ApeLook, x: CGFloat, y: CGFloat) {
        let top = y - 26
        switch L.hat {
        case 1:
            let p = CGMutablePath(); p.addArc(center: CGPoint(x: x, y: top + 8), radius: 23, startAngle: .pi, endAngle: 0, clockwise: false); p.closeSubpath()
            fillStroke(cg, p, L.shirt2)
            rrect(cg, CGRect(x: x - 25, y: top + 4, width: 50, height: 9), 4, L.shirt2.blended(withFraction: 0.3, of: .white) ?? L.shirt2)
            ellipse(cg, CGRect(x: x - 6, y: top - 22, width: 12, height: 12), .white)
        case 2:
            let p = CGMutablePath(); p.addArc(center: CGPoint(x: x, y: top + 7), radius: 22, startAngle: .pi, endAngle: 0, clockwise: false); p.closeSubpath()
            fillStroke(cg, p, L.shirt2)
            rrect(cg, CGRect(x: x - 34, y: top + 2, width: 36, height: 7), 3, L.shirt2)
        case 3:
            cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(4.5)
            cg.addArc(center: CGPoint(x: x, y: y), radius: 30, startAngle: .pi * 1.05, endAngle: .pi * 1.95, clockwise: false); cg.strokePath()
            cg.setStrokeColor(L.shirt2.cgColor); cg.setLineWidth(2.5)
            cg.addArc(center: CGPoint(x: x, y: y), radius: 30, startAngle: .pi * 1.05, endAngle: .pi * 1.95, clockwise: false); cg.strokePath()
            rrect(cg, CGRect(x: x - 36, y: y - 6, width: 11, height: 19), 4, L.shirt2)
            rrect(cg, CGRect(x: x + 25, y: y - 6, width: 11, height: 19), 4, L.shirt2)
        case 4:
            let p = CGMutablePath(); p.move(to: CGPoint(x: x - 12, y: top + 4)); p.addLine(to: CGPoint(x: x + 3, y: top - 28)); p.addLine(to: CGPoint(x: x + 14, y: top + 4)); p.closeSubpath()
            fillStroke(cg, p, L.shirt2)
            ellipse(cg, CGRect(x: x - 1, y: top - 34, width: 9, height: 9), Palette.rgb(0xFFD60A))
        case 5:
            rrect(cg, CGRect(x: x - 36, y: top + 2, width: 72, height: 8), 4, Palette.rgb(0xA0703C))
            rrect(cg, CGRect(x: x - 17, y: top - 18, width: 34, height: 24), 8, Palette.rgb(0xA0703C))
            cg.setFillColor(Palette.outline.cgColor); cg.fill(CGRect(x: x - 17, y: top - 1, width: 34, height: 3))
        case 6:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x + 12, y: top + 2)); p.addLine(to: CGPoint(x: x + 2, y: top - 8)); p.addLine(to: CGPoint(x: x + 2, y: top + 10)); p.closeSubpath()
            p.move(to: CGPoint(x: x + 12, y: top + 2)); p.addLine(to: CGPoint(x: x + 22, y: top - 8)); p.addLine(to: CGPoint(x: x + 22, y: top + 10)); p.closeSubpath()
            fillStroke(cg, p, L.shirt2, line: 1.8)
            ellipse(cg, CGRect(x: x + 8, y: top - 2, width: 8, height: 8), L.shirt2, line: 1.6)
        case 7:
            ellipse(cg, CGRect(x: x - 22, y: top - 26, width: 22, height: 22), .white)
            ellipse(cg, CGRect(x: x - 2, y: top - 28, width: 24, height: 24), .white)
            ellipse(cg, CGRect(x: x - 12, y: top - 34, width: 24, height: 22), .white)
            rrect(cg, CGRect(x: x - 19, y: top - 10, width: 38, height: 16), 3, .white)
        case 8:
            for k in 0..<5 {
                let ang = CGFloat.pi * (1.1 + 0.2 * CGFloat(k))
                let fx = x + cos(ang) * 22, fy = y - 6 + sin(ang) * 22
                ellipse(cg, CGRect(x: fx - 5, y: fy - 5, width: 10, height: 10), k % 2 == 0 ? L.shirt2 : Palette.rgb(0xFFD60A), line: 1.4)
            }
        case 9:
            ellipse(cg, CGRect(x: x - 27, y: top - 6, width: 48, height: 16), L.shirt2)
            ellipse(cg, CGRect(x: x - 3, y: top - 10, width: 5, height: 6), Palette.outline, line: 0)
        case 10:
            let p = CGMutablePath(); p.addArc(center: CGPoint(x: x, y: top + 10), radius: 25, startAngle: .pi, endAngle: 0, clockwise: false); p.closeSubpath()
            fillStroke(cg, p, L.shirt2)
            cg.setFillColor(NSColor.white.cgColor)
            for k in 0..<3 { cg.fillEllipse(in: CGRect(x: x - 14 + CGFloat(k) * 11, y: top - 2, width: 4, height: 4)) }
            let knot = CGMutablePath(); knot.move(to: CGPoint(x: x + 24, y: top + 8)); knot.addLine(to: CGPoint(x: x + 34, y: top + 16)); knot.addLine(to: CGPoint(x: x + 28, y: top + 20)); knot.closeSubpath()
            fillStroke(cg, knot, L.shirt2, line: 1.6)
        default: break
        }
    }

    private func drawStanding(_ cg: CGContext, _ L: ApeLook, x: CGFloat, walk: CGFloat, pulling: Bool) {
        let G = MonosView.ground
        let bob = abs(sin(walk)) * 3
        let headY: CGFloat = 90 - bob
        cg.setFillColor(NSColor.black.withAlphaComponent(0.14).cgColor)
        cg.fillEllipse(in: CGRect(x: x - 22, y: G - 4, width: 44, height: 8))
        let sw = sin(walk) * 7
        rrect(cg, CGRect(x: x - 15 + sw, y: 150 - bob, width: 13, height: G - 150 + bob - 2), 6, L.fur)
        rrect(cg, CGRect(x: x + 2 - sw, y: 150 - bob, width: 13, height: G - 150 + bob - 2), 6, L.fur)
        drawTorso(cg, L, x: x, top: headY + 20)
        drawHead(cg, L, x: x, y: headY, mood: .working, ph: 0)
        let hand = L.skin.blended(withFraction: 0.15, of: .black) ?? L.skin
        if pulling {
            ellipse(cg, CGRect(x: x + 14, y: 134, width: 14, height: 12), hand, line: 1.8)
            text("✨", Fonts.rounded(13, .bold), Palette.outline, center: CGPoint(x: x + 34, y: 126 - sin(t * 12) * 3))
        } else {
            rrect(cg, CGRect(x: x - 40, y: 120 - bob, width: 14, height: 32), 3, Palette.rgb(0xC9CDD6), line: 1.8)
            ellipse(cg, CGRect(x: x - 36, y: 126 - bob, width: 14, height: 12), hand, line: 1.8)
        }
    }
}
