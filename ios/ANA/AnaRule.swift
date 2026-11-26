import Foundation
import CryptoKit

/// ANA Rule v1 (spec/SPEC.md) on the iPhone: lessons, the root chain, keys and the 18 verdicts.
///
/// Written from the Spec, separately from the Python reference and the Java checker (spec/java/AnaRule.java), and
/// held to the same 47 test files: GitHub runs spec/vectors through this file on every build (ios/tests).
/// Foundation and CryptoKit only, so it also runs on a Mac for those tests. A verdict depends only on the file
/// bytes, the build and what this phone has already accepted: no clock, no network, no randomness.
final class AnaRule {
    static let classLesson = 30, classPermit = 31, classRevoke = 32
    static let hivesAll = ["watch", "efinote", "clipnote", "pacenote", "hivenote", "flex", "shell"]
    static let hivesLevel1 = ["watch", "shell"]

    let reader: Int
    let tier: String
    let hives: [String]
    var trusted: [String: Data] = [:]            // key id -> raw public key (65 bytes)
    var seq = 0
    var head = String(repeating: "0", count: 64)
    var chain: [Int: String] = [:]
    var revoked = Set<String>(), frozen = Set<String>()
    var lessonVer: [String: Int] = [:], lessonHash: [String: String] = [:]
    var last: Signed?                            // the file the last check accepted

    struct Signed {
        var cls = 0
        var kv: [(String, String)] = []          // "section|key", value, in file order (sig rows left out)
        var body = Data()
        var keyId = ""
        var sig = Data()
        func get(_ k: String) -> String? { kv.first { $0.0 == k }?.1 }
    }

    struct Bad: Error { let why: String }

    init(reader: Int, tier: String, hives: [String], trustedRawHex: [String]) {
        self.reader = reader
        self.tier = tier
        self.hives = hives
        for h in trustedRawHex {
            let raw = AnaRule.unhex(h)
            trusted[AnaRule.hex(Data(SHA256.hash(data: raw)))] = raw
        }
    }

    // ---------------------------------------------------------------- the container (Spec section 2)
    func parseSigned(_ f: Data) throws -> Signed {
        let b = [UInt8](f)
        if b.count < 20 { throw Bad(why: "too small") }
        var tl: UInt64 = 0
        for i in 0..<8 { tl = (tl << 8) | UInt64(b[b.count - 8 + i]) }
        if tl < 12 || tl > UInt64(b.count - 8) { throw Bad(why: "no trailer") }
        let start = b.count - 8 - Int(tl)
        let t = Array(b[start..<(b.count - 8)])
        if t[0] != 0x50 || t[1] != 0x4D || t[2] != 0x53 || t[3] != 0x48 { throw Bad(why: "magic") }
        var p = 4
        func u32() throws -> Int {
            if p + 4 > t.count { throw Bad(why: "short") }
            let v = (Int(t[p]) << 24) | (Int(t[p + 1]) << 16) | (Int(t[p + 2]) << 8) | Int(t[p + 3])
            p += 4
            return v
        }
        func str() throws -> String {
            let n = try u32()
            if n > 16_777_216 || p + n > t.count { throw Bad(why: "bad string") }
            guard let s = String(bytes: t[p..<(p + n)], encoding: .utf8) else { throw Bad(why: "bad utf-8") }
            p += n
            return s
        }
        if try u32() != 1 || u32() != 1 { throw Bad(why: "version or parts") }
        var s = Signed()
        s.cls = try u32()
        if try u32() != 3 || str() != "section" || str() != "key" || str() != "value" { throw Bad(why: "columns") }
        let nr = try u32()
        if nr < 3 || nr > 100_000 { throw Bad(why: "rows") }
        var rows: [[String]] = []
        var lastAt = 0
        for i in 0..<nr {
            if i == nr - 1 { lastAt = p }
            rows.append([try str(), try str(), try str()])
        }
        if p != t.count { throw Bad(why: "extra bytes") }
        let kid = rows[nr - 2], sg = rows[nr - 1]
        if kid[0] != "sig" || kid[1] != "key_id" || sg[0] != "sig" || sg[1] != "value" { throw Bad(why: "sig rows") }
        if !AnaRule.full("[0-9a-f]{64}", kid[2]) || !AnaRule.full("[0-9a-f]{128}", sg[2]) { throw Bad(why: "sig hex") }
        let ok = ["lesson", "coin", "address", "reader", "server", "param", "test", "feature", "permit", "chain", "revoke"]
        var seen = Set<String>()
        for i in 0..<(nr - 2) {
            if !ok.contains(rows[i][0]) { throw Bad(why: "section " + rows[i][0]) }
            let k = rows[i][0] + "|" + rows[i][1]
            if seen.contains(k) { throw Bad(why: "duplicate row " + k) }
            seen.insert(k)
            s.kv.append((k, rows[i][2]))
        }
        s.body = Data(t[0..<lastAt])
        s.keyId = kid[2]
        s.sig = AnaRule.unhex(sg[2])
        return s
    }

