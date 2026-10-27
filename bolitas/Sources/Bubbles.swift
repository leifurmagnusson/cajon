// Bolitas — las bolas: dibujadas a mano, rollo dibujo animado.

import AppKit

enum Palette {
    static func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }
    static let outline = rgb(0x2A2340)
    static func base(_ m: Mood) -> NSColor {
        switch m {
        case .working: return rgb(0x5BD16B)
        case .needsYou, .done: return rgb(0xFFCC33)
        case .idle: return rgb(0xB7BAC5)
        }
    }
    static func light(_ m: Mood) -> NSColor {
        switch m {
        case .working: return rgb(0xB4F5B9)
        case .needsYou, .done: return rgb(0xFFF1A8)
        case .idle: return rgb(0xE9EAEF)
        }
    }
    static func ink(_ m: Mood) -> NSColor {
        switch m {
        case .working: return rgb(0x1E7A33)
        case .needsYou, .done: return rgb(0x9A6A00)
        case .idle: return rgb(0x6B6E7A)
        }
    }
    static func badge(_ p: Provider) -> NSColor { p == .claude ? rgb(0xD97757) : rgb(0x34343F) }
    static let cheek = rgb(0xFF7FA0, 0.45)
    static let balloon = rgb(0xFFFFFF, 0.97)
    static let alert = rgb(0xE5484D)
}

enum Fonts {
    static func rounded(_ size: CGFloat, _ w: NSFont.Weight) -> NSFont {
        let f = NSFont.systemFont(ofSize: size, weight: w)
        if let d = f.fontDescriptor.withDesign(.rounded) { return NSFont(descriptor: d, size: size) ?? f }
        return f
    }
    static let name = rounded(11, .bold)
    static let time = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    static let balloon = rounded(10.5, .heavy)
    static let badge = rounded(10, .black)
    static let z = rounded(12, .heavy)
}

func elapsed(_ since: Date, _ now: Date = Date()) -> String {
    let s = max(0, Int(now.timeIntervalSince(since)))
    if s < 3600 { return String(format: "%d:%02d", s / 60, s % 60) }
    return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
}

func ago(_ since: Date, _ now: Date = Date()) -> String {
    let s = max(0, Int(now.timeIntervalSince(since)))
    if s < 60 { return "ahora" }
    if s < 3600 { return "hace \(s / 60) min" }
    return "hace \(s / 3600) h"
}

final class BubblesView: StageView {
    static let cellW: CGFloat = 92, cellH: CGFloat = 168, pad: CGFloat = 6, r: CGFloat = 28
    private var hover: Int? { hoverIndex }

    override class func size(for count: Int) -> NSSize {
        NSSize(width: CGFloat(max(1, count)) * cellW + pad * 2, height: cellH)
    }

    override func smokeSource(_ i: Int) -> NSPoint? {
        guard i < chats.count, chats[i].mood == .needsYou else { return nil }
        return NSPoint(x: BubblesView.pad + CGFloat(i) * BubblesView.cellW + BubblesView.cellW / 2, y: 126 - 2 * BubblesView.r)
    }

    override func actorIndex(at p: NSPoint) -> Int? {
        let i = Int(floor((p.x - BubblesView.pad) / BubblesView.cellW))
        return (i >= 0 && i < chats.count) ? i : nil
    }

