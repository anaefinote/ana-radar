import Foundation
import CryptoKit

/// BILLS (the core): the same rules and files as Android's BillCore.java. Paying bills earns eFLEX.
///
///   1  PLAN    a bill coming up; paid on or before the due date earns the most
///   2  PAID    a bill already paid, reported after: half
///   3  HELP    someone shares their bill (a signed file); you help pay it; they confirm and BOTH earn
///              (helper the full rate, the person helped half). Not a swap: the same two people again within
///              30 days earn less each time (1/2, 1/3 ...).
///
/// Proof: a notification from the app picked for the bill, carrying the exact amount, inside the bill's time
/// window, not used by another bill. On the iPhone these come relayed from Android ANA. No notification: a
/// picture (or the person's word) is CLAIMED, at a quarter; a later matching notification pays the difference.
///
/// Files: 40 bill, 41 help receipt, 42 thanks; rows section|key|value, then phone|key (raw 65-byte key, hex),
/// sig|key_id = sha256(raw key), sig|value = raw low-S r||s over "ANA-PMSH1|<class>|" || sha256(body).
/// Amounts are whole cents. BBD counts at 2 BBD to 1 USD.
enum BillCore {
    static let clsBill: Int32 = 40, clsHelp: Int32 = 41, clsThanks: Int32 = 42
    static let clsChat: Int32 = 46                 // CHATNOTE: a signed message, headless (no picture)
    static let clsSched: Int32 = 43, clsPaid: Int32 = 44, clsJourney: Int32 = 45     // a bill's locked schedule (iPhone -> its Android); the Android's signed "paid"
    static let rPlan = 1.0, rLate = 0.5, rPaid = 0.5, rHelper = 1.0, rHelped = 0.5, claimed = 0.25
    static let rAhead = 1.25                                  // settled a week or more before the due date
    static let aheadMs: Int64 = 7 * 86_400_000, goalMs: Int64 = 30 * 86_400_000
    static let noMoney = "Novvera never touches money. Not yours, not your group's, not ever. ANA can't pay, hold, move, "
        + "collect or send a single cent. You pay your billers yourself, in your own bank or biller app. ANA only keeps track, on your phone."
    static let day: Int64 = 86_400_000
    static let paidBefore = 7 * day, paidAfter = 2 * day, lateGrace = 7 * day, helpWindow = 14 * day, pairDays = 30 * day
    static let settle = 30 * day, maxOcc = 400
    static let units = ["day", "week", "month", "year"]

