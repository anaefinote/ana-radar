import UIKit
import CryptoKit

/// ANA entries as a .pngmesh: the same container as the Android app (AnaMesh.java) and the owner's 3D pngmesh
/// files, so a file made here opens there and the other way round:
///
///     [ a normal PNG ...IEND ]  [ trailer ]  [ trailer length: int64 big-endian ]
///
///     trailer:  "PMSH"  int32 version (1)  int32 parts (1)
///               part:   int32 class (20 = ANA entries, 21 = GST packs; 3D meshes use 3)
///                       int32 columns, then each column name   (string = int32 byte length + UTF-8 bytes)
///                       int32 rows,    then each row's values   (the log's columns)
///
/// The PNG in front is a picture of the entries, so the file still opens as an image anywhere.
/// The sidecar <name>.sha256 holds:  sha256-hex \n name \n byte-length \n   (readers check only the first line).
/// A .pngmesh is only read if its sidecar's hash matches.
enum AnaMesh {
    static let version: Int32 = 1
    static let classAnaEntries: Int32 = 20
    static let cols = ["src", "when", "postMs", "package", "title", "text", "key", "lagMs", "eventMs"]
    /// GST (Group Spend Technology) packs: invites, shared balances, spend alerts, turns, group buys, pledges.
    /// One row per pack; a, b, c, d depend on the kind (Gst.pde in the sketch reads and writes them).
    static let classGst: Int32 = 21
    static let gstCols = ["id", "kind", "group", "from", "fromName", "when", "a", "b", "c", "d"]

    /// Round-Trip (lesson L2): a fresh, nonce-unique proof body the human carries out through an app
    /// (WhatsApp) and back. The only thing that matters is that the exact bytes return — the body rides
    /// inside so the file is a valid .pngmesh, but the proof is the byte-match on its sha256.
    static let classRoundTrip: Int32 = 24
    static let rtCols = ["body"]
    static func writeRoundTrip(_ body: String) -> Data {
        write(classRoundTrip, rtCols, [[body]], [[]], "ANA round-trip")
    }

    /// Fence seal (v0.3): a signed roster of who was inside a fence over its window, carried as a
    /// .pngmesh so it can be shared and verified later. The payload rides in a single row.
    static let classSeal: Int32 = 25
    static let sealCols = ["seal"]
    static func writeSeal(_ body: String) -> Data {
        write(classSeal, sealCols, [[body]], [[]], "ANA fence seal")
    }

    struct Failure: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    // ---------------------------------------------------------------------------------------------- write
    static func write(_ rows: [[String]]) -> Data {
        write(classAnaEntries, cols, rows, rows, nil)
    }

    /// GST packs; the picture shows them as cards (pics: src, when, -, package, title, text)
    static func writeGst(_ rows: [[String]], pics: [[String]], head: String) -> Data {
        write(classGst, gstCols, rows, pics, head)
    }

    private static func write(_ cls: Int32, _ cols: [String], _ rows: [[String]], _ pics: [[String]], _ head: String?) -> Data {
        var file = preview(pics, head: head).pngData() ?? Data()
        var t = Data()
        t.append(contentsOf: Array("PMSH".utf8))
        putInt(&t, version)
        putInt(&t, 1)
        putInt(&t, cls)
        putInt(&t, Int32(cols.count))
        for c in cols { putStr(&t, c) }
        putInt(&t, Int32(rows.count))
        for r in rows {
            for i in 0..<cols.count { putStr(&t, i < r.count ? r[i] : "") }
        }
        file.append(t)
        putLong(&file, Int64(t.count))
        return file
    }

    private static func putInt(_ d: inout Data, _ v: Int32) {
        let u = UInt32(bitPattern: v)
        d.append(contentsOf: [UInt8(u >> 24 & 255), UInt8(u >> 16 & 255), UInt8(u >> 8 & 255), UInt8(u & 255)])
    }

    private static func putLong(_ d: inout Data, _ v: Int64) {
        let u = UInt64(bitPattern: v)
        var b = [UInt8]()
        for s in stride(from: 56, through: 0, by: -8) { b.append(UInt8(u >> UInt64(s) & 255)) }
        d.append(contentsOf: b)
    }

    private static func putStr(_ d: inout Data, _ s: String) {
        let b = Array(s.utf8)
        putInt(&d, Int32(b.count))
        d.append(contentsOf: b)
    }

