import UIKit
import CryptoKit

/// BILLS on the iPhone (rules: BillCore.swift, the same as Android's).
///
/// A bill repeats every N days / weeks / months / years (or once); its due dates are laid out 12 months ahead and
/// locked (signed schedule, class 43). The next due date goes on EFINOTE's Future window as a reminder.
///
/// THE ANDROID AUTHENTICATES: the iPhone can't read other apps' notifications, so each bill's signed schedule goes
/// to ANA on the linked Android (over Bluetooth, or as a file). The Android watches for the payment notification
/// and, when one fits a due date, signs a "paid" confirmation (class 44) and sends it back over the link. Here it
/// is checked against this phone's own locked schedule, and only the Android this phone is linked with is trusted
/// (its key is learned the first time a confirmation comes over the Bluetooth link). Without it: Claimed.
final class Bills {
    static let shared = Bills()
    static let pkg = "ana.flex"

    struct Help: Codable {
        var hid = "", helperKey = "", helperName = "", proof = "", note = "", occ = ""
        var cents: Int64 = 0, at: Int64 = 0
        init() { }
        init(from d: Decoder) throws {                   // "occ" is new: older helps have none
            let c = try d.container(keyedBy: CodingKeys.self)
            hid = (try c.decodeIfPresent(String.self, forKey: .hid)) ?? ""
            helperKey = (try c.decodeIfPresent(String.self, forKey: .helperKey)) ?? ""
            helperName = (try c.decodeIfPresent(String.self, forKey: .helperName)) ?? ""
            proof = (try c.decodeIfPresent(String.self, forKey: .proof)) ?? ""
            note = (try c.decodeIfPresent(String.self, forKey: .note)) ?? ""
            occ = (try c.decodeIfPresent(String.self, forKey: .occ)) ?? ""
            cents = (try c.decodeIfPresent(Int64.self, forKey: .cents)) ?? 0
            at = (try c.decodeIfPresent(Int64.self, forKey: .at)) ?? 0
        }
    }

    struct Occ: Codable {
        var state = "open", note = "", key = ""
        var paidAt: Int64 = 0
        var onTime = false
        var pts = 0.0
    }

    final class Bill: Codable {
        var id = BillCore.newId()
        var kind = "plan"
        var name = "", cur = "BBD", due = "", app = "", appName = ""
        var every = 0
        var unit = "month"
        var cents: Int64 = 0, made = AnaLog.nowMs()
        var pic = "", lock = ""
        var shared = false
        var occ = [String: Occ]()
        var helps = [Help]()
        var billId = "", ownerKey = "", ownerName = "", hid = "", reminded = ""
        var billCents: Int64 = 0
        var thanked = false
        var helpPts = 0.0
        var sentApp: String? = nil                       // the payment app last sent to the Android with the schedule
        var forBill = ""                                 // a daily set-aside for that bill (moves the goal, earns nothing itself)