    // ---------------------------------------------------------------- signatures (Spec sections 1 and 4)
    static let halfN: [UInt8] = AnaRule.halve([0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
                                               0xbc, 0xe6, 0xfa, 0xad, 0xa7, 0x17, 0x9e, 0x84, 0xf3, 0xb9, 0xca, 0xc2, 0xfc, 0x63, 0x25, 0x51])

    static func halve(_ n: [UInt8]) -> [UInt8] {
        var h = [UInt8](repeating: 0, count: 32)
        var carry: UInt8 = 0
        for i in 0..<32 { h[i] = (n[i] >> 1) | carry; carry = (n[i] & 1) << 7 }
        return h
    }

    func message(_ cls: Int, _ body: Data) -> Data {
        var m = Data("ANA-PMSH1|\(cls)|".utf8)
        m.append(Data(SHA256.hash(data: body)))
        return m
    }

    func highS(_ sig: Data) -> Bool {
        let s = [UInt8](sig[sig.startIndex.advanced(by: 32)..<sig.endIndex])
        return s.lexicographicallyPrecedes(AnaRule.halfN) == false && s != AnaRule.halfN
    }

    func verify(_ raw: Data?, _ msg: Data, _ sig: Data) -> Bool {
        guard let raw = raw, raw.count == 65, raw.first == 4, sig.count == 64, !highS(sig),
              let pk = try? P256.Signing.PublicKey(x963Representation: raw),
              let s = try? P256.Signing.ECDSASignature(rawRepresentation: sig) else { return false }
        return pk.isValidSignature(s, for: msg)
    }

