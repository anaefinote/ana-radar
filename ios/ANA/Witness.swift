import UIKit
import CryptoKit

/// The signed witness of an ownership proof (choice A): when a wallet goes Proven, this phone writes one
/// class 22 pngmesh holding the proof, signed with the phone's own P-256 key the Spec's way (raw 65-byte key,
/// raw low-S signature over "ANA-PMSH1|22|" || sha256(body)). Rows and checks: spec/py/proof_witness.py.
///
/// Saved to Documents/proofs/ (Files app: On My iPhone > ANA > proofs) with its .sha256 sidecar.
/// It shows which phone saw the proof and that nothing in it changed since. Mesh Rule v2 takes it over later.
enum Witness {
    static let cls: Int32 = 22
    static let fields = ["version", "coin", "address", "direction", "units", "amount", "txid", "block_time",
                         "notified_ms", "app", "via", "party", "note"]

    static var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("proofs")
    }

    static func fileName(_ w: Wallets.Wallet) -> String? {
        guard let d = w.proofDetail, let tx = d["txid"], !tx.isEmpty else { return nil }
        return "proof_" + (d["coin"] ?? "COIN") + "_" + String(tx.prefix(12)) + ".pngmesh"
    }

    static func exists(_ w: Wallets.Wallet) -> Bool {
        guard let n = fileName(w) else { return true }      // nothing to write
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent(n).path)
    }

    /// Writes the witness for this wallet's proof; returns the file name, or nil if it couldn't sign.
    @discardableResult
    static func save(_ w: Wallets.Wallet) -> String? {
        guard var d = w.proofDetail, let tx = d["txid"], !tx.isEmpty else { return nil }
        d["version"] = "1"
        var rows: [[String]] = fields.map { ["proof", $0, d[$0] ?? ""] }
        // the phone's key goes in before signing, so the signature covers it; sign once to learn the key
        guard let probe = Flex.signRaw(Data("probe".utf8)) else { return nil }
        let pubHex = hex(probe.pub)
        rows.append(["phone", "key", pubHex])
        rows.append(["sig", "key_id", hex(Data(SHA256.hash(data: probe.pub)))])
        let total = rows.count + 1
        let body = trailerPrefix(rows, total)
        var msg = Data("ANA-PMSH1|\(cls)|".utf8)
        msg.append(Data(SHA256.hash(data: body)))
        guard let signed = Flex.signRaw(msg), signed.pub == probe.pub else { return nil }
        var t = body
        putStr(&t, "sig"); putStr(&t, "value"); putStr(&t, hex(signed.sig))

        let pic = [["WATCH", AnaLog.when(Int64(Date().timeIntervalSince1970 * 1000)), "", "ana.watch",
                    "Ownership proven", d["note"] ?? ""]]
        var file = AnaMesh.preview(pic, head: "ANA ownership witness").pngData() ?? Data()
        file.append(t)
        putLong(&file, Int64(t.count))

        guard let name = fileName(w) else { return nil }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try file.write(to: dir.appendingPathComponent(name))
            try AnaMesh.sidecar(name: name, mesh: file).data(using: .utf8)?
                .write(to: dir.appendingPathComponent(String(name.dropLast(".pngmesh".count)) + ".sha256"))
        } catch { return nil }
        return name
    }

    // ------------------------------------------------------------------ the container (Spec section 2)
    private static func trailerPrefix(_ rows: [[String]], _ total: Int) -> Data {
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

    private static func putLong(_ d: inout Data, _ v: Int64) {
        let u = UInt64(bitPattern: v)
        for s in stride(from: 56, through: 0, by: -8) { d.append(UInt8(u >> UInt64(s) & 255)) }
    }

    private static func putStr(_ d: inout Data, _ s: String) {
        let b = Array(s.utf8)
        putInt(&d, Int32(b.count))
        d.append(contentsOf: b)
    }

    private static func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
}
