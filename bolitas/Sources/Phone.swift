// Bolitas — el estado de tus chats en el iPhone.
// • Widget (Scriptable, pantalla de bloqueo): Bolitas publica una línea por chat en un canal privado de ntfy.sh
//   cada vez que algo cambia (y cada 2 h aunque no cambie nada). El widget lee el último estado publicado.
// • Avisos: cuando un chat espera tu OK (permiso o pregunta), Bolitas manda una notificación al canal de avisos,
//   al que te suscribes con la app gratuita ntfy en el iPhone.
// Los nombres de los dos canales son aleatorios y se crean en tu Mac (no están en el código ni en GitHub).

import AppKit
import CoreImage

final class Phone {
    static let shared = Phone()
    private let server = "https://ntfy.sh"
    private var lastPayload = ""
    private var lastSent = Date.distantPast
    private var pendingTimer: Timer?

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "phone.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "phone.enabled"); if newValue { publish(force: true) } }
    }
    private func topic(_ key: String) -> String {
        if let t = UserDefaults.standard.string(forKey: key) { return t }
        let chars = Array("abcdefghijkmnpqrstuvwxyz23456789")
        let t = "bolitas-" + String((0..<22).map { _ in chars.randomElement()! })
        UserDefaults.standard.set(t, forKey: key)
        return t
    }
    var statusTopic: String { topic("phone.statusTopic") }
    var alertTopic: String { topic("phone.alertTopic") }

    // MARK: Estado (para el widget)

    private static let hhmm: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    private func payload() -> String {
        let order: [Mood] = [.needsYou, .done, .working, .idle]
        let chats = Store.shared.chats.filter { $0.mood != .idle }
            .sorted { (order.firstIndex(of: $0.mood) ?? 9, $1.since) < (order.firstIndex(of: $1.mood) ?? 9, $0.since) }
        let items: [[String: Any]] = chats.map { c in
            let (e, s): (String, String) = {
                switch c.mood {
                case .working: return ("🟢", "trabajando")
                case .needsYou: return ("🟡", "espera tu OK")
                case .done: return ("🎉", "ha terminado")
                case .idle: return ("⚪️", "parado")
                }
            }()
            return ["e": e, "n": c.title.isEmpty ? c.provider.name : c.title, "s": s, "h": Phone.hhmm.string(from: c.since)]
        }
        let d = try? JSONSerialization.data(withJSONObject: ["c": items], options: [.sortedKeys])
        return d.flatMap { String(data: $0, encoding: .utf8) } ?? "{\"c\":[]}"
    }

    /// Se llama cuando cambian los chats (y de vez en cuando). Agrupa los cambios: como mucho uno cada 20 s.
    func publish(force: Bool = false) {
        guard enabled else { return }
        let p = payload()
        let stale = Date().timeIntervalSince(lastSent) > 2 * 3600
        guard force || p != lastPayload || stale else { return }
        let wait = max(0, 20 - Date().timeIntervalSince(lastSent))
        if wait > 0 && !force {
            if pendingTimer == nil {
                pendingTimer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in
                    self?.pendingTimer = nil; self?.publish(force: true)
                }
            }
            return
        }
        lastPayload = p; lastSent = Date()
        var r = URLRequest(url: URL(string: "\(server)/\(statusTopic)")!)
        r.httpMethod = "POST"; r.httpBody = Data(p.utf8)
        r.setValue("12h", forHTTPHeaderField: "Cache")
        URLSession.shared.dataTask(with: r).resume()
    }

    // MARK: Avisos

    func alert(_ c: Chat) {
        guard enabled, c.mood == .needsYou else { return }
        let name = c.title.isEmpty ? c.provider.name : c.title
        var r = URLRequest(url: URL(string: "\(server)/\(alertTopic)")!)
        r.httpMethod = "POST"
        r.httpBody = Data("\(name) espera tu OK".utf8)
        r.setValue("Bolitas", forHTTPHeaderField: "Title")
        r.setValue("high", forHTTPHeaderField: "Priority")
        r.setValue("yellow_circle", forHTTPHeaderField: "Tags")
        r.setValue(c.provider == .claude ? "claude://" : "chatgpt://", forHTTPHeaderField: "Click")
        URLSession.shared.dataTask(with: r).resume()
        publish(force: true)
    }

    // MARK: Puesta en marcha en el iPhone

    /// El script del widget, ya con tu canal dentro (para pegarlo en Scriptable).
    var widgetScript: String {
        """
        // Bolitas — estado de tus chats de Claude (widget de Scriptable)
        const URL_ = "\(server)/\(statusTopic)/json?poll=1&since=12h"
        let data = null, when = null
        try {
          const txt = await new Request(URL_).loadString()
          for (const line of txt.trim().split("\\n")) {
            if (!line) continue
            const m = JSON.parse(line)
            if (m.event === "message") { data = JSON.parse(m.message); when = new Date(m.time * 1000) }
          }
        } catch (e) {}
        const fam = config.widgetFamily || "large"
        const lock = fam.startsWith("accessory")
        const max = lock ? 3 : (fam === "small" ? 4 : (fam === "medium" ? 4 : 10))
        const w = new ListWidget()
        w.refreshAfterDate = new Date(Date.now() + 5 * 60 * 1000)
        if (!lock) { w.backgroundColor = new Color("#1E3A2C"); w.setPadding(10, 12, 10, 12) }
        const add = (t, size, bold, color) => {
          const s = w.addText(t); s.font = bold ? Font.boldSystemFont(size) : Font.systemFont(size)
          s.lineLimit = 1; s.minimumScaleFactor = 0.7
          if (!lock && color) s.textColor = new Color(color)
        }
        const old = !when || (Date.now() - when.getTime()) > 3 * 3600 * 1000
        if (!data) {
          add("Bolitas: sin datos", lock ? 13 : 14, true, "#F2E8CF")
          add("¿Mac apagado?", lock ? 12 : 12, false, "#C9D6CF")
        } else {
          const c = data.c || []
          if (!lock) add("Bolitas", 13, true, "#F2C46D")
          if (c.length === 0) add("Ningún chat trabajando", lock ? 13 : 13, false, "#F2E8CF")
          const shown = c.length > max ? c.slice(0, max - 1) : c
          for (const x of shown) add(`${x.e} ${x.n} · ${x.s} · ${x.h}`, lock ? 13 : 13, x.e === "🟡", "#F2E8CF")
          if (c.length > max) {
            const rest = c.slice(max - 1)
            const work = rest.filter(x => x.e === "🟢").length
            add(work === rest.length ? `+${work} trabajando` : `+${rest.length} más`, lock ? 12 : 12, false, "#C9D6CF")
          }
          if (old && !lock) { const hh = when ? when.toTimeString().slice(0, 5) : "?"; add(`(Mac sin conexión desde ${hh})`, 10, false, "#C9D6CF") }
        }
        Script.setWidget(w)
        if (config.runsInApp) await w.presentLarge()
        Script.complete()
        """
    }

    func qrImage(_ text: String) -> NSImage? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(text.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size); img.addRepresentation(rep)
        return img
    }

    /// Ventana con los dos pasos para el iPhone.
    func showSetup() {
        if !enabled { enabled = true }
        let a = NSAlert()
        a.messageText = "Bolitas en el iPhone"
        a.informativeText = """
        1 · Avisos: instala la app gratuita «ntfy» en el iPhone. Pulsa aquí «Copiar el canal de avisos». \
        En ntfy toca «+», pega el canal (el portapapeles pasa del Mac al iPhone solo) y «Subscribe».
        Canal: \(alertTopic)

        2 · Widget: instala la app gratuita «Scriptable». Pulsa aquí «Copiar el widget». En Scriptable toca «+», \
        pega y ponle nombre. Después, mantén pulsada la pantalla de bloqueo → Personalizar → añade el widget \
        de Scriptable y elige ese script.
        """
        a.addButton(withTitle: "Copiar el canal de avisos")
        a.addButton(withTitle: "Copiar el widget")
        a.addButton(withTitle: "Cerrar")
        NSApp.activate(ignoringOtherApps: true)
        let r = a.runModal()
        if r == .alertFirstButtonReturn || r == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(r == .alertFirstButtonReturn ? alertTopic : widgetScript, forType: .string)
            // Vuelve a abrir la ventana para el otro paso
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.showSetup() }
        }
    }
}
