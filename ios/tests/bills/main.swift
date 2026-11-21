import Foundation
import CryptoKit

// BILLS: the iPhone's BillCore checked against files Android's BillCore.java made (spec/bills_vectors),
// and its own files read back. Same amounts, points and matching cases as Android's test.
var fails = 0
func ok(_ c: Bool, _ what: String) { print((c ? "ok   " : "FAIL ") + what); if !c { fails += 1 } }

ok(BillCore.cents("125") == 12500 && BillCore.cents("1,250.00") == 125000 && BillCore.cents("$12.5") == 1250 && BillCore.cents("12.345") == -1, "cents()")
ok(BillCore.amountsIn("Payment of BBD 125.00 to Light & Power on 19/11/2026") == [12500], "amountsIn: BBD 125.00, date skipped")
ok(BillCore.amountsIn("You paid $1,250.00. Balance $3,004.17") == [125000, 300417], "amountsIn: two amounts with commas")
ok(BillCore.amountsIn("Ref 2026 item 45").isEmpty, "amountsIn: bare numbers skipped")
ok(BillCore.amountsIn("Paid $60 to BWA") == [6000], "amountsIn: $60")
ok(BillCore.money(125000, "BBD") == "BBD 1,250.00" && BillCore.money(5, "USD") == "USD 0.05", "money()")
ok(BillCore.points(12500, "BBD", BillCore.rPlan) == 62.5, "BBD 125 on time = 62.5 eFLEX")
ok(BillCore.points(12500, "BBD", BillCore.rPlan * BillCore.claimed) == 15.625, "claimed = quarter")
ok(BillCore.points(350, "BBD", BillCore.rPlan * BillCore.claimed) == 0.437, "bus fare claimed = 0.437 (as Android)")
ok(BillCore.shared(50, 2) == 25 && abs(BillCore.shared(50, 3) - 16.666) < 1e-9, "pair repeats divide")
ok(BillCore.pts(62.5) == "62.5" && BillCore.pts(0.437) == "0.44" && BillCore.pts(3) == "3", "pts() words")
let mo = BillCore.schedule("2026-01-31", 1, "month")
ok(mo.count == 13 && mo[1] == "2026-02-28" && mo[2] == "2026-03-31" && mo[12] == "2027-01-31", "monthly from Jan 31 (as Android): \(mo.prefix(3))")
ok(BillCore.schedule("2026-11-20", 1, "day").count == 366, "daily: 366")
ok(BillCore.schedule("2026-11-20", 2, "week").count == 27, "every 2 weeks: 27")
ok(BillCore.schedule("2026-11-20", 1, "year").count == 2 && BillCore.schedule("2026-11-20", 0, "month").count == 1, "yearly 2, once 1")
ok(BillCore.schedule("2026-11-20", 10, "day")[1] == "2026-11-30", "every 10 days")
ok(BillCore.schedule("2028-02-29", 1, "year") == ["2028-02-29", "2029-02-28"] && BillCore.cal("2027-02-30") == nil, "Feb 29 yearly; 30 Feb refused (as Android)")
ok(BillCore.clean("Light\tbill\n\u{1f}x") == "Light bill x" && BillCore.clean(String(repeating: "x", count: 300)).count == 80, "names cleaned (as Android)")
ok(BillCore.repeatWords(1, "day") == "daily" && BillCore.repeatWords(3, "month") == "every 3 months", "repeat words")
let wm = BillCore.window("2026-12-20", 1, "month", 0), wd = BillCore.window("2026-12-20", 1, "day", 0)
ok(wm.1 - wm.0 == 30 * BillCore.day && wm.2 - wm.1 == 7 * BillCore.day && wd.1 - wd.0 == BillCore.day, "windows (as Android)")
let t0: Int64 = 1_763_500_000_000
let notes = [BillCore.Note(src: "IPHONE", at: t0 + 1000, pkg: "bank.app", title: "Payment sent", text: "BBD 125.00 to BL&P", key: "k1"),
             BillCore.Note(src: "IPHONE", at: t0 + 3000, pkg: "bank.app", title: "Payment sent", text: "BBD 125.00 to BWA", key: "k3")]