    // ---------------------------------------------------------------- the check (Spec section 8)
    func check(_ f: Data, _ sidecar: Data?) -> (String, String) {
        last = nil
        let want = sidecar.flatMap { AnaRule.sidecarHash($0) }
        if want == nil || want != AnaRule.hex(Data(SHA256.hash(data: f))) { return ("BAD_SIDECAR", "") }
        let s: Signed
        do { s = try parseSigned(f) } catch let b as Bad { return ("BAD_FORMAT", b.why) } catch { return ("BAD_FORMAT", "") }
        if s.cls != AnaRule.classLesson && s.cls != AnaRule.classPermit && s.cls != AnaRule.classRevoke { return ("BAD_FORMAT", "class") }
        if highS(s.sig) { return ("HIGH_S", "") }
        let msg = message(s.cls, s.body)
        let bh = AnaRule.hex(Data(SHA256.hash(data: s.body)))

        if s.cls != AnaRule.classLesson {
            guard let raw = trusted[s.keyId] else { return ("UNKNOWN_KEY", "") }
            if frozen.contains(s.keyId) { return ("FROZEN", "") }
            if revoked.contains(s.keyId) { return ("REVOKED", "") }
            if !verify(raw, msg, s.sig) { return ("BAD_SIGNATURE", "") }
            return chainStep(s, bh)
        }

        var raw = trusted[s.keyId]
        var permit: Signed? = nil
        if raw == nil {
            guard let pf = s.get("permit|file") else { return ("UNKNOWN_KEY", "") }
            guard let pd = Data(base64Encoded: pf, options: .ignoreUnknownCharacters), let pm = try? parseSigned(pd) else { return ("BAD_FORMAT", "permit") }
            if pm.cls != AnaRule.classPermit || highS(pm.sig) { return ("BAD_FORMAT", "permit") }
            guard let proot = trusted[pm.keyId], verify(proot, message(AnaRule.classPermit, pm.body), pm.sig) else { return ("UNKNOWN_KEY", "permit") }
            guard let pk = pm.get("permit|key"), AnaRule.full("[0-9a-f]{130}", pk) else { return ("BAD_FORMAT", "permit key") }
            raw = AnaRule.unhex(pk)
            if AnaRule.hex(Data(SHA256.hash(data: raw!))) != s.keyId { return ("UNKNOWN_KEY", "permit is for another key") }
            permit = pm
        }
        if revoked.contains(s.keyId) || (permit != nil && revoked.contains(permit!.keyId)) { return ("REVOKED", "") }
        if !verify(raw, msg, s.sig) { return ("BAD_SIGNATURE", "") }

        let need = AnaRule.intOr(s.get("lesson|needs_reader"), -1)
        if need < 1 { return ("BAD_RULES", "lesson|needs_reader") }
        let hive = s.get("lesson|hive") ?? ""
        if need > reader { return ("UPDATE_FIRST", "needs reader \(need)") }
        if !AnaRule.hivesLevel1.contains(hive) { return AnaRule.hivesAll.contains(hive) ? ("UPDATE_FIRST", "hive " + hive) : ("BAD_RULES", "lesson|hive") }
        let lt = s.get("lesson|tier") ?? ""
        if let pm = permit {
            if seq >= AnaRule.intOr(pm.get("permit|until_seq"), 0) { return ("EXPIRED", "") }
            let tk = s.get("coin|ticker") ?? ""
            let tickers = AnaRule.list(pm.get("permit|tickers"))
            if !AnaRule.list(pm.get("permit|tiers")).contains(lt) || !AnaRule.list(pm.get("permit|hives")).contains(hive)
                || !(tickers.contains("*") || tickers.contains(tk)) { return ("NOT_PERMITTED", "") }
        }
        if !hives.contains(hive) { return ("WRONG_HIVE", "") }
        if lt == "statia" && tier != "statia" { return ("WRONG_TIER", "") }
        let id = s.get("lesson|id") ?? ""
        let ver = AnaRule.intOr(s.get("lesson|version"), -1)
        if ver < 1 { return ("BAD_RULES", "lesson|version") }
        if let iv = lessonVer[id] {
            if ver < iv { return ("OLDER", "") }
            if ver == iv { return lessonHash[id] == bh ? ("DUPLICATE", "") : ("FORK", "") }
        }
        let errs = (hive == "shell") ? AnaRule.lintShell(s.kv) : lintLesson(s.kv)
        if !errs.isEmpty { return ("BAD_RULES", errs.joined(separator: "; ")) }
        lessonVer[id] = ver
        lessonHash[id] = bh
        last = s
        return ("ACCEPT", "")
    }

    func chainStep(_ s: Signed, _ bh: String) -> (String, String) {
        let n = AnaRule.intOr(s.get("chain|seq"), -1)
        guard n >= 1, let prev = s.get("chain|prev"), AnaRule.full("[0-9a-f]{64}", prev) else { return ("BAD_FORMAT", "chain rows") }
        if let have = chain[n] {
            if have == bh { return ("DUPLICATE", "") }
            frozen.formUnion(trusted.keys)
            return ("FORK", "")
        }
        if n > seq + 1 { return ("HOLE", "have \(seq)") }
        if prev != head { frozen.formUnion(trusted.keys); return ("FORK", "prev") }
        if s.cls == AnaRule.classPermit {
            guard let pk = s.get("permit|key"), AnaRule.full("04[0-9a-f]{128}", pk), AnaRule.intOr(s.get("permit|until_seq"), -1) >= 0 else { return ("BAD_FORMAT", "permit rows") }
        } else {
            let ks = AnaRule.list(s.get("revoke|keys"))
            if ks.isEmpty { return ("BAD_FORMAT", "revoke rows") }
            for k in ks where !AnaRule.full("[0-9a-f]{64}", k) { return ("BAD_FORMAT", "revoke rows") }
            revoked.formUnion(ks)
        }
        chain[n] = bh
        seq = n
        head = bh
        last = s
        return ("ACCEPT", "")
    }

