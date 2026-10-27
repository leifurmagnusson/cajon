// Bolitas — el humo de los que te esperan.
// En el club, primero se llena la sala de los gorilas; cuando está llena, el humo sale por la chimenea.
// Sale denso y oscuro de cada uno que te espera, sube, choca con el techo de la pantalla y se queda ahí,
// arrastrado poco a poco hacia la derecha. Se va acumulando: el techo de humo baja y todo se oscurece.
// El ratón lo empuja con la velocidad a la que lo mueves (despacio, poco; rápido, mucho).
// Cuando contestas, se va disipando. Es una capa transparente: nunca bloquea los clics.

import AppKit
import QuartzCore

private struct Particle {
    var layer: CALayer
    var x, y, vx, vy: CGFloat
    var size: CGFloat
    var age: CGFloat
    var life: CGFloat
    var settled: Bool
    var seed: CGFloat
    var inRoom: Bool = false
}

final class SmokeOverlay {
    private var window: NSWindow?
    private var root: CALayer?
    private var ceiling: CAGradientLayer?
    private var parts: [Particle] = []
    private var level: CGFloat = 0          // 0…1: cuánto humo se ha acumulado
    private var spawnAcc: [Int: CGFloat] = [:]
    private var lastMouse: NSPoint?
    private var idleTime: CGFloat = 0
    private var roomLevel: CGFloat = 0      // 0…1: cuánto se ha llenado la sala de los gorilas
    private var roomVeil: CALayer?
    private var chimneyAcc: CGFloat = 0

