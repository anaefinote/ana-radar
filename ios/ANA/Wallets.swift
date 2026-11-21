import Foundation
import CryptoKit

/// WATCH: wallets ANA keeps an eye on. Read-only: public addresses only (no keys, no signing, no login),
/// read straight from public blockchain data by the phone itself.
///
///  - ether.fi Cash: the user's Safe on OP Mainnet (Optimism), where ether.fi Cash lives since the move from Scroll.
///      Ready to spend = the USDC the Safe holds. Earning = the USDC ether.fi has lent out for the user, read
///      from ether.fi's LendGateway (0x01F8cDFb...1188E03F4, on Aave V4): suppliedOf(safe, USDC), interest
///      included; debtOf(safe, USDC) is what's borrowed (credit mode). If that read fails, Earning falls back
///      to the money moved into the gateway minus the money taken back (which misses card spends paid
///      straight from lending, so it can run high).
///      Activity = every USDC transfer in and out of the Safe, in plain words.
///  - Solana: a Solana address (a Jupiter wallet, or ether.fi's Solana deposit address): USDC and SOL.
///  - TRON: a TRON address (T..., 34 characters): USDT and TRX, read from TronGrid (public, no key).
///  - Litecoin and Bitcoin (ANA : STATIA only): an address you hold yourself (ltc1/L/M..., bc1/1/3...), from
///    litecoinspace.org and mempool.space (the same explorer, one for each coin).
///
/// When something new happens (money arrives, leaves, moves into or out of earning) it is added to ANA's log
/// as a WATCH entry, so it shows on Pulse like a notification.
final class Wallets {
    static let shared = Wallets()

    /// ANA : STATIA, ANA's big sister, also watches Litecoin (built with the STATIA flag).
    #if STATIA
    static let statia = true
    #else
    static let statia = false
    #endif

    struct Act: Codable {
        var t: Double            // seconds since 1970
        var amt: Double          // USDC (or the coin, when unit is set)
        var unit: String?        // nil = dollars; "LTC" / "BTC" = the coin
        var kind: String         // in, out, toEarn, fromEarn
        var label: String
        var id: String
    }

    struct Wallet: Codable {
        var id: String
        var name: String
        var kind: String         // "etherfi", "solana" or "tron"
        var addr: String
        var ready: Double = 0    // USDC ready to spend
        var earning: Double = 0  // ether.fi: USDC lent out
        var debt: Double?        // ether.fi: USDC borrowed (optional, so wallets saved by v0.6 still load)
        var earnExact: Bool?     // earning read from the gateway (not estimated)
        var borrowable: Double?  // ether.fi: available to borrow (USD), from getAccountData
        var sol: Double = 0      // Solana: SOL; TRON: TRX
        var updated: Double = 0
        var status: String = "Not checked yet"
        var activity: [Act] = []
        var seen: [String] = []
        var primed = false       // the first check only learns what's there (no alerts for old history)
        var hidden: Bool?        // SUB-WATCH: behind the front face (optional: wallets saved earlier still load)
        var hideUntil: Double?   // when it comes back to the front (0 or nil: until you bring it back)
        var shareHide: Bool?     // hide it while the screen is recorded or shared
        var proof: String?       // OWNERSHIP PROOF (Proof.swift): watching, proving, proven
        var proofNote: String?   // why, in plain words
        var proofTx: String?     // the transaction that proved it
        var proofDetail: [String: String]?   // what the signed witness records (Witness.swift)
        var lesson: String?      // LESSONS: the lesson that taught ANA this coin (kind "lesson")
    }

    var onNews: ((Wallet, [Act]) -> Void)?    // new activity since the last check (main thread)
    var onChange: (() -> Void)?
    var onProof: ((Wallet) -> Void)?          // a wallet has just been proven (a new matching transaction)
    private var again = false                 // asked to check while a check was running: check once more after

    private(set) var list: [Wallet] = []
    private(set) var busy = false
    var back = false             // SUB-WATCH is open (after the hold + Face ID); closes when ANA leaves the front
    var capturing = false        // the screen is being recorded, mirrored or shared: sub-watch stays shut
    private let key = "wallets_v1"

    // ------------------------------------------------------------------ chains and contracts
    private let opRPC = "https://mainnet.optimism.io"
    private let opUSDC = "0x0b2c639c533813f4aa9d7837caf62653d097ff85"        // Circle's USDC on Optimism
    private let opUSDCe = "0x7f5c764cbc14f9669b88837ca1490cca17c31607"       // the older bridged USDC.e
    private let opExplorer = "https://explorer.optimism.io/api/v2/addresses/"  // Blockscout (public, no key)
    private let lendPrefix = "0x01f8cdfb", lendSuffix = "1188e03f4"          // ether.fi Cash's lending contract
    private let lendGateway = "0x01f8cdfb1694ea8fe4ed6c38a0fd78d1188e03f4"   // LendGateway (proxy)
    private let rhinoBridge = "0x0bca65bf4b4c8803d2f0b49353ed57caaf3d66dc"   // Rhino.fi: Bridge
    private let solRPC = "https://api.mainnet-beta.solana.com"
    private let tronAPI = "https://api.trongrid.io/v1/accounts/"              // TronGrid (public, no key)
    private let tronUSDT = "TR7NHqjeKQxGTCi8q8ZYpPDdtsWPBQiYzr"               // Tether USD (TRC-20)
    private let ltcAPI = "https://litecoinspace.org/api/"                     // Litecoin explorer (public, no key)
    private let btcAPI = "https://mempool.space/api/"                          // Bitcoin explorer (public, no key)
    private let priceAPI = "https://api.coingecko.com/api/v3/simple/price?vs_currencies=usd&ids="
    private let solUSDC = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

