// Bolitas — el humo de los que te esperan.
// Sube muy despacio desde cada uno que te espera y se va quedando arriba del todo de la pantalla,
// acumulándose como en una sala de billar. Cuando contestas, la neblina se va disipando poco a poco.
// Es una capa transparente: no bloquea el ratón ni los clics.

import AppKit
import QuartzCore

final class SmokeOverlay {
    private var window: NSWindow?
    private var root: CALayer?
    private var plumes: [CAEmitterLayer] = []
    private var haze: CAEmitterLayer?
    private var hazeGlow: CAGradientLayer?
    private var level: CGFloat = 0          // 0…1: cuánta neblina hay acumulada arriba
    private var hideTimer: CGFloat = 0

    private static let puff: CGImage = {
        // Una bocanada suave e irregular: varias manchas difuminadas.
        let s = 128
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var d = Dice("humo")
        for _ in 0..<9 {
            let cx = 64 + CGFloat(Int(d.next() % 50) - 25), cy = 64 + CGFloat(Int(d.next() % 50) - 25)
            let r = 22 + CGFloat(d.next() % 22)
            let a = 0.18 + CGFloat(d.next() % 20) / 100
            let g = CGGradient(colorsSpace: cs, colors: [CGColor(red: 1, green: 1, blue: 1, alpha: a), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: cy), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: r, options: [])
        }
        return ctx.makeImage()!
    }()

    private func ensure(on screen: NSScreen) {
        if let w = window, w.frame == screen.frame { return }
        window?.orderOut(nil)
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let v = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        v.wantsLayer = true
        let root = CALayer(); root.frame = v.bounds
        v.layer?.addSublayer(root)
        w.contentView = v
        w.setFrame(screen.frame, display: false)

        // Neblina de arriba: un velo suave + bocanadas grandes que se mueven despacio de lado.
        let W = screen.frame.width, H = screen.frame.height
        let glow = CAGradientLayer()
        glow.frame = CGRect(x: 0, y: H - 260, width: W, height: 260)
        glow.colors = [NSColor(white: 0.92, alpha: 0).cgColor, NSColor(white: 0.9, alpha: 0.55).cgColor]
        glow.startPoint = CGPoint(x: 0.5, y: 0); glow.endPoint = CGPoint(x: 0.5, y: 1)
        glow.opacity = 0
        root.addSublayer(glow)

        let hz = CAEmitterLayer()
        hz.frame = root.bounds
        hz.emitterShape = .line
        hz.emitterPosition = CGPoint(x: W / 2, y: H - 70)
        hz.emitterSize = CGSize(width: W * 1.1, height: 0)
        hz.renderMode = .unordered
        let c = CAEmitterCell()
        c.contents = SmokeOverlay.puff
        c.birthRate = 0
        c.lifetime = 45; c.lifetimeRange = 10
        c.velocity = 7; c.velocityRange = 5
        c.emissionRange = .pi * 2
        c.yAcceleration = 0.4
        c.scale = 2.2; c.scaleRange = 0.8; c.scaleSpeed = 0.015
        c.spin = 0; c.spinRange = 0.06
        c.color = NSColor(white: 0.93, alpha: 0.10).cgColor
        c.alphaRange = 0.04
        c.alphaSpeed = -0.0018
        c.name = "haze"
        hz.emitterCells = [c]
        root.addSublayer(hz)

        window = w; self.root = root; haze = hz; hazeGlow = glow
        plumes.removeAll()
    }

    private func makePlume() -> CAEmitterLayer {
        let e = CAEmitterLayer()
        e.frame = root?.bounds ?? .zero
        e.emitterShape = .point
        e.renderMode = .unordered
        let c = CAEmitterCell()
        c.contents = SmokeOverlay.puff
        c.birthRate = 1.6
        c.lifetime = 75; c.lifetimeRange = 15
        c.velocity = 16; c.velocityRange = 6
        c.emissionLongitude = .pi / 2          // hacia arriba
        c.emissionRange = 0.25
        c.xAcceleration = 0.25
        c.yAcceleration = 0.6
        c.scale = 0.12; c.scaleRange = 0.04; c.scaleSpeed = 0.022
        c.spin = 0; c.spinRange = 0.12
        c.color = NSColor(white: 0.9, alpha: 0.32).cgColor
        c.alphaSpeed = -0.0045
        c.name = "plume"
        e.emitterCells = [c]
        root?.addSublayer(e)
        return e
    }

    /// sources: puntos (coordenadas de pantalla) de donde sale el humo.
    func step(t: CGFloat, dt: CGFloat, sources: [NSPoint], names: [String], screen: NSScreen?) {
        guard let screen = screen else { hide(); return }
        let dt = min(dt, 0.1)
        if sources.isEmpty && level <= 0.001 && window == nil { return }
        ensure(on: screen)
        guard let w = window else { return }
        let o = w.frame.origin

        CATransaction.begin(); CATransaction.setDisableActions(true)
        while plumes.count < sources.count { plumes.append(makePlume()) }
        for (i, e) in plumes.enumerated() {
            if i < sources.count {
                e.emitterPosition = CGPoint(x: sources[i].x - o.x, y: sources[i].y - o.y)
                e.birthRate = 1
            } else {
                e.birthRate = 0
            }
        }
        // La neblina de arriba crece mientras alguien espera (tarda ~3 min en llenarse) y se va despacio.
        if sources.isEmpty { level = max(0, level - dt / 90) } else { level = min(1, level + dt / 180 * CGFloat(min(sources.count, 3))) }
        haze?.birthRate = Float(level * 1.6)
        hazeGlow?.opacity = Float(level * 0.85)
        CATransaction.commit()

        if !w.isVisible { w.orderFrontRegardless() }
        if sources.isEmpty && level <= 0.001 {
            hideTimer += dt
            if hideTimer > 80 { hide() }        // espera a que se disipe lo último
        } else { hideTimer = 0 }
    }

    func hide() {
        window?.orderOut(nil)
        window = nil; root = nil; haze = nil; hazeGlow = nil
        plumes.removeAll()
        level = 0; hideTimer = 0
    }
}
