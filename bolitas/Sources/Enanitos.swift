// Bolitas — estilo «Fábrica de enanitos»: una cadena de montaje de regalos.
// Cada chat es un enanito distinto con su propio trabajo en la cadena
// (martillo, papel, lazo, sello, saco…). Al añadir uno, salta de dentro de una caja de regalo.
// La cinta solo se mueve mientras alguno trabaja.

import AppKit

struct ElfLook {
    var hat, tunic, trim: NSColor
    var skin: NSColor
    var beard: Bool
    var glasses: Bool
    var job: Int
    init(_ key: String, job: Int) {
        var d = Dice(key)
        let hats: [UInt32] = [0xD7263D, 0x1B998B, 0x2E86AB, 0xF46036, 0x6A4C93, 0x2A9D8F, 0xE63946, 0x3A86FF]
        let tunics: [UInt32] = [0x2D6A4F, 0xC1121F, 0x1D3557, 0x588157, 0x9D0208, 0x386641, 0x5E548E]
        let skins: [UInt32] = [0xF8D5B8, 0xF1C27D, 0xE0AC69, 0xC68642, 0xFFDBAC, 0x8D5524]
        hat = Palette.rgb(d.pick(hats)); tunic = Palette.rgb(d.pick(tunics)); trim = Palette.rgb(d.pick([0xFFD166, 0xFFFFFF, 0x06D6A0, 0xFFB4A2]))
        skin = Palette.rgb(d.pick(skins)); beard = d.chance(0.45); glasses = d.chance(0.3)
        self.job = job
    }
}

final class ElvesView: StageView {
    static let cellW: CGFloat = 92, H: CGFloat = 200, belt: CGFloat = 132, pad: CGFloat = 70
    static let jobs = ["martillo", "papel", "lazo", "sello", "saco"]
    private var looks: [String: ElfLook] = [:]
    private var beltPos: CGFloat = 0
    private var lastT: CGFloat = 0
    var usageLines: [String] = []
    var onSignClick: (() -> Void)?

    override class func size(for count: Int) -> NSSize {
        NSSize(width: pad + CGFloat(max(1, count)) * cellW + 70, height: H)
    }
    private func look(_ c: Chat, _ i: Int) -> ElfLook {
        if let l = looks[c.key] { return l }
        let l = ElfLook(c.key, job: i % 5); looks[c.key] = l; return l
    }
    private func slotX(_ i: Int) -> CGFloat { ElvesView.pad + CGFloat(i) * ElvesView.cellW + ElvesView.cellW / 2 }
    private var signRect: CGRect { CGRect(x: 6, y: 18, width: 58, height: 44) }