    private init() {
        if let d = UserDefaults.standard.data(forKey: key),
           let l = try? JSONDecoder().decode([Wallet].self, from: d) { list = l }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(list) { UserDefaults.standard.set(d, forKey: key) }
    }

    // ------------------------------------------------------------------ adding, renaming, removing
    /// What kind of address it is, or nil if it isn't one ANA can watch.
    static func kindOf(_ a: String) -> String? {
        let s = a.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.range(of: "^0x[0-9a-fA-F]{40}$", options: .regularExpression) != nil { return "etherfi" }
        // LESSONS: a coin a lesson taught ANA (STATIA keeps its own Bitcoin and Litecoin, with ownership proof)
        if Lessons.shared.forAddress(s) != nil && !(statia && (isLitecoin(s) || isBitcoin(s))) { return "lesson" }
        if isLitecoin(s) { return "litecoin" }                                   // before Solana: L.../M... fit its shape too
        if isBitcoin(s) { return "bitcoin" }                                     // likewise 1.../3...
        if s.range(of: "^T[1-9A-HJ-NP-Za-km-z]{33}$", options: .regularExpression) != nil { return "tron" }   // before Solana: same shape
        if s.range(of: "^[1-9A-HJ-NP-Za-km-z]{32,44}$", options: .regularExpression) != nil { return "solana" }
        return nil
    }

    @discardableResult
    func add(name: String, addr: String, behind: Bool = false) -> String? {
        let a = addr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let k = Wallets.kindOf(a) else { return "That isn't an address ANA can watch yet (or a lesson for its coin)" }
        if k == "litecoin" && !Wallets.statia { return "Litecoin is watched by ANA : STATIA, ANA's big sister" }
        if k == "bitcoin" && !Wallets.statia { return "Bitcoin is watched by ANA : STATIA, ANA's big sister" }
        if list.contains(where: { $0.addr.lowercased() == a.lowercased() }) { return "ANA is already watching that address" }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let taught = k == "lesson" ? Lessons.shared.forAddress(a) : nil
        list.append(Wallet(id: UUID().uuidString, name: n.isEmpty ? (taught?.name ?? (k == "etherfi" ? "ether.fi Cash" : k == "tron" ? "TRON wallet" : k == "litecoin" ? "Litecoin" : k == "bitcoin" ? "Bitcoin" : "Solana wallet")) : n,
                           kind: k, addr: a, hidden: behind, lesson: taught?.id))   // added in sub-watch: stays behind until brought out
        save()
        refreshAll()
        return nil
    }

    func rename(_ id: String, _ name: String) {
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { list[i].name = n; save(); onChange?() }
    }

    func remove(_ id: String) {
        list.removeAll { $0.id == id }
        save()
        onChange?()
    }

    func wallet(_ id: String) -> Wallet? { list.first { $0.id == id } }

    // ------------------------------------------------------------------ SUB-WATCH: what the front face shows
    /// Behind the front face right now (a hide timer that has run out brings it back).
    @discardableResult
    func offFront(_ i: Int) -> Bool {
        let now = Date().timeIntervalSince1970
        if list[i].hidden == true, let u = list[i].hideUntil, u > 0, now >= u { list[i].hidden = false; list[i].hideUntil = 0 }
        return list[i].hidden == true || (capturing && list[i].shareHide == true)
    }

    func isHidden(_ id: String) -> Bool {
        guard let i = list.firstIndex(where: { $0.id == id }) else { return false }
        offFront(i)
        return list[i].hidden == true
    }

