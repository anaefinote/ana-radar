import Foundation
import CryptoKit

/// Feature visibility for ANA ORBIT. Nothing is removed from the app — every feature asks
/// `Visibility.shared.seen("lessons")` before it draws. The answer comes from signed
/// class-30 pngmesh configs with hive=shell (feature/<key> = seen|unseen), applied by Lessons.
/// Default: everything SEEN until a config says otherwise. The "flavour" is a short fingerprint
/// of exactly which features are on — a build's identity that emerges from what's enabled.
final class Visibility {
    static let shared = Visibility()

    // the features ANA can show or hide (matches the Lesson Maker's registry)
    static let features = ["pulse", "archive", "appify", "timeline", "radar", "watch",
                           "eflex", "flex", "gst", "efinote", "settings", "lessons", "chatnote", "light"]

    private let key = "ana_visibility"               // UserDefaults: [feature: seen]
    private var state: [String: Bool] = [:]

    private init() {
        if let d = UserDefaults.standard.dictionary(forKey: key) as? [String: Bool] { state = d }
    }

    /// Default is SEEN; a config only ever turns things off (or back on).
    func seen(_ f: String) -> Bool { state[f] ?? true }

    /// Reset to the default (everything seen) — used before re-deriving from the kept configs.
    func reset() { state = [:]; save() }

    /// Merge a visibility map in (later configs override earlier ones).
    func apply(_ map: [String: Bool]) {
        for (k, v) in map { state[k] = v }
        save()
    }

    /// The build's flavour: first 8 hex of SHA-256 over the sorted list of SEEN features.
    func flavour() -> String {
        let on = Visibility.features.filter { seen($0) }.sorted()
        let joined = on.map { $0 + "," }.joined()
        let h = SHA256.hash(data: Data(joined.utf8))
        return String(h.map { String(format: "%02x", $0) }.joined().prefix(8))
    }

    /// For the web UI: {"pulse":1,"lessons":0,...,"_flavour":"ea80bc44"}
    func asJSON() -> String {
        var parts = Visibility.features.map { "\"\($0)\":\(seen($0) ? 1 : 0)" }
        parts.append("\"_flavour\":\"\(flavour())\"")
        return "{" + parts.joined(separator: ",") + "}"
    }

    private func save() { UserDefaults.standard.set(state, forKey: key) }
}
