// Bolitas — modelo: cada bola es un chat de Claude o de ChatGPT con su estado de ánimo.
//   verde  = trabajando / pensando (con cronómetro)
//   amarillo = te necesita: pide permiso, o ha terminado y espera tu respuesta
//   gris   = parada, ya la has visto

import AppKit

enum Provider: String, Codable {
    case claude, chatgpt
    var bundleIDs: [String] {
        switch self {
        case .claude: return ["com.anthropic.claudefordesktop"]
        case .chatgpt: return ["com.openai.chat", "com.openai.codex", "com.openai.chatgpt"]
        }
    }
    var letter: String { self == .claude ? "C" : "G" }
    var name: String { self == .claude ? "Claude" : "ChatGPT" }
}

enum Mood: String, Codable { case working, needsYou, done, idle }

/// De dónde salió la última prueba de que estaba trabajando.
enum Evidence: String, Codable { case current, sidebar, none }

struct Chat: Codable, Equatable {
    var key: String
    var provider: Provider
    var title: String
    var chatID: String?
    var pinned: Bool
    var mood: Mood
    var since: Date            // desde cuándo está en este estado
    var lastConfirmed: Date    // última vez que vimos el estado confirmado
    var evidence: Evidence
    var lastActive: Date       // última vez que estuvo verde o amarilla

    var shortTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return provider.name }
        return t.count > 16 ? String(t.prefix(15)) + "…" : t
    }
}

final class Store {
    static let shared = Store()
    private(set) var chats: [Chat] = []
    var onChange: (() -> Void)?
    var onNeedsYou: ((Chat) -> Void)?
    private let key = "chats.v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let c = try? JSONDecoder().decode([Chat].self, from: d) { chats = c }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(chats) { UserDefaults.standard.set(d, forKey: key) }
        onChange?()
    }

    func index(_ key: String) -> Int? { chats.firstIndex { $0.key == key } }

    @discardableResult
    func add(provider: Provider, title: String, chatID: String?, key: String, pinned: Bool) -> Chat {
        if let i = index(key) {
            if pinned { chats[i].pinned = true }
            if !title.isEmpty { chats[i].title = title }
            save(); return chats[i]
        }
        let now = Date()
        let c = Chat(key: key, provider: provider, title: title, chatID: chatID, pinned: pinned,
                     mood: .idle, since: now, lastConfirmed: now, evidence: .none, lastActive: now)
        chats.append(c); save(); return c
    }

    func remove(_ key: String) { chats.removeAll { $0.key == key }; save() }
    func togglePin(_ key: String) { if let i = index(key) { chats[i].pinned.toggle(); save() } }
    func removeIdle() { chats.removeAll { $0.mood == .idle }; save() }
    func markSeen(_ key: String) {
        if let i = index(key), chats[i].mood == .done { chats[i].mood = .idle; chats[i].since = Date(); save() }
    }

    func dismiss(_ key: String) {
        if let i = index(key), chats[i].mood != .idle && chats[i].mood != .working {
            chats[i].mood = .idle; chats[i].since = Date(); save()
        }
    }

    /// Aplica lo que se ha observado en las apps en esta pasada.
    func apply(_ observations: [Obs], frontmost: Set<Provider>, running: Set<Provider>) {
        let now = Date()
        var changed = false
        for o in observations {
            var i = index(o.key)
            if i == nil {
                // Solo aparecen solas las conversaciones que están haciendo algo.
                guard o.working || o.needs else { continue }
                let c = Chat(key: o.key, provider: o.provider, title: o.title, chatID: o.chatID, pinned: false,
                             mood: .idle, since: now, lastConfirmed: now, evidence: .none, lastActive: now)
                chats.append(c); i = chats.count - 1; changed = true
            }
            guard let k = i else { continue }
            var c = chats[k]
            let before = c
            if !o.title.isEmpty && o.title != c.title { c.title = o.title }
            if c.chatID == nil, let id = o.chatID { c.chatID = id }

            let viewing = o.current && frontmost.contains(o.provider)
            if o.needs {
                if c.mood != .needsYou { c.mood = .needsYou; c.since = now; onNeedsYou?(c) }
                c.lastConfirmed = now; c.lastActive = now
            } else if o.working {
                if c.mood != .working { c.mood = .working; c.since = now }
                c.evidence = o.current ? .current : .sidebar
                c.lastConfirmed = now; c.lastActive = now
            } else {
                switch c.mood {
                case .working:
                    // Si solo lo sabíamos por tenerlo abierto, al cambiar de chat no podemos saber si sigue:
                    // lo dejamos en verde un rato prudencial antes de darlo por terminado.
                    let stillUnknown = !o.current && c.evidence == .current && now.timeIntervalSince(c.lastConfirmed) < 20 * 60
                    if !stillUnknown {
                        if viewing { c.mood = .idle } else { c.mood = .done; onNeedsYou?(c) }
                        c.since = now; c.lastActive = now
                    }
                case .needsYou:
                    c.mood = viewing ? .idle : .done; c.since = now; c.lastActive = now
                case .done:
                    if viewing { c.mood = .idle; c.since = now }
                case .idle: break
                }
            }
            if c != before { chats[k] = c; changed = true }
        }
        // Las que no están fijadas y llevan dos horas dormidas se van solas.
        let n = chats.count
        chats.removeAll { !$0.pinned && $0.mood == .idle && now.timeIntervalSince($0.lastActive) > 2 * 3600 }
        if chats.count != n { changed = true }
        if changed { save() }
    }
}

enum Prefs {
    static var hidden: Bool {
        get { UserDefaults.standard.bool(forKey: "hidden") }
        set { UserDefaults.standard.set(newValue, forKey: "hidden") }
    }
    static var sound: Bool {
        get { UserDefaults.standard.object(forKey: "sound") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sound") }
    }
    static var theme: Theme {
        get { .monos }   // De momento, solo los monos (bolitas y enanitos aparcados).
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "theme") }
    }
    static func origin(for th: Theme) -> NSPoint? {
        guard let a = UserDefaults.standard.array(forKey: "origin." + th.rawValue) as? [Double], a.count == 2 else { return nil }
        return NSPoint(x: a[0], y: a[1])
    }
    static func setOrigin(_ p: NSPoint, for th: Theme) {
        UserDefaults.standard.set([Double(p.x), Double(p.y)], forKey: "origin." + th.rawValue)
    }
}