    // MARK: Dibujo

    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.clear(bounds)
        drawDropHint(cg, bounds.insetBy(dx: 2, dy: 18))
        if chats.isEmpty {
            drawCell(cg, i: 0, mood: .idle, provider: nil,
                     name: needsPermission ? "Dame permiso" : "Arrastra un chat",
                     sub: needsPermission ? "toca aquí" : "", balloon: nil, phase: 0)
            return
        }
        let now = Date()
        for (i, c) in chats.enumerated() {
            var sub = ""
            var balloon: String?
            switch c.mood {
            case .working: sub = elapsed(c.since, now)
            case .needsYou: sub = ago(c.since, now); balloon = "¡Permiso!"
            case .done: sub = ago(c.since, now); balloon = "¡Te toca!"
            case .idle: sub = ""
            }
            drawCell(cg, i: i, mood: c.mood, provider: c.provider, name: c.shortTitle, sub: sub,
                     balloon: balloon, phase: CGFloat(i) * 1.7, pinned: c.pinned)
        }
    }

    private func drawCell(_ cg: CGContext, i: Int, mood: Mood, provider: Provider?, name: String, sub: String,
                          balloon: String?, phase ph: CGFloat, pinned: Bool = false) {
        let x0 = BubblesView.pad + CGFloat(i) * BubblesView.cellW
        let cx = x0 + BubblesView.cellW / 2
        let groundY: CGFloat = 126
        var r = BubblesView.r
        if hover == i { r *= 1.08 }

        // Movimiento según el estado.
        var lift: CGFloat = 0, sx: CGFloat = 1, sy: CGFloat = 1
        switch mood {
        case .working:
            lift = abs(sin(t * 3 + ph)) * 3
            sx = 1 + 0.045 * sin(t * 6 + ph); sy = 1 - 0.045 * sin(t * 6 + ph)
        case .needsYou:
            let h = abs(sin(t * 5.5 + ph)); lift = h * 34
            let squash = max(0, 0.25 - h) * 0.5
            sx = 1 + squash; sy = 1 - squash
        case .done:
            let h = abs(sin(t * 3.6 + ph)); lift = h * 22
            let squash = max(0, 0.2 - h) * 0.4
            sx = 1 + squash; sy = 1 - squash
        case .idle:
            sx = 1 + 0.02 * sin(t * 1.4 + ph); sy = 1 - 0.02 * sin(t * 1.4 + ph)
        }
        let rx = r * sx, ry = r * sy
        let cy = groundY - ry - lift

        // Sombra en el suelo.
        let shW = rx * (1.5 - lift / 30)
        cg.setFillColor(NSColor.black.withAlphaComponent(0.16 - lift / 160).cgColor)
        cg.fillEllipse(in: CGRect(x: cx - shW / 2, y: groundY - 3, width: shW, height: 7))

        // Cuerpo con degradado y contorno gordo.
        let body = CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
        cg.saveGState()
        cg.addEllipse(in: body); cg.clip()
        let cs = CGColorSpaceCreateDeviceRGB()
        if let g = CGGradient(colorsSpace: cs, colors: [Palette.light(mood).cgColor, Palette.base(mood).cgColor] as CFArray, locations: [0, 1]) {
            cg.drawRadialGradient(g, startCenter: CGPoint(x: cx - rx * 0.35, y: cy - ry * 0.4), startRadius: 2,
                                  endCenter: CGPoint(x: cx, y: cy), endRadius: r * 1.15, options: [.drawsAfterEndLocation])
        }
        // Sombrita interior abajo.
        cg.setFillColor(NSColor.black.withAlphaComponent(0.07).cgColor)
        cg.fillEllipse(in: CGRect(x: cx - rx * 1.1, y: cy + ry * 0.35, width: rx * 2.2, height: ry * 1.2))
        cg.restoreGState()
        cg.setStrokeColor(Palette.outline.cgColor)
        cg.setLineWidth(3)
        cg.strokeEllipse(in: body)

        // Brillo.
        cg.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        cg.saveGState()
        cg.translateBy(x: cx - rx * 0.45, y: cy - ry * 0.52)
        cg.rotate(by: -0.6)
        cg.fillEllipse(in: CGRect(x: -rx * 0.22, y: -ry * 0.11, width: rx * 0.44, height: ry * 0.22))
        cg.restoreGState()
        cg.fillEllipse(in: CGRect(x: cx - rx * 0.12, y: cy - ry * 0.72, width: 4, height: 4))

        drawFace(cg, cx: cx, cy: cy, rx: rx, ry: ry, mood: mood, ph: ph)

        // Insignia de la app.
        if let p = provider {
            let b = CGRect(x: cx + rx * 0.5, y: cy + ry * 0.38, width: 18, height: 18)
            cg.setFillColor(Palette.badge(p).cgColor); cg.fillEllipse(in: b)
            cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(2); cg.strokeEllipse(in: b)
            drawTextB(p.letter, font: Fonts.badge, color: .white, center: CGPoint(x: b.midX, y: b.midY))
        }
        if pinned {
            // Chincheta pequeña: está fijada.
            let pin = CGRect(x: cx - rx * 0.95, y: cy - ry * 0.95, width: 9, height: 9)
            cg.setFillColor(Palette.alert.cgColor); cg.fillEllipse(in: pin)
            cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(1.5); cg.strokeEllipse(in: pin)
        }

        // Lo de encima: pensamiento, globo o zetas.
        switch mood {
        case .working: drawThought(cg, x: cx + rx * 0.55, y: cy - ry - 2, ph: ph)
        case .needsYou, .done:
            if let s = balloon { drawBalloon(cg, text: s, cx: cx, bottom: cy - ry - 4, urgent: mood == .needsYou, ph: ph) }
        case .idle: drawZB(cg, x: cx + rx * 0.6, y: cy - ry * 0.6, ph: ph)
        }

        // Nombre y tiempo.
        drawPill(name, font: Fonts.name, color: Palette.outline, center: CGPoint(x: cx, y: groundY + 13), maxW: BubblesView.cellW - 6)
        if !sub.isEmpty {
            drawTextB(sub, font: Fonts.time, color: Palette.ink(mood), center: CGPoint(x: cx, y: groundY + 30), halo: true)
        }
    }

    private func drawFace(_ cg: CGContext, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, mood: Mood, ph: CGFloat) {
        let ex = rx * 0.33, ey = cy - ry * 0.06
        cg.setStrokeColor(Palette.outline.cgColor)
        cg.setFillColor(Palette.outline.cgColor)
        cg.setLineCap(.round)

        // Mofletes.
        if mood != .idle {
            cg.setFillColor(Palette.cheek.cgColor)
            cg.fillEllipse(in: CGRect(x: cx - rx * 0.72, y: cy + ry * 0.12, width: rx * 0.34, height: ry * 0.2))
            cg.fillEllipse(in: CGRect(x: cx + rx * 0.38, y: cy + ry * 0.12, width: rx * 0.34, height: ry * 0.2))
            cg.setFillColor(Palette.outline.cgColor)
        }

        switch mood {
        case .working:
            // Ojos que miran alrededor mientras piensa, y algún parpadeo.
            let blink = (t + ph).truncatingRemainder(dividingBy: 3.6) < 0.12
            let a = t * 1.8 + ph
            let dx = cos(a) * 2.6, dy = -abs(sin(a)) * 2.2
            for s in [-1.0, 1.0] as [CGFloat] {
                let e = CGRect(x: cx + s * ex - 5.5, y: ey - 7, width: 11, height: blink ? 2 : 13)
                cg.setFillColor(NSColor.white.cgColor); cg.fillEllipse(in: e)
                cg.setLineWidth(2); cg.strokeEllipse(in: e)
                if !blink {
                    cg.setFillColor(Palette.outline.cgColor)
                    cg.fillEllipse(in: CGRect(x: cx + s * ex - 3 + dx, y: ey - 2.5 + dy, width: 6, height: 7))
                    cg.setFillColor(NSColor.white.cgColor)
                    cg.fillEllipse(in: CGRect(x: cx + s * ex - 1.5 + dx, y: ey - 1.5 + dy, width: 2, height: 2))
                }
            }
            // Boca "o" que va cambiando.
            let m = 3 + 1.5 * sin(t * 4 + ph)
            cg.setFillColor(Palette.outline.cgColor)
            cg.fillEllipse(in: CGRect(x: cx + 3 - m / 2, y: cy + ry * 0.36, width: m, height: m * 1.1))
        case .needsYou:
            // Ojazos mirándote y cejas levantadas.
            for s in [-1.0, 1.0] as [CGFloat] {
                let e = CGRect(x: cx + s * ex - 6.5, y: ey - 9, width: 13, height: 15)
                cg.setFillColor(NSColor.white.cgColor); cg.fillEllipse(in: e)
                cg.setLineWidth(2); cg.strokeEllipse(in: e)
                cg.setFillColor(Palette.outline.cgColor)
                cg.fillEllipse(in: CGRect(x: cx + s * ex - 4, y: ey - 4, width: 8, height: 9))
                cg.setFillColor(NSColor.white.cgColor)
                cg.fillEllipse(in: CGRect(x: cx + s * ex - 2, y: ey - 3, width: 3, height: 3))
                cg.setLineWidth(2.2)
                cg.move(to: CGPoint(x: cx + s * ex - 6, y: ey - 13 + s * 1.5))
                cg.addLine(to: CGPoint(x: cx + s * ex + 6, y: ey - 13 - s * 1.5))
                cg.strokePath()
            }
            // Boca abierta.
            let mouth = CGRect(x: cx - 5, y: cy + ry * 0.3, width: 10, height: 9)
            cg.setFillColor(Palette.rgb(0x8E2C3B).cgColor); cg.fillEllipse(in: mouth)
            cg.setLineWidth(2); cg.strokeEllipse(in: mouth)
        case .done:
            // Ojos felices ^ ^ y sonrisa.
            cg.setLineWidth(2.6)
            for s in [-1.0, 1.0] as [CGFloat] {
                cg.move(to: CGPoint(x: cx + s * ex - 5, y: ey + 2))
                cg.addQuadCurve(to: CGPoint(x: cx + s * ex + 5, y: ey + 2), control: CGPoint(x: cx + s * ex, y: ey - 7))
                cg.strokePath()
            }
            let smile = CGMutablePath()
            smile.move(to: CGPoint(x: cx - 8, y: cy + ry * 0.28))
            smile.addQuadCurve(to: CGPoint(x: cx + 8, y: cy + ry * 0.28), control: CGPoint(x: cx, y: cy + ry * 0.62))
            smile.closeSubpath()
            cg.addPath(smile); cg.setFillColor(Palette.rgb(0x8E2C3B).cgColor); cg.fillPath()
            cg.addPath(smile); cg.setLineWidth(2); cg.strokePath()
        case .idle:
            // Durmiendo: ojos cerrados y boquita.
            cg.setLineWidth(2.2)
            for s in [-1.0, 1.0] as [CGFloat] {
                cg.move(to: CGPoint(x: cx + s * ex - 5, y: ey))
                cg.addQuadCurve(to: CGPoint(x: cx + s * ex + 5, y: ey), control: CGPoint(x: cx + s * ex, y: ey + 5))
                cg.strokePath()
            }
            cg.move(to: CGPoint(x: cx - 2.5, y: cy + ry * 0.4))
            cg.addLine(to: CGPoint(x: cx + 2.5, y: cy + ry * 0.4))
            cg.strokePath()
        }
    }

    private func drawThought(_ cg: CGContext, x: CGFloat, y: CGFloat, ph: CGFloat) {
        // Nubecita de pensar con puntos que van y vienen.
        let float = sin(t * 2 + ph) * 1.5
        let small: [(CGFloat, CGFloat, CGFloat)] = [(0, 0, 3), (5, -6, 4.5)]
        for (dx, dy, rr) in small {
            let c = CGRect(x: x + dx - rr, y: y + dy - rr + float, width: rr * 2, height: rr * 2)
            cg.setFillColor(Palette.balloon.cgColor); cg.fillEllipse(in: c)
            cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(1.6); cg.strokeEllipse(in: c)
        }
        let cloud = CGRect(x: x - 4, y: y - 30 + float, width: 30, height: 18)
        let p = CGPath(roundedRect: cloud, cornerWidth: 9, cornerHeight: 9, transform: nil)
        cg.addPath(p); cg.setFillColor(Palette.balloon.cgColor); cg.fillPath()
        cg.addPath(p); cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(1.8); cg.strokePath()
        let step = Int(t * 3) % 4
        for k in 0..<3 {
            let on = k < step
            cg.setFillColor(Palette.outline.withAlphaComponent(on ? 1 : 0.25).cgColor)
            cg.fillEllipse(in: CGRect(x: cloud.minX + 6 + CGFloat(k) * 7, y: cloud.midY - 2, width: 4, height: 4))
        }
    }

    private func drawBalloon(_ cg: CGContext, text: String, cx: CGFloat, bottom: CGFloat, urgent: Bool, ph: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: Fonts.balloon]
        let w = (text as NSString).size(withAttributes: attrs).width + 14
        let wob = urgent ? sin(t * 14 + ph) * 0.06 : sin(t * 3 + ph) * 0.03
        cg.saveGState()
        cg.translateBy(x: cx, y: bottom)
        cg.rotate(by: wob)
        let rect = CGRect(x: -w / 2, y: -24, width: w, height: 18)
        let p = CGMutablePath()
        p.addRoundedRect(in: rect, cornerWidth: 9, cornerHeight: 9)
        p.move(to: CGPoint(x: -4, y: -6.5)); p.addLine(to: CGPoint(x: 1, y: 1)); p.addLine(to: CGPoint(x: 5, y: -6.5))
        cg.addPath(p)
        cg.setFillColor((urgent ? Palette.alert : Palette.balloon).cgColor); cg.fillPath()
        cg.addPath(p); cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(1.8); cg.strokePath()
        cg.restoreGState()
        drawTextB(text, font: Fonts.balloon, color: urgent ? .white : Palette.outline, center: CGPoint(x: cx, y: bottom - 15))
    }

    private func drawZB(_ cg: CGContext, x: CGFloat, y: CGFloat, ph: CGFloat) {
        for k in 0..<2 {
            let p = (t * 0.45 + ph * 0.1 + CGFloat(k) * 0.5).truncatingRemainder(dividingBy: 1)
            let a = sin(p * .pi)
            let size = 9 + p * 6
            let f = Fonts.rounded(size, .heavy)
            drawTextB("z", font: f, color: Palette.outline.withAlphaComponent(0.55 * a),
                     center: CGPoint(x: x + p * 12, y: y - p * 22))
        }
    }

    private func drawTextB(_ s: String, font: NSFont, color: NSColor, center: CGPoint, halo: Bool = false) {
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if halo {
            let sh = NSShadow(); sh.shadowColor = NSColor.white.withAlphaComponent(0.95); sh.shadowBlurRadius = 3; sh.shadowOffset = .zero
            attrs[.shadow] = sh
        }
        let sz = (s as NSString).size(withAttributes: attrs)
        (s as NSString).draw(at: NSPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2), withAttributes: attrs)
    }

    private func drawPill(_ s: String, font: NSFont, color: NSColor, center: CGPoint, maxW: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        var text = s
        while (text as NSString).size(withAttributes: attrs).width > maxW - 14 && text.count > 2 {
            text = String(text.dropLast(2)) + "…"
        }
        let sz = (text as NSString).size(withAttributes: attrs)
        let rect = NSRect(x: center.x - sz.width / 2 - 7, y: center.y - sz.height / 2 - 2, width: sz.width + 14, height: sz.height + 4)
        let p = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        Palette.rgb(0xFFFFFF, 0.93).setFill(); p.fill()
        p.lineWidth = 1.5; Palette.outline.setStroke(); p.stroke()
        (text as NSString).draw(at: NSPoint(x: rect.minX + 7, y: rect.minY + 2), withAttributes: attrs)
    }

}
