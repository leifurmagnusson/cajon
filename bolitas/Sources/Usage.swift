// Bolitas — cuánto uso de Claude te queda.
// Inicias sesión en claude.ai una vez dentro de Bolitas (ventana propia); a partir de ahí,
// cada 5 minutos pide a claude.ai el mismo porcentaje que ves en Ajustes → Uso.
// ChatGPT no ofrece ese dato, así que de ChatGPT no se muestra uso.

import AppKit
import WebKit

final class Usage: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let shared = Usage()
    private(set) var lines: [String] = []
    var onChange: (() -> Void)?

    private var hidden: WKWebView?
    private var loginWindow: NSWindow?
    private var loginView: WKWebView?
    private var step = 0
    private var orgID: String?
    private var busy = false

    var loggedIn: Bool {
        get { UserDefaults.standard.bool(forKey: "usage.loggedIn") }
        set { UserDefaults.standard.set(newValue, forKey: "usage.loggedIn") }
    }

    func start() {
        if loggedIn { refresh() }
        let tm = Timer(timeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(tm, forMode: .common)
    }

    // MARK: Inicio de sesión

    func showLogin() {
        if let w = loginWindow { NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil); return }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 680), configuration: cfg)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.customUserAgent = Usage.safariUA
        wv.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 680), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Bolitas · entra en Claude para ver tu uso"
        w.contentView = wv
        w.isReleasedWhenClosed = false
        w.center()
        loginWindow = w; loginView = wv
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    static let safariUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    /// Inicio de sesión con Google y similares: abren una ventana nueva; la cargamos en la misma.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = navigationAction.request.url { webView.load(URLRequest(url: u)) }
        return nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView === hidden { log("error de carga: \(error.localizedDescription)"); busy = false }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView === hidden { log("error de carga: \(error.localizedDescription)"); busy = false }
    }

    /// Deja constancia de la última lectura (para poder ver qué pasa si no sale el porcentaje).
    private func log(_ s: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/.bolitas")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? "\(Date())\n\(s.prefix(3000))\n".write(to: dir.appendingPathComponent("uso.txt"), atomically: true, encoding: .utf8)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === loginView {
            // Cuando ya has entrado, claude.ai te lleva fuera de /login.
            let path = webView.url?.path ?? ""
            if !path.hasPrefix("/login") && !path.contains("magic-link") && !path.hasPrefix("/oauth") {
                checkSession { ok in
                    if ok {
                        self.loggedIn = true
                        self.loginWindow?.close(); self.loginWindow = nil; self.loginView = nil
                        self.refresh()
                    }
                }
            }
            return
        }
        if webView === hidden { readHidden() }
    }

    private func checkSession(_ done: @escaping (Bool) -> Void) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            done(cookies.contains { $0.name == "sessionKey" && $0.domain.contains("claude.ai") })
        }
    }

    // MARK: Lectura del uso

    func refresh() {
        guard loggedIn, !busy else { return }
        busy = true
        if hidden == nil {
            let cfg = WKWebViewConfiguration(); cfg.websiteDataStore = .default()
            hidden = WKWebView(frame: NSRect(x: 0, y: 0, width: 10, height: 10), configuration: cfg)
            hidden?.navigationDelegate = self
            hidden?.customUserAgent = Usage.safariUA
        }
        if let id = orgID { step = 1; load("https://claude.ai/api/organizations/\(id)/usage") }
        else { step = 0; load("https://claude.ai/api/organizations") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 40) { self.busy = false }
    }

    private func load(_ s: String) { hidden?.load(URLRequest(url: URL(string: s)!)) }

    private func readHidden() {
        hidden?.evaluateJavaScript("(document.querySelector('pre') || document.body || {innerText:''}).innerText") { res, err in
            let txt = res as? String ?? ""
            self.log("paso \(self.step) · \(self.hidden?.url?.absoluteString ?? "") · \(err?.localizedDescription ?? "ok")\n\(txt)")
            let json = try? JSONSerialization.jsonObject(with: Data(txt.utf8))
            if self.step == 0 {
                guard let arr = json as? [[String: Any]], !arr.isEmpty else { self.failed(txt); return }
                // Preferimos la organización con chat (la cuenta personal o de equipo).
                let org = arr.first { (($0["capabilities"] as? [String]) ?? []).contains("chat") } ?? arr[0]
                self.orgID = org["uuid"] as? String
                guard let id = self.orgID else { self.failed(txt); return }
                self.step = 1
                self.load("https://claude.ai/api/organizations/\(id)/usage")
            } else {
                self.busy = false
                guard let d = json as? [String: Any] else { self.failed(txt); return }
                self.lines = Usage.format(d)
                self.onChange?()
            }
        }
    }

    private func failed(_ txt: String) {
        busy = false
        if txt.contains("account_session_invalid") || txt.contains("unauthorized") || txt.contains("permission_error") {
            loggedIn = false
            lines = ["Sesión de Claude caducada", "toca para volver a entrar"]
        } else {
            lines = ["No he podido leer el uso"]
        }
        onChange?()
    }

    static func pct(_ any: Any?) -> Int? {
        if let d = any as? [String: Any] {
            if let u = d["utilization"] as? Double { return Int(u.rounded()) }
            if let u = d["utilization"] as? Int { return u }
            if let u = d["percent_used"] as? Double { return Int(u) }
        }
        return nil
    }
    static func resets(_ any: Any?) -> String? {
        guard let d = any as? [String: Any], let s = d["resets_at"] as? String else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        guard let dt = date else { return nil }
        let m = Int(dt.timeIntervalSinceNow / 60)
        if m <= 0 { return nil }
        if m < 60 { return "en \(m) min" }
        if m < 48 * 60 { return "en \(m / 60) h \(m % 60) min" }
        return "en \(m / 1440) días"
    }

    static func format(_ d: [String: Any]) -> [String] {
        var out: [String] = []
        let pairs: [(String, String)] = [("five_hour", "Claude · 5 horas"), ("seven_day", "Claude · semana"),
                                         ("seven_day_opus", "Semana · Opus"), ("seven_day_sonnet", "Semana · Sonnet")]
        for (k, label) in pairs {
            if let p = pct(d[k]) {
                var l = "\(label): \(p)%"
                if let r = resets(d[k]) { l += " · se renueva \(r)" }
                out.append(l)
            }
        }
        if out.isEmpty {
            // Formato desconocido: buscamos cualquier porcentaje.
            for (k, v) in d { if let p = pct(v) { out.append("\(k): \(p)%") } }
        }
        return out.isEmpty ? ["Uso de Claude: sin datos"] : out
    }
}
