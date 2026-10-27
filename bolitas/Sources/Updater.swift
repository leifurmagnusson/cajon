// Bolitas — se actualiza sola desde las versiones publicadas en GitHub.
// Al arrancar y cada 6 horas mira si hay una versión nueva; si la hay, la descarga,
// comprueba que está entera, sustituye la app y se vuelve a abrir. Tus bolitas se conservan.

import AppKit

enum Updater {
    static let latestAPI = URL(string: "https://api.github.com/repos/leifurmagnusson/cajon/releases?per_page=30")!
    static let assetName = "Bolitas.zip"
    private static var busy = false

    static var localBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    }
    static var versionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "Versión \(v)"
    }

    /// manual = true cuando lo pide la persona desde el menú: entonces avisa también si no hay nada nuevo.
    static func check(manual: Bool = false) {
        guard !busy else { return }
        busy = true
        var req = URLRequest(url: latestAPI)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, _, _ in
            // El repo también publica Hold It: nos quedamos con la última versión de Bolitas.
            let list = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [[String: Any]]) ?? []
            let mine = list.filter { ($0["tag_name"] as? String)?.hasPrefix("bolitas-") == true }
            let json = mine.max { (Int(($0["tag_name"] as? String ?? "").split(separator: ".").last ?? "") ?? 0) < (Int(($1["tag_name"] as? String ?? "").split(separator: ".").last ?? "") ?? 0) }
            guard let json = json,
                  let tag = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]],
                  let asset = assets.first(where: { ($0["name"] as? String) == assetName }),
                  let s = asset["browser_download_url"] as? String, let url = URL(string: s) else {
                busy = false
                if manual { tell("No he podido comprobar si hay versión nueva", "Revisa la conexión a internet.") }
                return
            }
            let remote = Int(tag.split(separator: ".").last ?? "") ?? 0
            guard remote > localBuild else {
                busy = false
                if manual { tell("Bolitas está al día", versionText) }
                return
            }
            URLSession.shared.downloadTask(with: url) { tmp, _, _ in
                defer { busy = false }
                guard let tmp = tmp else { return }
                install(zip: tmp)
            }.resume()
        }.resume()
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    private static func install(zip: URL) {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("BolitasUpdate-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        let zipPath = work.appendingPathComponent("update.zip")
        do { try fm.moveItem(at: zip, to: zipPath) } catch { return }
        guard run("/usr/bin/ditto", ["-x", "-k", zipPath.path, work.path]) == 0 else { return }
        let newApp = work.appendingPathComponent("Bolitas.app")
        guard fm.fileExists(atPath: newApp.path),
              run("/usr/bin/codesign", ["--verify", "--deep", newApp.path]) == 0 else { return }

        let current = Bundle.main.bundleURL
        let backup = work.appendingPathComponent("anterior.app")
        do {
            try fm.moveItem(at: current, to: backup)
            try fm.moveItem(at: newApp, to: current)
        } catch {
            if !fm.fileExists(atPath: current.path) { try? fm.moveItem(at: backup, to: current) }
            return
        }
        // Se vuelve a abrir un segundo después de cerrarse.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"\(current.path)\""]
        try? p.run()
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    private static func tell(_ title: String, _ text: String) {
        DispatchQueue.main.async {
            let a = NSAlert()
            a.messageText = title
            a.informativeText = text
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
    }
}