    static func sidecar(name: String, mesh: Data) -> String {
        sha256(mesh) + "\n" + name + "\n" + String(mesh.count) + "\n"
    }

    static func sha256(_ d: Data) -> String {
        SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    // ---------------------------------------------------------------------------------------------- read
    private struct Reader {
        let b: [UInt8]
        var p: Int

        mutating func int32() throws -> Int32 {
            guard p + 4 <= b.count else { throw Failure(reason: "damaged pngmesh") }
            var v: UInt32 = 0
            for i in 0..<4 { v = (v << 8) | UInt32(b[p + i]) }
            p += 4
            return Int32(bitPattern: v)
        }

        mutating func str() throws -> String {
            let n = Int(try int32())
            guard n >= 0, n <= (1 << 24), p + n <= b.count else { throw Failure(reason: "damaged string in pngmesh") }
            let s = String(decoding: b[p..<(p + n)], as: UTF8.self)
            p += n
            return s
        }
    }

    private static func trailerStart(_ b: [UInt8]) -> Int? {
        guard b.count >= 20 else { return nil }
        var v: UInt64 = 0
        for i in (b.count - 8)..<b.count { v = (v << 8) | UInt64(b[i]) }
        let tl = Int64(bitPattern: v)
        guard tl >= 12, tl <= Int64(b.count - 8) else { return nil }
        return b.count - 8 - Int(tl)
    }

    /// true if the bytes end in a pngmesh trailer (whatever the file is called)
    static func looksLikePngmesh(_ d: Data) -> Bool {
        let b = [UInt8](d)
        guard let s = trailerStart(b) else { return false }
        return b[s] == 0x50 && b[s + 1] == 0x4D && b[s + 2] == 0x53 && b[s + 3] == 0x48     // "PMSH"
    }

    /// The rows (in the log's column order), or throws with the reason the file is not an ANA .pngmesh.
    static func read(_ d: Data) throws -> [[String]] {
        try read(d, want: classAnaEntries, wantCols: cols)
    }

    /// GST packs, in gstCols order
    static func readGst(_ d: Data) throws -> [[String]] {
        try read(d, want: classGst, wantCols: gstCols)
    }

    /// the first part's class (20 ANA entries, 21 GST), or -1 if it can't be read
    static func classOf(_ d: Data) -> Int32 {
        let b = [UInt8](d)
        guard let start = trailerStart(b), start + 16 <= b.count else { return -1 }
        var r = Reader(b: b, p: start + 12)
        return (try? r.int32()) ?? -1
    }

    private static func read(_ d: Data, want: Int32, wantCols: [String]) throws -> [[String]] {
        let b = [UInt8](d)
        guard let start = trailerStart(b) else { throw Failure(reason: "no pngmesh trailer") }
        var r = Reader(b: b, p: start)
        guard b[start] == 0x50 && b[start + 1] == 0x4D && b[start + 2] == 0x53 && b[start + 3] == 0x48 else {
            throw Failure(reason: "not a pngmesh trailer")
        }
        r.p += 4
        let ver = try r.int32()
        if ver != version { throw Failure(reason: "pngmesh version \(ver) is newer than this ANA") }
        let parts = try r.int32()
        var rows = [[String]]()
        for _ in 0..<max(0, Int(parts)) {
            let cls = try r.int32()
            if cls == 3 { throw Failure(reason: "this .pngmesh holds a 3D shape, not ANA entries") }
            if cls != want {
                throw Failure(reason: cls == classGst ? "this .pngmesh is a GST file"
                              : cls == classAnaEntries ? "this .pngmesh holds log entries, not GST" : "unknown pngmesh part class \(cls)")
            }
            let nc = Int(try r.int32())
            guard nc >= 0, nc < 1000 else { throw Failure(reason: "damaged pngmesh") }
            var names = [String]()
            for _ in 0..<nc { names.append(try r.str()) }
            let nr = Int(try r.int32())
            guard nr >= 0 else { throw Failure(reason: "damaged pngmesh") }
            for _ in 0..<nr {
                var v = [String]()
                for _ in 0..<nc { v.append(try r.str()) }
                // by column name, so a later file with more columns still reads
                var out = [String]()
                for c in wantCols {
                    if let i = names.firstIndex(of: c) { out.append(v[i]) } else { out.append("") }
                }
                rows.append(out)
            }
        }
        return rows
    }

    /// the hash on a sidecar's first line, or nil if this isn't a sidecar
    static func sidecarHash(_ d: Data) -> String? {
        guard d.count <= 4096, let s = String(data: d, encoding: .utf8) else { return nil }
        let first = (s.components(separatedBy: "\n").first ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return first.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil ? first : nil
    }

    // ---------------------------------------------------------------------------------------------- picture
    // The entries drawn like the sketch's cards (the same colours as the Android app), 1080 px wide.
    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> UIColor {
        UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
    private static let bg = rgb(0x0E, 0x16, 0x21), card = rgb(0x18, 0x21, 0x2D), cardE = rgb(0x16, 0x32, 0x4A)
    private static let ink = rgb(0xE8, 0xEE, 0xF5), mute = rgb(0x8F, 0xA3, 0xB8), dim = rgb(0x5F, 0x73, 0x88), body = rgb(0xB9, 0xC7, 0xD6)
    private static let maxDrawn = 40

    private static func tagColor(_ src: String) -> UIColor {
        switch src {
        case "LIVE": return rgb(0x3D, 0xDC, 0x97)
        case "SCAN": return rgb(0x4D, 0xA3, 0xFF)
        case "MANUAL": return rgb(0xF5, 0xB9, 0x42)
        case "IMPORT": return rgb(0xB4, 0x8C, 0xFF)
        case "GST": return rgb(0x3D, 0xDC, 0x97)
        default: return rgb(0x7A, 0x8B, 0xA0)
        }
    }

    /// text with its baseline at y (as Android's drawText), cut with … to fit w
    private static func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ c: UIColor, _ w: CGFloat = 4000) {
        let font = UIFont.systemFont(ofSize: size)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let r = CGRect(x: x, y: y - font.ascender, width: w, height: font.lineHeight + 2)
        (s as NSString).draw(in: r, withAttributes: [.font: font, .foregroundColor: c, .paragraphStyle: para])
    }

    static func preview(_ rows: [[String]], head head0: String? = nil) -> UIImage {
        let u: CGFloat = 1080 / 480, ch = 120 * u, head = 70 * u
        let drawn = min(rows.count, maxDrawn)
        let h = head + CGFloat(drawn) * ch + (rows.count > drawn ? 40 * u : 0) + 10 * u
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let size = CGSize(width: 1080, height: ceil(h))
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            bg.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            text(head0 != nil && !(head0 ?? "").hasPrefix("ANA") ? "GST" : "ANA", 14 * u, 34 * u, 24 * u, ink)   // GST packs; witnesses say ANA
            let sub: String = head0 != nil ? (head0 ?? "") + "  ·  .pngmesh  ·  check with its .sha256"
                : "\(rows.count) entr\(rows.count == 1 ? "y" : "ies")  ·  .pngmesh  ·  check with its .sha256"
            text(sub, 74 * u, 32 * u, 13 * u, mute)
            let w = 1080 - 24 * u
            for i in 0..<drawn {
                let r = rows[i] + Array(repeating: "", count: max(0, 9 - rows[i].count))
                let x = 12 * u, y = head + CGFloat(i) * ch
                let all = (r[3] + " " + r[4] + " " + r[5]).lowercased()
                (all.contains("ether") ? cardE : card).setFill()
                ctx.fill(CGRect(x: x, y: y, width: w, height: ch - 8 * u))
                tagColor(r[0]).setFill()
                ctx.fill(CGRect(x: x, y: y, width: 6 * u, height: ch - 8 * u))
                text(r[0], x + 16 * u, y + 21 * u, 13 * u, tagColor(r[0]))
                text(r[1], x + 170 * u, y + 21 * u, 13 * u, mute)
                text(r[3], x + 16 * u, y + 40 * u, 12 * u, dim, w - 24 * u)
                text(r[4], x + 16 * u, y + 61 * u, 15 * u, ink, w - 24 * u)
                text(r[5], x + 16 * u, y + 84 * u, 13 * u, body, w - 24 * u)
            }
            if rows.count > drawn {
                text("+ \(rows.count - drawn) more in the file", 14 * u, head + CGFloat(drawn) * ch + 26 * u, 13 * u, mute)
            }
        }
    }
}
