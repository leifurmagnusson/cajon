// Hold It — modelo: qué hay en la mano y cómo entra.

import AppKit
import ServiceManagement
import QuickLookThumbnailing

// MARK: - Preferencias

enum Prefs {
    /// Altura de la palma sobre el borde inferior de la pantalla (donde dejaste el brazo). nil = esquina de abajo.
    static var armOffset: CGFloat? {
        get { (UserDefaults.standard.object(forKey: "armOffset") as? Double).map { CGFloat($0) } }
        set { if let v = newValue { UserDefaults.standard.set(Double(v), forKey: "armOffset") } else { UserDefaults.standard.removeObject(forKey: "armOffset") } }
    }
    private static let d = UserDefaults.standard
    static var alwaysVisible: Bool {
        get { d.bool(forKey: "alwaysVisible") }
        set { d.set(newValue, forKey: "alwaysVisible") }
    }
    static var removeAfterDrag: Bool {
        get { d.object(forKey: "removeAfterDrag") as? Bool ?? true }
        set { d.set(newValue, forKey: "removeAfterDrag") }
    }
}

// MARK: - Modelo

final class ShelfItem {
    let id = UUID()
    let isClip: Bool               // true = lo creó Hold It (texto, imagen, enlace pegado)
    private(set) var bookmark: Data?
    private var fallback: URL

    /// Siempre resuelve el marcador: si mueves el archivo en Finder, Hold It lo sigue.
    var url: URL {
        if let b = bookmark {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: b, options: [.withoutUI, .withoutMounting],
                                relativeTo: nil, bookmarkDataIsStale: &stale) {
                if stale { bookmark = try? u.bookmarkData() }
                fallback = u
                return u
            }
        }
        return fallback
    }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    init(url: URL, isClip: Bool) {
        self.fallback = url
        self.isClip = isClip
        self.bookmark = try? url.bookmarkData()
    }

    init?(bookmark b: Data, isClip: Bool) {
        var stale = false
        guard let u = try? URL(resolvingBookmarkData: b, options: [.withoutUI, .withoutMounting],
                               relativeTo: nil, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: u.path) else { return nil }
        self.fallback = u
        self.isClip = isClip
        self.bookmark = stale ? (try? u.bookmarkData()) : b
    }
}

final class Store {
    static let shared = Store()
    private(set) var items: [ShelfItem] = []
    var onChange: (() -> Void)?
    let clipsDir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HoldIt", isDirectory: true)
        clipsDir = base.appendingPathComponent("Recortes", isDirectory: true)
        try? FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true)
        load()
        cleanOrphanClips()
    }

    func add(_ urls: [URL], isClip: Bool = false) {
        var changed = false
        for u in urls where !items.contains(where: { $0.url.path == u.path }) {
            items.append(ShelfItem(url: u, isClip: isClip))
            changed = true
        }
        if changed { save(); onChange?() }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        save(); onChange?()
    }

    func removeAll() {
        items.removeAll()
        save(); onChange?()
    }

    /// Quita los elementos cuyo archivo ya no existe (borrado, vaciado de papelera…).
    func prune() {
        let before = items.count
        items.removeAll { !$0.exists }
        if items.count != before { save(); onChange?() }
    }

    private func save() {
        let arr: [[String: Any]] = items.compactMap { i in
            guard let b = i.bookmark else { return nil }
            return ["b": b, "c": i.isClip]
        }
        UserDefaults.standard.set(arr, forKey: "items")
    }

    private func load() {
        guard let arr = UserDefaults.standard.array(forKey: "items") as? [[String: Any]] else { return }
        items = arr.compactMap { d in
            guard let b = d["b"] as? Data else { return nil }
            return ShelfItem(bookmark: b, isClip: d["c"] as? Bool ?? false)
        }
    }

    /// Borra recortes que ya no están en el cajón (se hace al arrancar, nunca en caliente,
    /// para no pisar a una app que aún esté leyendo un archivo que acabas de soltarle).
    private func cleanOrphanClips() {
        let base = clipsDir.standardizedFileURL.path + "/"
        var keep = Set<String>()
        for i in items where i.isClip {
            let p = i.url.standardizedFileURL.path
            if p.hasPrefix(base) {
                keep.insert(String(p.dropFirst(base.count)).components(separatedBy: "/").first ?? "")
            }
        }
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: clipsDir.path)) ?? []
        for e in entries where !keep.contains(e) {
            try? FileManager.default.removeItem(at: clipsDir.appendingPathComponent(e))
        }
    }

    // MARK: Recortes (lo que no es un archivo se convierte en archivo)

    private func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: Date())
    }

    private func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "-")
         .replacingOccurrences(of: ":", with: "-")
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func uniqueURL(_ base: String, ext: String) -> URL {
        var u = clipsDir.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: u.path) {
            u = clipsDir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return u
    }

    func clip(text: String) -> URL? {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let name = sanitize(String(first.prefix(40)))
        let u = uniqueURL(name.isEmpty ? "Texto \(stamp())" : name, ext: "txt")
        do { try text.write(to: u, atomically: true, encoding: .utf8); return u } catch { return nil }
    }

    func clip(image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let u = uniqueURL("Imagen \(stamp())", ext: "png")
        do { try png.write(to: u); return u } catch { return nil }
    }

    func clip(webURL: URL) -> URL? {
        let name = sanitize(webURL.host ?? "Enlace")
        let u = uniqueURL(name.isEmpty ? "Enlace" : name, ext: "webloc")
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: ["URL": webURL.absoluteString], format: .xml, options: 0) else { return nil }
        do { try data.write(to: u); return u } catch { return nil }
    }
}

let promiseQueue: OperationQueue = {
    let q = OperationQueue()
    q.qualityOfService = .userInitiated
    return q
}()

/// Mete en el cajón lo que haya en un portapapeles (de arrastre o el general).
@discardableResult
func ingest(_ pb: NSPasteboard) -> Bool {
    let store = Store.shared

    // 1. Archivos de verdad (Finder, escritorio…): se guarda una referencia, no una copia.
    if let urls = pb.readObjects(forClasses: [NSURL.self],
                                 options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
        store.add(urls)
        return true
    }
    // 2. Archivos "prometidos" (adjuntos de Mail, Fotos, imágenes de Safari…).
    if let promises = pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil)
        as? [NSFilePromiseReceiver], !promises.isEmpty {
        let dest = store.clipsDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        for p in promises {
            p.receivePromisedFiles(atDestination: dest, options: [:], operationQueue: promiseQueue) { url, error in
                guard error == nil else { return }
                DispatchQueue.main.async { store.add([url], isClip: true) }
            }
        }
        return true
    }
    // 3. Imágenes sueltas.
    if let imgs = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
       let img = imgs.first, let u = store.clip(image: img) {
        store.add([u], isClip: true)
        return true
    }
    // 4. Enlaces web.
    if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
       let w = urls.first(where: { !$0.isFileURL }), let u = store.clip(webURL: w) {
        store.add([u], isClip: true)
        return true
    }
    // 5. Texto.
    if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       let u = store.clip(text: s) {
        store.add([u], isClip: true)
        return true
    }
    return false
}