    // ---------------------------------------------------------------- lint (the Lesson Maker's rules, Spec section 6)
    static let sections = ["lesson", "coin", "address", "reader", "server", "param", "test"]

    /// The Lesson Maker's lint, on the lesson's rows without permit, hive and tier, plus the tier rule.
    func lintLesson(_ all: [(String, String)]) -> [String] {
        let kv = all.filter { !$0.0.hasPrefix("permit|") && $0.0 != "lesson|hive" && $0.0 != "lesson|tier" }
        var errs = AnaRule.lint(kv)
        let t = all.first { $0.0 == "lesson|tier" }?.1 ?? ""
        if t != "ana" && t != "statia" { errs.append("lesson|tier: ana or statia") }
        return errs
    }

    /// Visibility config (hive=shell): feature|<key> = seen|unseen. Nothing coin-related.
    static func lintShell(_ all: [(String, String)]) -> [String] {
        var e: [String] = []
        if !full("[a-z0-9][a-z0-9_-]{1,31}", all.first { $0.0 == "lesson|id" }?.1 ?? "") { e.append("lesson|id") }
        let feats = all.filter { $0.0.hasPrefix("feature|") }
        if feats.isEmpty { e.append("feature|*: none") }
        for (k, v) in feats {
            if !full("feature\\|[a-z0-9][a-z0-9_-]{1,31}", k) { e.append(k + ": name") }
            if v != "seen" && v != "unseen" { e.append(k + ": seen or unseen") }
        }
        let t = all.first { $0.0 == "lesson|tier" }?.1 ?? ""
        if t != "ana" && t != "statia" { e.append("lesson|tier") }
        return e
    }

