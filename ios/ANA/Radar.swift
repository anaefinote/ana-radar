import CoreBluetooth
import Foundation

/// ANA : RADAR — passive discovery of nearby ANA devices. No pairing, no connecting.
///
/// Every ANA device advertises ANA's one service UUID (the same `AndroidLink.service`). RADAR
/// scans for *that* UUID and tallies who's in the room. Discovery lives BENEATH pairing.
///
/// DIRECTIONAL RADAR: each phone also broadcasts a tiny payload — `selfId~name~row` — where the
/// row is its measured RSSI to every peer it hears (peer selfId + 1 char each). Every phone reads
/// everyone's row, assembles the pairwise distance matrix, and classical MDS (in the sketch) turns
/// it into real positions: 2 phones = a line, 3 = a triangle, 4+ = a fence. selfId is 3 hex of the
/// phone's key, so all phones agree on who is who.
///
/// iOS can only broadcast a STRING (the local name), so the payload rides there; Android broadcasts
/// the same bytes in manufacturer data. Each phone reads both channels, so a mixed room meshes.
final class Radar: NSObject, CBCentralManagerDelegate, CBPeripheralManagerDelegate {
    static let shared = Radar()
    static let service = CBUUID(string: "A7A0A001-0E0F-4A4E-8A00-414E41000001")   // ANA_SERVICE, as AndroidLink

    struct Peer {
        let id: UUID
        var selfId: String          // the peer's advertised 3-hex id ("" if an old-format beacon)
        var rssi: Int               // raw last reading
        var smRssi: Int             // smoothed (EMA) — steadier for MDS
        let firstSeen: Date
        var lastSeen: Date
        var name: String
        var row: [String: Int]      // the peer's own measured RSSI to others, keyed by their selfId
    }

    private(set) var peers: [UUID: Peer] = [:]
    private(set) var state = "Off"
    var onChange: (() -> Void)?

    private var central: CBCentralManager?
    private var pm: CBPeripheralManager?
    private var wanted = false
    private var beaconName = ""
    private let fresh: TimeInterval = 15
    private var sweep: Timer?
    private var lastPayload = ""

    /// 3 hex of this phone's key — the stable id every phone agrees on. Random fallback if no key yet.
    private lazy var selfId: String = {
        let h = Chat.shared.myKeyId().lowercased().filter { "0123456789abcdef".contains($0) }
        return h.count >= 3 ? String(h.prefix(3)) : String(format: "%03x", Int.random(in: 0..<4096))
    }()

    // MARK: control

    func setOn(_ on: Bool) {
        wanted = on
        if on {
            if central == nil { central = CBCentralManager(delegate: self, queue: nil) } else { startScan() }
            if pm == nil { pm = CBPeripheralManager(delegate: self, queue: nil) } else { startBeacon() }
        } else {
            central?.stopScan()
            pm?.stopAdvertising()
            peers.removeAll()
            sweep?.invalidate()
            lastPayload = ""
            state = "Off"
            onChange?()
        }
    }

    /// Collapse rotating-address ghosts: one entry per selfId (the freshest). A phone that re-rolls its
    /// BLE address stays ONE device, because selfId is stable.
    private func dedupedById() -> [Peer] {
        var bySelf: [String: Peer] = [:]
        for p in peers.values where !p.selfId.isEmpty {
            if let e = bySelf[p.selfId], e.lastSeen >= p.lastSeen { continue }
            bySelf[p.selfId] = p
        }
        return Array(bySelf.values)
    }

    /// Distinct devices: one per selfId, plus any that haven't announced one yet.
    var count: Int {
        var ids = Set<String>(); var idless = 0
        for p in peers.values { if p.selfId.isEmpty { idless += 1 } else { ids.insert(p.selfId) } }
        return ids.count + idless
    }

    func setName(_ n: String) {
        var nm = n.replacingOccurrences(of: ",", with: " ")
                  .replacingOccurrences(of: ";", with: " ")
                  .replacingOccurrences(of: "~", with: " ")
                  .trimmingCharacters(in: .whitespacesAndNewlines)
        if nm == "Me" { nm = "" }
        if nm.count > 10 { nm = String(nm.prefix(10)) }
        beaconName = nm
        refreshBeacon()
    }

