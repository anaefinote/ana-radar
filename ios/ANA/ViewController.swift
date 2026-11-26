import UIKit
import WebKit
import UniformTypeIdentifiers
import LocalAuthentication

/// Core ANA on iPhone / iPad: the user's Processing sketch (Web/*.pde) running in a web view, exactly as on
/// Android, with the native parts underneath: the log, manual entry, reminders, EXPORT / IMPORT .pngmesh.
///
/// The page calls AndroidANA.method(...) (iosbridge.js defines it). Each call arrives here as a JavaScript
/// prompt("ana-bridge", {"m": method, "a": [args]}) and is answered at once with the result as JSON, so the
/// sketch gets its answer synchronously, as it does on Android.
final class ViewController: UIViewController, WKUIDelegate, WKNavigationDelegate, UIDocumentPickerDelegate {
    private var web: WKWebView!
    private var pageReady = false
    private var delivered = 0                       // log lines already sent to the page
    private var waitingFiles = [URL]()              // files opened before the page was ready
    private var waitingMesh = [String: (String, Data)]()   // a .pngmesh waiting for its .sha256: hash -> (name, bytes)
    private var waitingSidecar = Set<String>()             // .sha256 hashes waiting for their .pngmesh
    let defaults = UserDefaults.standard

    private var webDir: URL { Bundle.main.bundleURL.appendingPathComponent("Web", isDirectory: true) }
    private let base = UIColor(red: 5 / 255, green: 7 / 255, blue: 12 / 255, alpha: 1)    // #05070C

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = base
        if let days = Int(pref("retention")), days > 0 { AnaLog.prune(days: days) }
        AndroidLink.shared.onNew = { [weak self] in                            // relayed iPhone notifications
            self?.deliverPending()
            Wallets.shared.refreshAll()        // a wallet app's notification may prove ownership (Proof.swift)

        }
        Chat.shared.onNew = { [weak self] m in self?.chatArrived(m) }           // CHATNOTE: a message arrived
        ChatNet.shared.onFile = { [weak self] f in self?.ingestPushedMesh(f) }  // MESH FILE PUSH: a whole pngmesh over Wi-Fi/Tailscale (e.g. GAXT notifications)
        AndroidLink.shared.onBillOk = { [weak self] f in                         // BILLS: the Android confirmed a payment
            if let m = Bills.shared.paid(f, viaLink: true) { self?.toast(m) }
            self?.deliverPending()
        }
        Bills.shared.tick()                                                     // BILLS: next due dates on the Future window
        AppStore.shared.onIcon = { [weak self] bundle in                       // APPify: an icon has arrived
            guard let self = self else { return }
            self.web.evaluateJavaScript("if (window.anaIconReady) anaIconReady(\(self.json(bundle)));", completionHandler: nil)
        }
        if pref("iphone") == "1" { AndroidLink.shared.setOn(true) }   // the link to ANA on Android, as it was left

