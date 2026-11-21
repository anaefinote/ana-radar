import Foundation
import CryptoKit

/// LESSONS: teach ANA a new coin with a signed lesson file instead of a new app release (spec/SPEC.md).
///
/// Every file is checked by AnaRule.swift, held to the Spec's 47 test files on every build. Accepted files are
/// kept in Documents/lessons with an order list; the rule's state is rebuilt from them on start (root-chain files
/// first, then lessons), so a revoke switches off what it covers. A watch-hive lesson teaches WATCH a coin: its
/// address shapes, the server that reads balances (esplora, evm or json), its decimals and its CoinGecko price id.
/// In ANA ORBIT, lessons sit under Experimental; in ANA : STATIA they are a regular part of WATCH.
///
/// TEST KEYS: until the Key Ceremony's public keys arrive, this build trusts only the Spec's TEST root and spare,
/// whose private halves are public. A test build, never for sharing.
final class Lessons {
    static let shared = Lessons()

    static let testKeys = true
    static let trusted = [      // Spec test vectors: TEST ROOT and TEST SPARE (never the real ones)
        "046ccf9b361b03195370d4ea27b07291b45923a37062a410e55295673ca2297b5a23099f458ca11e4129635df235f660db6bfb06199a83380c59885d75c9dbc3f5",
        "04975cef9f466270d282fbcb5b649e07370f08d195cf23eefa1cc51bc185d349e434d34e45ac32766ae865a229fd3b6c6920bdd0f9dc10a4d6e907e2cb92165825"]
    static let readerLevel = 1
    static let experimental = !Wallets.statia      // ANA ORBIT: lessons are experimental

    struct Lesson {
        var id: String
        var version: Int
        var file: String
        var keyId: String
        var kv: [(String, String)]
        func value(_ k: String) -> String { kv.first { $0.0 == k }?.1 ?? "" }
        var name: String { value("coin|name") }
        var ticker: String { value("coin|ticker") }
        var decimals: Int { AnaRule.intOr(value("coin|decimals"), 0) }
        var shown: Int { AnaRule.intOr(value("coin|display_decimals"), 4) }
        var forms: [[String]] { AnaRule.formsOf(kv) }
    }

    private(set) var list: [Lesson] = []
    private(set) var problems = ""
    private var rule: AnaRule!

    var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("lessons")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private init() { load() }

    private func fresh() -> AnaRule {
        AnaRule(reader: Lessons.readerLevel, tier: Wallets.statia ? "statia" : "ana", hives: ["watch"], trustedRawHex: Lessons.trusted)
    }

    // ---------------------------------------------------------------- state: rebuilt from the kept files
    func load() {
        let r = fresh()
        var l: [Lesson] = []
        var bad = ""
        let order = readOrder()
        for pass in 0..<2 {                              // root-chain files first, then lessons
            for name in order {
                guard let f = try? Data(contentsOf: dir.appendingPathComponent(name)) else { continue }
                let sc = try? Data(contentsOf: dir.appendingPathComponent(name + ".sha256"))
                let cls = Lessons.classOf(f)
                if (pass == 0) != (cls == AnaRule.classPermit || cls == AnaRule.classRevoke) { continue }
                let v = r.check(f, sc)
                if v.0 == "ACCEPT", cls == AnaRule.classLesson, let s = r.last {
                    let id = s.get("lesson|id") ?? ""
                    l.removeAll { $0.id == id }
                    l.append(Lesson(id: id, version: AnaRule.intOr(s.get("lesson|version"), 0), file: name, keyId: s.keyId, kv: s.kv))
                } else if v.0 != "ACCEPT" {
                    bad += name + ": " + Lessons.say(v.0) + "\n"
                }
            }
        }
        rule = r
        list = l
        problems = bad
    }

    /// What would happen if this file were added (nothing changes): (verdict, plain words, confirm text or "")
    func preview(_ f: Data, _ sidecar: Data?) -> (String, String, String) {
        let savedRule = rule, savedList = list, savedProblems = problems
        load()
        let v = rule.check(f, sidecar)
        var confirm = ""
        if v.0 == "ACCEPT", Lessons.classOf(f) == AnaRule.classLesson, let s = rule.last { confirm = Lessons.confirmText(s.kv) }
        rule = savedRule; list = savedList; problems = savedProblems
        return (v.0, Lessons.say(v.0) + (v.1.isEmpty || v.0 == "ACCEPT" ? "" : " (" + v.1 + ")"), confirm)
    }

