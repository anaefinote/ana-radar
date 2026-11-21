import UIKit
import CryptoKit

/// ANA : CHATNOTE, the basic version (as Android's Chat.java). A message is a headless signed pngmesh (class 46):
/// no picture, just chat|text, chat|name, chat|at, signed with this phone's own key. Signed, not secret: whoever
/// carries it could read it. Routes: Bluetooth (the iPhone <-> Android link) now; Wi-Fi, Internet and Light next.
/// Every message, sent or received, is also a CHAT line in ANA's log, so it shows in Pulse and the Archive.
final class Chat {
    static let shared = Chat()
    static let pkg = "ana.chat"                         // the log's app for CHATNOTE lines (label "CHATNOTE")
    private let pref = "chat_msgs"
    var onNew: ((Msg) -> Void)?

    struct Msg: Codable {
        var name = "", text = "", route = "", keyId = ""
        var at: Int64 = 0
        var mine = false
    }

    private(set) var all: [Msg] = []

    private init() {
        if let d = UserDefaults.standard.data(forKey: pref), let l = try? JSONDecoder().decode([Msg].self, from: d) { all = l }
    }

    // ------------------------------------------------------------------ the message
    func make(_ text: String) -> (Data, Int64)? {
        let at = Int64(Date().timeIntervalSince1970 * 1000)
        let rows = [["chat", "text", text], ["chat", "name", myName()], ["chat", "at", String(at)]]
        guard let f = BillCore.build(BillCore.clsChat, rows, signer: { Flex.signRaw($0) }, png: Data()) else { return nil }
        return (f, at)
    }

    /// A message from another phone: checked, kept, logged. nil when it's new and genuine, else why not.
    @discardableResult
    func receive(_ f: Data, route: String) -> String? {
        let s = BillCore.read(f)
        guard s.ok else { return "Not a genuine CHATNOTE message (\(s.why))" }
        guard s.cls == BillCore.clsChat else { return "Not a CHATNOTE message" }
        guard let at = Int64(s.get("chat|at")) else { return "No time in it" }
        var m = Msg()
        m.text = BillCore.clean500(s.get("chat|text"))
        m.name = BillCore.clean(s.get("chat|name"))
        if m.name.isEmpty { m.name = "Someone" }
        m.at = at
        m.keyId = s.keyId
        m.route = route
        guard s.keyId != myKeyId() else { return "That's your own message" }
        guard !all.contains(where: { $0.keyId == m.keyId && $0.at == m.at }) else { return "Already here" }
        keep(m)
        return nil
    }

    func sent(_ text: String, route: String, at: Int64) {
        var m = Msg()
        m.text = text; m.name = myName(); m.at = at; m.route = route; m.mine = true; m.keyId = myKeyId()
        keep(m)
    }

    private func keep(_ m: Msg) {
        all.append(m)
        if all.count > 100 { all.removeFirst(all.count - 100) }
        if let d = try? JSONEncoder().encode(all) { UserDefaults.standard.set(d, forKey: pref) }
        let who = m.mine ? "You" : m.name
        AnaLog.append(src: "CHAT", postMs: m.at, pkg: Chat.pkg, title: who + " \u{00B7} " + m.route + (m.mine ? "" : " \u{00B7} verified"),
                      text: m.text, key: "chat-" + String(m.keyId.prefix(12)) + "-" + String(m.at))
        if !m.mine { DispatchQueue.main.async { self.onNew?(m) } }
    }

    /// one line per message, oldest first: mine, name, key id, age in seconds, route, text (for Chat.pde)
    func listText() -> String {
        let now = Date().timeIntervalSince1970
        return all.map { m in
            let flat = { (s: String) in s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
            return [m.mine ? "1" : "0", flat(m.name), m.keyId, String(max(0, Int(now - Double(m.at) / 1000))), m.route, flat(m.text)].joined(separator: "\t")
        }.joined(separator: "\n")
    }

    /// forget one person's messages (CLEAR in Orbit)
    func clear(_ key: String) {
        all.removeAll { !$0.mine && $0.keyId == key }
        if let d = try? JSONEncoder().encode(all) { UserDefaults.standard.set(d, forKey: pref) }
    }

    func myName() -> String {
        let n = UserDefaults.standard.string(forKey: "bill_name") ?? ""
        return n.isEmpty ? "ANA on " + UIDevice.current.name : n
    }

    func myKeyId() -> String {
        guard let k = Flex.signRaw(Data("probe".utf8)) else { return "" }
        return BillCore.hex(Data(SHA256.hash(data: k.pub)))
    }
}

// ------------------------------------------------------------------ the screen
extension ViewController {
    func chatOpen() {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        var s = ""
        for m in Chat.shared.all.suffix(12) {
            s += (m.mine ? "You" : m.name + " \u{2713}") + "  \u{00B7} " + f.string(from: Date(timeIntervalSince1970: Double(m.at) / 1000))
                + " \u{00B7} " + m.route + "\n" + m.text + "\n\n"
        }
        if Chat.shared.all.isEmpty { s += "No messages yet. Say hello.\n\n" }
        s += "Signed by this phone, so the other phone knows it's you. Not secret yet: whoever carries it could read it."
        let a = UIAlertController(title: "CHATNOTE (experimental)", message: s, preferredStyle: .alert)
        a.addTextField { t in t.placeholder = "Type a message" }
        a.addAction(UIAlertAction(title: "Close", style: .cancel))
        a.addAction(UIAlertAction(title: "Send...", style: .default) { [weak self, weak a] _ in
            let text = (a?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            self?.chatRoute(String(text.prefix(500)))
        })
        present(a, animated: true)
    }

    /// the box to type in, then the route (the screen itself is drawn by the sketch: Chat.pde)
    func chatWrite() {
        let a = UIAlertController(title: "CHATNOTE", message: nil, preferredStyle: .alert)
        a.addTextField { t in t.placeholder = "Type a message" }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Send...", style: .default) { [weak self, weak a] _ in
            let text = (a?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            self?.chatRoute(String(text.prefix(500)))
        })
        present(a, animated: true)
    }

