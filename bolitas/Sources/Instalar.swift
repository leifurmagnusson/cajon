// Se coloca sola en Aplicaciones.
// Si la app se abre desde Descargas (o desde cualquier sitio que no sea Aplicaciones), se copia a
// /Applications (o a ~/Applications si no se puede), quita la marca de «descargado de internet»
// para que macOS no vuelva a preguntar, y se vuelve a abrir desde allí.

import AppKit

enum SelfInstall {
    /// Devuelve true si ha lanzado la copia instalada: entonces esta copia debe cerrarse.
    static func moveIfNeeded() -> Bool {
        let fm = FileManager.default
        let here = Bundle.main.bundleURL
        let name = here.lastPathComponent
        let userApps = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        let system = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let path = here.resolvingSymlinksInPath().path
        if path.hasPrefix(system.path + "/") || path.hasPrefix(userApps.resolvingSymlinksInPath().path + "/") { return false }

        let existing = [system, userApps].map { $0.appendingPathComponent(name) }.first { fm.fileExists(atPath: $0.path) }
        let base: URL
        if let e = existing { base = e.deletingLastPathComponent() }
        else if fm.isWritableFile(atPath: system.path) { base = system }
        else { try? fm.createDirectory(at: userApps, withIntermediateDirectories: true); base = userApps }
        let dest = base.appendingPathComponent(name)

        let tmp = base.appendingPathComponent(".\(UUID().uuidString)-\(name)")
        guard (try? fm.copyItem(at: here, to: tmp)) != nil else { return false }
        run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", tmp.path])

        // Si había otra copia abierta (una versión anterior), se cierra.
        if let id = Bundle.main.bundleIdentifier {
            for a in NSRunningApplication.runningApplications(withBundleIdentifier: id) where a != .current {
                a.terminate()
            }
        }
        if fm.fileExists(atPath: dest.path) {
            let old = fm.temporaryDirectory.appendingPathComponent("anterior-\(UUID().uuidString)-\(name)")
            guard (try? fm.moveItem(at: dest, to: old)) != nil else { try? fm.removeItem(at: tmp); return false }
        }
        guard (try? fm.moveItem(at: tmp, to: dest)) != nil else { return false }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"\(dest.path)\""]
        try? p.run()
        return true
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
}
