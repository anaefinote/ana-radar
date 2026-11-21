import CoreBluetooth
import Foundation

/// ANA : RADAR — passive discovery of nearby ANA devices. No pairing, no connecting.
///
/// Every ANA device advertises ANA's one service UUID (the same `AndroidLink.service`). RADAR
/// scans for *that* UUID and tallies who's in the room: how many ANA devices, how strong each
/// signal, how fresh. Discovery lives BENEATH pairing — knowing a device is there needs no
/// connection. The relay (AndroidLink) still connects when a payload actually moves; RADAR only
/// answers "who's here, right now."
///
/// Division of labour, forced by iOS and matching the rest of ANA:
///  - iOS is a strong SCANNER: scanning for a known UUID works foreground AND background. ✅
///  - iOS is a weak ADVERTISER: CoreBluetooth won't attach a custom payload, and in the background
///    it hides the UUID in an "overflow" area only other iPhones scanning for it can read, and drops
///    the name. Foreground an iPhone advertises fine. Android advertises freely, always.
///  So: Android devices are the rich always-on beacons; iPhones read the room and announce their
///  presence best-effort (strongest in foreground). Same shape as the ANCS relay — Android the
///  capable node, iPhone the reader.
final class Radar: NSObject, CBCentralManagerDelegate, CBPeripheralManagerDelegate {
    static let shared = Radar()
    static let service = CBUUID(string: "A7A0A001-0E0F-4A4E-8A00-414E41000001")   // ANA_SERVICE, as AndroidLink

    struct Peer {
        let id: UUID
        var rssi: Int
        let firstSeen: Date
        var lastSeen: Date
        var name: String
    }

    private(set) var peers: [UUID: Peer] = [:]
    private(set) var state = "Off"
    /// Called (main queue) when the set of nearby devices changes — the sketch repaints the globe.
    var onChange: (() -> Void)?

    private var central: CBCentralManager?
    private var pm: CBPeripheralManager?
    private var wanted = false
    private let fresh: TimeInterval = 15          // a peer counts as "here" if heard within this many seconds
    private var sweep: Timer?

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
            state = "Off"
            onChange?()
        }
    }

    /// How many ANA devices are in the room right now.
    var count: Int { peers.count }

    /// A compact line for the bridge/sketch:  "count\tid8,rssi,ageSec;id8,rssi,ageSec;…"  (strongest first)
    func snapshot() -> String {
        let now = Date()
        let rows = peers.values.sorted { $0.rssi > $1.rssi }.map {
            "\($0.id.uuidString.prefix(8)),\($0.rssi),\(Int(now.timeIntervalSince($0.lastSeen)))"
        }
        return "\(peers.count)\t" + rows.joined(separator: ";")
    }

    // MARK: scanning (see the room)

    private func startScan() {
        guard wanted, let c = central, c.state == .poweredOn else { return }
        // allowDuplicates keeps RSSI + last-seen live (foreground; iOS throttles it in the background,
        // which is fine — in the background we only need presence, not a live signal meter).
        c.scanForPeripherals(withServices: [Radar.service],
                             options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        state = "Listening for ANA devices nearby"
        sweep?.invalidate()
        sweep = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.expire() }
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
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? "ANA device"
        if var peer = peers[p.identifier] {
            peer.rssi = RSSI.intValue; peer.lastSeen = now; peer.name = name
            peers[p.identifier] = peer
        } else {
            peers[p.identifier] = Peer(id: p.identifier, rssi: RSSI.intValue, firstSeen: now, lastSeen: now, name: name)
            onChange?()
        }
    }

    // MARK: beacon (be seen) — best-effort on iOS, see the note at the top

    private func startBeacon() {
        guard wanted, let pm = pm, pm.state == .poweredOn, !pm.isAdvertising else { return }
        pm.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Radar.service],
            CBAdvertisementDataLocalNameKey: "ANA"
        ])
    }

    func peripheralManagerDidUpdateState(_ pm: CBPeripheralManager) {
        if pm.state == .poweredOn { startBeacon() }
    }
}