    private func chatRoute(_ text: String) {
        let ac = UIAlertController(title: "Send by", message: nil, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "Bluetooth (your paired Android)", style: .default) { [weak self] _ in self?.chatBluetooth(text) })
        ac.addAction(UIAlertAction(title: "Wi-Fi (same network)", style: .default) { [weak self] _ in self?.chatWifi(text) })
        ac.addAction(UIAlertAction(title: "Internet (Tailscale address)", style: .default) { [weak self] _ in self?.chatAddress(text) })
        ac.addAction(UIAlertAction(title: "Light (QR code, experimental)", style: .default) { [weak self] _ in self?.toast("Light is coming next") })
        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(ac, animated: true)
    }

    // ------------------------------------------------------------------ Wi-Fi and Internet
    private func chatWifi(_ text: String) {
        toast("Looking for ANA on this Wi-Fi...")
        ChatNet.shared.find { [weak self] peers in
            guard let self = self else { return }
            if peers.isEmpty {
                let a = UIAlertController(title: "No ANA found on this Wi-Fi",
                                          message: "Open ANA on the other phone, on the same Wi-Fi, and try again. If iPhone asked to find devices on your local network, allow it (Settings > ANA > Local Network).",
                                          preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(a, animated: true)
                return
            }
            let ac = UIAlertController(title: "Send to", message: nil, preferredStyle: .alert)
            for p in peers {
                ac.addAction(UIAlertAction(title: p.name, style: .default) { [weak self] _ in self?.chatNet(text, "Wi-Fi") { f, done in ChatNet.shared.send(f, to: p.endpoint, done) } })
            }
            ac.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            self.present(ac, animated: true)
        }
    }

    private func chatAddress(_ text: String) {
        let a = UIAlertController(title: "Send over the Internet",
                                  message: "Type the other phone's address. With Tailscale on both phones, it's the 100.x.y.z address Tailscale shows for it.",
                                  preferredStyle: .alert)
        a.addTextField { [weak self] t in
            t.placeholder = "100.x.y.z"
            t.keyboardType = .numbersAndPunctuation
            t.text = self?.defaults.string(forKey: "chat_addr")
        }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Send", style: .default) { [weak self, weak a] _ in
            let h = (a?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces)
            guard !h.isEmpty else { return }
            self?.defaults.set(h, forKey: "chat_addr")
            self?.chatNet(text, "Internet") { f, done in ChatNet.shared.send(f, host: h, done) }
        })
        present(a, animated: true)
    }

    private func chatNet(_ text: String, _ route: String, _ go: (Data, @escaping (String?) -> Void) -> Void) {
        guard let (f, at) = Chat.shared.make(text) else { toast("This phone couldn't sign the message"); return }
        go(f) { [weak self] why in
            if let w = why { self?.toast("Not sent: " + w); return }
            Chat.shared.sent(text, route: route, at: at)
            self?.toast("Sent over " + route)
            self?.deliverPending()
        }
    }

    private func chatBluetooth(_ text: String) {
        guard let (f, at) = Chat.shared.make(text) else { toast("This phone couldn't sign the message"); return }
        guard AndroidLink.shared.sendChat(f) else { toast("No Android linked: turn on Connect to Android ANA first"); return }
        Chat.shared.sent(text, route: "Bluetooth", at: at)
        toast("Sent to your Android over Bluetooth")
        deliverPending()
    }

    /// a message arrived: say so, unless something is already on screen (it's in the log either way)
    func chatArrived(_ m: Chat.Msg) {
        deliverPending()
        if presentedViewController == nil { toast("CHATNOTE from \(m.name): \(m.text)") }
    }
}
