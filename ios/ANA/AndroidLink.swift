import CoreBluetooth
import Foundation

/// Shares this iPhone's notifications with ANA on Android, over Bluetooth.
///
/// iOS itself sends the notifications: every iPhone publishes the Apple Notification Center Service (ANCS) to
/// the Bluetooth accessories it's paired with, the way smartwatches get them. ANA on Android plays that
/// accessory (AncsLink.java). This app's one job is the connection: it finds ANA on Android (which advertises
/// ANA's own service), connects, and keeps the link up. Once connected, ANA on Android pairs (the iPhone asks
/// to accept) and subscribes to ANCS; from then on iOS streams every notification to it.
///
/// The relay: ANA on Android sends every iPhone notification it receives straight back here (ANA_RELAY, one
/// line per notification: the log's columns, a tab, the app's name, "\n"), so this app's log has them all,
/// something iOS doesn't let an app do by itself. On (re)connecting it writes "since:<ms>" to ANA_CONTROL and
/// gets what it missed; "clear:<key>" asks ANA on Android to dismiss that notification on this iPhone.
///
/// The connection is kept in the background (UIBackgroundModes: bluetooth-central) and comes back by itself
/// when the Android device returns in range (a pending connect never times out on iOS).
final class AndroidLink: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = AndroidLink()
    static let service = CBUUID(string: "A7A0A001-0E0F-4A4E-8A00-414E41000001")   // as AncsLink.ANA_SERVICE
    static let nameChar = CBUUID(string: "A7A0A002-0E0F-4A4E-8A00-414E41000001")
    static let relayChar = CBUUID(string: "A7A0A003-0E0F-4A4E-8A00-414E41000001")     // as AncsLink.ANA_RELAY
    static let controlChar = CBUUID(string: "A7A0A004-0E0F-4A4E-8A00-414E41000001")   // as AncsLink.ANA_CONTROL

    /// Called (on the main queue) when relayed notifications were added to the log.
    var onNew: (() -> Void)?
    private var relay: CBCharacteristic?
    private var control: CBCharacteristic?
    private var inbox = Data()
    private var known: Set<String>?                  // keys of the iPhone notifications already in the log

    /// What the link is doing, in words for Settings.
    private(set) var state = "Off"
    /// Linked and receiving the relay (APPify's Live pill, the bar's RECORDING).
    var relaying: Bool { peripheral?.state == .connected && relay?.isNotifying == true }
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var wanted = false
    // LINK TIME and OUT OF RANGE ("Linked 2 h 14 m · last notification 3 min ago"; a 30 s countdown when out of range)
    private var linkedAt: Date?
    private var lastNotifAt: Date?
    private var lastRssiAt = Date()
    private var weak = 0
    private var countdown = -1
    private var ticker: Timer?
    private var tickN = 0
    private let savedKey = "android_peripheral"

    func setOn(_ on: Bool) {
        wanted = on
        if on {
            if central == nil {
                central = CBCentralManager(delegate: self, queue: nil,
                                           options: [CBCentralManagerOptionRestoreIdentifierKey: "ana-orbit-android-link"])
            } else {
                start()
            }
        } else {
            central?.stopScan()
            if let p = peripheral { central?.cancelPeripheralConnection(p) }
            peripheral = nil
            state = "Off"
        }
    }

    private func start() {
        guard wanted, let c = central else { return }
        guard c.state == .poweredOn else { return }            // centralManagerDidUpdateState says why
        // the Android device we linked to before
        if let s = UserDefaults.standard.string(forKey: savedKey), let id = UUID(uuidString: s),
           let p = c.retrievePeripherals(withIdentifiers: [id]).first {
            connect(p)
            return
        }
        // one that's already connected to the iPhone
        if let p = c.retrieveConnectedPeripherals(withServices: [AndroidLink.service]).first {
            connect(p)
            return
        }
        state = "Looking for ANA on Android nearby (turn on iPhone notifications there)"
        c.scanForPeripherals(withServices: [AndroidLink.service], options: nil)
    }

    private func connect(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        state = "Connecting to ANA on Android..."
        central?.connect(p, options: nil)
    }

    // ------------------------------------------------------------------------------------------ central
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: start()
        case .poweredOff: state = "Bluetooth is off"
        case .unauthorized: state = "Bluetooth isn't allowed for ANA: Settings > ANA > Bluetooth"
        case .unsupported: state = "This device has no Bluetooth LE"
        default: break
        }
    }

    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let ps = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = ps.first {
            wanted = true
            peripheral = p
            p.delegate = self
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        c.stopScan()
        UserDefaults.standard.set(p.identifier.uuidString, forKey: savedKey)
        connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        state = "Connected: accept the pairing request, and allow notifications if asked"
        p.discoverServices([AndroidLink.service])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        state = "Couldn't connect (\(error?.localizedDescription ?? "unknown")): trying again"
        if wanted { c.connect(p, options: nil) }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        relay = nil
        control = nil
        inbox.removeAll()
        linkedAt = nil
        countdown = -1
        guard wanted else { return }
        state = "ANA on Android is out of reach: it reconnects when it's back"
        c.connect(p, options: nil)
    }

    // ------------------------------------------------------------------------------------------ peripheral
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == AndroidLink.service }) else {
            // ANA on Android isn't serving yet (starting, or restarted): look again in a moment
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let me = self, me.wanted, me.relay == nil, p.state == .connected, me.peripheral === p else { return }
                p.discoverServices([AndroidLink.service])
            }
            return
        }
        p.discoverCharacteristics([AndroidLink.nameChar, AndroidLink.relayChar, AndroidLink.controlChar], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        relay = s.characteristics?.first(where: { $0.uuid == AndroidLink.relayChar })
        control = s.characteristics?.first(where: { $0.uuid == AndroidLink.controlChar })
        // reading the name needs pairing: iOS asks to pair the first time
        if let ch = s.characteristics?.first(where: { $0.uuid == AndroidLink.nameChar }) { p.readValue(for: ch) }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        if ch.uuid == AndroidLink.relayChar {
            if let d = ch.value { received(d) }
            return
        }
        guard ch.uuid == AndroidLink.nameChar, error == nil else { return }
        let name = ch.value.flatMap { String(data: $0, encoding: .utf8) } ?? "ANA on Android"
        state = "Linked to \(name): it receives this iPhone's notifications"
        if let r = relay, !r.isNotifying { p.setNotifyValue(true, for: r) }    // paired now: the relay
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        guard ch.uuid == AndroidLink.relayChar, ch.isNotifying else { return }
        send("since:\(lastRelayed())")                                       // what we're missing
        linkedAt = Date()
        lastRssiAt = Date()
        weak = 0
        startTicker()
        DispatchQueue.main.async { Bills.shared.sendSchedules(force: true) }   // BILLS: the Android checks their payments
        state = state.replacingOccurrences(of: ": it receives this iPhone's notifications", with: "") + ": relaying this iPhone's notifications here"
    }

    /// ANA on Android restarted (its app, Bluetooth or the phone): its service is gone, so the relay is dead
    /// though Bluetooth is still connected. Find the service again and subscribe again.
    func peripheral(_ p: CBPeripheral, didModifyServices invalidated: [CBService]) {
        guard invalidated.contains(where: { $0.uuid == AndroidLink.service }) else { return }
        relay = nil
        control = nil
        inbox.removeAll()
        linkedAt = nil
        state = "ANA on Android restarted: reconnecting"
        p.discoverServices([AndroidLink.service])
    }

    // ------------------------------------------------------------------------------------------ OUT OF RANGE
    // While ANA is open: every 5 s the Android's signal. No signal for 12 s, or weak 3 times in a row:
    // "Android out of range: disconnecting in 30 s", then a clean drop of ANA's own link (apps can't switch
    // Bluetooth itself). The iPhone then waits for the Android to come back and reconnects by itself.
    func peripheral(_ p: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        lastRssiAt = Date()
        weak = RSSI.intValue < -92 ? weak + 1 : 0
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        guard let p = peripheral, p.state == .connected, relaying else { countdown = -1; return }
        tickN += 1
        if tickN % 5 == 0 { p.readRSSI() }
        let gone = Date().timeIntervalSince(lastRssiAt) > 12 || weak >= 3
        if !gone {
            if countdown >= 0 { countdown = -1; state = "Linked: relaying this iPhone's notifications here" }
            return
        }
        if countdown < 0 { countdown = 30 }
        if countdown > 0 { state = "Android out of range: disconnecting in \(countdown) s"; countdown -= 1; return }
        countdown = -1
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        state = "Android out of range since \(f.string(from: Date())): it reconnects when it's back"
        central?.cancelPeripheralConnection(p)                           // didDisconnect waits for it to come back
    }

    /// Settings: how long the link has been up, and when the last notification came ("" when not linked).
    var times: String {
        guard relaying, countdown < 0, let l = linkedAt else { return "" }
        var s = "Linked " + AndroidLink.ago(Date().timeIntervalSince(l))
        if let n = lastNotifAt {
            let d = Date().timeIntervalSince(n)
            s += " \u{00B7} last notification " + (d < 60 ? "just now" : AndroidLink.ago(d) + " ago")
        }
        return s
    }

    private static func ago(_ t: TimeInterval) -> String {
        let m = Int(t / 60)
        if m < 1 { return "under a minute" }
        if m < 60 { return "\(m) min" }
        return "\(m / 60) h \(m % 60) m"
    }

    // ------------------------------------------------------------------------------------------ the relay
    /// The app came to the front: make sure the relay is on, and ask for anything missed meanwhile.
    func refresh() {
        guard wanted, let p = peripheral, p.state == .connected, let r = relay else { start(); return }
        if r.isNotifying { send("since:\(lastRelayed())") } else { p.setNotifyValue(true, for: r) }
    }

    // ------------------------------------------------------------------------------------------ BILLS
    /// Linked to ANA on Android (it checks bill payments for this iPhone).
    var linked: Bool { peripheral?.state == .connected && control != nil }
    /// Called (main queue) with each signed payment confirmation (class 44) from the Android.
    var onBillOk: ((Data) -> Void)?

    /// A bill's signed schedule to the Android, in pieces: "bsch:<transfer>:<i>:<n>:<base64 piece>".
    func sendBill(_ f: Data) -> Bool { sendPieces("bsch", f) }

    /// CHATNOTE: a signed message to the Android, in pieces: "chat:<transfer>:<i>:<n>:<base64 piece>".
    func sendChat(_ f: Data) -> Bool { sendPieces("chat", f) }

    private func sendPieces(_ head: String, _ f: Data) -> Bool {
        guard let p = peripheral, p.state == .connected, control != nil else { return false }
        let b64 = f.base64EncodedString()
        let tid = String(UInt32.random(in: 0...UInt32.max), radix: 36)
        let room = max(20, min(180, p.maximumWriteValueLength(for: .withoutResponse)) - 24)
        var parts = [String]()
        var i = b64.startIndex
        while i < b64.endIndex {
            let j = b64.index(i, offsetBy: room, limitedBy: b64.endIndex) ?? b64.endIndex
            parts.append(String(b64[i..<j]))
            i = j
        }
        for (k, part) in parts.enumerated() { send("\(head):\(tid):\(k):\(parts.count):" + part) }
        return true
    }

    private func send(_ cmd: String) {
        guard let p = peripheral, let c = control, p.state == .connected else { return }
        p.writeValue(Data(cmd.utf8), for: c, type: .withResponse)
    }

    /// APPify's CLEAR: ANA on Android dismisses every notification of this app that's still on the iPhone.
    func dismissApp(_ bundle: String) -> Bool {
        guard let p = peripheral, p.state == .connected, control != nil else { return false }
        send("clearapp:" + bundle)
        return true
    }

    /// CLEAR ON iPHONE (the reader): ANA on Android dismisses it here. false if not linked.
    func dismiss(_ key: String) -> Bool {
        guard let p = peripheral, p.state == .connected, control != nil else { return false }
        send("clear:" + key)
        return true
    }

    private func knownKeys() -> Set<String> {
        if let k = known { return k }
        var k = Set<String>()
        for l in AnaLog.readAll() {
            let f = l.components(separatedBy: "\t")
            if f.count >= 7 && f[0] == "IPHONE" { k.insert(f[6]) }
        }
        known = k
        return k
    }

    /// the newest iPhone notification already here (ms since 1970)
    private func lastRelayed() -> Int64 {
        var m: Int64 = 0
        for l in AnaLog.readAll() {
            let f = l.components(separatedBy: "\t")
            if f.count >= 3 && f[0] == "IPHONE", let t = Int64(f[2]), t > m { m = t }
        }
        return m
    }

    private func received(_ d: Data) {
        inbox.append(d)
        var added = 0
        while let nl = inbox.firstIndex(of: 10) {
            let line = String(decoding: inbox[inbox.startIndex..<nl], as: UTF8.self)
            inbox.removeSubrange(inbox.startIndex...nl)
            if line.hasPrefix("CHAT\t") {                                     // CHATNOTE: a message from the Android
                if let d = Data(base64Encoded: String(line.dropFirst(5))) { DispatchQueue.main.async { Chat.shared.receive(d, route: "Bluetooth") } }
                continue
            }
            if line.hasPrefix("BILLOK\t") {                                   // BILLS: the Android saw a bill paid
                if let d = Data(base64Encoded: String(line.dropFirst(7))) { DispatchQueue.main.async { self.onBillOk?(d) } }
                continue
            }
            let f = line.components(separatedBy: "\t")
            guard f.count >= 9 else { continue }
            var k = knownKeys()
            if k.contains(f[6]) { continue }
            AnaLog.append(src: "IPHONE", postMs: Int64(f[2]) ?? AnaLog.nowMs(), pkg: f[3], title: f[4], text: f[5],
                          key: f[6], lagMs: Int64(f[7]) ?? 0, eventMs: Int64(f[8]) ?? 0)
            if f.count >= 10 && !f[9].isEmpty { UserDefaults.standard.set(f[9], forKey: "ios_" + f[3]) }
            k.insert(f[6])
            known = k
            added += 1
        }
        if added > 0 { lastNotifAt = Date(); DispatchQueue.main.async { self.onNew?() } }
    }
}