        enum CodingKeys: String, CodingKey { case id, kind, name, cur, due, app, appName, every, unit, cents, made, pic, lock, shared, occ, helps, billId, ownerKey, ownerName, hid, reminded, billCents, thanked, helpPts, sentApp, forBill, state, proofNote, proofKey, paidAt, onTime, pts }
        init() { }
        /// reads every build's bills.json; bills from the first bills build keep their state on their one due date
        required init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            if let v = try c.decodeIfPresent(String.self, forKey: .id) { id = v }
            if let v = try c.decodeIfPresent(String.self, forKey: .kind) { kind = v }
            if let v = try c.decodeIfPresent(String.self, forKey: .name) { name = v }
            if let v = try c.decodeIfPresent(String.self, forKey: .cur) { cur = v }
            if let v = try c.decodeIfPresent(String.self, forKey: .due) { due = v }
            if let v = try c.decodeIfPresent(String.self, forKey: .app) { app = v }
            if let v = try c.decodeIfPresent(String.self, forKey: .appName) { appName = v }
            if let v = try c.decodeIfPresent(Int.self, forKey: .every) { every = v }
            if let v = try c.decodeIfPresent(String.self, forKey: .unit) { unit = v }
            if let v = try c.decodeIfPresent(Int64.self, forKey: .cents) { cents = v }
            if let v = try c.decodeIfPresent(Int64.self, forKey: .made) { made = v }
            if let v = try c.decodeIfPresent(String.self, forKey: .pic) { pic = v }
            if let v = try c.decodeIfPresent(String.self, forKey: .lock) { lock = v }
            if let v = try c.decodeIfPresent(Bool.self, forKey: .shared) { shared = v }
            if let v = try c.decodeIfPresent([String: Occ].self, forKey: .occ) { occ = v }
            if let v = try c.decodeIfPresent([Help].self, forKey: .helps) { helps = v }
            if let v = try c.decodeIfPresent(String.self, forKey: .billId) { billId = v }
            if let v = try c.decodeIfPresent(String.self, forKey: .ownerKey) { ownerKey = v }
            if let v = try c.decodeIfPresent(String.self, forKey: .ownerName) { ownerName = v }
            if let v = try c.decodeIfPresent(String.self, forKey: .hid) { hid = v }
            if let v = try c.decodeIfPresent(String.self, forKey: .reminded) { reminded = v }
            if let v = try c.decodeIfPresent(Int64.self, forKey: .billCents) { billCents = v }
            if let v = try c.decodeIfPresent(Bool.self, forKey: .thanked) { thanked = v }
            if let v = try c.decodeIfPresent(Double.self, forKey: .helpPts) { helpPts = v }
            if let v = try c.decodeIfPresent(String.self, forKey: .sentApp) { sentApp = v }
            if let v = try c.decodeIfPresent(String.self, forKey: .forBill) { forBill = v }
            if occ.isEmpty, let st = try c.decodeIfPresent(String.self, forKey: .state), st != "open", let first = dates().first {
                var o = Occ()
                o.state = st
                o.note = (try c.decodeIfPresent(String.self, forKey: .proofNote)) ?? ""
                o.key = (try c.decodeIfPresent(String.self, forKey: .proofKey)) ?? ""
                o.paidAt = (try c.decodeIfPresent(Int64.self, forKey: .paidAt)) ?? 0
                o.onTime = (try c.decodeIfPresent(Bool.self, forKey: .onTime)) ?? false
                o.pts = (try c.decodeIfPresent(Double.self, forKey: .pts)) ?? 0
                occ[first] = o
            }
            if kind == "help" && thanked && helpPts == 0 { helpPts = (try c.decodeIfPresent(Double.self, forKey: .pts)) ?? 0 }
        }
        func encode(to e: Encoder) throws {
            var c = e.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(kind, forKey: .kind)
            try c.encode(name, forKey: .name)
            try c.encode(cur, forKey: .cur)
            try c.encode(due, forKey: .due)
            try c.encode(app, forKey: .app)
            try c.encode(appName, forKey: .appName)
            try c.encode(every, forKey: .every)
            try c.encode(unit, forKey: .unit)
            try c.encode(cents, forKey: .cents)
            try c.encode(made, forKey: .made)
            try c.encode(pic, forKey: .pic)
            try c.encode(lock, forKey: .lock)
            try c.encode(shared, forKey: .shared)
            try c.encode(occ, forKey: .occ)
            try c.encode(helps, forKey: .helps)
            try c.encode(billId, forKey: .billId)
            try c.encode(ownerKey, forKey: .ownerKey)
            try c.encode(ownerName, forKey: .ownerName)
            try c.encode(hid, forKey: .hid)
            try c.encode(reminded, forKey: .reminded)
            try c.encode(billCents, forKey: .billCents)
            try c.encode(thanked, forKey: .thanked)
            try c.encode(helpPts, forKey: .helpPts)
            try c.encode(sentApp, forKey: .sentApp)
            try c.encode(forBill, forKey: .forBill)
        }

