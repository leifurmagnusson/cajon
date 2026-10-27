// Bolitas — el humo de los monos que te esperan.
// Sale de su cabeza y va invadiendo toda la pantalla. Si lo apartas con el ratón se aparta,
// pero vuelve, y no se va hasta que contestas. Es una capa transparente: no bloquea los clics.

import AppKit

struct Puff {
    var x, y, vx, vy, r, life, max, tx, ty, seed: CGFloat
}

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
            let a = (k < 0.08 ? k / 0.08 : (k > 0.85 ? (1 - k) / 0.15 : 1)) * 0.62
            let r = p.r * (1 + min(k * 6, 2.4))
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            cg.setFillColor(NSColor(white: 0.9 + 0.06 * sin(p.seed), alpha: a).cgColor)
            cg.fillEllipse(in: rect)
            cg.setStrokeColor(Palette.outline.withAlphaComponent(a * 0.28).cgColor); cg.setLineWidth(1.5)
            cg.strokeEllipse(in: rect)
        }
        guard !waiting.isEmpty else { return }
        let label = waiting.count == 1 ? "🐒  \(waiting[0]) te está esperando" : "🐒  \(waiting.count) monos te esperan: " + waiting.prefix(3).joined(separator: " · ")
        let font = Fonts.rounded(15, .heavy)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Palette.outline]
        let sz = (label as NSString).size(withAttributes: attrs)
        let w = sz.width + 56, h: CGFloat = 44
        let cx = bounds.midX + sin(t * 0.6) * 10
        let cy = bounds.maxY - 34 - h / 2 + sin(t * 1.1) * 3
        let cloud = CGMutablePath()
        let n = max(3, Int(w / 34))
        for k in 0...n {
            let bx = cx - w / 2 + CGFloat(k) * w / CGFloat(n)
            let br = 17 + 5 * sin(CGFloat(k) * 1.7 + t)
            cloud.addEllipse(in: CGRect(x: bx - br, y: cy + h / 2 - br * 0.9, width: br * 2, height: br * 2))
            cloud.addEllipse(in: CGRect(x: bx - br * 0.8, y: cy - h / 2 - br * 0.6, width: br * 1.6, height: br * 1.6))
        }
        cloud.addRoundedRect(in: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h), cornerWidth: 18, cornerHeight: 18)
        cg.addPath(cloud); cg.setFillColor(NSColor(white: 0.97, alpha: 0.98).cgColor); cg.fillPath()
        cg.addPath(cloud); cg.setStrokeColor(Palette.outline.withAlphaComponent(0.55).cgColor); cg.setLineWidth(2); cg.strokePath()
        cg.addPath(CGPath(roundedRect: CGRect(x: cx - w / 2 + 2, y: cy - h / 2 + 2, width: w - 4, height: h - 4), cornerWidth: 16, cornerHeight: 16, transform: nil))
        cg.setFillColor(NSColor(white: 0.98, alpha: 1).cgColor); cg.fillPath()
        (label as NSString).draw(at: NSPoint(x: cx - sz.width / 2, y: cy - sz.height / 2), withAttributes: attrs)
    }
}

final class SmokeOverlay {
    private var window: NSWindow?
    private var view: SmokeView?
    private var lastSpawn: [Int: CGFloat] = [:]

    private func ensure(on screen: NSScreen) {
        if let w = window, w.frame == screen.frame { return }
        window?.orderOut(nil)
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

    /// sources: puntos (coordenadas de pantalla) de donde sale humo; names: chats que te esperan.
    func step(t: CGFloat, dt: CGFloat, sources: [NSPoint], names: [String], screen: NSScreen?) {
        guard let screen = screen else { hide(); return }
        if sources.isEmpty && (view?.puffs.isEmpty ?? true) { hide(); return }
        ensure(on: screen)
        guard let v = view, let w = window else { return }
        let o = w.frame.origin, W = w.frame.width, H = w.frame.height
        let dt = min(dt, 0.1)

        for (i, s) in sources.enumerated() where t - (lastSpawn[i] ?? -10) > 0.09 && v.puffs.count < 380 {
            lastSpawn[i] = t
            let p = NSPoint(x: s.x - o.x, y: s.y - o.y)
            // Cada bocanada va a un sitio distinto de la pantalla: poco a poco lo llena todo.
            v.puffs.append(Puff(x: p.x + CGFloat.random(in: -5...5), y: p.y, vx: CGFloat.random(in: -20...20), vy: 90,
                                r: CGFloat.random(in: 7...13), life: 0, max: CGFloat.random(in: 12...20),
                                tx: CGFloat.random(in: 0...W), ty: CGFloat.random(in: H * 0.15...H * 0.95),
                                seed: CGFloat.random(in: 0...6.28)))
        }
        // El ratón aparta el humo.
        let m = NSEvent.mouseLocation
        let mx = m.x - o.x, my = m.y - o.y
        for k in v.puffs.indices {
            var p = v.puffs[k]
            p.life += dt
            // Va hacia su sitio, con un poco de bamboleo.
            let ax = (p.tx - p.x) * 0.35 + sin(t * 0.8 + p.seed) * 18
            let ay = (p.ty - p.y) * 0.35 + cos(t * 0.6 + p.seed) * 12
            p.vx += ax * dt; p.vy += ay * dt
            let dx = p.x - mx, dy = p.y - my
            let d = max(1, hypot(dx, dy))
            if d < 160 {
                let f = (160 - d) / 160 * 2600
                p.vx += dx / d * f * dt; p.vy += dy / d * f * dt
            }
            p.vx *= 0.94; p.vy *= 0.94
            p.x += p.vx * dt; p.y += p.vy * dt
            v.puffs[k] = p
        }
        v.puffs.removeAll { $0.life >= $0.max }
        if sources.isEmpty {
            // Ya le has hecho caso: el humo se disipa rápido.
            for k in v.puffs.indices where v.puffs[k].life < v.puffs[k].max * 0.85 { v.puffs[k].life = v.puffs[k].max * 0.85 }
        }
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