    // ------------------------------------------------------------------ repeating bills (as BillCore.java)
    static func cal(_ ymd: String) -> Date? {
        guard ymd.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { return nil }
        let p = ymd.split(separator: "-").map { Int($0) ?? 0 }
        guard let d = Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2])), BillCore.ymd(d) == ymd else { return nil }
        return d                                                  // 30 February is not a date (no rolling over)
    }

    static func ymd(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func ymd(ms: Int64) -> String { ymd(Date(timeIntervalSince1970: Double(ms) / 1000)) }

    static func schedule(_ first: String, _ every: Int, _ unit: String) -> [String] {
        guard let c0 = cal(first) else { return [] }
        if every <= 0 { return [first] }
        guard let end = Calendar.current.date(byAdding: .month, value: 12, to: c0) else { return [first] }
        let comp: Calendar.Component = unit == "day" ? .day : unit == "week" ? .weekOfYear : unit == "year" ? .year : .month
        var out = [String]()
        for k in 0..<maxOcc {
            guard let d = Calendar.current.date(byAdding: comp, value: k * every, to: c0), d <= end else { break }
            out.append(ymd(d))
        }
        return out
    }

    static func dayEnd(_ ymd: String) -> Int64 {
        guard let d = cal(ymd), let n = Calendar.current.date(byAdding: .day, value: 1, to: d) else { return 0 }
        return Int64((n.timeIntervalSince1970 * 1000).rounded()) - 1
    }

    static func period(_ every: Int, _ unit: String) -> Int64 {
        if every <= 0 { return settle }
        let u: Int64 = unit == "day" ? day : unit == "week" ? 7 * day : unit == "year" ? 365 * day : 30 * day
        return Int64(every) * u
    }

    static func window(_ due: String, _ every: Int, _ unit: String, _ made: Int64) -> (Int64, Int64, Int64) {
        let e = dayEnd(due), p = period(every, unit)
        return (max(made - day, e - min(settle, p)), e, e + min(lateGrace, p))
    }

    static func repeatWords(_ every: Int, _ unit: String) -> String {
        if every <= 0 { return "once" }
        if every == 1 { return unit == "day" ? "daily" : unit + "ly" }
        return "every \(every) " + unit + "s"
    }

    // ------------------------------------------------------------------ money
    static func cents(_ s0: String) -> Int64 {
        let s = s0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")
        guard s.range(of: "^[0-9]{1,9}(\\.[0-9]{1,2})?$", options: .regularExpression) != nil else { return -1 }
        let p = s.split(separator: ".", omittingEmptySubsequences: false)
        let whole = Int64(p[0]) ?? 0
        if p.count == 1 { return whole * 100 }
        var f = String(p[1])
        if f.count == 1 { f += "0" }
        return whole * 100 + (Int64(f) ?? 0)
    }

    static func money(_ c: Int64, _ cur: String) -> String {
        let a = abs(c)
        let whole = String(a / 100)
        var w = ""
        for (i, ch) in whole.enumerated() {
            if i > 0 && (whole.count - i) % 3 == 0 { w.append(",") }
            w.append(ch)
        }
        return (c < 0 ? "-" : "") + cur + " " + w + "." + (a % 100 < 10 ? "0" : "") + String(a % 100)
    }

    /// a CHATNOTE message as it's kept: no control characters but new lines, at most 500 (as Android)
    static func clean500(_ s: String) -> String {
        let t = String(s.unicodeScalars.map { ($0.value < 32 && $0.value != 10) || $0.value == 127 ? " " : Character($0) })
        return String(t.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
    }

    /// a name as it's kept: no control characters, at most 80 characters (as Android)
    static func clean(_ s: String) -> String {
        var t = String(s.unicodeScalars.map { $0.value < 32 || $0.value == 127 ? " " : Character($0) }).trimmingCharacters(in: .whitespaces)
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return String(t.prefix(80))
    }

    static func usd(_ c: Int64, _ cur: String) -> Double { cur == "BBD" ? Double(c) / 200 : Double(c) / 100 }

    private static let moneyRx = try! NSRegularExpression(pattern:
        "(?<![0-9.,])((?:\\$|BBD|USD|BDS)\\s*)?([0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(\\.[0-9]{2})?(?![0-9])")

    /// every amount in the text, in cents; a bare whole number (no $ / currency, no decimals) is skipped
    static func amountsIn(_ text: String) -> [Int64] {
        let ns = text as NSString
        var out = [Int64]()
        for m in moneyRx.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let cur = m.range(at: 1).location != NSNotFound, dec = m.range(at: 3).location != NSNotFound
            if !cur && !dec { continue }
            let c = cents(ns.substring(with: m.range(at: 2)) + (dec ? ns.substring(with: m.range(at: 3)) : ""))
            if c > 0 { out.append(c) }
        }
        return out
    }

    // ------------------------------------------------------------------ points
    /// fractions kept (fourteen $1 bus fares add up like one $14 bill)
    static func points(_ c: Int64, _ cur: String, _ rate: Double) -> Double {
        if c <= 0 || rate <= 0 { return 0 }
        return floor(usd(c, cur) * rate * 1000 + 1e-6) / 1000
    }

    static func shared(_ pts: Double, _ k: Int) -> Double { pts <= 0 ? 0 : floor(pts * 1000 / Double(max(1, k))) / 1000 }

    static func pts(_ p: Double) -> String {
        if p == floor(p) { return String(Int64(p)) }
        var s = String(format: p < 10 ? "%.2f" : "%.1f", p)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    // ------------------------------------------------------------------ matching
    struct Note { let src: String; let at: Int64; let pkg: String; let title: String; let text: String; let key: String }

    static func match(_ notes: [Note], _ pkg: String, _ c: Int64, _ from: Int64, _ to: Int64, _ used: Set<String>) -> Note? {
        if pkg.isEmpty || c <= 0 { return nil }
        var best: Note?
        for n in notes where n.pkg == pkg && n.at >= from && n.at <= to && !used.contains(n.key) {
            if !amountsIn(n.title + "\n" + n.text).contains(c) { continue }
            if best == nil || n.at < best!.at { best = n }
        }
        return best
    }

    // ------------------------------------------------------------------ the signed files
    typealias Signer = (Data) -> (pub: Data, sig: Data)?

    static func build(_ cls: Int32, _ rows0: [[String]], signer: Signer, png: Data) -> Data? {
        guard let probe = signer(Data("probe".utf8)) else { return nil }
        var rows = rows0
        rows.append(["phone", "key", hex(probe.pub)])
        rows.append(["sig", "key_id", hex(Data(SHA256.hash(data: probe.pub)))])
        let body = trailerPrefix(cls, rows, rows.count + 1)
        guard let s = signer(message(cls, body)), s.pub == probe.pub else { return nil }
        var t = body
        putStr(&t, "sig"); putStr(&t, "value"); putStr(&t, hex(s.sig))
        var f = png
        f.append(t)
        let u = UInt64(t.count)
        for i in stride(from: 56, through: 0, by: -8) { f.append(UInt8((u >> UInt64(i)) & 255)) }
        return f
    }

    static func message(_ cls: Int32, _ body: Data) -> Data {
        var m = Data("ANA-PMSH1|\(cls)|".utf8)
        m.append(Data(SHA256.hash(data: body)))
        return m
    }

    static func trailerPrefix(_ cls: Int32, _ rows: [[String]], _ total: Int) -> Data {
        var t = Data(Array("PMSH".utf8))
        putInt(&t, 1); putInt(&t, 1); putInt(&t, cls); putInt(&t, 3)
        for c in ["section", "key", "value"] { putStr(&t, c) }
        putInt(&t, Int32(total))
        for r in rows { for v in r { putStr(&t, v) } }
        return t
    }

    private static func putInt(_ d: inout Data, _ v: Int32) {
        let u = UInt32(bitPattern: v)
        d.append(contentsOf: [UInt8(u >> 24 & 255), UInt8(u >> 16 & 255), UInt8(u >> 8 & 255), UInt8(u & 255)])
    }

    private static func putStr(_ d: inout Data, _ s: String) {
        let b = Data(s.utf8)
        putInt(&d, Int32(b.count))
        d.append(b)
    }

    struct Signed {
        var cls: Int32 = -1
        var kv = [String: String]()
        var keyId = "", why = ""
        var ok = false
        func get(_ k: String) -> String { kv[k] ?? "" }
    }

    struct Bad: Error { let why: String; init(_ w: String) { why = w } }

    static func read(_ f0: Data) -> Signed {
        var s = Signed()
        do {
            let f = [UInt8](f0)
            guard f.count >= 20 else { throw Bad("too small") }
            var tl: UInt64 = 0
            for i in 0..<8 { tl = (tl << 8) | UInt64(f[f.count - 8 + i]) }
            guard tl >= 12, tl <= UInt64(f.count - 8) else { throw Bad("no trailer") }
            let t = Array(f[(f.count - 8 - Int(tl))..<(f.count - 8)])
            guard t[0] == 0x50, t[1] == 0x4D, t[2] == 0x53, t[3] == 0x48 else { throw Bad("not a pngmesh") }
            var p = 4
            func u32() throws -> Int32 {
                guard p + 4 <= t.count else { throw Bad("short") }
                let v = UInt32(t[p]) << 24 | UInt32(t[p + 1]) << 16 | UInt32(t[p + 2]) << 8 | UInt32(t[p + 3])
                p += 4
                return Int32(bitPattern: v)
            }
            func rs() throws -> String {
                let n = Int(try u32())
                guard n >= 0, n <= 65536, p + n <= t.count, let v = String(bytes: t[p..<(p + n)], encoding: .utf8) else { throw Bad("bad string") }
                p += n
                return v
            }
            guard try u32() == 1, try u32() == 1 else { throw Bad("version") }
            s.cls = try u32()
            guard s.cls >= clsBill && s.cls <= clsChat else { throw Bad("not a bill file") }
            guard try u32() == 3, try rs() == "section", try rs() == "key", try rs() == "value" else { throw Bad("columns") }
            let nr = Int(try u32())
            guard nr >= 4, nr <= 1000 else { throw Bad("rows") }
            var rows = [[String]]()
            var last = 0
            for i in 0..<nr {
                if i == nr - 1 { last = p }
                rows.append([try rs(), try rs(), try rs()])
            }
            guard p == t.count else { throw Bad("extra bytes") }
            let kid = rows[nr - 2], sig = rows[nr - 1]
            guard kid[0] == "sig", kid[1] == "key_id", sig[0] == "sig", sig[1] == "value" else { throw Bad("sig rows") }
            guard kid[2].range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
                  sig[2].range(of: "^[0-9a-f]{128}$", options: .regularExpression) != nil else { throw Bad("sig hex") }
            let section = s.cls == clsBill ? "bill" : s.cls == clsHelp ? "help" : s.cls == clsThanks ? "thanks" : s.cls == clsSched ? "sched" : s.cls == clsPaid ? "paid" : s.cls == clsChat ? "chat" : "journey"
            for r in rows[0..<(nr - 2)] {
                guard r[0] == section || r[0] == "phone" else { throw Bad("section " + r[0]) }
                let k = r[0] + "|" + r[1]
                guard s.kv[k] == nil else { throw Bad("duplicate " + k) }
                s.kv[k] = r[2]
            }
            guard let raw = unhex(s.get("phone|key")), raw.count == 65, raw.first == 4 else { throw Bad("phone key") }
            guard hex(Data(SHA256.hash(data: raw))) == kid[2] else { throw Bad("key id doesn't match the key") }
            let body = Data(t[0..<last])
            guard let sg = unhex(sig[2]), verify(raw, message(s.cls, body), sg) else {
                throw Bad("signature doesn't match: changed or not signed by that phone")
            }
            s.keyId = kid[2]
            s.ok = true
        } catch let b as Bad {
            s.why = b.why
        } catch {
            s.why = "unreadable"
        }
        return s
    }

    /// raw P-256 key, low-S raw signature (high S is refused, as the Spec says)
    static func verify(_ raw: Data, _ msg: Data, _ sig: Data) -> Bool {
        guard sig.count == 64 else { return false }
        let n: [UInt8] = [0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
                          0xbc, 0xe6, 0xfa, 0xad, 0xa7, 0x17, 0x9e, 0x84, 0xf3, 0xb9, 0xca, 0xc2, 0xfc, 0x63, 0x25, 0x51]
        var half = [UInt8](repeating: 0, count: 32)
        var carry: UInt8 = 0
        for i in 0..<32 { half[i] = (n[i] >> 1) | carry; carry = (n[i] & 1) << 7 }
        let sp = Array(sig[32..<64])
        if !sp.lexicographicallyPrecedes(half) && sp != half { return false }
        guard let k = try? P256.Signing.PublicKey(x963Representation: raw),
              let es = try? P256.Signing.ECDSASignature(rawRepresentation: sig) else { return false }
        return k.isValidSignature(es, for: msg)
    }

    static func classOf(_ f0: Data) -> Int32 {
        let f = [UInt8](f0)
        guard f.count > 24 else { return -1 }
        var tl: UInt64 = 0
        for i in 0..<8 { tl = (tl << 8) | UInt64(f[f.count - 8 + i]) }
        guard tl >= 16, tl <= UInt64(f.count - 8) else { return -1 }
        let st = f.count - 8 - Int(tl)
        guard f[st] == 0x50, f[st + 1] == 0x4D else { return -1 }
        return Int32(bitPattern: UInt32(f[st + 12]) << 24 | UInt32(f[st + 13]) << 16 | UInt32(f[st + 14]) << 8 | UInt32(f[st + 15]))
    }

    static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    static func unhex(_ s: String) -> Data? {
        guard s.count % 2 == 0, s.range(of: "^[0-9a-fA-F]*$", options: .regularExpression) != nil else { return nil }
        var d = Data()
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            d.append(UInt8(s[i..<j], radix: 16) ?? 0)
            i = j
        }
        return d
    }

    static func newId() -> String {
        var b = [UInt8](repeating: 0, count: 6)
        for i in 0..<6 { b[i] = UInt8.random(in: 0...255) }
        return hex(Data(b))
    }
}
