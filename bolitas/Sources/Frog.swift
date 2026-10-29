// Bolitas — la rana del tejado del club.
// En cuanto empiezas a arrastrar algo (un archivo, una imagen, un texto, un enlace…), la rana saca la lengua
// y se te pega al cursor, pero solo si lo acercas a su tercio de la pantalla. Si lo sueltas ahí, se lo traga.
// Si no quieres que se lo quede, sacude el ratón 3 o 4 veces (izquierda-derecha o arriba-abajo) y te suelta.
// La lengua se dibuja en una capa transparente que cubre la pantalla solo mientras arrastras.

import AppKit

final class TongueView: NSView {
    var from: NSPoint = .zero      // boca de la rana (coordenadas de la ventana)
    var to: NSPoint = .zero        // punta: el cursor
    var visible = false
    var t: CGFloat = 0
    var onDrop: ((NSPasteboard) -> Bool)?

    override var isFlipped: Bool { false }
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .URL, .string, .tiff, .png, NSPasteboard.PasteboardType("public.url")]
                                + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.clear(bounds)
        // Casi invisible: hace falta un pelín de color para que la pantalla entera reciba lo que sueltas.
        cg.setFillColor(NSColor(white: 0, alpha: 0.004).cgColor); cg.fill(bounds)
        guard visible else { return }
        let mid = CGPoint(x: (from.x + to.x) / 2 + sin(t * 9) * 8, y: max(from.y, to.y) + 30 + cos(t * 7) * 6)
        let p = CGMutablePath(); p.move(to: from); p.addQuadCurve(to: to, control: mid)
        cg.setLineCap(.round)
        cg.addPath(p); cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(11); cg.strokePath()
        cg.addPath(p); cg.setStrokeColor(Palette.rgb(0xFF6F91).cgColor); cg.setLineWidth(7.5); cg.strokePath()
        cg.addPath(p); cg.setStrokeColor(Palette.rgb(0xFFB3C6, 0.8).cgColor); cg.setLineWidth(2); cg.strokePath()
        // Punta pegajosa
        let r: CGFloat = 11
        cg.setFillColor(Palette.rgb(0xFF6F91).cgColor)
        cg.fillEllipse(in: CGRect(x: to.x - r, y: to.y - r, width: r * 2, height: r * 2))
        cg.setStrokeColor(Palette.outline.cgColor); cg.setLineWidth(2)
        cg.strokeEllipse(in: CGRect(x: to.x - r, y: to.y - r, width: r * 2, height: r * 2))
        cg.setFillColor(NSColor.white.withAlphaComponent(0.7).cgColor)
        cg.fillEllipse(in: CGRect(x: to.x - 5, y: to.y + 2, width: 5, height: 4))
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { onDrop?(sender.draggingPasteboard) ?? false }
}

final class Frog {
    static let shared = Frog()
    enum State { case resting, catching, letGo, swallowing }
    private(set) var state: State = .resting
    private(set) var swallowStart: CGFloat = 0
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "frog.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "frog.enabled") }
    }
    /// Mientras sacas tú una caja del tejado, la rana no intenta cazarla.
    var draggingOut = false

    private var window: NSWindow?
    private var view: TongueView?
    private let dragPB = NSPasteboard(name: .drag)
    private var baseline = NSPasteboard(name: .drag).changeCount
    private var dragActive = false
    private var armed = false      // este arrastre lo puede cazar (lo empezaste fuera del tejado)
    private var lastMouse: NSPoint?
    private var lastDirX = 0, lastDirY = 0
    private var flips: [CGFloat] = []
    private var accX: CGFloat = 0, accY: CGFloat = 0

    private func ensure(_ screen: NSScreen) {
        if let w = window, w.frame == screen.frame { return }
        window?.orderOut(nil)
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let v = TongueView(frame: NSRect(origin: .zero, size: screen.frame.size))
        v.onDrop = { [weak self] pb in self?.swallow(pb) ?? false }
        w.contentView = v
        w.setFrame(screen.frame, display: false)
        window = w; view = v
    }

    private func swallow(_ pb: NSPasteboard) -> Bool {
        let ok = ingestShelf(pb)
        state = .swallowing
        swallowStart = CGFloat(Date().timeIntervalSinceReferenceDate)
        if ok { NSSound(named: NSSound.Name("Pop"))?.play() }
        hideTongue()
        return ok
    }

    private func hideTongue() {
        view?.visible = false
        window?.orderOut(nil)
    }

    /// Se llama en cada fotograma. mouth: boca de la rana en coordenadas de pantalla (nil si no hay rana a la vista).
    func step(t: CGFloat, dt: CGFloat, mouth: NSPoint?) {
        let pressed = (NSEvent.pressedMouseButtons & 1) == 1
        let cc = dragPB.changeCount
        if state == .swallowing, CGFloat(Date().timeIntervalSinceReferenceDate) - swallowStart > 0.8 { state = .resting }
        if !pressed {
            baseline = cc
            if dragActive {
                dragActive = false
                if state == .catching || state == .letGo { state = .resting }
                hideTongue()
            }
            return
        }
        if cc != baseline && !dragActive {
            dragActive = true
            flips.removeAll(); lastMouse = nil; accX = 0; accY = 0; lastDirX = 0; lastDirY = 0
            armed = enabled && !draggingOut && mouth != nil
        }
        // La pantalla se divide en tres franjas: la rana solo saca la lengua cuando acercas
        // lo que arrastras a la franja donde está ella. Si te alejas, la recoge y no se lo queda.
        guard dragActive, armed, state != .letGo, let mouth = mouth else { return }
        let m0 = NSEvent.mouseLocation
        guard let fs = NSScreen.screens.first(where: { $0.frame.contains(mouth) }) ?? NSScreen.main else { return }
        let third = fs.frame.width / 3
        let frogZone = Int((mouth.x - fs.frame.minX) / third)
        let inZone = fs.frame.contains(m0) && Int((m0.x - fs.frame.minX) / third) == frogZone
        if !inZone {
            if state == .catching { state = .resting; hideTongue() }
            return
        }
        if state != .catching { state = .catching; flips.removeAll(); lastMouse = nil }
        let screen = fs

        // Sacudida: cuenta los cambios de dirección rápidos del ratón.
        let m = NSEvent.mouseLocation
        if let lm = lastMouse {
            accX += m.x - lm.x; accY += m.y - lm.y
            if abs(accX) > 28 {
                let d = accX > 0 ? 1 : -1
                if lastDirX != 0 && d != lastDirX { flips.append(t) }
                lastDirX = d; accX = 0
            }
            if abs(accY) > 28 {
                let d = accY > 0 ? 1 : -1
                if lastDirY != 0 && d != lastDirY { flips.append(t) }
                lastDirY = d; accY = 0
            }
        }
        lastMouse = m
        flips.removeAll { t - $0 > 1.3 }
        if flips.count >= 4 {
            state = .letGo
            NSSound(named: NSSound.Name("Tink"))?.play()
            hideTongue()
            return
        }

        ensure(screen)
        guard let w = window, let v = view else { return }
        let o = w.frame.origin
        v.from = NSPoint(x: mouth.x - o.x, y: mouth.y - o.y)
        v.to = NSPoint(x: m.x - o.x, y: m.y - o.y)
        v.visible = true
        v.t = t
        if !w.isVisible { w.orderFrontRegardless() }
        v.needsDisplay = true
    }
}
