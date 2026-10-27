// Magnusson — la tienda de apps de la familia para el Mac.
// • Lista las apps del catálogo (catalogo.json en GitHub) y las instala con un clic, sin avisos de macOS.
// • magnusson://instalar/<app> (el botón «Instalar» de magnusson.casa) abre la tienda e instala esa app.
// • Se queda en segundo plano y cada 6 horas actualiza las apps instaladas (y a sí misma).

import AppKit
import SwiftUI
import ServiceManagement

let catalogURL = URL(string: "https://raw.githubusercontent.com/leifurmagnusson/cajon/main/catalogo.json")!

// MARK: - Catálogo

struct CatalogApp: Codable, Identifiable, Equatable {
    var id: String { slug }
    let slug: String
    let nombre: String
    let descripcion: String
    let repo: String
    let prefijo: String
    let asset: String
    let app: String
    let bundle: String
    let icono: String?
    let oculta: Bool?
}

struct Catalog: Codable { let apps: [CatalogApp] }

struct Release {
    let build: Int
    let tag: String
    let download: URL
}

enum Estado: Equatable {
    case comprobando
    case noInstalada
    case alDia
    case actualizable
    case trabajando(String)
    case lista          // recién instalada
    case error(String)
}

// MARK: - Utilidades

@discardableResult
func run(_ path: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
}

let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)

/// Dónde está instalada (si lo está): primero ~/Applications, luego /Applications.
func installedURL(_ a: CatalogApp) -> URL? {
    for base in [userApps, URL(fileURLWithPath: "/Applications")] {
        let u = base.appendingPathComponent(a.app)
        if FileManager.default.fileExists(atPath: u.path) { return u }
    }
    return nil
}

func installedBuild(_ a: CatalogApp) -> Int? {
    guard let u = installedURL(a) else { return nil }
    let fromPlist = (Bundle(url: u)?.infoDictionary?["CFBundleVersion"] as? String).flatMap { Int($0) } ?? 0
    let recorded = UserDefaults.standard.integer(forKey: "build.\(a.slug)")
    return max(fromPlist, recorded)
}

func buildNumber(tag: String, prefix: String) -> Int? {
    guard tag.hasPrefix(prefix) else { return nil }
    return Int(tag.dropFirst(prefix.count).split(separator: ".").last ?? "")
}

// MARK: - Modelo

@MainActor
final class Shop: ObservableObject {
    static let shared = Shop()
    @Published var apps: [CatalogApp] = []
    @Published var estados: [String: Estado] = [:]
    @Published var iconos: [String: NSImage] = [:]
    @Published var cargando = true
    @Published var aviso: String?
    @Published var destacada: String?
    private var releases: [String: Release] = [:]
    private var pendiente: String?    // magnusson://instalar/… recibido antes de cargar el catálogo

    var visibles: [CatalogApp] { apps.filter { $0.oculta != true } }