    /// Keeps the file (after the person said Add) and rebuilds the state
    @discardableResult
    func add(_ f: Data, _ sidecar: Data?) -> String {
        let v = preview(f, sidecar)
        if v.0 != "ACCEPT" { return v.1 }
        let h = AnaRule.hex(Data(SHA256.hash(data: f)))
        let name = "f_" + String(h.prefix(16)) + ".pngmesh"
        try? f.write(to: dir.appendingPathComponent(name))
        try? Data((h + "\n" + name + "\n\(f.count)\n").utf8).write(to: dir.appendingPathComponent(name + ".sha256"))
        var order = readOrder()
        if !order.contains(name) { order.append(name) }
        writeOrder(order)
        load()
        return "Added"
    }

    func remove(_ id: String) {
        var order = readOrder()
        for l in list where l.id == id {
            order.removeAll { $0 == l.file }
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(l.file))
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(l.file + ".sha256"))
        }
        writeOrder(order)
        load()
    }

    func find(_ id: String) -> Lesson? { list.first { $0.id == id } }

    /// the lesson whose address rules this address fits
    func forAddress(_ a: String) -> Lesson? { list.first { AnaRule.anyFormOk($0.forms, a) } }

    // ---------------------------------------------------------------- reading a lesson coin's balance
    /// (raw balance in the coin's smallest unit as a decimal string, the server that answered)
    func balance(_ l: Lesson, _ addr: String) async throws -> (String, String) {
        let reader = l.value("reader|name")
        var lastErr = "no server"
        for i in 1..<100 {
            let u = l.value("server|\(i)")
            if u.isEmpty { break }
            do { return (try await probe(reader, u, l, addr), u) } catch { lastErr = (error as NSError).localizedDescription }
        }
        throw NSError(domain: "Lesson", code: 1, userInfo: [NSLocalizedDescriptionKey: lastErr])
    }

    private func probe(_ reader: String, _ url: String, _ l: Lesson, _ addr: String) async throws -> String {
        func fail(_ m: String) -> NSError { NSError(domain: "Lesson", code: 2, userInfo: [NSLocalizedDescriptionKey: m]) }
        func ask(_ method: String, _ u: String, _ body: String?) async throws -> Any {
            guard let url = URL(string: u) else { throw fail("bad server address") }
            var r = URLRequest(url: url)
            r.httpMethod = method
            r.timeoutInterval = 20
            r.setValue("application/json", forHTTPHeaderField: "Accept")
            if let b = body { r.httpBody = Data(b.utf8); r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            let (d, resp) = try await URLSession.shared.data(for: r)
            if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw fail("server said \(h.statusCode)") }
            return try JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed])
        }
        switch reader {
        case "esplora":
            let base = url.hasSuffix("/") ? url : url + "/"
            let j = try await ask("GET", base + "address/" + addr, nil)
            guard let f = Lessons.big(Lessons.path(j, "chain_stats.funded_txo_sum")), let s = Lessons.big(Lessons.path(j, "chain_stats.spent_txo_sum")) else { throw fail("reply has no chain_stats") }
            var bal = f - s
            if let mf = Lessons.big(Lessons.path(j, "mempool_stats.funded_txo_sum")), let ms = Lessons.big(Lessons.path(j, "mempool_stats.spent_txo_sum")) { bal += mf - ms }
            return Lessons.dec(bal)
        case "evm":
            let body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getBalance\",\"params\":[\"\(addr)\",\"latest\"]}"
            let j = try await ask("POST", url, body)
            guard let res = Lessons.path(j, "result") as? String, res.hasPrefix("0x") else { throw fail("reply has no result") }
            return Lessons.hexToDec(String(res.dropFirst(2)))
        case "json":
            let m = l.value("param|method").isEmpty ? "GET" : l.value("param|method")
            let body = l.value("param|body").isEmpty ? nil : l.value("param|body").replacingOccurrences(of: "{address}", with: addr)
            let j = try await ask(m, url.replacingOccurrences(of: "{address}", with: addr), body)
            let v = Lessons.path(j, l.value("param|balance_path"))
            if let s = v as? String, AnaRule.full("[0-9]+", s.trimmingCharacters(in: .whitespaces)) { return s.trimmingCharacters(in: .whitespaces) }
            if let n = v as? NSNumber { return n.stringValue.components(separatedBy: ".")[0] }
            throw fail("the balance was not where balance_path says")
        default:
            throw fail("unknown reader " + reader)
        }
    }

    /// "123456789" with 8 decimals -> 1.23456789
    static func toCoin(_ raw: String, _ decimals: Int) -> Double {
        (Decimal(string: raw) ?? 0).doubleValue(shiftingLeft: decimals)
    }

    // ---------------------------------------------------------------- words for people
    static func confirmText(_ kv: [(String, String)]) -> String {
        var hosts: [String] = []
        for (k, v) in kv where k.hasPrefix("server|") {
            let h = host(v)
            if !hosts.contains(h) { hosts.append(h) }
        }
        let g = { (k: String) in kv.first { $0.0 == k }?.1 ?? "" }
        return "Add \(g("coin|name")) (\(g("coin|ticker")))?  ANA will send the addresses you watch to: " + hosts.joined(separator: ", ")
    }

    static func host(_ u: String) -> String {
        var s = u
        if s.hasPrefix("https://") { s = String(s.dropFirst(8)) } else if s.hasPrefix("http://") { s = String(s.dropFirst(7)) }
        return String(s.prefix { $0 != "/" && $0 != ":" && $0 != "?" && $0 != "#" })
    }

    static func say(_ v: String) -> String {
        switch v {
        case "ACCEPT": return "Added"
        case "DUPLICATE": return "You already have this"
        case "HOLE": return "Something earlier is missing; waiting for it"
        case "UPDATE_FIRST": return "Update ANA to read this"
        case "BAD_SIDECAR": return "This file is damaged (it doesn't match its .sha256)"
        case "BAD_FORMAT": return "This file is damaged"
        case "HIGH_S", "BAD_SIGNATURE": return "This file was changed after signing"
        case "UNKNOWN_KEY": return "Signed by someone ANA doesn't trust"
        case "REVOKED": return "This signer was switched off"
        case "EXPIRED": return "This signer's licence has ended"
        case "NOT_PERMITTED": return "This signer isn't licensed for this"
        case "WRONG_TIER": return "Part of ANA : STATIA, ANA's big sister"
        case "WRONG_HIVE": return "This lesson is for a hive this app doesn't have"
        case "OLDER": return "You have a newer version"
        case "BAD_RULES": return "This lesson breaks a safety rule"
        case "FORK": return "Two different files claim the same place"
        case "FROZEN": return "This signer is frozen after a fork"
        default: return v
        }
    }

    /// one line per lesson for the sketch: id TAB name TAB ticker TAB version TAB servers
    func text() -> String {
        list.map { l in
            [l.id, l.name, l.ticker, String(l.version), l.kv.filter { $0.0.hasPrefix("server|") }.map { Lessons.host($0.1) }.joined(separator: ", ")]
                .map(AnaLog.clean).joined(separator: "\t")
        }.joined(separator: "\n")
    }

    // ---------------------------------------------------------------- small helpers
    static func classOf(_ f: Data) -> Int {
        let b = [UInt8](f)
        guard b.count > 24 else { return -1 }
        var tl: UInt64 = 0
        for i in 0..<8 { tl = (tl << 8) | UInt64(b[b.count - 8 + i]) }
        guard tl >= 16, tl <= UInt64(b.count - 8) else { return -1 }
        let st = b.count - 8 - Int(tl)
        return (Int(b[st + 12]) << 24) | (Int(b[st + 13]) << 16) | (Int(b[st + 14]) << 8) | Int(b[st + 15])
    }

    static func path(_ o: Any?, _ p: String) -> Any? {
        var o = o
        if p.isEmpty { return o }
        for part in p.split(separator: ".") {
            if let d = o as? [String: Any] { o = d[String(part)] }
            else if let a = o as? [Any], let i = Int(part) { o = (i >= 0 && i < a.count) ? a[i] : nil }
            else { return nil }
            if o == nil { return nil }
        }
        return o
    }

    // whole numbers as Decimal (balances can pass Int64 in wei)
    static func big(_ v: Any?) -> Decimal? {
        if let n = v as? NSNumber { return n.decimalValue }
        if let s = v as? String { return Decimal(string: s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func dec(_ d: Decimal) -> String { NSDecimalNumber(decimal: d).stringValue }

    static func hexToDec(_ h: String) -> String {
        var digits: [Int] = [0]                    // little-endian base-10
        for c in h {
            guard let v = c.hexDigitValue else { break }
            var carry = v
            for i in 0..<digits.count { let x = digits[i] * 16 + carry; digits[i] = x % 10; carry = x / 10 }
            while carry > 0 { digits.append(carry % 10); carry /= 10 }
        }
        while digits.count > 1 && digits.last == 0 { digits.removeLast() }
        return digits.reversed().map(String.init).joined()
    }

    private func readOrder() -> [String] {
        guard let s = try? String(contentsOf: dir.appendingPathComponent("order.txt"), encoding: .utf8) else { return [] }
        return s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func writeOrder(_ o: [String]) {
        try? Data((o.joined(separator: "\n") + "\n").utf8).write(to: dir.appendingPathComponent("order.txt"))
    }
}

extension Decimal {
    /// this value divided by 10^n, as a Double
    func doubleValue(shiftingLeft n: Int) -> Double {
        var v = self
        var r = Decimal()
        NSDecimalMultiplyByPowerOf10(&r, &v, Int16(-n), .plain)
        return NSDecimalNumber(decimal: r).doubleValue
    }
}
