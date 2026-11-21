import Foundation

// Runs every scenario in spec/vectors/vectors.json through the iPhone's AnaRule.swift (a fresh phone per
// scenario) and compares each verdict. GitHub runs this on every build: the app is built only if all pass.
//   swiftc ios/ANA/AnaRule.swift ios/tests/main.swift -o rv && ./rv spec/vectors
let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "spec/vectors")
let doc = try! JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("vectors.json"))) as! [String: Any]
let trusted = doc["trusted_raw"] as! [String]
let builds = doc["builds"] as! [String: [String: Any]]
var total = 0, fails = 0
for sc in doc["scenarios"] as! [[String: Any]] {
    let b = builds[sc["build"] as! String]!
    let phone = AnaRule(reader: (b["reader"] as! NSNumber).intValue, tier: b["tier"] as! String, hives: b["hives"] as! [String], trustedRawHex: trusted)
    for st in sc["steps"] as! [[String: Any]] {
        let name = st["file"] as! String
        let f = (try? Data(contentsOf: dir.appendingPathComponent(name))) ?? Data()
        let side = try? Data(contentsOf: dir.appendingPathComponent(name + ".sha256"))
        let got = phone.check(f, side)
        let ok = got.0 == (st["expect"] as! String)
        total += 1
        if !ok { fails += 1 }
        print((ok ? "ok   " : "FAIL ") + (sc["name"] as! String).padding(toLength: 26, withPad: " ", startingAt: 0)
              + name.padding(toLength: 37, withPad: " ", startingAt: 0) + got.0 + (ok ? "" : "  expected \(st["expect"]!)  \(got.1)"))
    }
}
print("swift: \(total - fails)/\(total) verdicts as expected")
exit(fails == 0 ? 0 : 1)