        func dates() -> [String] {
            if kind == "plan" { return BillCore.schedule(due, every, unit) }
            return [kind == "paid" ? BillCore.ymd(ms: made) : "help"]
        }
        func get(_ d: String) -> Occ { occ[d] ?? Occ() }
        func helped(_ d: String) -> Int64 { helps.filter { $0.occ == d || $0.occ.isEmpty }.reduce(0) { $0 + $1.cents } }
        func window(_ d: String) -> (Int64, Int64, Int64) {
            if kind == "plan" { return BillCore.window(d, every, unit, made) }
            if kind == "paid" { return (made - BillCore.paidBefore, made + BillCore.paidAfter, made + BillCore.paidAfter) }
            return (made - BillCore.day, made + BillCore.helpWindow, made + BillCore.helpWindow)
        }
        func current() -> String? {
            let now = AnaLog.nowMs()
            var next: String?
            for d in dates() {
                if get(d).state == "proven" { continue }
                if kind == "plan" && cents - helped(d) <= 0 { continue }   // paid in full by the people who helped
                let w = window(d)
                if w.2 < now && kind == "plan" { continue }
                if w.0 <= now { return d }
                if next == nil { next = d }
            }
            return next
        }
        var pts: Double { occ.values.reduce(0) { $0 + $1.pts } + helpPts }
    }

    struct Earned: Codable { var at: Int64; var what: String; var pts: Double; var pair: String }

    private struct Store: Codable {
        var bills = [Bill](); var earned = [Earned](); var seenHelps = [String](); var seenPaid = [String](); var authenticators = [String]()
        init(bills: [Bill], earned: [Earned], seenHelps: [String], seenPaid: [String], authenticators: [String]) {
            self.bills = bills; self.earned = earned; self.seenHelps = seenHelps; self.seenPaid = seenPaid; self.authenticators = authenticators
        }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            bills = (try c.decodeIfPresent([Bill].self, forKey: .bills)) ?? []
            earned = (try c.decodeIfPresent([Earned].self, forKey: .earned)) ?? []
            seenHelps = (try c.decodeIfPresent([String].self, forKey: .seenHelps)) ?? []
            seenPaid = (try c.decodeIfPresent([String].self, forKey: .seenPaid)) ?? []
            authenticators = (try c.decodeIfPresent([String].self, forKey: .authenticators)) ?? []
        }
    }

    var list = [Bill]()
    var earned = [Earned]()
    var seenHelps = Set<String>(), seenPaid = Set<String>()
    var authenticators = Set<String>()                  // key ids of the Android(s) trusted to confirm payments
    private var myKey: String?

    static var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("bills")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private init() {
        if let d = try? Data(contentsOf: Bills.dir.appendingPathComponent("bills.json")),
           let s = try? JSONDecoder().decode(Store.self, from: d) {
            list = s.bills; earned = s.earned; seenHelps = Set(s.seenHelps); seenPaid = Set(s.seenPaid); authenticators = Set(s.authenticators)
        }
    }

    func save() {
        let s = Store(bills: list, earned: earned, seenHelps: Array(seenHelps), seenPaid: Array(seenPaid), authenticators: Array(authenticators))
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: Bills.dir.appendingPathComponent("bills.json"), options: .atomic) }
    }

    func find(_ id: String) -> Bill? { list.first { $0.id == id } }
    var totalExact: Double { earned.reduce(0) { $0 + $1.pts } }
    var total: Int { Int(floor(totalExact + 1e-9)) }

    func text() -> String {
        let open = list.filter { $0.kind == "help" ? !$0.thanked : $0.current() != nil }.count
        let g = goal()
        return "\(open)\t\(total)\t\(list.count)\t\(g.bills == 0 ? -1 : g.pct)"
    }

    func earn(_ what: String, _ pts: Double, _ pair: String = "") {
        if pts <= 0 { return }
        earned.append(Earned(at: AnaLog.nowMs(), what: what, pts: pts, pair: pair))
        AnaLog.append(src: "FLEX", postMs: AnaLog.nowMs(), pkg: Bills.pkg, title: "Bills", text: what + "  ·  +" + BillCore.pts(pts) + " eFLEX",
                      key: "bill-" + BillCore.newId())
    }

    func pairCount(_ pair: String) -> Int {
        let cut = AnaLog.nowMs() - BillCore.pairDays
        return 1 + earned.filter { $0.pair == pair && $0.at > cut }.count
    }

    static func pairOf(_ a: String, _ b: String) -> String { a < b ? a + "|" + b : b + "|" + a }

    func myKeyId() -> String {
        if let k = myKey { return k }
        guard let p = Flex.signRaw(Data("probe".utf8)) else { return "" }
        myKey = BillCore.hex(Data(SHA256.hash(data: p.pub)))
        return myKey!
    }

    /// apps that sent notifications lately (relayed by Android ANA), most recent first: the payment app is one of these
    func recentApps() -> [String] {
        let cut = AnaLog.nowMs() - 60 * BillCore.day
        var seen = Set<String>(), out = [String]()
        for l in AnaLog.readAll().reversed() {
            let f = l.components(separatedBy: "\t")
            guard f.count >= 7, f[0] == "IPHONE", let at = Int64(f[2]), at > cut, !f[3].hasPrefix("ana."), !seen.contains(f[3]) else { continue }
            seen.insert(f[3]); out.append(f[3])
        }
        return out
    }

    static func fmtDay(_ ms: Int64) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }

    static func fmtDue(_ ymd: String) -> String {
        guard let d = BillCore.cal(ymd) else { return ymd }
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }

    // ------------------------------------------------------------------ the Future window + the Android
    /// keeps the next due dates on the Future window and the Android up to date (call after any change)
    func tick() {
        for b in list where b.kind == "plan" { remind(b) }
        sendSchedules()
        save()
    }

    func remind(_ b: Bill) {
        guard let d = b.current(), d != b.reminded, b.get(d).state == "open", let day = BillCore.cal(d) else { return }
        let all = b.dates()
        let left = all.count - (all.firstIndex(of: d) ?? 0) - 1
        AnaLog.append(src: "REMIND", postMs: AnaLog.nowMs(), pkg: Bills.pkg, title: "Bill due: " + b.name,
                      text: BillCore.money(b.cents, b.cur) + "  ·  " + BillCore.repeatWords(b.every, b.unit) + (left > 0 ? "  ·  \(left) more in the next 12 months" : ""),
                      key: "billdue-" + b.id + "-" + d, eventMs: Int64(day.timeIntervalSince1970 * 1000) + 9 * 3_600_000)
        b.reminded = d
    }

    /// every bill with a payment app goes to the Android (again if its app changed); the Android ignores repeats
    func sendSchedules(force: Bool = false) {
        guard AndroidLink.shared.linked else { return }
        for b in list where !b.app.isEmpty && (force || b.sentApp != b.app) && !(b.kind == "help" && b.thanked) {
            if let f = schedFile(b, withApp: true), AndroidLink.shared.sendBill(f) { b.sentApp = b.app }
        }
    }

    // ------------------------------------------------------------------ actions
    @discardableResult
    func add(_ kind: String, _ name: String, _ cents: Int64, _ cur: String, _ due: String, every: Int = 0, unit: String = "month") -> Bill {
        let b = Bill()
        b.kind = kind; b.name = BillCore.clean(name); b.cents = cents; b.cur = cur; b.due = due; b.every = every; b.unit = unit
        lock(b)
        list.insert(b, at: 0)
        tick()
        return b
    }

    func lock(_ b: Bill) {
        if let f = schedFile(b, withApp: false) { b.lock = BillCore.hex(Data(SHA256.hash(data: f))) }
    }

    func setApp(_ b: Bill, _ app: String, _ label: String) { b.app = app; b.appName = label; tick() }

    func award(_ b: Bill, _ d: String, _ paid: Int64) -> Double {
        if b.kind == "help" || !b.forBill.isEmpty { return 0 }
        var o = b.get(d)
        let c = paid > 0 ? paid : b.cents
        var rate = b.kind == "plan" ? (o.onTime ? BillCore.rPlan : BillCore.rLate) : BillCore.rPaid
        if b.kind == "plan" && o.onTime && o.paidAt > 0 && o.paidAt <= BillCore.dayEnd(d) - BillCore.aheadMs { rate = BillCore.rAhead }
        if o.state == "claimed" { rate *= BillCore.claimed }
        let want = BillCore.points(c, b.cur, rate)
        let add = max(0, want - o.pts)
        o.pts = max(o.pts, want)
        b.occ[d] = o
        return add
    }

    func claim(_ b: Bill, pic: String) -> String {
        guard let d = b.current() else { return "Nothing due" }
        var o = b.get(d)
        if o.state == "proven" { return "Already proven" }
        o.state = "claimed"
        o.paidAt = AnaLog.nowMs()
        o.onTime = b.kind != "plan" || o.paidAt <= BillCore.dayEnd(d)
        o.note = "Claimed " + Bills.fmtDay(o.paidAt) + (pic.isEmpty ? "" : ", with a picture") + ". The Android's confirmation makes it Proven."
        b.occ[d] = o
        if !pic.isEmpty { b.pic = pic }
        let now = award(b, d, b.cents - (b.kind == "plan" ? b.helped(d) : 0))
        if now > 0 { earn(b.name + " (" + (d == "help" ? "help" : Bills.fmtDue(d)) + "): paid (claimed)", now) }
        tick()
        return b.name + ": claimed" + (now > 0 ? " (+" + BillCore.pts(now) + " eFLEX)" : "")
    }

    func remove(_ b: Bill) { list.removeAll { $0 === b }; save() }

    // ------------------------------------------------------------------ THE 30-DAY SETTLEMENT GOAL (as Android's Bills.java)
    static func settled(_ o: Occ?) -> Bool { o?.state == "proven" || o?.state == "claimed" }

    func setAside(_ b: Bill) -> Int64 {
        var last = ""
        for d in b.dates() where Bills.settled(b.occ[d]) { last = d }
        var sum: Int64 = 0
        for k in list where k.forBill == b.id {
            for (d, o) in k.occ where Bills.settled(o) && d > last { sum += k.cents }
        }
        return sum
    }

    struct Goal {
        var covered: Int64 = 0, total: Int64 = 0
        var pct = 0, bills = 0
        var lines = [String]()
        var open = [[String]]()                        // [bill id, name, cents, cur, due]
    }

    func goal() -> Goal {
        var g = Goal()
        let now = AnaLog.nowMs(), end = now + BillCore.goalMs
        for b in list where b.kind == "plan" && b.forBill.isEmpty {
            var pool = setAside(b), bc: Int64 = 0, bt: Int64 = 0
            var any = false
            for d in b.dates() {
                let e = BillCore.dayEnd(d)
                if e < now { continue }
                if e > end { break }
                any = true
                let left = b.cents - b.helped(d)
                let u = Int64((BillCore.usd(b.cents, b.cur) * 100).rounded())
                bt += u
                if Bills.settled(b.occ[d]) || left <= 0 { bc += u; continue }
                if pool >= left { pool -= left; bc += u; continue }
                bc += Int64((BillCore.usd(b.cents - left + pool, b.cur) * 100).rounded())
                pool = 0
                g.open.append([b.id, b.name, "\(left)", b.cur, d])
            }
            if !any { continue }
            g.bills += 1; g.total += bt; g.covered += bc
            g.lines.append(b.name + ": " + (bc >= bt ? "settled" : "\(Int((100.0 * Double(bc) / Double(max(1, bt))).rounded()))% settled") + "  ·  " + ahead(b))
        }
        let hasPlans = list.contains { $0.kind == "plan" && $0.forBill.isEmpty }
        if g.bills == 0 && hasPlans { g.bills = 1; g.pct = 100 }
        else { g.pct = g.total == 0 ? 0 : min(100, Int(floor(100.0 * Double(g.covered) / Double(g.total)))) }
        return g
    }

    func aheadDays(_ b: Bill) -> Int {
        let now = AnaLog.nowMs()
        var pool = setAside(b), first = true
        for d in b.dates() {
            let e = BillCore.dayEnd(d)
            if e < now { continue }
            let left = b.cents - b.helped(d)
            var ok = Bills.settled(b.occ[d]) || left <= 0
            if !ok && pool >= left { pool -= left; ok = true }
            if !ok { return first ? 0 : Int(max(0, (e - now) / BillCore.day)) }
            first = false
        }
        return first ? 0 : 366
    }

    func ahead(_ b: Bill) -> String {
        let a = aheadDays(b)
        return a >= 366 ? "settled for the year" : a >= 30 ? "\(a) days ahead: off the payday cycle" : a > 1 ? "\(a) days ahead" : a == 1 ? "1 day ahead" : "not ahead yet"
    }

    func enjoyed(_ b: Bill) -> Int {
        let now = AnaLog.nowMs()
        var from = b.made
        for d in b.dates() { let e = BillCore.dayEnd(d); if e < now { from = e } else { break } }
        return Int(max(0, (now - from) / BillCore.day))
    }

    func passOn() -> Bool { list.contains { !$0.helps.isEmpty } && goal().pct >= 100 }

    @discardableResult
    func addSetAside(_ p: Bill) -> Bill {
        if let k = list.first(where: { $0.forBill == p.id }) { return k }
        let days = max(1, BillCore.period(p.every, p.unit) / BillCore.day)
        let b = Bill()
        b.kind = "plan"; b.name = "Set aside: " + p.name; b.cur = p.cur; b.every = 1; b.unit = "day"
        b.cents = (p.cents + days - 1) / days
        b.due = BillCore.ymd(ms: AnaLog.nowMs())
        b.forBill = p.id
        lock(b)
        list.insert(b, at: (list.firstIndex { $0 === p } ?? 0) + 1)
        tick()
        return b
    }

    // ------------------------------------------------------------------ the journey (45)
    func shareJourney(_ me: String, showHelpers: Bool) -> [URL]? {
        let g = goal()
        var rows = [["journey", "version", "1"], ["journey", "owner_name", me], ["journey", "pct", "\(g.pct)"],
                    ["journey", "covered_usd_cents", "\(g.covered)"], ["journey", "total_usd_cents", "\(g.total)"], ["journey", "made_ms", "\(AnaLog.nowMs())"]]
        for (i, o) in g.open.prefix(8).enumerated() { rows.append(["journey", "bill\(i)", o.joined(separator: "\u{1f}")]) }
        if showHelpers {
            var names = [String]()
            for b in list { for h in b.helps where !names.contains(h.helperName) { names.append(h.helperName) } }
            rows.append(["journey", "helped_by", names.joined(separator: ", ")])
        }
        let words = (g.open.isEmpty ? "Everything due in the next 30 days is settled." : "\(g.open.count) bill" + (g.open.count == 1 ? "" : "s") + " left to settle. Open with ANA to step in.")
            + " Novvera never touches money: helpers pay the biller themselves."
        guard let all = BillCore.build(BillCore.clsJourney, rows, signer: signer,
              png: picture("ANA journey", me + ": \(g.pct)% of the way to 30 days ahead", words)) else { return nil }
        return write("journey_" + BillCore.newId() + ".pngmesh", all)
    }

    static func journeyBills(_ s: BillCore.Signed) -> [[String]] {
        var out = [[String]]()
        for i in 0..<8 {
            let v = s.get("journey|bill\(i)")
            if v.isEmpty { break }
            let f = v.components(separatedBy: "\u{1f}")
            if f.count == 5 { out.append(f) }
        }
        return out
    }

    func acceptFromJourney(_ s: BillCore.Signed, _ jb: [String], _ myCents: Int64) -> Bill {
        let h = Bill()
        h.kind = "help"
        h.billId = jb[0]; h.ownerKey = s.keyId; h.ownerName = BillCore.clean(s.get("journey|owner_name"))
        h.name = BillCore.clean(jb[1] + " (" + h.ownerName + ")")
        h.cur = jb[3]; h.due = jb[4]
        h.billCents = Int64(jb[2]) ?? 0
        h.cents = max(1, min(myCents, h.billCents))
        h.hid = BillCore.newId()
        lock(h)
        list.insert(h, at: 0)
        save()
        return h
    }

    // ------------------------------------------------------------------ the Android's signed confirmation (44)
    /// viaLink: it came over the Bluetooth link (the first one teaches this phone which Android to trust)
    @discardableResult
    func paid(_ f: Data, viaLink: Bool) -> String? {
        let s = BillCore.read(f)
        guard s.ok, s.cls == BillCore.clsPaid else { return "Payment confirmation not accepted: " + s.why }
        let tag = s.get("paid|bill_id") + "|" + s.get("paid|due")
        if seenPaid.contains(tag) { return nil }
        if !authenticators.contains(s.keyId) {
            if viaLink && authenticators.isEmpty { authenticators.insert(s.keyId) }       // the linked Android
            else { return "A payment confirmation from an Android this iPhone isn't linked with: ignored" }
        }
        guard s.get("paid|owner_key_id") == myKeyId(), let b = find(s.get("paid|bill_id")) else { return nil }
        let d = s.get("paid|due")
        guard b.dates().contains(d) else { return "A payment confirmation for a date not in " + b.name + "'s locked schedule: ignored" }
        let c = Int64(s.get("paid|cents")) ?? 0, at = Int64(s.get("paid|notified_ms")) ?? 0
        guard c == b.cents || c == b.cents - b.helped(d) else { return "A payment confirmation with the wrong amount: ignored" }
        let w = b.window(d)
        guard at >= w.0 && at <= w.2 else { return "A payment confirmation outside the due date's window: ignored" }
        seenPaid.insert(tag)
        var o = b.get(d)
        if o.state == "proven" { save(); return nil }
        o.state = "proven"
        o.paidAt = at
        o.onTime = at <= w.1
        o.note = "Proven by your Android: " + s.get("paid|note")
        b.occ[d] = o
        let now = award(b, d, c)
        if now > 0 { earn(b.name + " (" + (d == "help" ? "help" : Bills.fmtDue(d)) + "): " + (b.kind == "plan" ? (o.onTime ? "paid on time" : "paid late") : "paid"), now) }
        tick()
        return b.name + ": payment proven by your Android" + (now > 0 ? " (+" + BillCore.pts(now) + " eFLEX)" : "")
    }

    // ------------------------------------------------------------------ files
    private func picture(_ head: String, _ title: String, _ text: String) -> Data {
        AnaMesh.preview([["FLEX", AnaLog.when(AnaLog.nowMs()), "", Bills.pkg, title, text]], head: head).pngData() ?? Data()
    }

    private static let dot = BillCore.unhex("89504e470d0a1a0a0000000d4948445200000001000000010806000000"
        + "1f15c4890000000a49444154789c63000100000500010d0a2db40000000049454e44ae426082") ?? Data()

    private func write(_ name: String, _ all: Data) -> [URL]? {
        let m = Bills.dir.appendingPathComponent(name)
        let s = Bills.dir.appendingPathComponent(String(name.dropLast(8)) + ".sha256")
        do {
            try all.write(to: m)
            try AnaMesh.sidecar(name: name, mesh: all).data(using: .utf8)?.write(to: s)
        } catch { return nil }
        return [m, s]
    }

    private let signer: BillCore.Signer = { Flex.signRaw($0) }

    func schedFile(_ b: Bill, withApp: Bool) -> Data? {
        var rows = [["sched", "version", "1"], ["sched", "id", b.id], ["sched", "kind", b.kind], ["sched", "name", b.name],
                    ["sched", "cents", "\(b.cents)"], ["sched", "currency", b.cur], ["sched", "first_due", b.kind == "plan" ? b.due : ""],
                    ["sched", "every", "\(b.every)"], ["sched", "unit", b.unit], ["sched", "made_ms", "\(b.made)"]]
        if withApp { rows.append(["sched", "app", b.app]) }
        return BillCore.build(BillCore.clsSched, rows, signer: signer, png: Bills.dot)
    }

    /// the schedule as files, for an Android that isn't linked over Bluetooth
    func shareSchedule(_ b: Bill) -> [URL]? {
        guard let f = schedFile(b, withApp: true) else { return nil }
        return write("schedule_" + b.id + ".pngmesh", f)
    }

    func shareBill(_ b: Bill, _ me: String) -> [URL]? {
        guard let d = b.current() else { return nil }
        let left = b.cents - b.helped(d)
        let rows = [["bill", "version", "1"], ["bill", "id", b.id], ["bill", "name", b.name], ["bill", "cents", "\(left)"],
                    ["bill", "currency", b.cur], ["bill", "due", d], ["bill", "occ", d], ["bill", "owner_name", me], ["bill", "made_ms", "\(b.made)"]]
        guard let all = BillCore.build(BillCore.clsBill, rows, signer: signer,
              png: picture("ANA bill", "Help pay: " + b.name, BillCore.money(left, b.cur) + ", due " + d + ". Open with ANA to help. You both earn eFLEX.")) else { return nil }
        b.shared = true
        save()
        return write("bill_" + b.id + "_" + d + ".pngmesh", all)
    }

    func shareReceipt(_ h: Bill, _ me: String) -> [URL]? {
        let o = h.get("help")
        let rows = [["help", "version", "1"], ["help", "id", h.hid], ["help", "bill_id", h.billId], ["help", "occ", h.due], ["help", "owner_key_id", h.ownerKey],
                    ["help", "cents", "\(h.cents)"], ["help", "currency", h.cur], ["help", "proof", o.state], ["help", "note", o.note],
                    ["help", "paid_ms", "\(o.paidAt)"], ["help", "helper_name", me]]
        guard let all = BillCore.build(BillCore.clsHelp, rows, signer: signer,
              png: picture("ANA help receipt", me + " helped pay: " + h.name, BillCore.money(h.cents, h.cur) + ". Open with ANA to confirm.")) else { return nil }
        return write("help_" + h.hid + ".pngmesh", all)
    }

    private func shareThanks(_ b: Bill, _ h: Help) -> [URL]? {
        let rows = [["thanks", "version", "1"], ["thanks", "bill_id", b.id], ["thanks", "help_id", h.hid], ["thanks", "helper_key_id", h.helperKey],
                    ["thanks", "cents", "\(h.cents)"], ["thanks", "currency", b.cur], ["thanks", "confirmed_ms", "\(AnaLog.nowMs())"]]
        guard let all = BillCore.build(BillCore.clsThanks, rows, signer: signer,
              png: picture("ANA thanks", "Thank you: " + b.name, BillCore.money(h.cents, b.cur) + " confirmed. Open with ANA for your eFLEX.")) else { return nil }
        return write("thanks_" + h.hid + ".pngmesh", all)
    }

    // ------------------------------------------------------------------ files arriving (help between people)
    func look(_ s: BillCore.Signed) -> (Bool, String) {
        if !s.ok { return (false, "Not accepted: " + s.why) }
        let me = myKeyId()
        if s.cls == BillCore.clsBill {
            if s.keyId == me { return (false, "That's your own bill. Share it with someone who'll help.") }
            let c = Int64(s.get("bill|cents")) ?? -1
            if c <= 0 { return (false, "The bill has no amount") }
            if list.contains(where: { $0.kind == "help" && $0.billId == s.get("bill|id") && $0.ownerKey == s.keyId && $0.due == s.get("bill|occ") }) {
                return (false, "You're already helping with this bill")
            }
            return (true, s.get("bill|owner_name") + " asks for help with a bill:\n\n" + s.get("bill|name") + "   " + BillCore.money(c, s.get("bill|currency"))
                    + (s.get("bill|due").isEmpty ? "" : "\nDue " + s.get("bill|due"))
                    + "\n\nPay the biller yourself (ANA never handles money). When " + s.get("bill|owner_name") + " confirms you helped, you both earn eFLEX.")
        }
        if s.cls == BillCore.clsHelp {
            guard let b = find(s.get("help|bill_id")), b.kind == "plan" else { return (false, "This receipt is for a bill that isn't on this phone") }
            if s.get("help|owner_key_id") != me { return (false, "This receipt is for someone else's bill") }
            if s.keyId == me { return (false, "You can't help yourself") }
            if seenHelps.contains(s.get("help|id")) { return (false, "Already confirmed") }
            let c = Int64(s.get("help|cents")) ?? -1, d = s.get("help|occ")
            if c <= 0 || c > b.cents - b.helped(d) { return (false, "The amount is more than what's left on the bill") }
            let who = s.get("help|helper_name")
            return (true, who + " says they helped pay " + b.name + (d.isEmpty ? "" : " (due " + d + ")") + ":\n\n" + BillCore.money(c, b.cur)
                    + (s.get("help|proof") == "proven" ? "\nProven by their payment notification" : "\nClaimed (no payment notification)")
                    + "\n" + s.get("help|note") + "\n\nDid " + who + " help you? Confirming sends them a signed thank-you, and you both earn eFLEX.")
        }
        if s.cls == BillCore.clsThanks {
            guard let h = list.first(where: { $0.kind == "help" && $0.hid == s.get("thanks|help_id") }) else {
                return (false, "This thank-you is for help that isn't on this phone")
            }
            if s.keyId != h.ownerKey || s.get("thanks|bill_id") != h.billId { return (false, "Not signed by the bill's owner") }
            if s.get("thanks|helper_key_id") != me { return (false, "This thank-you is for someone else") }
            if h.thanked { return (false, "Already counted") }
            return (true, h.ownerName + " confirmed your help with " + h.name + ": " + BillCore.money(h.cents, h.cur))
        }
        return (false, "That's a bill schedule: it's for ANA on Android")
    }

    func acceptBill(_ s: BillCore.Signed, _ myCents: Int64) -> Bill {
        let h = Bill()
        h.kind = "help"
        h.billId = s.get("bill|id"); h.ownerKey = s.keyId; h.ownerName = BillCore.clean(s.get("bill|owner_name"))
        h.name = BillCore.clean(s.get("bill|name") + " (" + h.ownerName + ")")
        h.cur = s.get("bill|currency"); h.due = s.get("bill|occ")
        h.billCents = Int64(s.get("bill|cents")) ?? 0
        h.cents = max(1, min(myCents, h.billCents))                   // never more than the bill
        h.hid = BillCore.newId()
        lock(h)
        list.insert(h, at: 0)
        save()
        return h
    }

    func confirmHelp(_ s: BillCore.Signed) -> [URL]? {
        guard let b = find(s.get("help|bill_id")) else { return nil }
        var h = Help()
        h.hid = s.get("help|id"); h.helperKey = s.keyId; h.helperName = BillCore.clean(s.get("help|helper_name"))
        h.proof = s.get("help|proof"); h.note = s.get("help|note"); h.occ = s.get("help|occ"); h.cents = Int64(s.get("help|cents")) ?? 0
        h.at = AnaLog.nowMs()
        b.helps.append(h)
        seenHelps.insert(h.hid)
        let pair = Bills.pairOf(myKeyId(), h.helperKey)
        let pts = BillCore.shared(BillCore.points(h.cents, b.cur, BillCore.rHelped), pairCount(pair))
        earn(b.name + ": " + h.helperName + " helped pay " + BillCore.money(h.cents, b.cur), pts, pair)
        save()
        return shareThanks(b, h)
    }

    func thanked(_ s: BillCore.Signed) -> String {
        guard let h = list.first(where: { $0.kind == "help" && $0.hid == s.get("thanks|help_id") }) else { return "Not found" }
        h.thanked = true
        let pair = Bills.pairOf(myKeyId(), h.ownerKey)
        let rate = BillCore.rHelper * (h.get("help").state == "proven" ? 1 : BillCore.claimed)
        let pts = BillCore.shared(BillCore.points(h.cents, h.cur, rate), pairCount(pair))
        h.helpPts = pts
        earn("Helped " + h.ownerName + " pay " + h.name + " (" + BillCore.money(h.cents, h.cur) + ")", pts, pair)
        save()
        return "Thank-you from " + h.ownerName + ": +" + BillCore.pts(pts) + " eFLEX"
    }

    // ------------------------------------------------------------------ words
    static func line(_ b: Bill) -> String {
        let head = BillCore.money(b.cents, b.cur) + "  " + b.name
        if b.kind == "help" {
            let st = b.get("help").state
            return head + " · helping · " + (b.thanked ? "Thanked · " + BillCore.pts(b.helpPts) + " eFLEX" : st == "open" ? "To pay" : st.capitalized + ", send receipt")
        }
        if b.kind == "paid" { return head + " · paid · " + b.get(b.dates()[0]).state.capitalized + (b.pts > 0 ? " · " + BillCore.pts(b.pts) + " eFLEX" : "") }
        let d = b.current()
        if !b.forBill.isEmpty { return head + " · daily · " + (d == nil ? "done" : settled(b.occ[d!]) ? "set aside today" : "set aside today?") }
        return head + " · " + BillCore.repeatWords(b.every, b.unit) + (d == nil ? " · done" : " · settle up " + fmtDue(d!)) + " · " + Bills.shared.ahead(b) + (b.pts > 0 ? " · " + BillCore.pts(b.pts) + " eFLEX" : "")
    }

    static func detail(_ b: Bill, _ appLabel: String) -> String {
        var s = BillCore.money(b.cents, b.cur)
        if b.kind == "plan" && b.forBill.isEmpty {
            let d = b.current()
            s += "\n\nYou've had \(Bills.shared.enjoyed(b)) days of " + b.name + " since the last settle-up." + (d == nil ? "" : " Time to settle up by " + fmtDue(d!) + ".")
            let a = Bills.shared.ahead(b)
            s += "\n" + a.prefix(1).uppercased() + a.dropFirst()
            let sa = Bills.shared.setAside(b)
            if sa > 0 { s += "\nSet aside so far: " + BillCore.money(sa, b.cur) }
        }
        if !b.forBill.isEmpty { s += "\nA little each day, so the settle-up is ready before it's due. It moves your 30-day goal (it earns no eFLEX itself)." }
        if b.kind == "plan" { s += "\nRepeats: " + BillCore.repeatWords(b.every, b.unit) + ", first due " + b.due + " (locked)" }
        if b.kind == "paid" { s += "\nAlready paid (reported after)" }
        if b.kind == "help" { s += "\nYou're helping " + b.ownerName + " (their bill: " + BillCore.money(b.billCents, b.cur) + ", due " + b.due + ")" }
        s += "\nPayment app: " + (b.app.isEmpty ? "not picked yet" : appLabel)
        s += "\nChecked by: " + (b.app.isEmpty ? "nothing yet (pick the payment app)" : b.sentApp == b.app ? "your Android (schedule sent)" : "your Android (sends when linked)")
        let now = AnaLog.nowMs()
        var proven = 0, claimed = 0, missed = 0, shown = 0, rows = ""
        for d in b.dates() {
            let o = b.occ[d]
            var st = o?.state ?? "open"
            if st == "proven" { proven += 1 } else if st == "claimed" { claimed += 1 }
            else if b.kind == "plan" && b.window(d).2 < now { missed += 1; st = "missed" }
            let near = o != nil || b.kind != "plan" || b.window(d).0 <= now + 7 * BillCore.day
            if near && shown < 6 {
                rows += "\n  " + (d == "help" ? "Your payment" : fmtDue(d)) + ": " + st + ((o?.note ?? "").isEmpty ? "" : "  ·  " + o!.note)
                shown += 1
            }
        }
        if b.kind == "plan" && b.dates().count > 1 {
            s += "\n\n\(b.dates().count) due dates in 12 months: \(proven) proven, \(claimed) claimed" + (missed > 0 ? ", \(missed) missed" : "")
        }
        s += "\n" + rows
        if !b.helps.isEmpty {
            s += "\n\nHelped by:"
            for h in b.helps { s += "\n  " + h.helperName + "  " + BillCore.money(h.cents, b.cur) + (h.occ.isEmpty ? "" : "  (" + h.occ + ")") + "  " + h.proof }
        }
        if b.kind == "help" { s += b.thanked ? "\n\nThanked: +" + BillCore.pts(b.helpPts) + " eFLEX" : "\n\nWhen it's paid, send your receipt to " + b.ownerName + ". You earn when they confirm." }
        else if b.pts > 0 { s += "\n\neFLEX earned: " + BillCore.pts(b.pts) }
        return s
    }
}