    /// seconds > 0: hide for that long; 0: until you bring it back; < 0: back to the front
    func hide(_ id: String, _ seconds: Double) {
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].hidden = seconds >= 0
        list[i].hideUntil = seconds > 0 ? Date().timeIntervalSince1970 + seconds : 0
        save()
        onChange?()
    }

    func setShareHide(_ id: String, _ on: Bool) {
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].shareHide = on
        save()
        onChange?()
    }

    static func left(_ secs: Double) -> String {
        let s = max(60, Int(secs)), d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func state(_ i: Int) -> String {
        offFront(i)
        if list[i].hidden != true { return "On the front" }
        if let u = list[i].hideUntil, u > 0 { return "Hidden  ·  back in " + Wallets.left(u - Date().timeIntervalSince1970) }
        return "Hidden until you bring it back"
    }

    // ------------------------------------------------------------------ checking
    func refreshAll() {
        if busy { again = true; return }
        if list.isEmpty { return }
        busy = true
        onChange?()
        let snapshot = list
        Task {
            var done = [Wallet]()
            for w in snapshot { done.append(await self.check(w)) }
            let results = done
            await MainActor.run {
                var news = [(Wallet, [Act])]()
                var proven = [Wallet]()
                for var w in results {
                    guard let i = self.list.firstIndex(where: { $0.id == w.id }) else { continue }
                    w.name = self.list[i].name                  // changed while checking: keep the newest
                    w.hidden = self.list[i].hidden
                    w.hideUntil = self.list[i].hideUntil
                    w.shareHide = self.list[i].shareHide
                    let fresh = self.newActivity(&w)
                    if w.proof == "proven", let t = w.proofTx, t != self.list[i].proofTx { proven.append(w) }
                    else if w.proof == "proven" && !Witness.exists(w) { Witness.save(w) }   // proven before witnesses existed
                    self.list[i] = w
                    if !fresh.isEmpty && !self.offFront(i) { news.append((w, fresh)) }   // hidden: quiet
                }
                self.busy = false
                self.save()
                for n in news { self.onNews?(n.0, n.1) }
                for p in proven { self.onProof?(p) }
                self.onChange?()
                if self.again { self.again = false; self.refreshAll() }
            }
        }
    }

    /// Activity not seen before (oldest first). The first check of a wallet only remembers what's there.
    private func newActivity(_ w: inout Wallet) -> [Act] {
        var have = Set(w.seen)
        var fresh = [Act]()
        for a in w.activity.reversed() where !have.contains(a.id) {
            have.insert(a.id)
            w.seen.append(a.id)
            if w.primed { fresh.append(a) }
        }
        if w.seen.count > 600 { w.seen.removeFirst(w.seen.count - 600) }
        w.primed = true
        return fresh
    }

    private func check(_ w0: Wallet) async -> Wallet {
        var w = w0
        do {
            w.status = ""                                // a check may set its own note (Litecoin: pending)
            if w.kind == "etherfi" { try await checkEtherfi(&w) }
            else if w.kind == "tron" { try await checkTron(&w) }
            else if Wallets.isCoin(w.kind) { try await checkCoin(&w) }
            else if w.kind == "lesson" { try await checkLesson(&w) }
            else { try await checkSolana(&w) }
            w.updated = Date().timeIntervalSince1970
        } catch {
            w.status = "Couldn't check: " + (error as NSError).localizedDescription
        }
        return w
    }

    // ------------------------------------------------------------------ ether.fi Cash on Optimism
    private func checkEtherfi(_ w: inout Wallet) async throws {
        let me = w.addr.lowercased()
        let a = try await erc20Balance(opUSDC, me)
        let b = (try? await erc20Balance(opUSDCe, me)) ?? 0
        w.ready = a + b

        // every USDC transfer in and out of the Safe (newest first, up to 10 pages of 50)
        var items = [[String: Any]]()
        var query = "type=ERC-20&token=" + opUSDC
        for _ in 0..<10 {
            let obj = try await getJSON(opExplorer + me + "/token-transfers?" + query)
            let page = (obj["items"] as? [[String: Any]]) ?? []
            items += page
            guard let next = obj["next_page_params"] as? [String: Any], !next.isEmpty, !page.isEmpty else { break }
            query = "type=ERC-20&token=" + opUSDC
            for (k, v) in next { query += "&\(k)=" + (String(describing: v).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") }
        }

        var acts = [Act]()
        var earning = 0.0
        for it in items {
            let from = (it["from"] as? [String: Any]) ?? [:], to = (it["to"] as? [String: Any]) ?? [:]
            let fromA = ((from["hash"] as? String) ?? "").lowercased(), toA = ((to["hash"] as? String) ?? "").lowercased()
            let total = (it["total"] as? [String: Any]) ?? [:]
            let dec = Int(String(describing: total["decimals"] ?? "6")) ?? 6
            let v = decimalValue(String(describing: total["value"] ?? "0"), dec)
            if v == 0 { continue }
            let incoming = toA == me
            let other = incoming ? fromA : toA
            let otherName = ((incoming ? from["name"] : to["name"]) as? String) ?? ""
            let lname = otherName.lowercased()
            let isLend = (other.hasPrefix(lendPrefix) && other.hasSuffix(lendSuffix)) || lname.contains("debtmanager") || lname.contains("lending")
            let tx = (it["transaction_hash"] as? String) ?? (it["tx_hash"] as? String) ?? UUID().uuidString
            let li = String(describing: it["log_index"] ?? "")
            let t = isoSeconds((it["timestamp"] as? String) ?? "")
            let kind: String, label: String
            if isLend {
                kind = incoming ? "fromEarn" : "toEarn"
                label = incoming ? "Taken out of earning" : "Moved into earning"
                earning += incoming ? -v : v
            } else if incoming {
                kind = "in"
                let via = friendly(otherName, other)
                label = via.isEmpty ? "Arrived" : "Arrived via " + via
            } else {
                kind = "out"
                let via = friendly(otherName, other)
                label = via.isEmpty ? "Sent out" : via == "card payment" ? "Card payment" : "Sent out via " + via
            }
            acts.append(Act(t: t, amt: v, kind: kind, label: label, id: tx + "#" + li))
        }
        // the exact figures, straight from ether.fi's lending gateway
        // suppliedOf returns 0 for an asset the gateway doesn't know, so check USDC is registered first
        let registered = ((try? await gatewayFlag("0xc3c5a547" + String(repeating: "0", count: 24) + String(opUSDC.dropFirst(2)))) ?? false)
        if registered, let sup = try? await gatewayRead("0x05a5b843", me) {   // suppliedOf(address,address)
            w.earning = sup
            w.earnExact = true
            w.debt = (try? await gatewayRead("0x4c4ab169", me)) ?? 0         // debtOf(address,address)
            w.borrowable = try? await availableToBorrow(me)
        } else {
            w.earning = max(0, earning)
            w.earnExact = false
        }
        w.activity = Array(acts.sorted { $0.t > $1.t }.prefix(40))
    }

    /// LendGateway.getAccountData(safe): (collateralUsd, debtUsd, availableBorrowsUsd, maxBorrowUsd, healthFactor),
    /// USD fields 6-decimal. Returns availableBorrowsUsd, what ether.fi shows as "Available to borrow".
    private func availableToBorrow(_ safe: String) async throws -> Double {
        let data = "0x5d78650e" + String(repeating: "0", count: 24) + String(safe.dropFirst(2))
        let obj = try await rpc(opRPC, "eth_call", [["to": lendGateway, "data": data], "latest"])
        guard let hex = obj["result"] as? String, hex.count >= 2 + 64 * 3 else { throw err("No account data") }
        let body = Array(hex.dropFirst(2))
        let word = String(body[128..<192])                                  // the third word
        return hexValue("0x" + word, 6)
    }

    /// LendGateway.isRegistered(asset) and the like: a true / false answer
    private func gatewayFlag(_ data: String) async throws -> Bool {
        let obj = try await rpc(opRPC, "eth_call", [["to": lendGateway, "data": data], "latest"])
        guard let hex = obj["result"] as? String, hex.count > 2 else { throw err("No answer from ether.fi's lending gateway") }
        return hexValue(hex, 0) > 0
    }

    /// LendGateway.f(safe, USDC) -> USDC (6 decimals; 18 if the number says so)
    private func gatewayRead(_ selector: String, _ safe: String) async throws -> Double {
        let pad = String(repeating: "0", count: 24)
        let data = selector + pad + String(safe.dropFirst(2)) + pad + String(opUSDC.dropFirst(2))
        let obj = try await rpc(opRPC, "eth_call", [["to": lendGateway, "data": data], "latest"])
        guard let hex = obj["result"] as? String, hex.count > 2 else { throw err("No answer from ether.fi's lending gateway") }
        let v6 = hexValue(hex, 6)
        return v6 > 1e12 ? hexValue(hex, 18) : v6
    }

    /// Plain names for the contracts money moves through ("" when the explorer only knows a generic proxy name)
    private func friendly(_ n: String, _ addr: String) -> String {
        let l = n.lowercased()
        if addr == rhinoBridge || l.contains("rhino") { return "Rhino.fi bridge" }
        if l.contains("cctp") { return "Circle's bridge" }
        if l.contains("settlement") { return "card payment" }
        if l.contains("proxy") || l.hasPrefix("erc1967") { return "" }
        return n
    }

    private func erc20Balance(_ token: String, _ owner: String) async throws -> Double {
        let data = "0x70a08231" + String(repeating: "0", count: 24) + owner.dropFirst(2)
        let obj = try await rpc(opRPC, "eth_call", [["to": token, "data": data], "latest"])
        guard let hex = obj["result"] as? String else { throw err("No balance from Optimism") }
        return hexValue(hex, 6)
    }

    // ------------------------------------------------------------------ Solana
    private func checkSolana(_ w: inout Wallet) async throws {
        let bal = try await rpc(solRPC, "getBalance", [w.addr])
        if let r = bal["result"] as? [String: Any], let lam = r["value"] as? Double { w.sol = lam / 1e9 }
        else if let r = bal["result"] as? [String: Any], let lam = r["value"] as? Int { w.sol = Double(lam) / 1e9 }
        let tok = try await rpc(solRPC, "getTokenAccountsByOwner", [w.addr, ["mint": solUSDC], ["encoding": "jsonParsed"]])
        var usdc = 0.0
        if let r = tok["result"] as? [String: Any], let v = r["value"] as? [[String: Any]] {
            for acct in v {
                let info = (((acct["account"] as? [String: Any])?["data"] as? [String: Any])?["parsed"] as? [String: Any])?["info"] as? [String: Any]
                let amt = (info?["tokenAmount"] as? [String: Any])?["uiAmountString"] as? String
                usdc += Double(amt ?? "0") ?? 0
            }
        }
        // Solana: ANA notices changes in the USDC balance (each one becomes an activity line)
        let diff = usdc - w.ready
        if w.primed && abs(diff) >= 0.005 {
            let now = Date().timeIntervalSince1970
            w.activity.insert(Act(t: now, amt: abs(diff), kind: diff > 0 ? "in" : "out",
                                  label: diff > 0 ? "USDC arrived" : "USDC left", id: "bal-\(Int(now))"), at: 0)
            if w.activity.count > 40 { w.activity.removeLast(w.activity.count - 40) }
        }
        w.ready = usdc
    }

    // ------------------------------------------------------------------ TRON
    private func checkTron(_ w: inout Wallet) async throws {
        let acc = try await getJSON(tronAPI + w.addr)
        var trx = 0.0, usdt = 0.0
        if let data = acc["data"] as? [[String: Any]], let a = data.first {   // empty until the address has received something
            if let b = a["balance"] as? NSNumber { trx = b.doubleValue / 1e6 }
            if let t20 = a["trc20"] as? [[String: Any]] {
                for o in t20 { if let v = o[tronUSDT] as? String { usdt += decimalValue(v, 6) } }
            }
        }
        w.sol = trx
        w.ready = usdt

        // the latest USDT transfers in and out
        let tx = try await getJSON(tronAPI + w.addr + "/transactions/trc20?limit=40&contract_address=" + tronUSDT)
        var acts: [Act] = []
        for it in (tx["data"] as? [[String: Any]]) ?? [] {
            let dec = ((it["token_info"] as? [String: Any])?["decimals"] as? NSNumber)?.intValue ?? 6
            let value = (it["value"] as? String) ?? "0"
            let v = decimalValue(value, dec)
            if v == 0 { continue }
            let incoming = (it["to"] as? String) == w.addr
            let other = (incoming ? it["from"] : it["to"]) as? String ?? ""
            let label = incoming ? "USDT arrived from " + Wallets.short(other) : "USDT sent to " + Wallets.short(other)
            let t = ((it["block_timestamp"] as? NSNumber)?.doubleValue ?? 0) / 1000
            let txid = (it["transaction_id"] as? String) ?? UUID().uuidString
            acts.append(Act(t: t, amt: v, kind: incoming ? "in" : "out", label: label, id: txid + "#" + other + "#" + value))
        }
        acts.sort { $0.t > $1.t }
        w.activity = Array(acts.prefix(40))
    }

    // ------------------------------------------------------------------ Litecoin (ANA : STATIA)
    /// ltc1... (native), or L... / M... with a valid Base58Check checksum (so a Solana address never passes).
    static func isLitecoin(_ s: String) -> Bool {
        if s.range(of: "^ltc1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{25,87}$", options: .regularExpression) != nil { return true }
        if s.range(of: "^[LM][1-9A-HJ-NP-Za-km-z]{32,33}$", options: .regularExpression) == nil { return false }
        return base58check(s, 0x30, 0x32)
    }

    /// bc1... (native / taproot), or 1... / 3... with a valid Base58Check checksum.
    static func isBitcoin(_ s: String) -> Bool {
        if s.range(of: "^bc1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{25,87}$", options: .regularExpression) != nil { return true }
        if s.range(of: "^[13][1-9A-HJ-NP-Za-km-z]{25,34}$", options: .regularExpression) == nil { return false }
        return base58check(s, 0x00, 0x05)
    }

    static func isCoin(_ kind: String) -> Bool { kind == "litecoin" || kind == "bitcoin" }

    /// an activity's amount: $4.70, or 0.5000 LTC / 0.012345 BTC
    static func actAmount(_ a: Act) -> String {
        guard let u = a.unit else { return money(a.amt) }
        return String(format: u == "BTC" ? "%.6f " : "%.4f ", a.amt) + u
    }

    /// GST: the dollar value of every watched wallet, and of those on the front face: "all TAB front"
    func totals() -> String {
        var all = 0.0, front = 0.0, proven = 0.0
        for i in list.indices {
            let w = list[i]
            let v = w.kind == "etherfi" ? w.ready + w.earning - max(0, w.debt ?? 0) : w.ready
            all += v
            if !offFront(i) { front += v }
            if w.proof == "proven" { proven += v }                // OWNERSHIP PROOF: proven wallets earn more eFLEX
        }
        return String(format: "%.2f\t%.2f\t%@\t%.2f", all, front, capturing ? "1" : "0", proven)   // 3rd: screen shared, 4th: proven
    }

    /// 0.5000 LTC / 0.012345 BTC (Bitcoin's coins are worth more, so two more places)
    static func coinAmount(_ w: Wallet) -> String {
        w.kind == "bitcoin" ? String(format: "%.6f BTC", w.sol) : String(format: "%.4f LTC", w.sol)
    }

    private static func base58check(_ s: String, _ v1: UInt8, _ v2: UInt8) -> Bool {
        guard let b = base58(s), b.count == 25, b[0] == v1 || b[0] == v2 else { return false }
        let h = Array(SHA256.hash(data: Data(SHA256.hash(data: Data(b[0..<21])))))
        return Array(h[0..<4]) == Array(b[21..<25])
    }

    private static func base58(_ s: String) -> [UInt8]? {
        let abc = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        var bytes: [UInt8] = []                       // big-endian, built up digit by digit
        for ch in s {
            guard let d = abc.firstIndex(of: ch) else { return nil }
            var carry = d
            for i in stride(from: bytes.count - 1, through: 0, by: -1) {
                carry += Int(bytes[i]) * 58
                bytes[i] = UInt8(carry & 0xff)
                carry >>= 8
            }
            while carry > 0 { bytes.insert(UInt8(carry & 0xff), at: 0); carry >>= 8 }
        }
        let lead = s.prefix { $0 == "1" }.count
        return Array(repeating: 0, count: lead) + bytes
    }

    /// Litecoin or Bitcoin: the same explorer format (one site per coin).
    private func checkCoin(_ w: inout Wallet) async throws {
        let btc = w.kind == "bitcoin"
        let api = btc ? btcAPI : ltcAPI, unit = btc ? "BTC" : "LTC", coin = btc ? "Bitcoin" : "Litecoin", id = btc ? "bitcoin" : "litecoin"
        let a = try await getJSON(api + "address/" + w.addr)
        func num(_ o: [String: Any]?, _ k: String) -> Int64 { (o?[k] as? NSNumber)?.int64Value ?? 0 }
        let cs = a["chain_stats"] as? [String: Any], ms = a["mempool_stats"] as? [String: Any]
        let lit = num(cs, "funded_txo_sum") - num(cs, "spent_txo_sum")
        let pending = num(ms, "funded_txo_sum") - num(ms, "spent_txo_sum")
        w.sol = Double(lit + pending) / 1e8                      // the coin (as SOL and TRX)
        if let p = (try? await getJSON(priceAPI + id))?[id] as? [String: Any],
           let usd = (p["usd"] as? NSNumber)?.doubleValue, usd > 0 { w.earning = usd }   // earning holds the price for litecoin
        w.ready = w.sol * w.earning
        if pending != 0 { w.status = "Pending: " + String(format: btc ? "%+.6f BTC" : "%+.4f LTC", Double(pending) / 1e8) }

        // every transaction in or out (the latest 25), from the inputs and outputs that are this address's
        guard let u = URL(string: api + "address/" + w.addr + "/txs") else { return }
        var r = URLRequest(url: u)
        r.timeoutInterval = 20
        let (d, _) = try await URLSession.shared.data(for: r)
        let txs = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] ?? []
        var acts: [Act] = []
        for tx in txs {
            var got: Int64 = 0, spent: Int64 = 0
            for o in (tx["vout"] as? [[String: Any]]) ?? [] where (o["scriptpubkey_address"] as? String) == w.addr {
                got += (o["value"] as? NSNumber)?.int64Value ?? 0
            }
            for i in (tx["vin"] as? [[String: Any]]) ?? [] {
                if let pv = i["prevout"] as? [String: Any], (pv["scriptpubkey_address"] as? String) == w.addr {
                    spent += (pv["value"] as? NSNumber)?.int64Value ?? 0
                }
            }
            let net = got - spent
            if net == 0 { continue }
            let st = tx["status"] as? [String: Any]
            let conf = (st?["confirmed"] as? Bool) ?? false
            let t: Double = conf ? ((st?["block_time"] as? NSNumber)?.doubleValue ?? 0) : Date().timeIntervalSince1970
            let label = coin + (net > 0 ? " arrived" : " sent") + (conf ? "" : " (pending)")
            let txid = ((tx["txid"] as? String) ?? UUID().uuidString) + (conf ? "" : "#p")
            acts.append(Act(t: t, amt: Double(abs(net)) / 1e8, unit: unit, kind: net > 0 ? "in" : "out", label: label, id: txid))
        }
        acts.sort { $0.t > $1.t }
        w.activity = Array(acts.prefix(40))

        // OWNERSHIP PROOF: the wallet app's own notifications against these same transactions
        let pr = Proof.evaluate(addr: w.addr, ticker: unit, txs: txs.compactMap { Proof.Tx($0) }, balance: lit + pending)
        w.proof = pr.state
        w.proofNote = pr.note
        w.proofTx = pr.txid
        w.proofDetail = pr.detail
    }

    // ------------------------------------------------------------------ LESSONS: a coin taught by a lesson
    private func checkLesson(_ w: inout Wallet) async throws {
        guard let l = Lessons.shared.find(w.lesson ?? "") else { throw err("its lesson was removed") }
        let (raw, server) = try await Lessons.shared.balance(l, w.addr)
        w.sol = Lessons.toCoin(raw, l.decimals)
        let pid = l.value("coin|price_id")
        if let p = (try? await getJSON(priceAPI + pid))?[pid] as? [String: Any],
           let usd = (p["usd"] as? NSNumber)?.doubleValue, usd > 0 { w.earning = usd }   // earning holds the price
        w.ready = w.sol * w.earning
        // esplora servers also list transactions: activity, the same way as Bitcoin and Litecoin
        guard l.value("reader|name") == "esplora", let u = URL(string: (server.hasSuffix("/") ? server : server + "/") + "address/" + w.addr + "/txs") else {
            w.proof = nil; w.proofNote = nil; w.proofTx = nil
            return
        }
        var r = URLRequest(url: u)
        r.timeoutInterval = 20
        let (d, _) = try await URLSession.shared.data(for: r)
        let txs = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] ?? []
        let scale = pow(10.0, Double(l.decimals))
        var acts: [Act] = []
        for tx in txs {
            var got: Int64 = 0, spent: Int64 = 0
            for o in (tx["vout"] as? [[String: Any]]) ?? [] where (o["scriptpubkey_address"] as? String) == w.addr { got += (o["value"] as? NSNumber)?.int64Value ?? 0 }
            for i in (tx["vin"] as? [[String: Any]]) ?? [] {
                if let pv = i["prevout"] as? [String: Any], (pv["scriptpubkey_address"] as? String) == w.addr { spent += (pv["value"] as? NSNumber)?.int64Value ?? 0 }
            }
            let net = got - spent
            if net == 0 { continue }
            let st = tx["status"] as? [String: Any]
            let conf = (st?["confirmed"] as? Bool) ?? false
            let t: Double = conf ? ((st?["block_time"] as? NSNumber)?.doubleValue ?? 0) : Date().timeIntervalSince1970
            acts.append(Act(t: t, amt: Double(abs(net)) / scale, unit: l.ticker, kind: net > 0 ? "in" : "out",
                            label: l.name + (net > 0 ? " arrived" : " sent") + (conf ? "" : " (pending)"),
                            id: ((tx["txid"] as? String) ?? UUID().uuidString) + (conf ? "" : "#p")))
        }
        acts.sort { $0.t > $1.t }
        w.activity = Array(acts.prefix(40))

        // OWNERSHIP PROOF works for lesson coins too: the same wallet-app notifications against these transactions
        if Proof.decimals[l.ticker] == nil { Proof.decimals[l.ticker] = l.decimals }
        let pr = Proof.evaluate(addr: w.addr, ticker: l.ticker, txs: txs.compactMap { Proof.Tx($0) }, balance: Int64(raw) ?? 0)
        w.proof = pr.state
        w.proofNote = pr.note
        w.proofTx = pr.txid
        w.proofDetail = pr.detail
    }

    static func lessonAmount(_ w: Wallet) -> String {
        let l = Lessons.shared.find(w.lesson ?? "")
        return String(format: "%.\(l?.shown ?? 4)f ", w.sol) + (l?.ticker ?? "")
    }

    // ------------------------------------------------------------------ plumbing
    private func err(_ m: String) -> NSError { NSError(domain: "Watch", code: 1, userInfo: [NSLocalizedDescriptionKey: m]) }

    private func rpc(_ url: String, _ method: String, _ params: [Any]) async throws -> [String: Any] {
        var r = URLRequest(url: URL(string: url)!)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.timeoutInterval = 20
        r.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        let (d, _) = try await URLSession.shared.data(for: r)
        guard let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { throw err("Bad answer from \(method)") }
        if let e = o["error"] as? [String: Any] { throw err((e["message"] as? String) ?? "Error from \(method)") }
        return o
    }

    private func getJSON(_ url: String) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw err("Bad address") }
        var r = URLRequest(url: u)
        r.timeoutInterval = 20
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        let (d, resp) = try await URLSession.shared.data(for: r)
        if let h = resp as? HTTPURLResponse, h.statusCode == 404 { return ["items": []] }   // no transfers yet
        guard let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { throw err("The explorer didn't answer") }
        return o
    }

    /// "0x..." (big number) -> value / 10^dec
    private func hexValue(_ hex: String, _ dec: Int) -> Double {
        var v = 0.0
        for c in hex.dropFirst(2) { v = v * 16 + Double(c.hexDigitValue ?? 0) }
        return v / pow(10, Double(dec))
    }

    /// "14150000" -> 14.15 (decimal string, any length)
    private func decimalValue(_ s: String, _ dec: Int) -> Double {
        var v = 0.0
        for c in s { if let d = c.wholeNumberValue { v = v * 10 + Double(d) } }
        return v / pow(10, Double(dec))
    }

    private func isoSeconds(_ s: String) -> Double {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d.timeIntervalSince1970 }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)?.timeIntervalSince1970 ?? 0
    }

    // ------------------------------------------------------------------ for the page
    static func money(_ v: Double) -> String { String(format: "$%.2f", v) }

    static func short(_ a: String) -> String { a.count > 12 ? String(a.prefix(6)) + "..." + String(a.suffix(4)) : a }

    static func ago(_ t: Double) -> String {
        if t <= 0 { return "Not checked yet" }
        let s = Int(Date().timeIntervalSince1970 - t)
        if s < 60 { return "Checked just now" }
        if s < 3600 { return "Checked \(s / 60) min ago" }
        if s < 86400 { return "Checked \(s / 3600) h ago" }
        return "Checked \(s / 86400) days ago"
    }

    static func when(_ t: Double) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        return f.string(from: Date(timeIntervalSince1970: t))
    }

    /// One line per wallet, then its activity, tab-separated (the sketch splits it):
    ///   W  id  name  sub  total  label1  value1  label2  value2  checked  status  [label3  value3]
    ///   A  wallet-name  when  sign(+ - ~)  amount  label
    func pageText() -> String {
        var out = [String]()
        if back {                       // SUB-WATCH: every wallet, with where it is
            for i in list.indices {
                let st = state(i), off = offFront(i)
                let w = list[i]
                let total = w.kind == "etherfi" ? w.ready + w.earning - (w.debt ?? 0) : w.ready
                let coin = Wallets.isCoin(w.kind)
                let chain = w.kind == "etherfi" ? "ether.fi  ·  Optimism  ·  " : w.kind == "tron" ? "TRON  ·  "
                    : w.kind == "litecoin" ? "Litecoin  ·  " : w.kind == "bitcoin" ? "Bitcoin  ·  " : w.kind == "lesson" ? "Lesson coin  ·  " : "Solana  ·  "
                var shown = coin && w.earning <= 0 ? Wallets.coinAmount(w) : Wallets.money(total)
                if w.kind == "lesson" { shown = w.earning > 0 ? Wallets.money(w.ready) : Wallets.lessonAmount(w) }
                out.append(["S", w.id, w.name, chain + Wallets.short(w.addr), shown, st, off ? "1" : "0",
                            w.shareHide == true ? "Hides while the screen is shared" : ""].map(AnaLog.clean).joined(separator: "\t"))
            }
            return out.joined(separator: "\n")
        }
        let front = list.indices.filter { !offFront($0) }.map { list[$0] }
        for w in front {
            if w.kind == "lesson" {                     // LESSONS: a coin taught by a lesson
                let l = Lessons.shared.find(w.lesson ?? "")
                let held = Wallets.lessonAmount(w), coin = l?.name ?? "Lesson coin"
                let st = busy ? "Checking..." : w.status.isEmpty ? (w.proofNote ?? "") : w.status
                var row = ["W", w.id, w.name, coin + " (lesson)  ·  " + Wallets.short(w.addr), w.earning > 0 ? Wallets.money(w.ready) : held,
                           "Holding", held, (l?.ticker ?? "") + " price", w.earning > 0 ? Wallets.money(w.earning) : "...",
                           Wallets.ago(w.updated), st]
                if l?.value("reader|name") == "esplora" { row += ["Ownership", Proof.badge(w.proof)] }   // proof needs the transactions
                out.append(row.map(AnaLog.clean).joined(separator: "\t"))
                continue
            }
            if Wallets.isCoin(w.kind) {
                let held = Wallets.coinAmount(w), coin = w.kind == "bitcoin" ? "Bitcoin" : "Litecoin"
                let st = busy ? "Checking..." : w.status.isEmpty ? (w.proofNote ?? "") : w.status
                out.append(["W", w.id, w.name, coin + "  ·  " + Wallets.short(w.addr), w.earning > 0 ? Wallets.money(w.ready) : held,
                            "Holding", held, coin + " price", w.earning > 0 ? Wallets.money(w.earning) : "...",
                            Wallets.ago(w.updated), st, "Ownership", Proof.badge(w.proof)].map(AnaLog.clean).joined(separator: "\t"))
                continue
            }
            let debt = w.debt ?? 0
            let total = w.kind == "etherfi" ? w.ready + w.earning - debt : w.ready
            let tr = w.kind == "tron"
            let chain = w.kind == "etherfi" ? "ether.fi Safe  ·  Optimism  ·  " : tr ? "TRON  ·  " : "Solana  ·  "
            let sub = chain + Wallets.short(w.addr)
            let r1 = w.kind == "etherfi" ? ["Ready to spend", Wallets.money(w.ready)] : [tr ? "USDT" : "USDC", Wallets.money(w.ready)]
            let earnLabel = (w.earnExact ?? false) ? "Earning (lent out)" : "Earning (estimate)"
            let r2 = w.kind == "etherfi" ? [earnLabel, Wallets.money(w.earning)] : (tr ? ["TRX", String(format: "%.2f", w.sol)] : ["SOL", String(format: "%.4f", w.sol)])
            var status: String = w.status
            if busy { status = "Checking..." }
            else if status.isEmpty && debt > 0.004 { status = "Borrowed " + Wallets.money(debt) + "  ·  " + Wallets.ago(w.updated) }
            var row: [String] = ["W", w.id, w.name, sub, Wallets.money(total), r1[0], r1[1], r2[0], r2[1], Wallets.ago(w.updated), status]
            if w.kind == "etherfi", let b = w.borrowable { row += ["Available to borrow", Wallets.money(b)] }
            out.append(row.map(AnaLog.clean).joined(separator: "\t"))
        }
        var all = [(Double, String)]()
        for w in front {
            for a in w.activity {
                let sign = a.kind == "in" ? "+" : a.kind == "out" ? "-" : "~"
                let amt = a.unit == nil ? Wallets.money(a.amt) : String(format: a.unit == "BTC" ? "%.6f " : "%.4f ", a.amt) + (a.unit ?? "")
                all.append((a.t, ["A", w.name, Wallets.when(a.t), sign, amt, a.label].map(AnaLog.clean).joined(separator: "\t")))
            }
        }
        for a in all.sorted(by: { $0.0 > $1.0 }).prefix(20) { out.append(a.1) }
        return out.joined(separator: "\n")
    }
}