    func refrescar() async {
        cargando = true
        aviso = nil
        do {
            var req = URLRequest(url: catalogURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            let (data, _) = try await URLSession.shared.data(for: req)
            apps = try JSONDecoder().decode(Catalog.self, from: data).apps
        } catch {
            cargando = false
            aviso = "No he podido conectar. Revisa internet y vuelve a intentarlo."
            return
        }
        for a in apps where estados[a.slug] == nil { estados[a.slug] = .comprobando }
        await cargarReleases()
        for a in apps { actualizarEstado(a) }
        cargando = false
        for a in apps { Task { await cargarIcono(a) } }
        if let p = pendiente { pendiente = nil; instalar(slug: p) }
    }

    private func cargarReleases() async {
        let repos = Set(apps.map { $0.repo })
        for repo in repos {
            guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=60") else { continue }
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            guard let res = try? await URLSession.shared.data(for: req),
                  let list = try? JSONSerialization.jsonObject(with: res.0) as? [[String: Any]] else { continue }
            for a in apps where a.repo == repo {
                var best: Release?
                for r in list {
                    guard let tag = r["tag_name"] as? String, let n = buildNumber(tag: tag, prefix: a.prefijo),
                          let assets = r["assets"] as? [[String: Any]],
                          let asset = assets.first(where: { ($0["name"] as? String) == a.asset }),
                          let s = asset["browser_download_url"] as? String, let u = URL(string: s) else { continue }
                    if best == nil || n > best!.build { best = Release(build: n, tag: tag, download: u) }
                }
                releases[a.slug] = best
            }
        }
    }

    private func cargarIcono(_ a: CatalogApp) async {
        if let u = installedURL(a) { iconos[a.slug] = NSWorkspace.shared.icon(forFile: u.path) }
        guard let s = a.icono, let url = URL(string: s),
              let res = try? await URLSession.shared.data(from: url), let img = NSImage(data: res.0) else { return }
        iconos[a.slug] = img
    }

    func actualizarEstado(_ a: CatalogApp) {
        if case .trabajando = estados[a.slug] { return }
        guard let local = installedBuild(a) else { estados[a.slug] = .noInstalada; return }
        if let r = releases[a.slug], r.build > local { estados[a.slug] = .actualizable } else { estados[a.slug] = .alDia }
    }

    // MARK: Acciones

    func instalar(slug: String) {
        guard !apps.isEmpty else { pendiente = slug; return }
        guard let a = apps.first(where: { $0.slug == slug }) else {
            aviso = "No encuentro la app «\(slug)» en la tienda."
            return
        }
        destacada = slug
        if installedBuild(a) != nil, case .alDia = estados[slug] {
            abrir(a)
            return
        }
        Task { await instalar(a, abrirAlTerminar: true) }
    }

    func instalar(_ a: CatalogApp, abrirAlTerminar: Bool) async {
        guard let r = releases[a.slug] else {
            estados[a.slug] = .error("Todavía no hay ninguna versión publicada")
            return
        }
        if case .trabajando = estados[a.slug] { return }
        estados[a.slug] = .trabajando("Descargando…")
        let result = await Task.detached(priority: .userInitiated) { () -> Result<URL, InstallError> in
            Installer.install(a, from: r.download)
        }.value
        switch result {
        case .success(let dest):
            UserDefaults.standard.set(r.build, forKey: "build.\(a.slug)")
            estados[a.slug] = .lista
            if a.slug == "tienda" { Installer.relaunch(dest); return }
            if abrirAlTerminar { NSWorkspace.shared.openApplication(at: dest, configuration: .init(), completionHandler: nil) }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            estados[a.slug] = .alDia
        case .failure(let e):
            estados[a.slug] = .error(e.texto)
        }
        if let ic = installedURL(a) { iconos[a.slug] = iconos[a.slug] ?? NSWorkspace.shared.icon(forFile: ic.path) }
    }

    func abrir(_ a: CatalogApp) {
        guard let u = installedURL(a) else { return }
        NSWorkspace.shared.openApplication(at: u, configuration: .init(), completionHandler: nil)
    }

    /// Actualiza en silencio todo lo instalado que tenga versión nueva (la tienda la última).
    func actualizarTodo() async {
        await refrescar()
        let orden = apps.filter { $0.slug != "tienda" } + apps.filter { $0.slug == "tienda" }
        for a in orden where estados[a.slug] == .actualizable {
            let running = !NSRunningApplication.runningApplications(withBundleIdentifier: a.bundle).isEmpty
            await instalar(a, abrirAlTerminar: running)
        }
    }
}

// MARK: - Instalador

enum InstallError: Error {
    case descarga, archivo, firma, sustituir
    var texto: String {
        switch self {
        case .descarga: return "No se ha podido descargar"
        case .archivo: return "El archivo descargado no es válido"
        case .firma: return "La app descargada está dañada"
        case .sustituir: return "No se ha podido colocar en Aplicaciones"
        }
    }
}

enum Installer {
    /// Descarga, comprueba y coloca la app. Lo descargado así no lleva la marca de
    /// «descargado de internet», por eso macOS no muestra avisos al abrirla.
    static func install(_ a: CatalogApp, from url: URL) -> Result<URL, InstallError> {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("Magnusson-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { if a.slug != "tienda" { try? fm.removeItem(at: work) } }

        let sem = DispatchSemaphore(value: 0)
        var downloaded: URL?
        URLSession.shared.downloadTask(with: url) { tmp, resp, _ in
            if let tmp = tmp, (resp as? HTTPURLResponse)?.statusCode ?? 0 < 400 {
                let z = work.appendingPathComponent("app.zip")
                if (try? fm.moveItem(at: tmp, to: z)) != nil { downloaded = z }
            }
            sem.signal()
        }.resume()
        sem.wait()
        guard let zip = downloaded else { return .failure(.descarga) }

        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path]) == 0 else { return .failure(.archivo) }
        let newApp = work.appendingPathComponent(a.app)
        guard fm.fileExists(atPath: newApp.path) else { return .failure(.archivo) }
        guard run("/usr/bin/codesign", ["--verify", "--deep", newApp.path]) == 0 else { return .failure(.firma) }
        run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

        // Si está abierta, se cierra (salvo la propia tienda, que se reinicia al final).
        if a.slug != "tienda" {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: a.bundle)
            running.forEach { $0.terminate() }
            for _ in 0..<40 where running.contains(where: { !$0.isTerminated }) { usleep(100_000) }
            running.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
        }