    override func actorIndex(at p: NSPoint) -> Int? {
        for i in chats.indices where abs(p.x - slotX(i)) < ElvesView.cellW / 2 && p.y > 30 { return i }
        return nil
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if signRect.insetBy(dx: -4, dy: -4).contains(p) { onSignClick?(); return }
        super.mouseUp(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.clear(bounds)
        drawDropHint(cg, bounds.insetBy(dx: 2, dy: 20))
        cg.setLineCap(.round); cg.setLineJoin(.round)
        let dt = max(0, min(0.1, t - lastT)); lastT = t
        let anyWorking = chats.contains { $0.mood == .working }
        if anyWorking { beltPos += dt * 26 }

        let B = ElvesView.belt
        let W = bounds.width

        // Nieve suave
        for k in 0..<14 {
            let x = CGFloat((k * 73) % Int(max(W, 1))) + sin(t * 0.7 + CGFloat(k)) * 6
            let y = (CGFloat(k * 37) + t * 14).truncatingRemainder(dividingBy: B - 10) + 4
            cg.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            cg.fillEllipse(in: CGRect(x: x, y: y, width: 3.5, height: 3.5))
            cg.setStrokeColor(Palette.outline.withAlphaComponent(0.25).cgColor); cg.setLineWidth(0.6)
            cg.strokeEllipse(in: CGRect(x: x, y: y, width: 3.5, height: 3.5))
        }

        // Cartel de la fábrica (y del uso)
        cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(2)
        cg.move(to: CGPoint(x: signRect.midX, y: 4)); cg.addLine(to: CGPoint(x: signRect.midX, y: signRect.minY)); cg.strokePath()
        rrect(cg, signRect, 6, Palette.rgb(0xC1121F), line: 2.2)
        text("FÁBRICA", Fonts.rounded(9, .black), .white, center: CGPoint(x: signRect.midX, y: signRect.minY + 12))
        let pct = usageLines.first.flatMap { Rx.first($0, "[0-9]+ ?%") } ?? "uso?"
        text(pct, Fonts.rounded(13, .black), Palette.rgb(0xFFD166), center: CGPoint(x: signRect.midX, y: signRect.minY + 30))

        // Tolva de entrada y saco de salida
        let hop = CGMutablePath()
        hop.move(to: CGPoint(x: 26, y: B - 30)); hop.addLine(to: CGPoint(x: 62, y: B - 30)); hop.addLine(to: CGPoint(x: 56, y: B)); hop.addLine(to: CGPoint(x: 32, y: B)); hop.closeSubpath()
        fillStroke(cg, hop, Palette.rgb(0x8D99AE))
        let sx = W - 40
        let sack = CGMutablePath()
        sack.move(to: CGPoint(x: sx - 22, y: B + 52)); sack.addQuadCurve(to: CGPoint(x: sx + 22, y: B + 52), control: CGPoint(x: sx, y: B + 62))
        sack.addQuadCurve(to: CGPoint(x: sx + 12, y: B - 8), control: CGPoint(x: sx + 30, y: B + 10))
        sack.addLine(to: CGPoint(x: sx - 12, y: B - 8))
        sack.addQuadCurve(to: CGPoint(x: sx - 22, y: B + 52), control: CGPoint(x: sx - 30, y: B + 10)); sack.closeSubpath()
        fillStroke(cg, sack, Palette.rgb(0xB5651D))
        rrect(cg, CGRect(x: sx - 14, y: B - 12, width: 28, height: 7), 3, Palette.rgb(0xFFD166), line: 1.8)

        // Enanitos (detrás de la cinta)
        for (i, c) in chats.enumerated() { drawElf(cg, c, i) }

        // Cinta transportadora
        let beltR = CGRect(x: 40, y: B, width: W - 86, height: 14)
        rrect(cg, beltR, 7, Palette.rgb(0x495057), line: 2.2)
        cg.saveGState(); cg.addPath(CGPath(roundedRect: beltR, cornerWidth: 7, cornerHeight: 7, transform: nil)); cg.clip()
        cg.setStrokeColor(Palette.rgb(0x868E96).cgColor); cg.setLineWidth(2)
        var x = beltR.minX - 12 + beltPos.truncatingRemainder(dividingBy: 12)
        while x < beltR.maxX + 12 { cg.move(to: CGPoint(x: x, y: B + 2)); cg.addLine(to: CGPoint(x: x - 5, y: B + 12)); x += 12 }
        cg.strokePath(); cg.restoreGState()
        // Patas de la cinta
        var lx = beltR.minX + 20
        while lx < beltR.maxX - 10 {
            rrect(cg, CGRect(x: lx, y: B + 14, width: 6, height: ElvesView.H - B - 34), 2, Palette.rgb(0x6C757D), line: 1.6)
            lx += 110
        }

        // Paquetes que avanzan: su aspecto depende de cuántos enanitos han pasado ya
        let spacing: CGFloat = 70
        var px = beltR.minX + 10 + beltPos.truncatingRemainder(dividingBy: spacing)
        while px < beltR.maxX - 18 {
            var stage = 0
            for i in chats.indices where slotX(i) < px - 6 { stage = i + 1 }
            drawPackage(cg, x: px, y: B, stage: min(stage, 5))
            px += spacing
        }

        // Nombres
        for (i, c) in chats.enumerated() where age(c) > 0.9 {
            pill(c.shortTitle, center: CGPoint(x: slotX(i), y: ElvesView.H - 12), maxW: ElvesView.cellW - 4)
        }
        if chats.isEmpty {
            pill(needsPermission ? "Dame permiso · toca aquí" : "Arrastra aquí un chat", center: CGPoint(x: W / 2 + 10, y: 70), maxW: 220)
        }
        if let hp = hoverPoint, signRect.contains(hp) { drawUsageCard(cg) }
    }

    private func drawUsageCard(_ cg: CGContext) {
        let lines = usageLines.isEmpty ? ["Toca el cartel para", "ver tu uso de Claude"] : usageLines
        let font = Fonts.rounded(11, .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let w = (lines.map { ($0 as NSString).size(withAttributes: attrs).width }.max() ?? 80) + 20
        let h = CGFloat(lines.count) * 15 + 12
        let r = CGRect(x: signRect.maxX + 6, y: signRect.minY, width: w, height: h)
        rrect(cg, r, 8, Palette.rgb(0xFFF7E2), line: 2)
        for (k, l) in lines.enumerated() { text(l, font, Palette.outline, center: CGPoint(x: r.midX, y: r.minY + 13 + CGFloat(k) * 15)) }
    }

    private func drawPackage(_ cg: CGContext, x: CGFloat, y: CGFloat, stage: Int) {
        let r = CGRect(x: x - 11, y: y - 20, width: 22, height: 20)
        let paper: [UInt32] = [0xC8A27A, 0xC8A27A, 0xE63946, 0xE63946, 0x2A9D8F, 0x2A9D8F]
        rrect(cg, r, 2, Palette.rgb(paper[stage]), line: 1.8)
        if stage >= 2 {
            cg.setFillColor(Palette.rgb(0xFFD166).cgColor)
            cg.fill(CGRect(x: x - 2, y: r.minY, width: 4, height: r.height)); cg.fill(CGRect(x: r.minX, y: r.midY - 2, width: r.width, height: 4))
        }
        if stage >= 3 {
            ellipse(cg, CGRect(x: x - 8, y: r.minY - 6, width: 8, height: 7), Palette.rgb(0xFFD166), line: 1.4)
            ellipse(cg, CGRect(x: x, y: r.minY - 6, width: 8, height: 7), Palette.rgb(0xFFD166), line: 1.4)
        }
        if stage >= 4 { text("✓", Fonts.rounded(9, .black), .white, center: CGPoint(x: x + 6, y: r.maxY - 5)) }
        if stage == 1 {
            cg.setStrokeColor(Palette.outline.withAlphaComponent(0.5).cgColor); cg.setLineWidth(1)
            cg.move(to: CGPoint(x: r.minX + 3, y: r.minY + 5)); cg.addLine(to: CGPoint(x: r.maxX - 3, y: r.minY + 5)); cg.strokePath()
        }
    }

    // MARK: El enanito

    private func drawElf(_ cg: CGContext, _ c: Chat, _ i: Int) {
        let L = look(c, i)
        let a = age(c)
        let ph = CGFloat(seed(c.key) % 100) / 15
        let x = slotX(i)
        let B = ElvesView.belt

        // Entrada: una caja de regalo aparece, se abre la tapa y el enanito sale de un salto.
        if a < 0.9 {
            let box = CGRect(x: x - 20, y: B - 32, width: 40, height: 32)
            let lidUp = a > 0.35 ? ease((a - 0.35) / 0.2) : 0
            let jump = a > 0.4 ? sin(clamp01((a - 0.4) / 0.5) * .pi) : 0
            if a > 0.4 { drawElfBody(cg, L, x: x, headY: B - 30 - jump * 40, mood: .working, ph: ph, pose: 0, armsUp: true) }
            rrect(cg, box, 3, Palette.rgb(0xE63946))
            cg.setFillColor(Palette.rgb(0xFFD166).cgColor); cg.fill(CGRect(x: x - 3, y: box.minY, width: 6, height: box.height))
            cg.saveGState()
            cg.translateBy(x: x + 22, y: box.minY - lidUp * 26); cg.rotate(by: lidUp * 1.1)
            rrect(cg, CGRect(x: -44, y: -8, width: 44, height: 9), 3, Palette.rgb(0xE63946))
            cg.restoreGState()
            if a > 0.35 { text("¡TACHÁN!", Fonts.rounded(13, .black), Palette.rgb(0xC1121F, 1 - clamp01((a - 0.7) / 0.2)), center: CGPoint(x: x, y: 18), halo: .white) }
            return
        }

        var headY: CGFloat = 70
        var pose: CGFloat = 0
        switch c.mood {
        case .working: pose = sin(t * 8 + ph); headY += pose * 1.5
        case .needsYou: headY -= abs(sin(t * 6 + ph)) * 8
        case .done: headY -= 2
        case .idle: headY = 84
        }
        drawElfBody(cg, L, x: x, headY: headY, mood: c.mood, ph: ph, pose: pose, armsUp: false)

        // Herramienta según el trabajo
        if c.mood == .working {
            switch L.job {
            case 0: // martillo
                let ang = -0.9 + (pose > 0 ? 1.1 : 0)
                cg.saveGState(); cg.translateBy(x: x + 14, y: B - 18); cg.rotate(by: ang)
                rrect(cg, CGRect(x: -2, y: -26, width: 4, height: 26), 2, Palette.rgb(0xA0703C), line: 1.4)
                rrect(cg, CGRect(x: -8, y: -32, width: 16, height: 8), 2, Palette.rgb(0x8D99AE), line: 1.6)
                cg.restoreGState()
                if pose < -0.6 { text("¡pum!", Fonts.rounded(8, .heavy), Palette.outline.withAlphaComponent(0.6), center: CGPoint(x: x + 28, y: B - 26)) }
            case 1: // papel de regalo
                cg.saveGState(); cg.translateBy(x: x, y: B - 22); cg.rotate(by: pose * 0.3)
                rrect(cg, CGRect(x: -14, y: -10, width: 28, height: 18), 2, Palette.rgb(0xE63946), line: 1.6)
                cg.setFillColor(Palette.rgb(0xFFFFFF, 0.8).cgColor)
                for k in 0..<3 { cg.fillEllipse(in: CGRect(x: -10 + CGFloat(k) * 9, y: -6, width: 4, height: 4)) }
                cg.restoreGState()
            case 2: // lazo
                let s = 0.8 + 0.25 * pose
                ellipse(cg, CGRect(x: x - 12 * s, y: B - 30, width: 11 * s, height: 9), Palette.rgb(0xFFD166), line: 1.5)
                ellipse(cg, CGRect(x: x + 1, y: B - 30, width: 11 * s, height: 9), Palette.rgb(0xFFD166), line: 1.5)
            case 3: // sello
                let up = pose > 0 ? 12 : 0
                rrect(cg, CGRect(x: x - 7, y: B - 40 - CGFloat(up), width: 14, height: 10), 2, Palette.rgb(0xA0703C), line: 1.5)
                rrect(cg, CGRect(x: x - 9, y: B - 31 - CGFloat(up), width: 18, height: 6), 2, Palette.rgb(0x6A4C93), line: 1.5)
                if up == 0 { text("OK", Fonts.rounded(8, .black), Palette.rgb(0x6A4C93), center: CGPoint(x: x + 18, y: B - 24)) }
            default: // carga al saco
                let lift = pose * 10
                rrect(cg, CGRect(x: x - 10, y: B - 44 - lift, width: 20, height: 18), 2, Palette.rgb(0x2A9D8F), line: 1.6)
            }
        }

        switch c.mood {
        case .needsYou:
            // campana que suena
            let sw = sin(t * 18 + ph) * 0.4
            cg.saveGState(); cg.translateBy(x: x + 26, y: headY - 20); cg.rotate(by: sw)
            let bell = CGMutablePath(); bell.move(to: CGPoint(x: -7, y: 8)); bell.addQuadCurve(to: CGPoint(x: 7, y: 8), control: CGPoint(x: 0, y: -14)); bell.closeSubpath()
            fillStroke(cg, bell, Palette.rgb(0xFFD166), line: 1.6)
            cg.restoreGState()
            balloon(cg, "¡Permiso!", center: CGPoint(x: x, y: headY - 50), urgent: true, wobble: sin(t * 14 + ph) * 0.06)
        case .done:
            balloon(cg, "¡Te toca!", center: CGPoint(x: x, y: headY - 50), urgent: false, wobble: sin(t * 3 + ph) * 0.04)
            // levanta el regalo terminado
            rrect(cg, CGRect(x: x - 11, y: headY - 34 + sin(t * 3) * 2, width: 22, height: 18), 2, Palette.rgb(0x2A9D8F), line: 1.6)
        case .idle:
            z(cg, x: x + 18, y: headY - 20, ph: ph)
        case .working: break
        }

        var sub = ""
        switch c.mood {
        case .working: sub = elapsed(c.since)
        case .needsYou, .done: sub = ago(c.since)
        case .idle: break
        }
        if !sub.isEmpty { text(sub, Fonts.time, Palette.outline, center: CGPoint(x: x, y: ElvesView.H - 28), halo: .white) }
        let bdg = CGRect(x: x + 22, y: B + 18, width: 15, height: 15)
        ellipse(cg, bdg, Palette.badge(c.provider), line: 1.5)
        text(c.provider.letter, Fonts.rounded(8.5, .black), .white, center: CGPoint(x: bdg.midX, y: bdg.midY))
    }

    private func drawElfBody(_ cg: CGContext, _ L: ElfLook, x: CGFloat, headY y: CGFloat, mood: Mood, ph: CGFloat, pose: CGFloat, armsUp: Bool) {
        let B = ElvesView.belt
        // Túnica
        let body = CGMutablePath()
        body.move(to: CGPoint(x: x - 14, y: y + 16)); body.addLine(to: CGPoint(x: x + 14, y: y + 16))
        body.addLine(to: CGPoint(x: x + 22, y: B + 4)); body.addLine(to: CGPoint(x: x - 22, y: B + 4)); body.closeSubpath()
        fillStroke(cg, body, L.tunic)
        cg.setFillColor(Palette.outline.cgColor); cg.fill(CGRect(x: x - 19, y: y + 40, width: 38, height: 4))
        rrect(cg, CGRect(x: x - 4, y: y + 38, width: 8, height: 8), 1.5, Palette.rgb(0xFFD166), line: 1.2)
        // Brazos
        let armY: CGFloat = armsUp ? y - 6 : (mood == .idle ? B - 4 : B - 14 + pose * 3)
        cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(7)
        cg.move(to: CGPoint(x: x - 12, y: y + 22)); cg.addLine(to: CGPoint(x: x - 18, y: armY))
        cg.move(to: CGPoint(x: x + 12, y: y + 22)); cg.addLine(to: CGPoint(x: x + 18, y: armY)); cg.strokePath()
        cg.setStrokeColor(L.tunic.cgColor); cg.setLineWidth(4)
        cg.move(to: CGPoint(x: x - 12, y: y + 22)); cg.addLine(to: CGPoint(x: x - 18, y: armY))
        cg.move(to: CGPoint(x: x + 12, y: y + 22)); cg.addLine(to: CGPoint(x: x + 18, y: armY)); cg.strokePath()
        ellipse(cg, CGRect(x: x - 23, y: armY - 4, width: 9, height: 9), L.skin, line: 1.5)
        ellipse(cg, CGRect(x: x + 14, y: armY - 4, width: 9, height: 9), L.skin, line: 1.5)

        // Orejas puntiagudas
        for s in [-1.0, 1.0] as [CGFloat] {
            let e = CGMutablePath()
            e.move(to: CGPoint(x: x + s * 14, y: y - 4)); e.addLine(to: CGPoint(x: x + s * 26, y: y - 10)); e.addLine(to: CGPoint(x: x + s * 15, y: y + 6)); e.closeSubpath()
            fillStroke(cg, e, L.skin, line: 1.8)
        }
        // Cabeza
        ellipse(cg, CGRect(x: x - 16, y: y - 16, width: 32, height: 32), L.skin)
        if L.beard {
            let bd = CGMutablePath()
            bd.move(to: CGPoint(x: x - 15, y: y + 2)); bd.addQuadCurve(to: CGPoint(x: x + 15, y: y + 2), control: CGPoint(x: x, y: y + 34)); bd.closeSubpath()
            fillStroke(cg, bd, .white, line: 1.8)
        }
        // Mofletes y ojos
        cg.setFillColor(Palette.cheek.cgColor)
        cg.fillEllipse(in: CGRect(x: x - 13, y: y + 1, width: 7, height: 5)); cg.fillEllipse(in: CGRect(x: x + 6, y: y + 1, width: 7, height: 5))
        let ey = y - 3
        cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(2)
        for s in [-1.0, 1.0] as [CGFloat] {
            let ex = x + s * 6
            if mood == .idle || mood == .done {
                cg.move(to: CGPoint(x: ex - 3, y: ey)); cg.addQuadCurve(to: CGPoint(x: ex + 3, y: ey), control: CGPoint(x: ex, y: mood == .done ? ey - 4 : ey + 3)); cg.strokePath()
            } else {
                cg.setFillColor(Palette.outline.cgColor)
                let big: CGFloat = mood == .needsYou ? 1.4 : 1
                cg.fillEllipse(in: CGRect(x: ex - 2 * big, y: ey - 2.5 * big + (mood == .working ? 1.5 : 0), width: 4 * big, height: 5 * big))
            }
        }
        if L.glasses && mood != .idle {
            cg.setLineWidth(1.4)
            cg.strokeEllipse(in: CGRect(x: x - 11, y: ey - 5, width: 10, height: 10)); cg.strokeEllipse(in: CGRect(x: x + 1, y: ey - 5, width: 10, height: 10))
        }
        // Boca
        if !L.beard || mood == .needsYou {
            if mood == .needsYou { ellipse(cg, CGRect(x: x - 3, y: y + 5, width: 6, height: 6), Palette.rgb(0x8E2C3B), line: 1.4) }
            else { cg.move(to: CGPoint(x: x - 4, y: y + 6)); cg.addQuadCurve(to: CGPoint(x: x + 4, y: y + 6), control: CGPoint(x: x, y: y + 10)); cg.strokePath() }
        }
        // Gorro puntiagudo con pompón que se balancea
        let tip = CGPoint(x: x + 20 + sin(t * 3 + ph) * 4, y: y - 40)
        let hat = CGMutablePath()
        hat.move(to: CGPoint(x: x - 17, y: y - 8)); hat.addQuadCurve(to: tip, control: CGPoint(x: x - 2, y: y - 40))
        hat.addQuadCurve(to: CGPoint(x: x + 17, y: y - 8), control: CGPoint(x: x + 12, y: y - 22)); hat.closeSubpath()
        fillStroke(cg, hat, L.hat)
        rrect(cg, CGRect(x: x - 18, y: y - 12, width: 36, height: 7), 3.5, L.trim, line: 1.8)
        ellipse(cg, CGRect(x: tip.x - 5, y: tip.y - 5, width: 10, height: 10), .white, line: 1.6)
    }
}