    static func lint(_ kv: [(String, String)]) -> [String] {
        func get(_ k: String) -> String? { kv.first { $0.0 == k }?.1 }
        var e: [String] = []
        var flagged: [String] = []
        var structural = false
        for (k, v) in kv {
            let sec = String(k.prefix { $0 != "|" })
            if !sections.contains(sec) { e.append(k + ": unknown section"); structural = true }
            if v == "?" { e.append(k + ": still says ?"); flagged.append(k) }
        }
        if structural { return e }
        let formsIncomplete = flagged.contains { $0.hasPrefix("address|") }
        if !full("[a-z0-9][a-z0-9_-]{1,31}", get("lesson|id") ?? "") { e.append("lesson|id") }
        if !isInt(get("lesson|version"), 1, 1_000_000) { e.append("lesson|version") }
        if !isInt(get("lesson|needs_reader"), 1, 1000) { e.append("lesson|needs_reader") }
        if (get("coin|name") ?? "").trimmingCharacters(in: .whitespaces).isEmpty { e.append("coin|name") }
        if !full("[A-Z0-9]{1,10}", get("coin|ticker") ?? "") { e.append("coin|ticker") }
        if !isInt(get("coin|decimals"), 0, 30) { e.append("coin|decimals") }
        if !isInt(get("coin|display_decimals"), 0, 18) { e.append("coin|display_decimals") }
        if !full("[a-z0-9-]{1,60}", get("coin|price_id") ?? "") { e.append("coin|price_id") }

        let forms = formsOf(kv)
        if forms.isEmpty { e.append("address: need at least one form") }
        for f in forms {
            let nm = "address|" + f[0]
            if !["base58check", "bech32", "hex_evm", "base58"].contains(f[1]) { e.append(nm + ".kind") }
            if f[2].isEmpty || (try? NSRegularExpression(pattern: f[2])) == nil { e.append(nm + ".pattern") }
            if f[1] == "bech32" && !full("[a-z0-9]{1,20}", f[3]) { e.append(nm + ".hrp") }
            if f[1] == "base58check" && !full("[0-9]{1,3}(,[0-9]{1,3})*", f[4]) { e.append(nm + ".versions") }
        }
        let rd = get("reader|name") ?? ""
        if !["esplora", "evm", "json"].contains(rd) { e.append("reader|name") }

        var servers = 0
        for (k, u) in kv where k.hasPrefix("server|") {
            servers += 1
            if !full("[0-9]{1,2}", String(k.dropFirst(7))) { e.append(k + ": numbers") }
            if !full("https://[^/\\s@?#]+(/\\S*)?", u) { e.append(k + ": https only") }
            if full(".*[?&](api_?key|key|token|secret|project_id|auth|access_token)=.*", u.lowercased()) { e.append(k + ": carries a key") }
        }
        if servers < 1 { e.append("server|1") }
        for (k, v) in kv where !k.hasPrefix("test|") {
            if full(".*(apikey|api_key|api-key|x-api|authorization|bearer |project_id|secret).*", v.lowercased()) { e.append(k + ": looks like a secret") }
        }
        if rd == "json" {
            let m = get("param|method")
            if m != "GET" && m != "POST" { e.append("param|method") }
            if (get("param|balance_path") ?? "").trimmingCharacters(in: .whitespaces).isEmpty { e.append("param|balance_path") }
            let bt = get("param|balance_type")
            if bt != "number" && bt != "text_integer" { e.append("param|balance_type") }
            if m == "POST" && !(get("param|body") ?? "").contains("{address}") { e.append("param|body") }
            if m == "GET" { for (k, u) in kv where k.hasPrefix("server|") && !u.contains("{address}") { e.append(k + ": {address}") } }
        }
        if rd == "evm" && !isInt(get("param|chain_id"), 1, Int(Int32.max)) { e.append("param|chain_id") }

        var good = 0, bad = 0
        for (k, v) in kv {
            if k.hasPrefix("test|good.") { good += 1; if !formsIncomplete && !anyFormOk(forms, v) { e.append(k + ": should pass") } }
            if k.hasPrefix("test|bad.") { bad += 1; if !formsIncomplete && anyFormOk(forms, v) { e.append(k + ": should fail") } }
        }
        if !formsIncomplete, let pa = get("test|probe_address"), !anyFormOk(forms, pa) { e.append("test|probe_address") }
        if good < 1 { e.append("test|good.1") }
        if bad < 1 { e.append("test|bad.1") }
        // a value still saying ? is reported once; drop follow-on complaints about that key
        return e.filter { m in m.contains("still says ?") || !flagged.contains { m.hasPrefix($0 + ":") || m.hasPrefix($0 + ".") || m == $0 } }
    }

    /// [name, kind, pattern, hrp, versions] for each address|formN.kind
    static func formsOf(_ kv: [(String, String)]) -> [[String]] {
        var out: [[String]] = []
        for (k, v) in kv {
            guard k.hasPrefix("address|form"), k.hasSuffix(".kind") else { continue }
            let n = String(k.dropFirst(8).dropLast(5))
            guard full("form[0-9]+", n) else { continue }
            func g(_ x: String) -> String { kv.first { $0.0 == "address|" + n + "." + x }?.1 ?? "" }
            out.append([n, v, g("pattern"), g("hrp"), g("versions")])
        }
        return out
    }

    static func anyFormOk(_ forms: [[String]], _ a: String) -> Bool {
        forms.contains { addrOk($0[1], $0[2], $0[3], $0[4], a) }
    }

    // ---------------------------------------------------------------- address checks (the same as the Lesson Maker)
    static let b58 = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    static let b32 = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")