        // WATCH: wallets, read-only. Checked when ANA comes to the front and every 2 minutes while it's open;
        // anything new (money in, out, into or out of earning) becomes a WATCH entry in the log, on Pulse.
        Wallets.shared.onNews = { [weak self] w, acts in
            for a in acts {
                let sign: String = a.kind == "in" ? "+" : (a.kind == "out" ? "-" : "")
                let text: String = sign + Wallets.actAmount(a) + "  " + a.label
                AnaLog.append(src: "WATCH", postMs: Int64(a.t * 1000), pkg: "ana.watch", title: w.name,
                              text: text, key: "watch-" + a.id)
            }
            self?.deliverPending()
            if let last = acts.last {
                let sign: String = last.kind == "in" ? "+" : (last.kind == "out" ? "-" : "")
                let msg: String = w.name + ": " + sign + Wallets.actAmount(last) + " " + last.label.lowercased()
                self?.toast(msg)
            }
        }
        // OWNERSHIP PROOF: a wallet notification matched its transaction on the chain
        Wallets.shared.onProof = { [weak self] w in
            let saved = Witness.save(w)          // the signed witness, in Files > ANA > proofs
            AnaLog.append(src: "WATCH", postMs: AnaLog.nowMs(), pkg: "ana.watch", title: w.name,
                          text: "Ownership proven. " + (w.proofNote ?? "") + (saved.map { "  ·  Signed witness: " + $0 } ?? ""),
                          key: "proof-" + (w.proofTx ?? w.id))
            self?.deliverPending()
            self?.toast(w.name + ": ownership proven")
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Wallets.shared.refreshAll()
        }
        // SUB-WATCH: closes when ANA leaves the front (Face ID's own sheet doesn't count), and stays shut
        // while the screen is recorded, mirrored or shared
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            if self?.revealing != true { Wallets.shared.back = false }
        }
        Wallets.shared.capturing = UIScreen.main.isCaptured
        NotificationCenter.default.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { _ in
            Wallets.shared.capturing = UIScreen.main.isCaptured
            if Wallets.shared.capturing { Wallets.shared.back = false }
        }
        Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            if UIApplication.shared.applicationState == .active { Wallets.shared.refreshAll() }
        }

        let cfg = WKWebViewConfiguration()
        if let js = try? String(contentsOf: webDir.appendingPathComponent("iosbridge.js"), encoding: .utf8) {
            cfg.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        if Wallets.statia {                                          // ANA : STATIA: the page shows her name
            cfg.userContentController.addUserScript(WKUserScript(source: "window.__ANA_EDITION = 'statia';",
                                                                 injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        web = WKWebView(frame: .zero, configuration: cfg)
        web.uiDelegate = self
        web.navigationDelegate = self
        web.isOpaque = false
        web.backgroundColor = base
        web.scrollView.backgroundColor = base
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(web)
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: g.trailingAnchor),
            web.topAnchor.constraint(equalTo: g.topAnchor),
            web.bottomAnchor.constraint(equalTo: g.bottomAnchor),
        ])
        web.loadFileURL(webDir.appendingPathComponent("index.html"), allowingReadAccessTo: webDir)
    }

    // the page was killed in the background (memory): load it again
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pageReady = false
        delivered = 0
        webView.reload()
    }

    // ================================================================================================ the bridge
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard prompt == "ana-bridge",
              let text = defaultText, let data = text.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let m = obj["m"] as? String else {
            completionHandler(nil)
            return
        }
        let a = (obj["a"] as? [String]) ?? []
        completionHandler(json(call(m, a)))
    }

    private func json(_ v: Any) -> String {
        if let d = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed]),
           let s = String(data: d, encoding: .utf8) { return s }
        return "\"\""
    }

    private func arg(_ a: [String], _ i: Int) -> String { i < a.count ? a[i] : "" }

    /// Anything that shows something or changes the log runs after the answer (the page is waiting for it).
    private func later(_ f: @escaping () -> Void) { DispatchQueue.main.async(execute: f) }

    private func call(_ m: String, _ a: [String]) -> Any {
        switch m {
        case "readSketch": return readSketch()
        case "ready":
            later {
                self.pageReady = true
                self.delivered = 0
                self.deliverPending()
                if !self.waitingFiles.isEmpty {
                    let f = self.waitingFiles
                    self.waitingFiles.removeAll()
                    self.importURLs(f)
                }
            }
            return true
        case "status": return AndroidLink.shared.relaying ? "CONNECTED" : "IOS"   // Live / RECORDING while linked
        case "visibility": return Visibility.shared.asJSON()   // {"pulse":1,"lessons":0,...,"_flavour":"ea80bc44"} — the page hides features marked 0
        case "watchList": return defaults.string(forKey: "watch") ?? ""
        case "saveWatch": defaults.set(arg(a, 0), forKey: "watch"); return true
        case "pref": return pref(arg(a, 0))
        case "setPref": defaults.set(arg(a, 1), forKey: "p_" + arg(a, 0)); return true
        case "skinData": return skinData(arg(a, 0))
        case "appLabel": return label(arg(a, 0))
        case "appIcon": return AppStore.shared.iconData(arg(a, 0))           // APPify: from the App Store, by bundle ID
        case "appCategory": return AppStore.shared.category(arg(a, 0))
        case "usageToday": return ""
        case "launchApp":
            let b = arg(a, 0), n = label(b)
            later { AppStore.shared.open(b, label: n) }
            return true
        case "usageOk", "closeApp": return false                        // iOS: no other apps' usage or closing
        case "clearNotifs": return AndroidLink.shared.dismissApp(arg(a, 0)) ? 1 : -1   // through ANA on Android
        case "appStatus": return "active"
        case "sdkInt": return 0
        case "scan": return true
        case "openOwnInfo", "openAccess", "openUsageAccess", "appSettings":
            later {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            }
            return true
        case "manualEntry": later { self.showManualEntry() }; return true
        case "addReminder": later { self.showReminder() }; return true
        case "exportLog": later { self.exportLog() }; return true
        case "exportPngmesh":
            let lines = arg(a, 0)
            later { self.exportPngmesh(lines) }
            return true
        case "importFiles": later { self.pickFiles() }; return true
        case "iphoneLink":
            let on = arg(a, 0) == "true"
            defaults.set(on ? "1" : "0", forKey: "p_iphone")
            later { AndroidLink.shared.setOn(on) }
            return true
        case "iphoneState": return AndroidLink.shared.state
        case "iphoneTimes": return AndroidLink.shared.times
        case "iphoneDismiss": return AndroidLink.shared.dismiss(arg(a, 0))
        // RADAR: passive nearby-ANA-device discovery, no pairing (scans ANA's own service UUID)
        case "radarOn":
            let on = arg(a, 0) == "true"
            later { Radar.shared.setOn(on) }
            return true
        case "radarCount": return Radar.shared.count
        case "radarPeers": return Radar.shared.snapshot()
        case "radarName":
            let nm = arg(a, 0)
            later { Radar.shared.setName(nm) }
            return true
        // ANA FENCE
        case "fenceCreate":
            let nm = arg(a, 0), rad = Int(arg(a, 1)) ?? 25, dur = Int(arg(a, 2)) ?? 480
            later { Radar.shared.fenceCreate(nm, rad, dur) }
            return true
        case "fenceJoin":
            let fid = arg(a, 0)
            later { Radar.shared.fenceJoin(fid) }
            return true
        case "fenceRequest":
            let fid = arg(a, 0)
            later { Radar.shared.fenceRequest(fid) }
            return true
        case "fenceAccept":
            let id = arg(a, 0)
            later { Radar.shared.fenceAccept(id) }
            return true
        case "fenceDecline":
            let id = arg(a, 0)
            later { Radar.shared.fenceDecline(id) }
            return true
        case "fenceLeave":
            later { Radar.shared.fenceLeave() }
            return true
        case "fenceInfo": return Radar.shared.fenceInfo()
        case "fenceKnockers": return Radar.shared.fenceKnockers()
        case "fenceOffers": return Radar.shared.fenceOffers()
        case "walletText": return Wallets.shared.pageText()
        case "lessonsText": return Lessons.shared.text()
        case "lessonsOpen": later { self.showLessons() }; return true
        case "penText": return detainPenText()               // ANA #2 1b slice 3: detain-pen count for a badge
        case "penOpen": later { self.showDetainPen() }; return true
        case "billsText": return Bills.shared.text()
        case "billsOpen": later { self.billsOpen() }; return true
        case "chatOpen": later { self.chatOpen() }; return true
        case "chatList": return Chat.shared.listText()
        case "chatWrite": later { self.chatWrite() }; return true
        case "findAdd": later { self.findAdd() }; return true
        case "findRemove":
            let n = arg(a, 0)
            defaults.set(pref("finds").components(separatedBy: "\n").filter { $0 != n && !$0.isEmpty }.joined(separator: "\n"), forKey: "p_finds")
            return true
        case "chatClear": Chat.shared.clear(arg(a, 0)); return true
        case "walletBusy": return Wallets.shared.busy
        case "walletRefresh": later { Wallets.shared.refreshAll() }; return true
        case "walletAdd": later { self.showWalletAdd() }; return true
        case "walletEdit":
            let id = arg(a, 0)
            later { self.showWalletEdit(id) }
            return true
        case "walletReveal": later { self.revealSubWatch() }; return true
        case "walletBack": return Wallets.shared.back
        case "walletFront": Wallets.shared.back = false; return true
        // GST
        case "walletTotals": return Wallets.shared.totals()
        case "gstSend":
            let n = arg(a, 0), h = arg(a, 1), r = arg(a, 2), p = arg(a, 3)
            later { self.gstSend(n, h, r, p) }
            return true
        case "gstInbox":
            let s = gstInbox.joined(separator: "\n")
            gstInbox.removeAll()
            return s
        // ROUND-TRIP (L2): share a fresh proof out; collect the hashes of any that came back.
        case "roundTripShare":
            return roundTripShare(arg(a, 0))        // builds the file, returns its sha256, pops the share sheet
        case "roundTripInbox":
            let s = rtInbox.joined(separator: "\n")  // sha256 of each round-trip file imported since last asked
            rtInbox.removeAll()
            return s
        case "sealExport":                           // FENCE SEAL (v0.3): share a signed roster as a .pngmesh
            let body = arg(a, 0)
            later { self.sealExport(body) }
            return true
        case "coSignRequest":                         // CO-SIGN hop 1: share A's commitment, return its hash
            return coSignShare(arg(a, 0), reply: false)
        case "coSignReply":                           // CO-SIGN hop 2: share the full moment + both sigs
            _ = coSignShare(arg(a, 0), reply: true)
            return true
        case "coSignInbox":
            let s = coSignInbox.joined(separator: "\n@@@\n")
            coSignInbox.removeAll()
            return s
        case "lanPeers":                              // PRESENCE MESH: ANAs reachable on this Wi-Fi ("tag~name;...")
            ChatNet.shared.start()                    // announce this phone so others can find it
            ChatNet.shared.startMesh()                // keep a live browse of the LAN
            return ChatNet.shared.lanList()
        case "tailAdd":                               // PRESENCE MESH: add a tailnet peer by address (manual directory)
            later { self.tailAdd() }
            return true
        case "tailPeers":                             // PRESENCE MESH: known tailnet peers + live flag ("addr~name~1/0;...")
            ChatNet.shared.start()                    // be reachable too
            tailRefresh()                             // (re)check who answers
            return tailList()
        case "entryTrust":                            // ANA #2 1b: an entry's trust by key, for the Pulse badge
            return trustFor(arg(a, 0))
        case "gstAsk":
            let id = arg(a, 0), t = arg(a, 1), m = arg(a, 2), s = arg(a, 3)
            later { self.gstAsk(id, t, m, s) }
            return true
        case "gstPick":
            let id = arg(a, 0), t = arg(a, 1), items = arg(a, 2)
            later { self.gstPick(id, t, items) }
            return true
        // FLEX: this phone's signing key, signatures, sha256
        case "flexKey": return Flex.publicKey()
        case "flexSign": return Flex.sign(arg(a, 0))
        case "flexVerify": return Flex.verify(arg(a, 0), arg(a, 1), arg(a, 2))
        case "flexHash": return Flex.sha256(arg(a, 0))
        case "gstAnswer":
            let v = gstAnswers[arg(a, 0)] ?? ""
            gstAnswers[arg(a, 0)] = nil
            return v
        case "copyText":
            let t = arg(a, 0)
            later { UIPasteboard.general.string = t }
            return true
        default: return ""
        }
    }

    private func pref(_ k: String) -> String { defaults.string(forKey: "p_" + k) ?? "" }

    /// The sketch: the main tab first, then the others alphabetically (as Processing 1.5.1 and the Android app).
    private func readSketch() -> String {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: webDir.path)) ?? [])
            .filter { $0.hasSuffix(".pde") && $0 != "ANA_PoC.pde" }
            .sorted()
        var src = ""
        for n in ["ANA_PoC.pde"] + names {
            if let s = try? String(contentsOf: webDir.appendingPathComponent(n), encoding: .utf8) { src += s + "\n" }
        }
        return src
    }

    /// A skin image as a data: URL (a file:// image would make the canvas unreadable).
    private func skinData(_ f: String) -> String {
        guard f.range(of: "^[A-Za-z0-9_]+\\.png$", options: .regularExpression) != nil,
              let d = try? Data(contentsOf: webDir.appendingPathComponent(f)) else { return "" }
        return "data:image/png;base64," + d.base64EncodedString()
    }

    func label(_ pkg: String) -> String {
        if pkg == "manual" { return "Manual entry" }
        if pkg == "ana.reminder" { return "Reminder" }
        if pkg == "ana.watch" { return "Watch" }
        if pkg == "ana.gst" { return "GST" }
        if pkg == Bills.pkg { return "Bills" }
        if pkg == Chat.pkg { return "CHATNOTE" }
        if pkg.hasPrefix("find:") { return String(pkg.dropFirst(5)) }             // FIND: the name typed in
        if let n = defaults.string(forKey: "ios_" + pkg), !n.isEmpty { return n }     // named by ANA on Android
        if let n = AppStore.shared.name(pkg), !n.isEmpty { return n }                  // or by the App Store
        return pkg
    }

    // ================================================================================================ the log -> the page
    /// Every log line the page hasn't had yet, as anaDeliver(src, when, pkg, title, text, key, lag, line, ev).
    func deliverPending() {
        guard pageReady else { return }
        let lines = AnaLog.readAll()
        guard delivered < lines.count else { return }
        var js = ""
        for i in delivered..<lines.count {
            let f = lines[i].components(separatedBy: "\t")
            if f.count < 8 { continue }
            let ev = f.count > 8 ? AnaLog.whenOrEmpty(f[8]) : ""
            js += "anaDeliver(\(json(f[0])),\(json(f[1])),\(json(f[3])),\(json(f[4])),\(json(f[5])),\(json(f[6])),\(json(f[7])),\(i),\(json(ev)));\n"
        }
        delivered = lines.count
        web.evaluateJavaScript(js, completionHandler: nil)
    }

    // ================================================================================================ PRESENCE MESH: tailnet peers
    // The tailnet is the directory (settled: no WAN auto-discovery) — you add a peer by its Tailscale
    // address once, ANA pings it to light it up on the radar as "reachable via Tailscale" (never "near").
    private func tailAdd() {
        let ac = UIAlertController(title: "Add a Tailscale peer",
            message: "With Tailscale running on both phones, enter the other phone's 100.x.y.z address (or its MagicDNS name) and a name to show.",
            preferredStyle: .alert)
        ac.addTextField { t in t.placeholder = "100.x.y.z"; t.keyboardType = .URL; t.autocapitalizationType = .none; t.autocorrectionType = .no }
        ac.addTextField { t in t.placeholder = "Name"; t.autocapitalizationType = .words }
        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        ac.addAction(UIAlertAction(title: "Add", style: .default) { [weak self, weak ac] _ in
            guard let self = self else { return }
            let addr = (ac?.textFields?[0].text ?? "").trimmingCharacters(in: .whitespaces)
            var name = (ac?.textFields?[1].text ?? "").trimmingCharacters(in: .whitespaces)
            if addr.isEmpty { return }
            for ch in ["~", ";", "\t", "\n"] { name = name.replacingOccurrences(of: ch, with: " ") }
            if name.isEmpty { name = addr }
            let cur = self.defaults.string(forKey: "tailPeers") ?? ""
            var lines = cur.split(separator: "\n").map(String.init).filter { !$0.hasPrefix(addr + "\t") }
            lines.append(addr + "\t" + name)
            self.defaults.set(lines.joined(separator: "\n"), forKey: "tailPeers")
        })
        sheet(ac)
    }
    private func tailRefresh() {
        let cur = defaults.string(forKey: "tailPeers") ?? ""
        for line in cur.split(separator: "\n") {
            let addr = String(line.split(separator: "\t").first ?? "")
            if addr.isEmpty { continue }
            ChatNet.shared.ping(host: addr) { [weak self] ok in
                if ok { self?.tailLive.insert(addr) } else { self?.tailLive.remove(addr) }
            }
        }
    }
    private func tailList() -> String {
        let cur = defaults.string(forKey: "tailPeers") ?? ""
        var out = [String]()
        for line in cur.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard let addr = parts.first, !addr.isEmpty else { continue }
            let name = parts.count > 1 ? parts[1] : addr
            out.append(addr + "~" + name + "~" + (tailLive.contains(addr) ? "1" : "0"))
        }
        return out.joined(separator: ";")
    }

    // ================================================================================================ manual entry, reminder
    private func showManualEntry() {
        let ac = UIAlertController(title: "Manual entry", message: nil, preferredStyle: .alert)
        ac.addTextField { t in
            t.placeholder = "Amount (e.g. 12.50)"
            t.keyboardType = .decimalPad
        }
        ac.addTextField { t in
            t.placeholder = "Merchant"
            t.autocapitalizationType = .words
        }
        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        ac.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak ac] _ in
            let amount = ac?.textFields?[0].text ?? ""
            let merchant = ac?.textFields?[1].text ?? ""
            let now = AnaLog.nowMs()
            AnaLog.append(src: "MANUAL", postMs: now, pkg: "manual", title: merchant, text: "Amount: " + amount, key: "manual-\(now)")
            self?.deliverPending()
        })
        present(ac, animated: true)
    }

    /// EFINOTE: a reminder of your own, for the future ball
    private func showReminder() {
        let r = ReminderViewController()
        r.onSave = { [weak self] what, date in
            let now = AnaLog.nowMs()
            AnaLog.append(src: "REMIND", postMs: now, pkg: "ana.reminder", title: what, text: "Reminder",
                          key: "remind-\(now)", eventMs: Int64(date.timeIntervalSince1970 * 1000))
            self?.deliverPending()
        }
        let nav = UINavigationController(rootViewController: r)
        nav.overrideUserInterfaceStyle = .dark
        present(nav, animated: true)
    }

    // ================================================================================================ SUB-WATCH
    private var revealing = false

    /// Check Now was held: Face ID (or the passcode), then sub-watch opens.
    private func revealSubWatch() {
        if Wallets.shared.capturing { toast("Sub-watch stays shut while the screen is shared or recorded"); return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let ctx = LAContext()
        var e: NSError?
        if !ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &e) {
            Wallets.shared.back = true
            toast("Set a passcode and sub-watch will ask for Face ID")
            return
        }
        revealing = true
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open sub-watch") { ok, _ in
            DispatchQueue.main.async {
                self.revealing = false
                if ok && !Wallets.shared.capturing { Wallets.shared.back = true }
            }
        }
    }

    private func sheet(_ ac: UIAlertController) {
        if let pop = ac.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        present(ac, animated: true)
    }

    /// How long to keep a wallet behind the front face.
    private func showHideMenu(_ id: String) {
        let ac = UIAlertController(title: "Hide it from the front", message: nil, preferredStyle: .actionSheet)
        let times: [(String, Double)] = [("For 1 hour", 3600), ("For 8 hours", 8 * 3600), ("For 1 day", 86400)]
        for t in times {
            ac.addAction(UIAlertAction(title: t.0, style: .default) { _ in Wallets.shared.hide(id, t.1) })
        }
        ac.addAction(UIAlertAction(title: "For a time I choose...", style: .default) { [weak self] _ in self?.showHideCustom(id) })
        ac.addAction(UIAlertAction(title: "Until I bring it back", style: .default) { _ in Wallets.shared.hide(id, 0) })
        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet(ac)
    }

    private func showHideCustom(_ id: String) {
        let ac = UIAlertController(title: "Hide it for", message: "Days, hours and minutes", preferredStyle: .alert)
        for (ph, v) in [("Days", ""), ("Hours", "2"), ("Minutes", "")] {
            ac.addTextField { t in t.placeholder = ph; t.text = v; t.keyboardType = .numberPad }
        }
        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        ac.addAction(UIAlertAction(title: "Hide", style: .default) { [weak self, weak ac] _ in
            let f = ac?.textFields ?? []
            let d = Double(f.count > 0 ? f[0].text ?? "" : "") ?? 0
            let h = Double(f.count > 1 ? f[1].text ?? "" : "") ?? 0
            let m = Double(f.count > 2 ? f[2].text ?? "" : "") ?? 0
            let secs: Double = d * 86400 + h * 3600 + m * 60
            if secs < 60 { self?.toast("Pick at least a minute"); return }
            Wallets.shared.hide(id, secs)
        })
        present(ac, animated: true)
    }

    // ================================================================================================ WATCH: add / edit a wallet
    private func showWalletAdd() {
        let behind = Wallets.shared.back
        let ac = UIAlertController(title: behind ? "Add to sub-watch" : "Watch an address",
                                   message: "A public address only: an ether.fi Safe (0x..., on Optimism), a Solana wallet, a TRON wallet (T...)" + (Wallets.statia ? " or a Litecoin or Bitcoin wallet you hold yourself (ltc1... / bc1...)." : ".") + " ANA never needs keys or recovery words.",
                                   preferredStyle: .alert)
        let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        ac.addTextField { t in
            t.placeholder = "Name (e.g. ether.fi Cash, Jupiter)"
            t.autocapitalizationType = .words
        }
        ac.addTextField { t in
            t.placeholder = "Address"
            t.autocapitalizationType = .none
            t.autocorrectionType = .no
            if Wallets.kindOf(clip) != nil { t.text = clip }            // a copied address is filled in
        }
        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        ac.addAction(UIAlertAction(title: "Watch", style: .default) { [weak self, weak ac] _ in
            let name = ac?.textFields?[0].text ?? "", addr = ac?.textFields?[1].text ?? ""
            if let problem = Wallets.shared.add(name: name, addr: addr, behind: behind) { self?.toast(problem) }
            else { self?.toast(behind ? "In sub-watch, hidden from the front: checking now" : "Watching it: checking now") }
        })
        present(ac, animated: true)
    }

    private func showWalletEdit(_ id: String) {
        guard let w = Wallets.shared.wallet(id) else { return }
        let ac = UIAlertController(title: w.name, message: w.addr, preferredStyle: .actionSheet)
        let behind = Wallets.shared.back
        if w.proof == "proven", w.proofDetail != nil {           // OWNERSHIP PROOF: its details and the signed witness
            ac.addAction(UIAlertAction(title: "Ownership: Proven (details)", style: .default) { [weak self] _ in self?.showProof(w) })
        }
        if behind {
            if Wallets.shared.isHidden(id) {
                ac.addAction(UIAlertAction(title: "Bring it to the front", style: .default) { _ in Wallets.shared.hide(id, -1) })
            } else {
                ac.addAction(UIAlertAction(title: "Hide it from the front...", style: .default) { [weak self] _ in self?.showHideMenu(id) })
            }
            let on = w.shareHide == true
            ac.addAction(UIAlertAction(title: "Hide while the screen is shared: " + (on ? "ON" : "OFF"), style: .default) { _ in
                Wallets.shared.setShareHide(id, !on)
            })
        }
        ac.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            let r = UIAlertController(title: "Rename", message: nil, preferredStyle: .alert)
            r.addTextField { t in t.text = w.name; t.autocapitalizationType = .words }
            r.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            r.addAction(UIAlertAction(title: "Save", style: .default) { [weak r] _ in
                Wallets.shared.rename(id, r?.textFields?[0].text ?? "")
            })
            self?.present(r, animated: true)
        })
        ac.addAction(UIAlertAction(title: "Copy the address", style: .default) { [weak self] _ in
            UIPasteboard.general.string = w.addr
            self?.toast("Address copied")
        })
        ac.addAction(UIAlertAction(title: "Check now", style: .default) { _ in Wallets.shared.refreshAll() })
        if !behind {
            ac.addAction(UIAlertAction(title: "Hide it from the front...", style: .default) { [weak self] _ in self?.showHideMenu(id) })
        }
        ac.addAction(UIAlertAction(title: "Stop watching", style: .destructive) { _ in Wallets.shared.remove(id) })
        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = ac.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        present(ac, animated: true)
    }

    // ================================================================================================ EXPORT
    private func exportDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// lines: "12,15,20", entries' line numbers in ana_log.txt. Shares <name>.pngmesh + <name>.pngmesh.sha256.
    private func exportPngmesh(_ lines: String) {
        let log = AnaLog.readAll()
        var rows = [[String]]()
        for t in lines.split(separator: ",") {
            if let i = Int(t.trimmingCharacters(in: .whitespaces)), i >= 0, i < log.count {
                let f = log[i].components(separatedBy: "\t")
                if f.count >= 8 { rows.append(f) }
            }
        }
        if rows.isEmpty { toast("Nothing to export"); return }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        let name = "ana_\(fmt.string(from: Date()))_\(rows.count).pngmesh"
        let mesh = AnaMesh.write(rows)
        let dir = exportDir()
        let meshURL = dir.appendingPathComponent(name), sideURL = dir.appendingPathComponent(name + ".sha256")
        do {
            try mesh.write(to: meshURL)
            try Data(AnaMesh.sidecar(name: name, mesh: mesh).utf8).write(to: sideURL)
        } catch {
            toast("Export failed: \(error.localizedDescription)")
            return
        }
        share([meshURL, sideURL])
    }

    /// ROUND-TRIP (L2): write the sketch's fresh proof body as a .pngmesh + .sha256 and pop the share
    /// sheet so the human can carry it out through WhatsApp. Returns the file's sha256 — the sketch
    /// remembers it and mints eFlex when the exact same hash comes back in via IMPORT.
    private func roundTripShare(_ body: String) -> String {
        toast("Preparing round-trip\u{2026}")      // breadcrumb: confirms the tap reached native
        let mesh = AnaMesh.writeRoundTrip(body)
        let hash = AnaMesh.sha256(mesh)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        let name = "ana_roundtrip_\(fmt.string(from: Date())).pngmesh"
        let dir = exportDir()
        let meshURL = dir.appendingPathComponent(name), sideURL = dir.appendingPathComponent(name + ".sha256")
        do {
            try mesh.write(to: meshURL)
            try Data(AnaMesh.sidecar(name: name, mesh: mesh).utf8).write(to: sideURL)
        } catch {
            toast("Round-trip share failed: \(error.localizedDescription)")
            return ""
        }
        later { self.share([meshURL, sideURL]) }
        return hash
    }

    /// CO-SIGN (L1): write the commitment (hop 1) or the finished moment (hop 2) as a .pngmesh + .sha256
    /// and pop the share sheet so the other phone can carry it. Returns the file's sha256.
    @discardableResult
    private func coSignShare(_ body: String, reply: Bool) -> String {
        let mesh = reply ? AnaMesh.writeCoSignReply(body) : AnaMesh.writeCoSign(body)
        let hash = AnaMesh.sha256(mesh)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        let name = "ana_cosign_\(fmt.string(from: Date())).pngmesh"
        let dir = exportDir()
        let meshURL = dir.appendingPathComponent(name), sideURL = dir.appendingPathComponent(name + ".sha256")
        do {
            try mesh.write(to: meshURL)
            try Data(AnaMesh.sidecar(name: name, mesh: mesh).utf8).write(to: sideURL)
        } catch {
            toast("Co-sign share failed: \(error.localizedDescription)")
            return ""
        }
        later { self.share([meshURL, sideURL]) }
        return hash
    }

    /// FENCE SEAL (v0.3): write the host's signed roster as a .pngmesh + .sha256 and pop the share sheet.
    /// Unlike exportPngmesh (which exports existing log lines by index), this seals the payload itself.
    private func sealExport(_ body: String) {
        let mesh = AnaMesh.writeSeal(body)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        let name = "ana_fenceseal_\(fmt.string(from: Date())).pngmesh"
        let dir = exportDir()
        let meshURL = dir.appendingPathComponent(name), sideURL = dir.appendingPathComponent(name + ".sha256")
        do {
            try mesh.write(to: meshURL)
            try Data(AnaMesh.sidecar(name: name, mesh: mesh).utf8).write(to: sideURL)
        } catch {
            toast("Seal failed: \(error.localizedDescription)")
            return
        }
        share([meshURL, sideURL])
    }

    private func exportLog() {
        let u = exportDir().appendingPathComponent("ana_log.txt")
        do { try Data(AnaLog.readText().utf8).write(to: u) } catch { toast("Export failed"); return }
        share([u])
    }

    /// OWNERSHIP PROOF: the whole proof in plain words, and the signed witness to share
    private func showProof(_ w: Wallets.Wallet) {
        guard let d = w.proofDetail else { return }
        let inbound = d["direction"] == "in"
        let block = Double(d["block_time"] ?? "") ?? 0
        let pushed = (Double(d["notified_ms"] ?? "") ?? 0) / 1000
        let lag = Int(pushed - block)
        let coin = d["coin"] ?? ""
        let party = d["party"] ?? ""
        let app = d["app"] ?? ""
        var m = (inbound ? "Received " : "Sent ") + (d["amount"] ?? "") + " " + coin
        m += "\n(exactly " + (d["units"] ?? "") + (coin == "BTC" ? " satoshis)" : " litoshis)")
        if !party.isEmpty { m += (inbound ? "\nfrom " : "\nto ") + party }
        m += "\n\nOn the chain\n" + Wallets.when(block) + "  ·  confirmed\n" + (d["txid"] ?? "")
        m += "\n\nYour wallet's notification\n" + Wallets.when(pushed) + "  ·  "
            + (app == "com.sixdays.trust" || app == "com.wallet.crypto.trustapp" ? "Trust Wallet" : app)
            + " on the iPhone, relayed by Android ANA"
        m += "\n" + (lag >= 0 ? "Push came \(lag / 60) min \(lag % 60) s after the block" : "Push came before the block")
        let have = Witness.exists(w), name = Witness.fileName(w)
        m += "\n\nSigned witness\n" + (have && name != nil ? name! + "\nsigned by this phone's own key\nFiles > " + (Wallets.statia ? "STATIA" : "ANA") + " > proofs" : "not saved yet (Check now)")
        let a = UIAlertController(title: w.name + ": ownership proven", message: m, preferredStyle: .alert)
        if have, let n = name {
            a.addAction(UIAlertAction(title: "Share signed witness", style: .default) { [weak self] _ in
                let mesh = Witness.dir.appendingPathComponent(n)
                let side = Witness.dir.appendingPathComponent(String(n.dropLast(".pngmesh".count)) + ".sha256")
                self?.share([mesh, side])
            })
        }
        a.addAction(UIAlertAction(title: "Close", style: .cancel))
        present(a, animated: true)
    }

    func share(_ items: [Any]) {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let pop = vc.popoverPresentationController {          // iPad: the share sheet needs an anchor
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        var top: UIViewController = self                        // present from the top-most controller,
        while let p = top.presentedViewController, !p.isBeingDismissed { top = p }   // else present silently no-ops
        top.present(vc, animated: true)
    }

    // ================================================================================================ IMPORT
    // ================================================================================================ LESSONS
    /// a lesson (or root-chain file) arrived: check it, and for a lesson ask before ANA learns the coin
    private func showLessonImport(_ f: Data, _ sc: Data) {
        let v = Lessons.shared.preview(f, sc)
        if v.0 != "ACCEPT" { toast("Lesson: " + v.1); return }
        if v.2.isEmpty { toast("Root chain: " + Lessons.shared.add(f, sc)); return }    // a permission or a revoke
        let a = UIAlertController(title: Lessons.testKeys ? "Add a lesson  (TEST build)" : "Add a lesson",
                                  message: v.2 + (Lessons.testKeys ? "\n\nThis build trusts TEST keys only. Never share it." : ""), preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Not now", style: .cancel))
        a.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            self?.toast(Lessons.shared.add(f, sc))
            Wallets.shared.refreshAll()
        })
        present(a, animated: true)
    }

    /// the coins lessons taught ANA: tap one to remove it, or import a lesson
    private func showLessons() {
        let title = (Lessons.experimental ? "Lessons (experimental)" : "Lessons") + (Lessons.testKeys ? "  ·  TEST keys" : "")
        let ac = UIAlertController(title: title, message: Lessons.shared.list.isEmpty ? "No lessons yet. Import a lesson's .pngmesh and its .sha256 together." : nil, preferredStyle: .actionSheet)
        for l in Lessons.shared.list {
            ac.addAction(UIAlertAction(title: l.name + " (" + l.ticker + ")   version \(l.version)", style: .default) { [weak self] _ in
                let d = UIAlertController(title: l.name + " (" + l.ticker + ")",
                                          message: Lessons.confirmText(l.kv).replacingOccurrences(of: "Add ", with: "Learned ").replacingOccurrences(of: "?  ANA will send", with: ".  ANA sends")
                                            + "\n\nLesson " + l.id + ", version \(l.version)\nSigned by key " + String(l.keyId.prefix(16))
                                            + (Lessons.shared.problems.isEmpty ? "" : "\n\nNot in use:\n" + Lessons.shared.problems), preferredStyle: .alert)
                d.addAction(UIAlertAction(title: "Close", style: .cancel))
                d.addAction(UIAlertAction(title: "Remove", style: .destructive) { _ in
                    Lessons.shared.remove(l.id)
                    self?.toast("Removed " + l.name)
                    Wallets.shared.refreshAll()
                })
                self?.present(d, animated: true)
            })
        }
        ac.addAction(UIAlertAction(title: "Import a lesson...", style: .default) { [weak self] _ in self?.pickFiles() })
        let penN = penRecords().count
        ac.addAction(UIAlertAction(title: penN > 0 ? "Detain pen (\(penN) held)\u{2026}" : "Detain pen\u{2026}",
                                   style: penN > 0 ? .destructive : .default) { [weak self] _ in self?.showDetainPen() })
        ac.addAction(UIAlertAction(title: "Close", style: .cancel))
        if let pop = ac.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        present(ac, animated: true)
    }

    func pickFiles() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        importURLs(urls)
    }

    /// .pngmesh files and their .sha256 sidecars, together or one at a time, in either order.
    /// A .pngmesh is read only when its sidecar's hash matches.
    func importURLs(_ urls: [URL]) {
        if !pageReady {
            waitingFiles.append(contentsOf: urls)
            return
        }
        var added = 0, skipped = 0, gst = 0
        var notes = [String]()
        for u in urls {
            let scoped = u.startAccessingSecurityScopedResource()
            defer { if scoped { u.stopAccessingSecurityScopedResource() } }
            let name = u.lastPathComponent
            guard let b = try? Data(contentsOf: u) else {
                notes.append("\(name): can't read it")
                continue
            }
            if AnaMesh.looksLikePngmesh(b) {
                waitingMesh[AnaMesh.sha256(b)] = (name, b)
            } else if let h = AnaMesh.sidecarHash(b) {
                waitingSidecar.insert(h)
            } else {
                notes.append("\(name) is not a .pngmesh or .sha256")
            }
        }
        for (h, m) in waitingMesh where waitingSidecar.contains(h) {
            waitingMesh[h] = nil
            waitingSidecar.remove(h)
            let r = ingestOneMesh(m.1, h, name: m.0)
            added += r.added; skipped += r.skipped; gst += r.gst
            if let n = r.note { notes.append(n) }
        }
        for (_, m) in waitingMesh { notes.append("\(m.0): waiting for its .sha256 (IMPORT it too)") }
        if !waitingSidecar.isEmpty && waitingMesh.isEmpty && added == 0 && skipped == 0 && gst == 0 {
            notes.append("Got a .sha256: now IMPORT its .pngmesh")
        }
        var msg = ""
        if added + skipped > 0 { msg = "Imported \(added)" + (skipped > 0 ? ", \(skipped) already here" : "") }
        if gst > 0 { msg += (msg.isEmpty ? "" : "\n") + "GST: \(gst) " + (gst == 1 ? "update" : "updates") + " received" }
        for n in notes { msg += (msg.isEmpty ? "" : "\n") + n }
        if !msg.isEmpty { toast(msg) }
        deliverPending()
    }

    /// Adds imported rows to the log as IMPORT; skips rows already in it (same time, key and text).
    private func addToLog(_ rows: [[String]]) -> (Int, Int) {
        var have = Set<String>()
        for line in AnaLog.readAll() {
            let f = line.components(separatedBy: "\t")
            if f.count >= 8 { have.insert(f[2] + "\t" + f[6] + "\t" + f[5]) }
        }
        var added = 0, skipped = 0
        for r0 in rows {
            let r = r0 + Array(repeating: "", count: max(0, 9 - r0.count))
            let id = r[2] + "\t" + r[6] + "\t" + r[5]
            if have.contains(id) { skipped += 1; continue }
            let post = Int64(r[2]) ?? AnaLog.nowMs()
            AnaLog.append(src: "IMPORT", postMs: post, pkg: r[3], title: r[4], text: r[5], key: r[6],
                          lagMs: Int64(r[7]) ?? 0, eventMs: Int64(r[8]) ?? 0)
            have.insert(id)
            added += 1
        }
        return (added, skipped)
    }

    /// Route ONE imported/pushed .pngmesh by its class — the single place that decides what each class does, so
    /// the file importer (two-file pairing) and the mesh file push (framed, one payload) stay in step.
    private func ingestOneMesh(_ f: Data, _ h: String, name: String, released: Bool = false) -> (added: Int, skipped: Int, gst: Int, note: String?) {
        if AnaMesh.classOf(f) == AnaMesh.classRoundTrip {     // ROUND-TRIP: a proof the human carried out and back
            rtInbox.append(h)                                 // hand its sha256 to the sketch; it mints if it matches what it sent
            return (0, 0, 0, "Round-trip proof received \u{2713}")
        }
        if AnaMesh.classOf(f) == AnaMesh.classCoSign {        // CO-SIGN hop 1: a signed commitment from A
            let b = AnaMesh.readCoSign(f)
            if !b.isEmpty { coSignInbox.append("REQ\t" + b) }
            return (0, 0, 0, "Co-sign request received")
        }
        if AnaMesh.classOf(f) == AnaMesh.classCoSignReply {   // CO-SIGN hop 2: the full moment + both sigs
            let b = AnaMesh.readCoSignReply(f)
            if !b.isEmpty { coSignInbox.append("REPLY\t" + b) }
            return (0, 0, 0, "Co-sign reply received")
        }
        let bc = BillCore.classOf(f)                          // BILLS / CHATNOTE carried as a file
        if bc == BillCore.clsChat {
            DispatchQueue.main.async { if let why = Chat.shared.receive(f, route: "File") { self.toast(why) } }
            return (0, 0, 0, nil)
        }
        if bc >= BillCore.clsBill && bc <= BillCore.clsJourney {
            DispatchQueue.main.async { self.billReceived(f) }
            return (0, 0, 0, nil)
        }
        let lc = Lessons.classOf(f)                           // LESSONS: a lesson (30) or a root-chain file (31, 32)
        if lc == AnaRule.classLesson || lc == AnaRule.classPermit || lc == AnaRule.classRevoke {
            let sc = Data((h + "\n").utf8)
            // ANA #2 1b (slice 3): the detain pen. The authority tier is FAIL-CLOSED. A suspicious verdict
            // (bad signature, unknown key, fork, malformed, revoked, ...) is DETAINED at rung 0 — held and
            // described, NEVER executed, and NEVER silently dropped. distrust != reject. A capsule the human
            // released from the pen carries `released` and skips this, routing through the normal import.
            if !released {
                let v = Lessons.shared.preview(f, sc)         // dry run: saves/restores state, mutates nothing
                if penShouldDetain(v.0) {
                    let fresh = detain(f, h, cls: lc, reason: v.0, words: v.1)
                    return (0, 0, 0, (fresh ? "Detained \u{2014} " : "Already in the pen \u{2014} ") + v.1)
                }
            }
            DispatchQueue.main.async { self.showLessonImport(f, sc) }
            return (0, 0, 0, nil)
        }
        do {
            if AnaMesh.classOf(f) == AnaMesh.classGst {       // GST packs
                return (0, 0, gstReceived(try AnaMesh.readGst(f)), nil)
            }
            // ANA entries (class 20) -> the log. ANA #2 Tier-1: verify each row's signature if present.
            // Distrust by default — unsigned still imports, visibly unverified; signed earns a "verified" note.
            let signed = try AnaMesh.readSigned(f)
            // ANA #2 1b: verify + rung. A verified entry from a PINNED companion key = rung 3 ("your companion").
            // First verified companion ever seen is pinned (TOFU). A verified entry from a different, unpinned key
            // while others are pinned = rung 2 ("unrecognized companion") — never silently trusted.
            var pins = pinnedCompanions
            var vPinned = 0, vUnknown = 0, newlyPinned = false
            var pinnedTag = "", unknownTag = ""
            var trustUpdates = [String: String]()            // entry key -> trust, for the per-entry badge (slice 2)
            for row in signed {
                let sig = row.count > 9 ? row[9] : "", sgn = row.count > 10 ? row[10] : ""
                let ekey = row.count > 6 ? row[6] : ""
                if sig.isEmpty || sgn.isEmpty { continue }
                if !AnaMesh.verifyEntry(sgn, AnaMesh.canonicalEntry(row), sig) { continue }
                let tag = AnaMesh.signerTag(sgn)
                if pins.contains(sgn) {
                    vPinned += 1; if pinnedTag.isEmpty { pinnedTag = tag }
                    if !ekey.isEmpty { trustUpdates[ekey] = "pinned\t" + tag }
                } else if pins.isEmpty {
                    pins.insert(sgn); newlyPinned = true
                    vPinned += 1; if pinnedTag.isEmpty { pinnedTag = tag }
                    if !ekey.isEmpty { trustUpdates[ekey] = "pinned\t" + tag }
                } else {
                    vUnknown += 1; if unknownTag.isEmpty { unknownTag = tag }
                    if !ekey.isEmpty { trustUpdates[ekey] = "unknown\t" + tag }
                }
            }
            if newlyPinned { pinnedCompanions = pins }       // persist the first-pinned companion
            recordTrust(trustUpdates)                        // persist per-entry trust for the badge
            let r = addToLog(signed.map { Array($0.prefix(9)) })
            var parts = [String]()
            if vPinned > 0 { parts.append("\(vPinned) verified \u{00b7} " + (newlyPinned ? "new \(pinnedTag) (pinned as yours)" : "your \(pinnedTag)")) }
            if vUnknown > 0 { parts.append("\(vUnknown) signed \u{00b7} unrecognized \(unknownTag)") }
            return (r.0, r.1, 0, parts.isEmpty ? nil : parts.joined(separator: "\n"))
        } catch {
            return (0, 0, 0, "\(name): \(error.localizedDescription)")
        }
    }

    /// A whole .pngmesh pushed over the mesh (ChatNet file push). Self-verified by its own trailer + the framed
    /// length, so no .sha256 sidecar is needed. Returns nil if ANA took it, else why not.
    func ingestPushedMesh(_ f: Data) -> String? {
        guard AnaMesh.looksLikePngmesh(f) else { return "not a .pngmesh" }
        let r = ingestOneMesh(f, AnaMesh.sha256(f), name: "pushed")
        var msg = ""
        if r.added + r.skipped > 0 { msg = "Imported \(r.added)" + (r.skipped > 0 ? ", \(r.skipped) already here" : "") }
        if r.gst > 0 { msg += (msg.isEmpty ? "" : "\n") + "GST: \(r.gst) " + (r.gst == 1 ? "update" : "updates") + " received" }
        if let n = r.note { msg += (msg.isEmpty ? "" : "\n") + n }
        if !msg.isEmpty { toast(msg) }
        deliverPending()
        return nil
    }

    // ================================================================================================ GST
    // Group Spend Technology, Phase 1: packs travel as .pngmesh + .sha256 (the default). The sketch (Gst.pde)
    // keeps the groups, pools and feed; here: send packs, take in received ones, and simple dialogs.
    private var gstInbox = [String]()                 // received pack rows, tab-separated, for the sketch
    private var rtInbox = [String]()                  // ROUND-TRIP: sha256 of each round-trip .pngmesh imported back
    private var coSignInbox = [String]()              // CO-SIGN: "REQ\t<body>" / "REPLY\t<body>" of each imported co-sign file
    private var tailLive = Set<String>()              // PRESENCE MESH: tailnet addresses that answered a reachability ping
    // ANA #2 1b: companion signer keys this phone has pinned (TOFU). A verified entry from one of these is rung 3.
    private var pinnedCompanions: Set<String> {
        get { Set((UserDefaults.standard.array(forKey: "ana_pinned_companions") as? [String]) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "ana_pinned_companions") }
    }
    // ANA #2 1b (slice 2): per-entry trust, keyed by the entry's key, for the Pulse badge.
    private func recordTrust(_ updates: [String: String]) {
        guard !updates.isEmpty else { return }
        var m = (UserDefaults.standard.dictionary(forKey: "ana_entry_trust") as? [String: String]) ?? [:]
        for (k, v) in updates { m[k] = v }
        if m.count > 4000 { m = [:] ; for (k, v) in updates { m[k] = v } }   // simple cap; prune properly later
        UserDefaults.standard.set(m, forKey: "ana_entry_trust")
    }
    private func trustFor(_ key: String) -> String {
        ((UserDefaults.standard.dictionary(forKey: "ana_entry_trust") as? [String: String]) ?? [:])[key] ?? ""
    }

    // ============================================================================== ANA #2 1b slice 3: DETAIN PEN
    // Rung 0. A sealed store of authority capsules that failed the fail-closed check. Each record DESCRIBES the
    // capsule (class, sha, verdict, words, first/last seen, hit-count) and keeps its bytes so the human can
    // release it — but ANA never RUNS a held capsule. Dedup by sha; a hard cap drops the oldest first.
    private let penKey = "ana_detain_pen"
    private let penCap = 50
    /// fail-closed: anything that is not a clean accept or a benign redundancy is held.
    private func penShouldDetain(_ verdict: String) -> Bool {
        !["ACCEPT", "DUPLICATE", "OLDER", "UPDATE_FIRST"].contains(verdict)
    }
    private func penRecords() -> [[String: Any]] {
        (UserDefaults.standard.array(forKey: penKey) as? [[String: Any]]) ?? []
    }
    private func penSave(_ recs: [[String: Any]]) { UserDefaults.standard.set(recs, forKey: penKey) }
    /// Hold a capsule. Returns true if newly held, false if it was already in the pen (hit-count bumped).
    @discardableResult
    private func detain(_ f: Data, _ sha: String, cls: Int, reason: String, words: String) -> Bool {
        var recs = penRecords()
        let now = Int(Date().timeIntervalSince1970 * 1000)
        if let i = recs.firstIndex(where: { ($0["sha"] as? String) == sha }) {
            recs[i]["count"] = ((recs[i]["count"] as? Int) ?? 1) + 1   // dedup: same capsule knocking again
            recs[i]["lastMs"] = now
            penSave(recs)
            return false
        }
        recs.append(["sha": sha, "cls": cls, "reason": reason, "words": words,
                     "firstMs": now, "lastMs": now, "count": 1, "b64": f.base64EncodedString()])
        if recs.count > penCap {                                       // cap: keep the newest, drop the oldest seen
            recs.sort { (($0["firstMs"] as? Int) ?? 0) < (($1["firstMs"] as? Int) ?? 0) }
            recs.removeFirst(recs.count - penCap)
        }
        penSave(recs)
        return true
    }
    /// Let a held capsule out: remove it, then re-feed it through the normal path (crypto checks still apply).
    func releaseFromPen(_ sha: String) {
        var recs = penRecords()
        guard let i = recs.firstIndex(where: { ($0["sha"] as? String) == sha }),
              let b64 = recs[i]["b64"] as? String, let f = Data(base64Encoded: b64) else { return }
        recs.remove(at: i); penSave(recs)
        _ = ingestOneMesh(f, sha, name: "released", released: true)    // bypass the pen, route normally
        toast("Released from the pen")
    }
    func discardFromPen(_ sha: String) {
        var recs = penRecords(); recs.removeAll { ($0["sha"] as? String) == sha }; penSave(recs)
        toast("Discarded from the pen")
    }
    private func detainPenText() -> String {                           // simple count for a badge; expand later
        let n = penRecords().count
        return n == 0 ? "" : "\(n)"
    }
    private func showDetainPen() {
        let recs = penRecords().sorted { (($0["lastMs"] as? Int) ?? 0) > (($1["lastMs"] as? Int) ?? 0) }
        let ac = UIAlertController(
            title: "Detain pen",
            message: recs.isEmpty
                ? "Nothing held. Suspicious authority capsules \u{2014} bad signature, unknown key, fork, malformed \u{2014} are quarantined here, described but never run, until you release them."
                : "\(recs.count) held \u{2014} described, never run. Release to retry through the normal import, or discard.",
            preferredStyle: .actionSheet)
        for rec in recs {
            let sha = (rec["sha"] as? String) ?? ""
            let cls = (rec["cls"] as? Int) ?? 0
            let words = (rec["words"] as? String) ?? ((rec["reason"] as? String) ?? "held")
            let cnt = (rec["count"] as? Int) ?? 1
            let kind = cls == AnaRule.classLesson ? "lesson" : (cls == AnaRule.classPermit ? "permit" : "revoke")
            let label = kind + " \u{00b7} " + words + (cnt > 1 ? "  (\u{00d7}\(cnt))" : "") + "  \u{00b7} " + String(sha.prefix(8))
            ac.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in self?.showPenRecord(sha, kind, words) })
        }
        ac.addAction(UIAlertAction(title: "Close", style: .cancel))
        if let pop = ac.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        present(ac, animated: true)
    }
    private func showPenRecord(_ sha: String, _ kind: String, _ words: String) {
        let d = UIAlertController(
            title: "Held " + kind,
            message: words + "\n\n" + String(sha.prefix(16))
                + "\n\nThis capsule is described, not run. Release it to retry through the normal import (crypto checks still apply), or discard it.",
            preferredStyle: .alert)
        d.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        d.addAction(UIAlertAction(title: "Release", style: .default) { [weak self] _ in self?.releaseFromPen(sha) })
        d.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in self?.discardFromPen(sha) })
        present(d, animated: true)
    }
    private var gstAnswers = [String: String]()       // dialog id -> "O\tvalues..." or "C"

    /// received packs: to the sketch; spend alerts also land on Pulse
    private func gstReceived(_ rows: [[String]]) -> Int {
        for r0 in rows {
            let r = r0 + Array(repeating: "", count: max(0, 10 - r0.count))
            gstInbox.append(r.joined(separator: "\t"))
            if r[1] != "ALERT" { continue }
            let text: String = "About to spend " + r[6] + " " + r[7] + (r[8].isEmpty ? "" : " on " + r[8])
            AnaLog.append(src: "GST", postMs: AnaLog.nowMs(), pkg: "ana.gst", title: "Spend alert from " + r[4],
                          text: text, key: "gst-" + r[0])
        }
        return rows.count
    }

    /// rows: tab-separated GST rows, one per line; pics: the cards on the picture (title TAB text per line)
    private func gstSend(_ name: String, _ head: String, _ rowsText: String, _ picsText: String) {
        let rows = rowsText.components(separatedBy: "\n").filter { !$0.isEmpty }.map { $0.components(separatedBy: "\t") }
        if rows.isEmpty { return }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        let when = fmt.string(from: Date())
        var pics = [[String]]()
        for line in picsText.components(separatedBy: "\n") where !line.isEmpty {
            let p = line.components(separatedBy: "\t")
            pics.append(["GST", when, "", "GST", p[0], p.count > 1 ? p[1] : "", "", "", ""])
        }
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        let safe = name.replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "_", options: .regularExpression)
        let file = "gst_" + safe + "_" + fmt.string(from: Date()) + ".pngmesh"
        let mesh = AnaMesh.writeGst(rows, pics: pics, head: head)
        let dir = exportDir()
        let meshURL = dir.appendingPathComponent(file), sideURL = dir.appendingPathComponent(file + ".sha256")
        do {
            try mesh.write(to: meshURL)
            try Data(AnaMesh.sidecar(name: file, mesh: mesh).utf8).write(to: sideURL)
        } catch {
            toast("Couldn't make the GST file: \(error.localizedDescription)")
            return
        }
        share([meshURL, sideURL])
    }

    /// spec: one field per line, "label|default|number" or "label|default|text"
    private func gstAsk(_ id: String, _ title: String, _ message: String, _ spec: String) {
        let ac = UIAlertController(title: title, message: message.isEmpty ? nil : message, preferredStyle: .alert)
        for line in spec.components(separatedBy: "\n") where !line.isEmpty {
            let f = line.components(separatedBy: "|")
            ac.addTextField { t in
                t.placeholder = f[0]
                t.text = f.count > 1 ? f[1] : ""
                t.keyboardType = f.count > 2 && f[2] == "number" ? .decimalPad : .default
                t.autocapitalizationType = .sentences
            }
        }
        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.gstAnswers[id] = "C" })
        ac.addAction(UIAlertAction(title: "OK", style: .default) { [weak self, weak ac] _ in
            var v = "O"
            for t in ac?.textFields ?? [] {
                let s = (t.text ?? "").replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
                v += "\t" + s.trimmingCharacters(in: .whitespaces)
            }
            self?.gstAnswers[id] = v
        })
        present(ac, animated: true)
    }

    /// items: one choice per line; the answer is "O TAB index"
    private func gstPick(_ id: String, _ title: String, _ items: String) {
        let ac = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for (i, it) in items.components(separatedBy: "\n").enumerated() {
            ac.addAction(UIAlertAction(title: it, style: .default) { [weak self] _ in self?.gstAnswers[id] = "O\t\(i)" })
        }
        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.gstAnswers[id] = "C" })
        if let pop = ac.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        present(ac, animated: true)
    }

    // ================================================================================================ a short message
    func toast(_ msg: String) {
        let box = UIView()
        box.backgroundColor = UIColor(white: 0.12, alpha: 0.94)
        box.layer.cornerRadius = 14
        box.translatesAutoresizingMaskIntoConstraints = false
        let l = UILabel()
        l.text = msg
        l.textColor = .white
        l.font = .systemFont(ofSize: 15)
        l.numberOfLines = 0
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(l)
        view.addSubview(box)
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            l.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
            l.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            l.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
            box.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            box.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48),
            box.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -150),
        ])
        UIView.animate(withDuration: 0.3, delay: 3.0, options: [], animations: { box.alpha = 0 }, completion: { _ in
            box.removeFromSuperview()
        })
    }
}