    private func cleanName(_ s: String) -> String {
        if s == "ANA" || s == "ANA device" { return "" }
        return s.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: ";", with: " ")
    }

    // MARK: payload encoding (shared byte-for-byte with Android)
    // "selfId(3) ~ name(<=6, no ~) ~ [peerId(3) + rssiChar]..."  rssiChar: clamp[-100,-40] -> '!'..']'

    private func encRssi(_ r: Int) -> Character { Character(UnicodeScalar(UInt8(33 + max(0, min(60, -r - 40))))) }
    private func decRssi(_ c: Character) -> Int { -(Int(c.asciiValue ?? 33) - 33) - 40 }

    private func packPayload() -> String {
        var s = selfId + "~" + String(cleanName(beaconName).prefix(5)) + "~"
        let mine = dedupedById().sorted { $0.smRssi > $1.smRssi }.prefix(4)
        for p in mine { s += p.selfId + String(encRssi(p.smRssi)) }
        return s
    }

    private func parsePayload(_ s: String) -> (String, String, [String: Int])? {
        let parts = s.components(separatedBy: "~")
        guard parts.count >= 3, parts[0].count == 3 else { return nil }
        let sid = parts[0], name = parts[1]
        let body = Array(parts[2...].joined(separator: "~"))
        var row: [String: Int] = [:]
        var i = 0
        while i + 4 <= body.count {
            row[String(body[i..<i+3])] = decRssi(body[i+3])
            i += 4
        }
        return (sid, name, row)
    }

    /// snapshot-v2:  "count \t id,rssi,age,name;…  \t  matrixRow;matrixRow;…"
    /// matrix node 0 = this phone; nodes 1..k = peers (deterministic selfId order). Values are RSSI.
    func snapshot() -> String {
        let now = Date()
        let withId = dedupedById()
        let ordered = withId.sorted { $0.selfId < $1.selfId }
        let listed = withId.sorted { $0.smRssi > $1.smRssi }
        let peerRows = listed.map { p in
            "\(p.selfId),\(p.smRssi),\(Int(now.timeIntervalSince(p.lastSeen))),\(cleanName(p.name))"
        }.joined(separator: ";")

        let ids = [selfId] + ordered.map { $0.selfId }
        let n = ids.count
        func rowVal(_ node: Int, _ otherId: String) -> Int? {
            node == 0 ? peers.values.first(where: { $0.selfId == otherId })?.smRssi : ordered[node-1].row[otherId]
        }
        func between(_ a: Int, _ b: Int) -> Int {
            if a == b { return 0 }
            let ab = rowVal(a, ids[b]), ba = rowVal(b, ids[a])
            if let x = ab, let y = ba { return (x + y) / 2 }
            return ab ?? ba ?? 0
        }
        var mrows: [String] = []
        for i in 0..<n {
            var r: [String] = []
            for j in 0..<n { r.append(String(between(i, j))) }
            mrows.append(r.joined(separator: ","))
        }
        let mtx = n >= 2 ? mrows.joined(separator: ";") : ""
        return "\(peers.count)\t\(peerRows)\t\(mtx)"
    }

    // MARK: scanning (see the room)

    private func startScan() {
        guard wanted, let c = central, c.state == .poweredOn else { return }
        c.scanForPeripherals(withServices: [Radar.service],
                             options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        state = "Listening for ANA devices nearby"
        sweep?.invalidate()
        sweep = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.expire(); self?.refreshBeacon()
        }
    }

    private func expire() {
        let cut = Date().addingTimeInterval(-fresh)
        let before = peers.count
        peers = peers.filter { $0.value.lastSeen >= cut }
        if peers.count != before { onChange?() }
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:   startScan()
        case .poweredOff:  state = "Bluetooth is off"; peers.removeAll(); onChange?()
        case .unauthorized: state = "Bluetooth isn't allowed for ANA: Settings > ANA > Bluetooth"
        case .unsupported: state = "This device has no Bluetooth LE"
        default: break
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let now = Date()
        // read the payload from the local name (iPhones) or manufacturer data (Android)
        var raw = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        if raw == nil || raw == "ANA",
           let md = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, md.count > 2 {
            raw = String(data: md.subdata(in: 2..<md.count), encoding: .utf8)
        }
        var sid = "", nm = "", prow: [String: Int] = [:]
        if let s = raw, let parsed = parsePayload(s) { sid = parsed.0; nm = parsed.1; prow = parsed.2 }
        else { nm = raw ?? "" }                        // old-format beacon: plain name, no matrix row
        let resolved = cleanName(nm).isEmpty ? (p.name ?? "ANA device") : cleanName(nm)
        let r = RSSI.intValue

        if var peer = peers[p.identifier] {
            peer.rssi = r
            peer.smRssi = Int(0.6 * Double(peer.smRssi) + 0.4 * Double(r))   // EMA smoothing
            peer.lastSeen = now; peer.name = resolved
            if !sid.isEmpty { peer.selfId = sid; peer.row = prow }
            peers[p.identifier] = peer
        } else {
            peers[p.identifier] = Peer(id: p.identifier, selfId: sid, rssi: r, smRssi: r,
                                       firstSeen: now, lastSeen: now, name: resolved, row: prow)
            onChange?()
        }
    }

    // MARK: beacon (be seen) — payload in the local name, refreshed as the row changes

    private func startBeacon() {
        guard wanted, let pm = pm, pm.state == .poweredOn, !pm.isAdvertising else { return }
        let payload = packPayload()
        lastPayload = payload
        pm.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Radar.service],
            CBAdvertisementDataLocalNameKey: payload.isEmpty ? "ANA" : payload
        ])
    }

    private func refreshBeacon() {
        guard wanted, let pm = pm, pm.state == .poweredOn else { return }
        let payload = packPayload()
        if payload != lastPayload {
            pm.stopAdvertising()
            lastPayload = payload
            pm.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [Radar.service],
                CBAdvertisementDataLocalNameKey: payload.isEmpty ? "ANA" : payload
            ])
        }
    }

    func peripheralManagerDidUpdateState(_ pm: CBPeripheralManager) {
        if pm.state == .poweredOn { startBeacon() }
    }
}
