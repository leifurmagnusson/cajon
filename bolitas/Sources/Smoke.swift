// Bolitas — el humo de los monos: sube desde el mono que te espera hasta arriba de la pantalla,
// y allí se queda una nube con el nombre del chat. Es una capa transparente que no se interpone con el ratón.

import AppKit

struct Puff { var x, y, vx, vy, r, life, max: CGFloat }

final class SmokeView: NSView {
    var puffs: [Puff] = []
    var waiting: [String] = []
    var t: CGFloat = 0
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.clear(bounds)
        for p in puffs {
            let k = p.life / p.max
            let a = (k < 0.1 ? k / 0.1 : 1 - (k - 0.1) / 0.9) * 0.75
            let r = p.r * (1 + k * 2.2)
            cg.setFillColor(NSColor(white: 0.93, alpha: a).cgColor)
            cg.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            cg.setStrokeColor(Palette.outline.withAlphaComponent(a * 0.35).cgColor); cg.setLineWidth(1.4)
            cg.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        guard !waiting.isEmpty else { return }
        // La nube de arriba
        let label = waiting.count == 1 ? "🐒 \(waiting[0]) te espera" : "🐒 \(waiting.count) monos te esperan: " + waiting.prefix(3).joined(separator: " · ")
        let font = Fonts.rounded(13, .heavy)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Palette.outline]
        let sz = (label as NSString).size(withAttributes: attrs)
        let w = sz.width + 50, h: CGFloat = 40
        let cx = bounds.midX + sin(t * 0.6) * 8
        let cy = bounds.maxY - 24 - h / 2 + sin(t * 1.1) * 2
        let cloud = CGMutablePath()
        let n = max(3, Int(w / 34))
        for k in 0...n {
            let bx = cx - w / 2 + CGFloat(k) * w / CGFloat(n)
            let br = 16 + 5 * sin(CGFloat(k) * 1.7 + t)
            cloud.addEllipse(in: CGRect(x: bx - br, y: cy + h / 2 - br * 0.9, width: br * 2, height: br * 2))
            cloud.addEllipse(in: CGRect(x: bx - br * 0.8, y: cy - h / 2 - br * 0.6, width: br * 1.6, height: br * 1.6))
        }
        cloud.addRoundedRect(in: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h), cornerWidth: 18, cornerHeight: 18)
        cg.addPath(cloud); cg.setFillColor(NSColor(white: 0.96, alpha: 0.97).cgColor); cg.fillPath()
        cg.addPath(cloud); cg.setStrokeColor(Palette.outline.withAlphaComponent(0.55).cgColor); cg.setLineWidth(2); cg.strokePath()
        cg.addPath(CGPath(roundedRect: CGRect(x: cx - w / 2 + 2, y: cy - h / 2 + 2, width: w - 4, height: h - 4), cornerWidth: 16, cornerHeight: 16, transform: nil))
        cg.setFillColor(NSColor(white: 0.97, alpha: 1).cgColor); cg.fillPath()
        (label as NSString).draw(at: NSPoint(x: cx - sz.width / 2, y: cy - sz.height / 2), withAttributes: attrs)
    }
}

final class SmokeOverlay {
    private var window: NSWindow?
    private var view: SmokeView?
    private var lastSpawn: [Int: CGFloat] = [:]

    private func ensure(on screen: NSScreen) {
        if let w = window, w.screen == screen || w.frame == screen.frame { return }
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let v = SmokeView(frame: NSRect(origin: .zero, size: screen.frame.size))
        w.contentView = v
        w.setFrame(screen.frame, display: false)
        window = w; view = v
    }

    /// sources: puntos en coordenadas de pantalla de donde sale humo; names: chats que esperan.
    func step(t: CGFloat, dt: CGFloat, sources: [NSPoint], names: [String], screen: NSScreen?) {
        guard let screen = screen else { hide(); return }
        if sources.isEmpty && (view?.puffs.isEmpty ?? true) { hide(); return }
        ensure(on: screen)
        guard let v = view, let w = window else { return }
        let origin = w.frame.origin
        for (i, s) in sources.enumerated() where t - (lastSpawn[i] ?? -10) > 0.22 {
            lastSpawn[i] = t
            let p = NSPoint(x: s.x - origin.x, y: s.y - origin.y)
            let top = w.frame.height - 40
            let life = max(2.5, (top - p.y) / 120)
            v.puffs.append(Puff(x: p.x + CGFloat.random(in: -4...4), y: p.y, vx: CGFloat.random(in: -10...10),
                                vy: (top - p.y) / life, r: CGFloat.random(in: 5...8), life: 0, max: life))
        }
        for k in v.puffs.indices {
            v.puffs[k].life += dt
            v.puffs[k].x += (v.puffs[k].vx + sin(t * 2 + CGFloat(k)) * 14) * dt
            v.puffs[k].y += v.puffs[k].vy * dt
        }
        v.puffs.removeAll { $0.life >= $0.max }
        if v.puffs.count > 400 { v.puffs.removeFirst(v.puffs.count - 400) }
        v.waiting = sources.isEmpty ? [] : names
        v.t = t
        if !w.isVisible { w.orderFrontRegardless() }
        v.needsDisplay = true
    }

    func hide() {
        if let w = window, w.isVisible { w.orderOut(nil) }
        view?.puffs.removeAll()
    }
}