    private static func puff(_ gray: CGFloat, _ alpha: CGFloat) -> CGImage {
        let s = 128
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var d = Dice("humo\(gray)")
        for _ in 0..<10 {
            let cx = 64 + CGFloat(Int(d.next() % 46) - 23), cy = 64 + CGFloat(Int(d.next() % 46) - 23)
            let r = 20 + CGFloat(d.next() % 26)
            let a = alpha * (0.5 + CGFloat(d.next() % 50) / 100)
            let g = CGGradient(colorsSpace: cs, colors: [CGColor(red: gray, green: gray, blue: gray * 1.03, alpha: a),
                                                         CGColor(red: gray, green: gray, blue: gray, alpha: 0)] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: cy), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: r, options: [])
        }
        return ctx.makeImage()!
    }
    private static let fresh = puff(0.42, 0.55)    // la bocanada al salir: gris
    private static let old = puff(0.16, 0.6)       // la que se queda arriba: casi negra

    private func ensure(on screen: NSScreen) {
        if let w = window, w.frame == screen.frame { return }
        hide()
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let v = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        v.wantsLayer = true
        let root = CALayer(); root.frame = v.bounds
        v.layer?.addSublayer(root)
        let ceil = CAGradientLayer()
        ceil.frame = CGRect(x: 0, y: 0, width: screen.frame.width, height: screen.frame.height)
        ceil.startPoint = CGPoint(x: 0.5, y: 0); ceil.endPoint = CGPoint(x: 0.5, y: 1)
        ceil.opacity = 0
        root.addSublayer(ceil)
        let veil = CALayer()
        veil.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        veil.opacity = 0
        root.addSublayer(veil)
        roomVeil = veil
        w.contentView = v
        w.setFrame(screen.frame, display: false)
        window = w; self.root = root; ceiling = ceil
    }

    func step(t: CGFloat, dt rawDt: CGFloat, sources: [NSPoint], names: [String], screen: NSScreen?,
              room roomScreen: NSRect? = nil, chimney chimneyScreen: NSPoint? = nil) {
        guard let screen = screen else { hide(); return }
        let dt = min(max(rawDt, 0.001), 0.1)
        if sources.isEmpty && parts.isEmpty && level <= 0.001 { if window != nil { hide() }; return }
        ensure(on: screen)
        guard let w = window, let root = root else { return }
        let o = w.frame.origin, W = w.frame.width, H = w.frame.height

        // La sala se llena primero (unos 20 s con uno esperando); luego el humo sale por la chimenea.
        let room = roomScreen.map { NSRect(x: $0.minX - o.x, y: $0.minY - o.y, width: $0.width, height: $0.height) }
        if room != nil {
            if sources.isEmpty { roomLevel = max(0, roomLevel - dt / 18) }
            else { roomLevel = min(1, roomLevel + dt / 20 * CGFloat(min(sources.count, 3))) }
        } else { roomLevel = 0 }
        let chimneyOn = room != nil && chimneyScreen != nil && roomLevel >= 0.97 && !sources.isEmpty
        let feedsScreen = room == nil ? !sources.isEmpty : chimneyOn
        // El techo de humo de la pantalla baja a medida que se acumula (hasta media pantalla).
        if !feedsScreen { level = max(0, level - dt / 60) } else { level = min(1, level + dt / 150 * CGFloat(min(max(sources.count, 1), 3))) }
        let ceilY = H - 50 - level * H * 0.45

        CATransaction.begin(); CATransaction.setDisableActions(true)

        // Por la chimenea, cuando la sala ya está llena
        if chimneyOn, let c = chimneyScreen, parts.count < 420 {
            chimneyAcc += dt * 6 * CGFloat(min(sources.count, 3))
            while chimneyAcc >= 1 {
                chimneyAcc -= 1
                let l = CALayer()
                l.contents = SmokeOverlay.old
                let size = CGFloat.random(in: 24...36)
                l.bounds = CGRect(x: 0, y: 0, width: size, height: size)
                root.addSublayer(l)
                parts.append(Particle(layer: l, x: c.x - o.x + CGFloat.random(in: -4...4), y: c.y - o.y,
                                      vx: CGFloat.random(in: -6...10), vy: CGFloat.random(in: 80...120),
                                      size: size, age: 0, life: CGFloat.random(in: 70...130), settled: false,
                                      seed: CGFloat.random(in: 0...100)))
            }
        }

        // Bocanadas nuevas (en el club, se quedan dentro de la sala)
        let roomParts = parts.filter { $0.inRoom }.count
        for (i, s) in sources.enumerated() where parts.count < 420 && (room == nil || roomParts < 150) {
            spawnAcc[i, default: 0] += dt * 7
            while spawnAcc[i, default: 0] >= 1 {
                spawnAcc[i, default: 0] -= 1
                let l = CALayer()
                l.contents = SmokeOverlay.fresh
                let size = CGFloat.random(in: 26...40)
                l.bounds = CGRect(x: 0, y: 0, width: size, height: size)
                root.addSublayer(l)
                parts.append(Particle(layer: l, x: s.x - o.x + CGFloat.random(in: -3...3), y: s.y - o.y,
                                      vx: CGFloat.random(in: -8...14), vy: CGFloat.random(in: 70...110),
                                      size: size, age: 0, life: CGFloat.random(in: 70...130), settled: false,
                                      seed: CGFloat.random(in: 0...100), inRoom: room != nil))
            }
        }

        // El ratón: empuja con su propia velocidad.
        let m = NSEvent.mouseLocation
        let mp = NSPoint(x: m.x - o.x, y: m.y - o.y)
        var mv = CGVector(dx: 0, dy: 0)
        if let lm = lastMouse { mv = CGVector(dx: (mp.x - lm.x) / dt, dy: (mp.y - lm.y) / dt) }
        lastMouse = mp
        let mspeed = hypot(mv.dx, mv.dy)

        let wind: CGFloat = 16 + level * 10           // todo va hacia la derecha
        for k in parts.indices {
            var p = parts[k]
            p.age += dt
            if p.inRoom, let r = room {
                // Dentro de la sala: sube hasta el techo de la sala y se va acumulando hacia abajo
                let top = r.maxY - p.size * 0.4
                let fill = top - roomLevel * r.height * 0.85
                if p.y < fill { p.vy += (34 - p.vy) * 0.8 * dt }
                else {
                    if !p.settled { p.settled = true; p.layer.contents = SmokeOverlay.old }
                    p.vy += (((fill + top) / 2 - p.y) * 0.8 - p.vy) * 1.4 * dt
                }
                p.vx += sin(t * 0.9 + p.seed) * 14 * dt
                p.vx *= 0.97; p.vy *= 0.97
                p.x += p.vx * dt; p.y += p.vy * dt
                p.x = min(max(p.x, r.minX + p.size * 0.3), r.maxX - p.size * 0.3)
                p.y = min(max(p.y, r.minY), top)
                let sz = p.size * (1 + min(p.age / 5, 1) * 1.6)
                p.layer.position = CGPoint(x: p.x, y: p.y)
                p.layer.bounds = CGRect(x: 0, y: 0, width: sz, height: sz)
                let fadeOut = sources.isEmpty ? max(0, 1 - idleTime / 18) : 1
                p.layer.opacity = Float(min(1, p.age / 0.4) * fadeOut * 0.7)
                if p.age > p.life - 10 { p.age = p.life - 10 }   // no se muere de viejo dentro de la sala
                parts[k] = p
                continue
            }
            // Sube; al llegar al techo se frena, se aplana y se queda.
            if p.y < ceilY {
                p.vy += (40 - p.vy) * 0.6 * dt
            } else {
                if !p.settled { p.settled = true; p.layer.contents = SmokeOverlay.old }
                p.vy += ((ceilY + (H - ceilY) * 0.5 - p.y) * 0.4 - p.vy) * 1.2 * dt
            }
            p.vx += (wind * (p.settled ? 1 : 0.35) - p.vx) * 0.5 * dt
            p.vx += sin(t * 0.7 + p.seed) * 6 * dt
            p.vy += cos(t * 0.5 + p.seed * 1.3) * 4 * dt
            // Empuje del ratón
            if mspeed > 2 {
                let dx = p.x - mp.x, dy = p.y - mp.y
                let d = hypot(dx, dy)
                let R: CGFloat = 140
                if d < R {
                    let f = (1 - d / R)
                    p.vx += mv.dx * f * 0.9 * dt * 6
                    p.vy += mv.dy * f * 0.9 * dt * 6
                }
            }
            p.vx *= 0.985; p.vy *= 0.985
            p.x += p.vx * dt; p.y += p.vy * dt
            // Contra la pared derecha se acumula
            if p.x > W - p.size * 0.3 { p.x = W - p.size * 0.3; p.vx = min(p.vx, 0) - 2 }
            if p.x < -p.size { p.x = -p.size }
            if p.y > H + p.size { p.y = H + p.size }
            // Crece al expandirse y se oscurece con el tiempo
            let grow = 1 + min(p.age / 6, 1) * (p.settled ? 3.2 : 1.6)
            let sz = p.size * grow
            let fadeIn = min(1, p.age / 0.4)
            let fadeOut = sources.isEmpty ? max(0, 1 - idleTime / 25) : 1
            let lifeFade = p.age > p.life - 10 ? max(0, (p.life - p.age) / 10) : 1
            p.layer.position = CGPoint(x: p.x, y: p.y)
            p.layer.bounds = CGRect(x: 0, y: 0, width: sz, height: sz)
            p.layer.opacity = Float(fadeIn * fadeOut * lifeFade * (p.settled ? 0.85 : 0.75))
            parts[k] = p
        }
        let dead = parts.filter { $0.age >= $0.life || (sources.isEmpty && idleTime > 26) || ($0.inRoom && sources.isEmpty && idleTime > 18) }
        for d in dead { d.layer.removeFromSuperlayer() }
        parts.removeAll { $0.age >= $0.life || (sources.isEmpty && idleTime > 26) || ($0.inRoom && sources.isEmpty && idleTime > 18) }

        // Neblina de la sala
        if let v = roomVeil {
            if let r = room { v.frame = r; v.opacity = Float(roomLevel * 0.45) } else { v.opacity = 0 }
        }
        // Velo oscuro arriba que va bajando y oscureciéndose.
        if let c = ceiling {
            let edge = 1 - (ceilY - 80) / H
            c.colors = [NSColor(white: 0.08, alpha: 0).cgColor, NSColor(white: 0.08, alpha: 0).cgColor,
                        NSColor(white: 0.1, alpha: 0.55).cgColor, NSColor(white: 0.06, alpha: 0.8).cgColor]
            c.locations = [0, NSNumber(value: Double(max(0, 1 - edge - 0.08))), NSNumber(value: Double(1 - edge * 0.6)), 1]
            c.opacity = Float(min(0.9, level * 1.1))
        }
        CATransaction.commit()

        if sources.isEmpty { idleTime += dt } else { idleTime = 0 }
        if !w.isVisible { w.orderFrontRegardless() }
        if sources.isEmpty && parts.isEmpty && level <= 0.001 && roomLevel <= 0.001 { hide() }
    }

    func hide() {
        for p in parts { p.layer.removeFromSuperlayer() }
        parts.removeAll()
        window?.orderOut(nil)
        window = nil; root = nil; ceiling = nil
        level = 0; idleTime = 0; spawnAcc.removeAll(); lastMouse = nil
        roomLevel = 0; roomVeil = nil; chimneyAcc = 0
    }
}
