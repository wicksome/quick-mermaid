import Foundation

/// Recent rendered diagrams, stored in UserDefaults and shared across the resident
/// app and CLI instances. Each entry is { code, ts(epoch seconds), engine? }. Most-recent
/// first, capped at `maxItems`. Only successfully-rendered diagrams are added. `engine`
/// ("mermaid"/"plantuml") is persisted so re-rendering from history routes to the same
/// engine instead of re-guessing from content (which mis-detects fenced PlantUML).
enum History {
    static let maxItems = 30
    private static let d = UserDefaults.standard
    private static let key = "recentDiagrams"

    static func items() -> [[String: Any]] {
        (d.array(forKey: key) as? [[String: Any]]) ?? []
    }

    static func add(_ code: String, engine: String?) {
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var list = items().filter { ($0["code"] as? String) != code }   // de-dupe (move to front)
        var item: [String: Any] = ["code": code, "ts": Date().timeIntervalSince1970]
        if let engine { item["engine"] = engine }
        list.insert(item, at: 0)
        if list.count > maxItems { list = Array(list.prefix(maxItems)) }
        d.set(list, forKey: key)
    }

    static func remove(_ code: String) {
        d.set(items().filter { ($0["code"] as? String) != code }, forKey: key)
    }
}