/// "Add a reminder": what, and when (for EFINOTE's future ball).
final class ReminderViewController: UIViewController {
    var onSave: ((String, Date) -> Void)?
    private let field = UITextField()
    private let picker = UIDatePicker()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "New reminder"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))
        field.placeholder = "Reminder"
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .sentences
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .inline
        picker.minimumDate = Date()
        let stack = UIStackView(arrangedSubviews: [field, picker])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
        ])
    }

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func save() {
        let t = (field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        onSave?(t.isEmpty ? "Reminder" : t, picker.date)
        dismiss(animated: true)
    }
}

extension ViewController {

    // ------------------------------------------------------------------ APPify FIND (experimental)
    /// Type any app name: it becomes a tile on APPify; OPEN on it searches the App Store for that name.
    func findAdd() {
        let a = UIAlertController(title: "Find an app", message: "Type any app's name. It goes on the globe; OPEN looks it up in the App Store.", preferredStyle: .alert)
        a.addTextField { t in t.placeholder = "App name"; t.autocapitalizationType = .words }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Add", style: .default) { [weak self, weak a] _ in
            guard let self = self else { return }
            let n = (a?.textFields?.first?.text ?? "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty else { return }
            var l = self.pref("finds").components(separatedBy: "\n").filter { !$0.isEmpty && $0 != n }
            l.insert(String(n.prefix(40)), at: 0)
            self.defaults.set(l.prefix(40).joined(separator: "\n"), forKey: "p_finds")
        })
        present(a, animated: true)
    }
}
