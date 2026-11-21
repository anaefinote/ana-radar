import Foundation

/// OWNERSHIP PROOF (step 2): a wallet app's own notification, matched to exactly one transaction on the chain.
///
/// Anyone can send coins to any address, but only the app holding the address is told about it. So when a
/// wallet app's "Received" (or "Sent") notification reaches ANA and the chain shows the same transaction,
/// ANA has seen the owner's side of it:
///
///   - the amount, exact to the satoshi / litoshi (kept as a whole number, never a decimal)
///   - the "From" / "To" fingerprint (first and last characters of the other address) fits the transaction
///   - the transaction's block time is near the notification (wallets push after the block)
///   - it is confirmed, and it is the ONLY transaction that fits (two or more: not proven)
///   - the notification came from a known wallet app (its app id, as the relay reports it)
///
/// States, shown on the wallet's card as Ownership:
///   Watching  nothing matched yet (or the address was emptied since the last proof: proof lasts until emptied)
///   Proving   a wallet notification arrived in the last hour and ANA is waiting for the chain to agree
///   Proven    a notification and a transaction matched, and the address hasn't been emptied since
///
/// The rules are the same as spec/py/proof_parse.py and proof_match.py, which pass on the real
/// Trust Wallet notification of Nov 17 2026 (0.00008683 BTC, tx 8122dd2c...cd645).
enum Proof {
    /// wallet apps whose notifications can prove ownership (iPhone bundle id, Android package)
    static let walletApps: Set<String> = ["com.sixdays.trust", "com.wallet.crypto.trustapp"]
    static var decimals: [String: Int] = ["BTC": 8, "LTC": 8]   // lesson coins add theirs (Wallets.checkLesson)
    static let windowBefore: Double = 3600     // the block may be up to an hour before the push
    static let windowAfter: Double = 3600      // wallets that push on broadcast: the block comes after
    static let lookBackDays: Double = 30

    struct Cand {
        let incoming: Bool
        let ticker: String
        let units: Int64
        let amount: String
        let prefix: String?, suffix: String?
        let at: Double                         // when the notification was posted (seconds)
        let key: String
        var app = ""                           // the wallet app's id, as the log has it
        var via = ""                           // iphone-relay (this app's log: relayed by Android ANA)
    }

    struct Tx {
        let txid: String
        let confirmed: Bool
        let time: Double
        let ins: [(String, Int64)]
        let outs: [(String, Int64)]

        init?(_ j: [String: Any]) {
            guard let id = j["txid"] as? String else { return nil }
            txid = id
            let st = j["status"] as? [String: Any]
            confirmed = (st?["confirmed"] as? Bool) ?? false
            time = confirmed ? ((st?["block_time"] as? NSNumber)?.doubleValue ?? 0) : Date().timeIntervalSince1970
            ins = ((j["vin"] as? [[String: Any]]) ?? []).map { (i: [String: Any]) -> (String, Int64) in
                Tx.pair(i["prevout"] as? [String: Any])
            }
            outs = ((j["vout"] as? [[String: Any]]) ?? []).map { (o: [String: Any]) -> (String, Int64) in Tx.pair(o) }
        }

        /// (address, value in satoshis) of an output
        static func pair(_ o: [String: Any]?) -> (String, Int64) {
            ((o?["scriptpubkey_address"] as? String) ?? "", (o?["value"] as? NSNumber)?.int64Value ?? 0)
        }

        func net(_ addr: String) -> Int64 {
            outs.filter { $0.0 == addr }.reduce(0) { $0 + $1.1 } - ins.filter { $0.0 == addr }.reduce(0) { $0 + $1.1 }
        }
    }

    struct Result {
        var state: String          // "watching", "proving", "proven"
        var note: String
        var txid: String?
        var detail: [String: String] = [:]    // what the signed witness records (Witness.swift)
    }

    // ------------------------------------------------------------------ reading the notification
    private static let head = try! NSRegularExpression(pattern: "(Received|Sent)\\s*:?\\s*([0-9]+(?:\\.[0-9]+)?)\\s+([A-Z]{2,10})\\b")
    private static let party = try! NSRegularExpression(pattern: "\\b(From|To)\\s+([A-Za-z0-9]+)(?:\\.{3}|\u{2026})([A-Za-z0-9]+)")

    /// "0.00008683" BTC -> 8683. nil if the coin is unknown or there are more decimals than it has.
    static func units(_ amount: String, _ ticker: String) -> Int64? {
        guard let d = decimals[ticker] else { return nil }
        let parts = amount.split(separator: ".", omittingEmptySubsequences: false)
        let whole = Int64(parts[0]) ?? 0
        let frac = parts.count > 1 ? String(parts[1]) : ""
        if frac.count > d { return nil }
        let padded = frac + String(repeating: "0", count: d - frac.count)
        var scale: Int64 = 1
        for _ in 0..<d { scale *= 10 }
        return whole * scale + (Int64(padded) ?? 0)
    }