ok(BillCore.match(notes, "bank.app", 12500, t0, t0 + 10000, [])?.key == "k1", "match: earliest")
ok(BillCore.match(notes, "bank.app", 12500, t0, t0 + 10000, ["k1"])?.key == "k3", "match: used skipped")
ok(BillCore.match(notes, "bank.app", 12600, t0, t0 + 10000, []) == nil, "match: wrong amount")

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
func file(_ n: String) -> Data { (try? Data(contentsOf: dir.appendingPathComponent(n))) ?? Data() }
let b = BillCore.read(file("bill_40.pngmesh")), h = BillCore.read(file("help_41.pngmesh")), th = BillCore.read(file("thanks_42.pngmesh"))
ok(b.ok && b.cls == 40 && b.get("bill|name") == "Light bill" && b.get("bill|cents") == "12500", "Android bill file reads on iPhone " + b.why)
ok(h.ok && h.cls == 41 && h.get("help|owner_key_id") == b.keyId && h.keyId != b.keyId, "Android help receipt " + h.why)
ok(th.ok && th.keyId == b.keyId && th.get("thanks|helper_key_id") == h.keyId, "Android thank-you, signed by the owner " + th.why)
let bad = BillCore.read(file("bill_40_changed.pngmesh"))
ok(!bad.ok && bad.why.contains("signature"), "changed bill refused: " + bad.why)
ok(BillCore.classOf(file("help_41.pngmesh")) == 41, "classOf")
let sc = BillCore.read(file("sched_43.pngmesh")), pd = BillCore.read(file("paid_44.pngmesh"))
ok(sc.ok && sc.cls == 43 && sc.get("sched|unit") == "day", "schedule (43) reads on iPhone " + sc.why)
ok(pd.ok && pd.cls == 44 && pd.get("paid|owner_key_id") == sc.keyId, "Android's paid confirmation (44) reads on iPhone " + pd.why)
let ch = BillCore.read(file("chat_46.pngmesh"))
ok(ch.ok && ch.cls == 46 && ch.get("chat|text") == "hello from the J5" && ch.get("chat|name") == "Karl", "CHATNOTE: Android's signed message (46) reads on iPhone " + ch.why)
var chBad = file("chat_46.pngmesh"); chBad[chBad.count / 2] ^= 1
ok(!BillCore.read(chBad).ok, "CHATNOTE: a changed message is refused")
ok(BillCore.clean500("hi\tthere\nfriend") == "hi there\nfriend", "CHATNOTE: text cleaned, new lines kept")
let jr = BillCore.read(file("journey_45.pngmesh"))
ok(jr.ok && jr.cls == 45 && jr.get("journey|bill0").components(separatedBy: "\u{1f}").count == 5 && jr.keyId == b.keyId, "Android journey (45) reads on iPhone " + jr.why)

// the iPhone's own file, read back (a software key; on the phone it's the Secure Enclave-backed key)
let k = P256.Signing.PrivateKey()
let signer: BillCore.Signer = { msg in
    for _ in 0..<64 {                                          // keep a low-S signature, as the Spec wants
        guard let s = try? k.signature(for: msg) else { return nil }
        let raw = s.rawRepresentation
        if BillCore.verify(k.publicKey.x963Representation, msg, raw) { return (k.publicKey.x963Representation, raw) }
    }
    return nil
}
if let mine = BillCore.build(BillCore.clsBill, [["bill", "version", "1"], ["bill", "id", "abc"], ["bill", "name", "Water"], ["bill", "cents", "6000"],
                                                ["bill", "currency", "BBD"], ["bill", "due", "2026-11-30"], ["bill", "owner_name", "T"], ["bill", "made_ms", "1"]],
                             signer: signer, png: file("bill_40.pngmesh").prefix(64)) {
    let r = BillCore.read(mine)
    ok(r.ok && r.get("bill|name") == "Water", "iPhone-made bill reads back " + r.why)
    try? mine.write(to: URL(fileURLWithPath: "/tmp/iphone_bill_40.pngmesh"))
} else { ok(false, "iPhone-made bill") }
print(fails == 0 ? "ALL PASS" : "\(fails) FAILED")
exit(fails == 0 ? 0 : 1)