        try? fm.createDirectory(at: userApps, withIntermediateDirectories: true)
        let dest = installedURL(a) ?? userApps.appendingPathComponent(a.app)
        let old = work.appendingPathComponent("anterior-\(a.app)")
        if fm.fileExists(atPath: dest.path) {
            do { try fm.moveItem(at: dest, to: old) } catch { return .failure(.sustituir) }
        }
        do {
            try fm.moveItem(at: newApp, to: dest)
        } catch {
            if fm.fileExists(atPath: old.path) { try? fm.moveItem(at: old, to: dest) }
            return .failure(.sustituir)
        }
        return .success(dest)
    }

    static func relaunch(_ dest: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"\(dest.path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }
}

// MARK: - Pantalla

struct AppRow: View {
    let app: CatalogApp
    @ObservedObject var shop: Shop

    var estado: Estado { shop.estados[app.slug] ?? .comprobando }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if let img = shop.iconos[app.slug] {
                    Image(nsImage: img).resizable().interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.15))
                }
            }
            .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 3) {
                Text(app.nombre).font(.system(size: 15, weight: .semibold))
                Text(app.descripcion).font(.system(size: 12)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .error(let t) = estado {
                    Text(t).font(.system(size: 11, weight: .medium)).foregroundColor(.red)
                }
            }
            Spacer(minLength: 8)
            boton
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentColor.opacity(shop.destacada == app.slug ? 0.9 : 0), lineWidth: 2)
        )
    }

    @ViewBuilder var boton: some View {
        switch estado {
        case .comprobando:
            ProgressView().controlSize(.small).frame(width: 96)
        case .trabajando(let t):
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(t).font(.system(size: 12)) }.frame(width: 120)
        case .lista:
            Label("¡Lista!", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                .font(.system(size: 13, weight: .semibold)).frame(width: 96)
        case .noInstalada, .error:
            Button("Instalar") { shop.instalar(slug: app.slug) }
                .buttonStyle(.borderedProminent).controlSize(.large).frame(width: 96)
        case .actualizable:
            Button("Actualizar") { Task { await shop.instalar(app, abrirAlTerminar: false) } }
                .buttonStyle(.borderedProminent).controlSize(.large).frame(width: 96)
        case .alDia:
            Button("Abrir") { shop.abrir(app) }
                .buttonStyle(.bordered).controlSize(.large).frame(width: 96)
        }
    }
}

struct ShopView: View {
    @ObservedObject var shop = Shop.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apps de la familia").font(.system(size: 20, weight: .bold))
                    Text("Se instalan con un clic y se actualizan solas.").font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
                Button { Task { await shop.refrescar() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Volver a mirar")
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)

            if let aviso = shop.aviso {
                Text(aviso).font(.system(size: 12)).foregroundColor(.orange).padding(.horizontal, 20).padding(.bottom, 8)
            }

            ScrollView {
                VStack(spacing: 12) {
                    if shop.cargando && shop.apps.isEmpty {
                        ProgressView().padding(40)
                    }
                    ForEach(shop.visibles) { a in AppRow(app: a, shop: shop) }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
            Divider()
            HStack {
                Text("magnusson.casa").font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Text("Versión \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 360, idealHeight: 470)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let silent = ProcessInfo.processInfo.arguments.contains("--fondo")
        if !silent { showWindow() }
        if !UserDefaults.standard.bool(forKey: "didSetupLogin") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "didSetupLogin")
        }
        Task { @MainActor in await Shop.shared.refrescar() }
        // Actualizaciones automáticas cada 6 horas (y una a los 2 minutos de arrancar).
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { Task { @MainActor in await Shop.shared.actualizarTodo() } }
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { _ in Task { @MainActor in await Shop.shared.actualizarTodo() } }
        RunLoop.main.add(t, forMode: .common)
    }

    @objc func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: s), url.scheme == "magnusson" else { return }
        // magnusson://instalar/hold-it
        let parts = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).filter { !$0.isEmpty }
        showWindow()
        if parts.count >= 2, parts[0] == "instalar" {
            Task { @MainActor in Shop.shared.instalar(slug: parts[1]) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func showWindow() {
        NSApp.setActivationPolicy(.regular)
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Magnusson"
            w.titlebarAppearsTransparent = true
            w.contentView = NSHostingView(rootView: ShopView())
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            if !Shop.shared.cargando { await Shop.shared.refrescar() }
        }
    }

    // Al cerrar la ventana la tienda sigue en segundo plano (sin icono en el Dock) para actualizar.
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let m = NSMenu()
        m.addItem(withTitle: "Acerca de Magnusson", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "Cerrar ventana", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        m.addItem(withTitle: "Salir de Magnusson", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = m
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