    static func addrOk(_ kind: String, _ pattern: String, _ hrp: String, _ versions: String, _ a: String) -> Bool {
        if !pattern.isEmpty && !full(pattern, a) { return false }
        switch kind {
        case "hex_evm": return full("0x[0-9a-fA-F]{40}", a)
        case "base58check": return b58checkOk(a, versions)
        case "bech32": return bech32Variant(a, hrp) != 0
        case "base58": if let d = b58dec(a) { return d.count == 32 } else { return false }   // plain base58, 32-byte key (Solana, no checksum)
        default: return false
        }
    }

    static func b58dec(_ s: String) -> [UInt8]? {
        var num: [UInt8] = []                     // big-endian base-256
        for c in s {
            guard let ix = b58.firstIndex(of: c) else { return nil }
            var carry = ix
            for i in stride(from: num.count - 1, through: 0, by: -1) {
                carry += Int(num[i]) * 58
                num[i] = UInt8(carry & 255)
                carry >>= 8
            }
            while carry > 0 { num.insert(UInt8(carry & 255), at: 0); carry >>= 8 }
        }
        while num.first == 0 { num.removeFirst() }
        let zeros = s.prefix { $0 == "1" }.count
        return [UInt8](repeating: 0, count: zeros) + num
    }

    static func b58checkOk(_ a: String, _ versions: String) -> Bool {
        guard let d = b58dec(a), d.count == 25 else { return false }
        let h = [UInt8](SHA256.hash(data: Data(SHA256.hash(data: Data(d[0..<21])))))
        if Array(h[0..<4]) != Array(d[21..<25]) { return false }
        return versions.split(separator: ",").contains { Int($0.trimmingCharacters(in: .whitespaces)) == Int(d[0]) }
    }

    static func bech32Variant(_ a: String, _ hrp: String) -> Int {
        if a.count < 8 { return 0 }
        let low = a.lowercased()
        if a != low && a != a.uppercased() { return 0 }
        guard let posIdx = low.lastIndex(of: "1") else { return 0 }
        let pos = low.distance(from: low.startIndex, to: posIdx)
        if pos < 1 || pos + 7 > low.count { return 0 }
        let h = String(low.prefix(pos))
        if !hrp.isEmpty && h != hrp.lowercased() { return 0 }
        var v: [UInt32] = []
        for c in h.unicodeScalars { if c.value < 33 || c.value > 126 { return 0 }; v.append(c.value >> 5) }
        v.append(0)
        for c in h.unicodeScalars { v.append(c.value & 31) }
        for c in low.suffix(low.count - pos - 1) { guard let ix = b32.firstIndex(of: c) else { return 0 }; v.append(UInt32(ix)) }
        let gen: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var chk: UInt32 = 1
        for x in v {
            let top = chk >> 25
            chk = ((chk & 0x1ffffff) << 5) ^ x
            for j in 0..<5 where (top >> UInt32(j)) & 1 != 0 { chk ^= gen[j] }
        }
        if chk == 1 { return 1 }
        if chk == 0x2bc830a3 { return 2 }
        return 0
    }

    // ---------------------------------------------------------------- small helpers
    static func full(_ pattern: String, _ s: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: "^(?:" + pattern + ")$") else { return false }
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    static func intOr(_ s: String?, _ d: Int) -> Int {
        guard let s = s, let v = Int32(s.trimmingCharacters(in: .whitespaces)) else { return d }
        return Int(v)
    }

    static func isInt(_ s: String?, _ lo: Int, _ hi: Int) -> Bool {
        guard let s = s, let v = Int32(s.trimmingCharacters(in: .whitespaces)) else { return false }
        return Int(v) >= lo && Int(v) <= hi
    }

    static func list(_ s: String?) -> [String] {
        (s ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func sidecarHash(_ sc: Data) -> String? {
        if sc.count > 4096 { return nil }
        let s = String(decoding: sc, as: UTF8.self)
        let first = (s.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return full("[0-9a-f]{64}", first) ? first : nil
    }

    static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    static func unhex(_ s: String) -> Data {
        var d = Data()
        var it = s.makeIterator()
        while let a = it.next(), let b = it.next() {
            guard let v = UInt8(String([a, b]), radix: 16) else { break }
            d.append(v)
        }
        return d
    }
}
