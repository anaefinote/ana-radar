import Foundation

/// Plain-text, tab-separated log: the same file and columns as the Android app (AnaLog.java), so a line written
/// here reads the same there. One line per entry:
///
///     src  when  postMs  package  title  text  key  lagMs  eventMs
///
/// It lives in the app's Documents folder (visible in the Files app: On My iPhone > ANA > ana_log.txt).
enum AnaLog {
    static let header = "#src\twhen\tpostMs\tpackage\ttitle\ttext\tkey\tlagMs\teventMs"

    static var url: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("ana_log.txt")
    }

    static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private static let whenFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// ms since 1970 -> "yyyy-mm-dd hh:mm:ss" (local)
    static func when(_ ms: Int64) -> String {
        whenFormat.string(from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000))
    }

    /// the eventMs column -> "yyyy-mm-dd hh:mm:ss", "" for none (EFINOTE's future ball)
    static func whenOrEmpty(_ ms: String) -> String {
        guard let t = Int64(ms), t > 0 else { return "" }
        return when(t)
    }

    /// One line, one field: tabs and line breaks out (as AnaLog.clean in Java).
    static func clean(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            switch u {
            case "\t", "\r":
                out.append(" ")
            case "\n", "\u{2028}", "\u{2029}", "\u{0B}", "\u{0C}", "\u{85}":
                out.append(contentsOf: " / ".unicodeScalars)
            default:
                out.append(u)
            }
        }
        return String(out).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func append(src: String, postMs: Int64, pkg: String, title: String, text: String, key: String,
                       lagMs: Int64 = 0, eventMs: Int64 = 0) {
        var line = ""
        if !FileManager.default.fileExists(atPath: url.path) { line += header + "\n" }
        line += [clean(src), when(postMs), String(postMs), clean(pkg), clean(title), clean(text), clean(key),
                 String(lagMs), String(eventMs)].joined(separator: "\t") + "\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            h.closeFile()
        } else {
            try? data.write(to: url)
        }
    }

    /// Data lines only (header / comment lines skipped).
    static func readAll() -> [String] {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return s.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// The whole file, header included, for "Export the text log".
    static func readText() -> String {
        var s = header + "\n"
        for l in readAll() { s += l + "\n" }
        return s
    }

    /// EFINOTE > Retention Period: drop lines older than `days` days (0 = keep forever). Run at start-up,
    /// before the log is sent to the page, so the line numbers the page uses stay right.
    @discardableResult
    static func prune(days: Int) -> Int {
        guard days > 0 else { return 0 }
        let cut = nowMs() - Int64(days) * 86_400_000
        var keep = header + "\n"
        var dropped = 0
        for l in readAll() {
            let col = l.components(separatedBy: "\t")
            let t = col.count > 2 ? (Int64(col[2]) ?? 0) : 0
            if t > 0 && t < cut { dropped += 1; continue }
            keep += l + "\n"
        }
        if dropped > 0 { try? keep.data(using: .utf8)?.write(to: url) }
        return dropped
    }
}