    static func parse(title: String, text: String, at: Double, key: String) -> Cand? {
        let s = title + "\n" + text
        let ns = s as NSString
        guard let m = head.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let dir = ns.substring(with: m.range(at: 1)), amt = ns.substring(with: m.range(at: 2)), tk = ns.substring(with: m.range(at: 3))
        guard let u = units(amt, tk) else { return nil }
        var pre: String? = nil, suf: String? = nil
        if let p = party.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            pre = ns.substring(with: p.range(at: 2))
            suf = ns.substring(with: p.range(at: 3))
        }
        return Cand(incoming: dir == "Received", ticker: tk, units: u, amount: amt, prefix: pre, suffix: suf, at: at, key: key)
    }

    static func fitsParty(_ c: Cand, _ a: String) -> Bool {
        guard let p = c.prefix, let s = c.suffix else { return true }
        return a.hasPrefix(p) && a.hasSuffix(s)
    }

    /// Wallet-app notifications for this coin, from the log (relayed iPhone notifications), newest first.
    static func candidates(_ ticker: String) -> [Cand] {
        let cut = Date().timeIntervalSince1970 - lookBackDays * 86400
        var out = [Cand]()
        for l in AnaLog.readAll() {
            let f = l.components(separatedBy: "\t")
            guard f.count >= 7, f[0] == "IPHONE", walletApps.contains(f[3]) else { continue }
            let at = Double(Int64(f[2]) ?? 0) / 1000
            guard at > cut, var c = parse(title: f[4], text: f[5], at: at, key: f[6]), c.ticker == ticker else { continue }
            c.app = f[3]
            c.via = "iphone-relay"
            out.append(c)
        }
        return out.sorted { $0.at > $1.at }
    }

    // ------------------------------------------------------------------ matching
    static func fits(_ c: Cand, _ t: Tx, _ addr: String) -> Bool {
        guard t.confirmed, t.time >= c.at - windowBefore, t.time <= c.at + windowAfter else { return false }
        if c.incoming {
            guard t.outs.contains(where: { $0.0 == addr && $0.1 == c.units }) else { return false }
            return c.prefix == nil || t.ins.contains(where: { fitsParty(c, $0.0) })
        }
        guard t.ins.contains(where: { $0.0 == addr }) else { return false }
        // a send is matched by the output to the receiver; the change comes back as its own output
        return t.outs.contains(where: { $0.0 != addr && $0.1 == c.units && fitsParty(c, $0.0) })
    }

    /// The ownership state of one address, from its latest transactions (newest first, as the explorer
    /// gives them) and its balance in satoshis / litoshis.
    static func evaluate(addr: String, ticker: String, txs: [Tx], balance: Int64) -> Result {
        if balance <= 0 {
            return Result(state: "watching", note: "Empty: proof starts again with the next Received", txid: nil)
        }
        // when the address was last emptied (walking back from today's balance)
        var bal = balance
        var emptiedAt = 0.0
        for t in txs.sorted(by: { $0.time > $1.time }) {
            if bal == 0 && emptiedAt == 0 { emptiedAt = t.time }
            bal -= t.net(addr)
        }
        let now = Date().timeIntervalSince1970
        var waiting: Cand? = nil
        var unclear = false
        for c in candidates(ticker) {
            let hits = txs.filter { fits(c, $0, addr) }
            if hits.count == 1 {
                let t = hits[0]
                if t.time <= emptiedAt { continue }        // proved once, but emptied since
                let lag = Int(c.at - t.time)
                let who = c.prefix.map { (c.incoming ? " from " : " to ") + $0 + "..." + (c.suffix ?? "") } ?? ""
                let when = Wallets.when(c.at)
                let speed = lag >= 0 ? "push \(lag / 60) min \(lag % 60) s after the block" : "push \((-lag) / 60) min before the block"
                let note = "Proven: " + (c.incoming ? "+" : "-") + c.amount + " " + ticker + who + "  ·  " + when + "  ·  " + speed
                var r = Result(state: "proven", note: note, txid: t.txid)
                r.detail = ["coin": ticker, "address": addr, "direction": c.incoming ? "in" : "out", "units": String(c.units),
                            "amount": c.amount, "txid": t.txid, "block_time": String(Int64(t.time)),
                            "notified_ms": String(Int64(c.at * 1000)), "app": c.app, "via": c.via,
                            "party": c.prefix.map { $0 + "..." + (c.suffix ?? "") } ?? "", "note": note]
                return r
            }
            if hits.count > 1 { unclear = true }
            if hits.isEmpty && waiting == nil && now - c.at < windowBefore { waiting = c }
        }
        if let c = waiting {
            return Result(state: "proving", note: "Wallet notification caught (" + c.amount + " " + ticker + "), waiting for the chain", txid: nil)
        }
        return Result(state: "watching", note: unclear ? "Two transactions fit one notification: not proven" : "", txid: nil)
    }

    static func badge(_ state: String?) -> String {
        state == "proven" ? "Proven" : state == "proving" ? "Proving..." : "Watching"
    }
}
