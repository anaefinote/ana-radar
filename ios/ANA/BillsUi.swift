import UIKit
import PhotosUI

/// BILLS: the screens on the iPhone (the same choices as Android's BillsUi.java).
extension ViewController: PHPickerViewControllerDelegate {

    private func sheet(_ title: String?, _ msg: String?) -> UIAlertController {
        let ac = UIAlertController(title: title, message: msg, preferredStyle: .actionSheet)
        if let pop = ac.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        return ac
    }

    func billsOpen() {
        if !defaults.bool(forKey: "bill_nomoney_ok") {         // said plainly, before anything else
            let a = UIAlertController(title: "Before you start: Novvera never touches money",
                                      message: BillCore.noMoney + "\n\nWhen someone helps with your bill, they pay your biller directly, from their own bank or biller app. "
                                        + "When you help, you do the same. Groups that pool money choose their own person to hold it. Never Novvera, never ANA.",
                                      preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Not now", style: .cancel))
            a.addAction(UIAlertAction(title: "I understand", style: .default) { [weak self] _ in
                self?.defaults.set(true, forKey: "bill_nomoney_ok")
                self?.billsOpen()
            })
            present(a, animated: true)
            return
        }
        Bills.shared.tick()
        let g = Bills.shared.goal()
        let ac = sheet("Bills  ·  \(Bills.shared.total) eFLEX earned", "Novvera never touches money. You pay your billers yourself.")
        ac.addAction(UIAlertAction(title: "30-day goal:  " + ViewController.bar(g.pct) + "  " + (g.bills == 0 ? "add a bill" : "\(g.pct)%"), style: .default) { [weak self] _ in self?.billGoal() })
        if Bills.shared.passOn() {
            ac.addAction(UIAlertAction(title: "You're 30 days ahead. Pass it on", style: .default) { [weak self] _ in self?.billInvite(passOn: true) })
        }
        for b in Bills.shared.list {
            ac.addAction(UIAlertAction(title: Bills.line(b), style: .default) { [weak self] _ in self?.billShow(b) })
        }
        ac.addAction(UIAlertAction(title: "+  A bill coming up (settle it on time)", style: .default) { [weak self] _ in self?.billNew("plan") })
        ac.addAction(UIAlertAction(title: "+  A bill I already paid", style: .default) { [weak self] _ in self?.billNew("paid") })
        ac.addAction(UIAlertAction(title: "Import a bill, journey, receipt or thank-you...", style: .default) { [weak self] _ in self?.pickFiles() })
        ac.addAction(UIAlertAction(title: "Tell someone about ANA", style: .default) { [weak self] _ in self?.billInvite(passOn: false) })
        ac.addAction(UIAlertAction(title: "Novvera never touches money (read this)", style: .default) { [weak self] _ in
            let a = UIAlertController(title: "Novvera never touches money", message: BillCore.noMoney, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in self?.billsOpen() })
            self?.present(a, animated: true)
        })
        ac.addAction(UIAlertAction(title: "Close", style: .cancel))
        present(ac, animated: true)
    }

    static func bar(_ pct: Int) -> String {
        let n = max(0, min(10, pct / 10))
        return String(repeating: "\u{2588}", count: n) + String(repeating: "\u{2591}", count: 10 - n)
    }

    // ------------------------------------------------------------------ the 30-day goal and the journey
    func billGoal() {
        let g = Bills.shared.goal()
        var m = "Have everything due in the next 30 days settled before it's due. Then this month's pay isn't paying this month's bills: you're off the payday cycle.\n\n"
        if g.bills == 0 { m += "Add your bills (light, water, phone, internet, TV ...) and they show here." }
        else {
            m += ViewController.bar(g.pct) + "  \(g.pct)%\n"
            m += g.pct >= 100 ? "You're there: everything due in the next 30 days is settled.\n"
                : "To go: " + BillCore.money(max(0, g.total - g.covered), "USD") + " of " + BillCore.money(g.total, "USD") + " (in US dollars)\n"
            for l in g.lines { m += "\n" + l }
            m += "\n\nTwo ways forward: settle a bill early, or set a little aside each day. And your people can step in: post your journey."
        }
        let a = UIAlertController(title: "Your 30-day settlement goal", message: m, preferredStyle: .alert)
        if g.bills > 0 && g.pct < 100 { a.addAction(UIAlertAction(title: "Post my journey", style: .default) { [weak self] _ in self?.billJourney() }) }
        a.addAction(UIAlertAction(title: "Back", style: .cancel) { [weak self] _ in self?.billsOpen() })
        present(a, animated: true)
    }

    func billJourney() {
        if (defaults.string(forKey: "bill_name") ?? "").isEmpty { billAskName { [weak self] in self?.billJourney() }; return }
        let a = UIAlertController(title: "Post your journey",
                                  message: "It shows how far you are from 30 days ahead and which bills are left, so your people can step in. It goes only to who you send it to: a family chat, your church group, your GST group.\n\nShow the names of people who've helped you?",
                                  preferredStyle: .alert)
        for (t, show) in [("Show them", true), ("Keep them private", false)] {
            a.addAction(UIAlertAction(title: t, style: .default) { [weak self] _ in
                guard let self = self else { return }
                if let f = Bills.shared.shareJourney(self.defaults.string(forKey: "bill_name") ?? "", showHelpers: show) { self.share(f) }
                else { self.toast("Couldn't make the file") }
            })
        }
        present(a, animated: true)
    }

    func billInvite(passOn: Bool) {
        let t = (passOn ? "Someone helped me get my bills 30 days ahead, so I'm passing it on. " : "")
            + "I'm using ANA to get my bills settled before they're due and off the payday cycle. Friends and family can step in and help, "
            + "and everybody who helps earns eFLEX. Novvera never touches money: you always pay your biller yourself. Ask me about it."
        share([t])
    }

    func billAskName(_ then: @escaping () -> Void) {
        let a = UIAlertController(title: "Your name", message: "It goes in the files you share.", preferredStyle: .alert)
        a.addTextField { $0.placeholder = "Your name, as friends know you"; $0.autocapitalizationType = .words }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "OK", style: .default) { [weak self, weak a] _ in
            let n = (a?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\t", with: " ")
            if n.isEmpty { return }
            self?.defaults.set(n, forKey: "bill_name")
            then()
        })
        present(a, animated: true)
    }

    /// someone's journey: step in on one of their bills (you pay the biller yourself)
    func billJourneyReceived(_ s: BillCore.Signed) {
        if s.keyId == Bills.shared.myKeyId() { toast("That's your own journey"); return }
        let open = Bills.journeyBills(s), who = s.get("journey|owner_name")
        var m = who + " is " + s.get("journey|pct") + "% of the way to having their bills settled 30 days ahead."
        if !s.get("journey|helped_by").isEmpty { m += "\nHelped so far by: " + s.get("journey|helped_by") }
        m += "\n\nNovvera never touches money. If you step in, you pay the biller yourself, from your own bank or biller app. When " + who + " confirms, you both earn eFLEX."
        let ac = sheet(who + "'s journey  ·  " + s.get("journey|pct") + "%", open.isEmpty ? m + "\n\nNothing left to settle right now." : m)
        for jb in open {
            let full = Int64(jb[2]) ?? 0
            ac.addAction(UIAlertAction(title: "Step in: " + BillCore.money(full, jb[3]) + "  " + jb[1] + "  ·  due " + Bills.fmtDue(jb[4]), style: .default) { [weak self] _ in
                let a = UIAlertController(title: jb[1], message: "How much will you pay (" + jb[3] + ")? You pay the biller yourself.", preferredStyle: .alert)
                a.addTextField { t in t.keyboardType = .decimalPad; t.text = BillCore.money(full, "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "") }
                a.addAction(UIAlertAction(title: "Back", style: .cancel))
                a.addAction(UIAlertAction(title: "I'll help", style: .default) { [weak self, weak a] _ in
                    let c = BillCore.cents(a?.textFields?.first?.text ?? "")
                    if c <= 0 || c > full { self?.toast("Between 0.01 and the bill's amount"); return }
                    let h = Bills.shared.acceptFromJourney(s, jb, c)
                    self?.billPickApp(h) { [weak self] in self?.billShow(h) }
                })
                self?.present(a, animated: true)
            })
        }
        ac.addAction(UIAlertAction(title: "Not now", style: .cancel))
        present(ac, animated: true)
    }

    func billShow(_ b: Bills.Bill) {
        let ac = sheet(b.name, Bills.detail(b, b.appName.isEmpty ? label(b.app) : b.appName))
        let cd = b.current()
        let cst = cd.map { b.get($0).state } ?? "proven"
        let paid = cst == "proven"
        if !paid {
            ac.addAction(UIAlertAction(title: b.app.isEmpty ? "Pick the app you'll pay with" : "Change the payment app", style: .default) { [weak self] _ in
                self?.billPickApp(b, then: nil)
            })
            if !b.app.isEmpty {
                ac.addAction(UIAlertAction(title: AndroidLink.shared.linked ? "Send to my Android again" : "Send to my Android as a file", style: .default) { [weak self] _ in
                    if AndroidLink.shared.linked { Bills.shared.sendSchedules(force: true); self?.toast("Sent: your Android checks " + b.name) }
                    else if let f = Bills.shared.shareSchedule(b) { self?.share(f) }
                })
            }
            if cst != "claimed" {
                ac.addAction(UIAlertAction(title: b.forBill.isEmpty ? "I paid: add a picture of the receipt" : "I set it aside today: add a picture", style: .default) { [weak self] _ in self?.billPicture(b) })
                ac.addAction(UIAlertAction(title: b.forBill.isEmpty ? "I paid (no picture)" : "I set it aside today", style: .default) { [weak self] _ in
                    self?.toast(Bills.shared.claim(b, pic: ""))
                    self?.deliverPending()
                })
            }
        }
        if b.kind == "plan" && b.forBill.isEmpty && b.every > 0 && !Bills.shared.list.contains(where: { $0.forBill == b.id }) {
            let days = max(1, BillCore.period(b.every, b.unit) / BillCore.day)
            ac.addAction(UIAlertAction(title: "Set aside a little each day (about " + BillCore.money((b.cents + days - 1) / days, b.cur) + ")", style: .default) { [weak self] _ in
                let k = Bills.shared.addSetAside(b)
                self?.toast("Added: " + k.name + ", daily. Tap it each day you set it aside.")
                self?.deliverPending()
            })
        }
        if b.kind == "plan" && !paid && b.forBill.isEmpty {
            ac.addAction(UIAlertAction(title: b.shared ? "Share this bill again (ask for help)" : "Ask for help: share this bill", style: .default) { [weak self] _ in self?.billShare(b) })
        }
        if b.kind == "help" && !b.thanked && b.get("help").state != "open" {
            ac.addAction(UIAlertAction(title: "Send my receipt to " + b.ownerName, style: .default) { [weak self] _ in self?.billShare(b) })
        }
        ac.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            Bills.shared.remove(b)
            self?.toast("Removed " + b.name + ". The eFLEX it earned stays.")
        })
        ac.addAction(UIAlertAction(title: "Back", style: .cancel) { [weak self] _ in self?.billsOpen() })
        present(ac, animated: true)
    }

    func billNew(_ kind: String) {
        let a = UIAlertController(title: kind == "plan" ? "A bill coming up" : "A bill I already paid",
                                  message: kind == "plan" ? "Pay it on or before the due date and it earns the most eFLEX." : "Reported after paying: it earns half of paying on time.",
                                  preferredStyle: .alert)
        a.addTextField { $0.placeholder = "Bill (e.g. Light bill, Water, Phone)"; $0.autocapitalizationType = .sentences }
        a.addTextField { $0.placeholder = "Amount (e.g. 125.00)"; $0.keyboardType = .decimalPad }
        a.addTextField { [weak self] t in t.placeholder = "Currency"; t.text = self?.defaults.string(forKey: "bill_cur") ?? "BBD"; t.autocapitalizationType = .allCharacters }
        if kind == "plan" {
            a.addTextField { t in
                t.placeholder = "First due date (yyyy-mm-dd)"
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
                t.text = f.string(from: Date().addingTimeInterval(7 * 86400))
            }
        }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Next", style: .default) { [weak self, weak a] _ in
            guard let self = self, let f = a?.textFields else { return }
            let n = (f[0].text ?? "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\t", with: " ")
            let c = BillCore.cents(f[1].text ?? "")
            let cy = (f[2].text ?? "").trimmingCharacters(in: .whitespaces).uppercased()
            let due = kind == "plan" ? (f[3].text ?? "").trimmingCharacters(in: .whitespaces) : ""
            if n.isEmpty || c <= 0 || cy.range(of: "^[A-Z]{3}$", options: .regularExpression) == nil {
                self.toast("Give the bill a name, an amount and a currency (BBD or USD)"); return
            }
            if kind == "plan" && BillCore.dayEnd(due) == 0 { self.toast("The due date as yyyy-mm-dd, e.g. 2026-11-25"); return }
            self.defaults.set(cy, forKey: "bill_cur")
            if kind == "paid" {
                let b = Bills.shared.add(kind, n, c, cy, due)
                self.billPickApp(b) { [weak self] in self?.billShow(b) }
                return
            }
            self.billRepeat { [weak self] every, unit in
                let b = Bills.shared.add(kind, n, c, cy, due, every: every, unit: unit)
                self?.toast(b.dates().count > 1 ? "Locked: \(b.dates().count) due dates in the next 12 months" : "Locked")
                self?.billPickApp(b) { [weak self] in self?.billShow(b) }
            }
        })
        present(a, animated: true)
    }

    /// how often: once, daily ... yearly, or every N days / weeks / months / years
    func billRepeat(_ done: @escaping (Int, String) -> Void) {
        let ac = sheet("How often is it due?", nil)
        let opts: [(String, Int, String)] = [("Once", 0, "month"), ("Daily", 1, "day"), ("Weekly", 1, "week"), ("Every 2 weeks", 2, "week"),
                                              ("Monthly", 1, "month"), ("Every 3 months", 3, "month"), ("Yearly", 1, "year")]
        for o in opts { ac.addAction(UIAlertAction(title: o.0, style: .default) { _ in done(o.1, o.2) }) }
        ac.addAction(UIAlertAction(title: "Every ... (choose)", style: .default) { [weak self] _ in
            let a = UIAlertController(title: "Every ...", message: "How many, then days, weeks, months or years", preferredStyle: .alert)
            a.addTextField { $0.placeholder = "e.g. 10"; $0.keyboardType = .numberPad }
            for u in BillCore.units {
                a.addAction(UIAlertAction(title: u + "s", style: .default) { [weak self, weak a] _ in
                    let n = Int(a?.textFields?.first?.text ?? "") ?? 0
                    if n < 1 || n > 366 { self?.toast("A number from 1 to 366"); return }
                    done(n, u)
                })
            }
            a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            self?.present(a, animated: true)
        })
        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(ac, animated: true)
    }

    func billPickApp(_ b: Bills.Bill, then: (() -> Void)?) {
        let apps = Bills.shared.recentApps()
        if apps.isEmpty {
            let a = UIAlertController(title: "Pick the payment app",
                                      message: "No payment notification has come through yet. On iPhone they arrive through Android ANA (iPhone notifications, over Bluetooth). Pay the bill; when your bank's notification arrives, open the bill and pick the app.",
                                      preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in then?() })
            present(a, animated: true)
            return
        }
        let ac = sheet("Which app will show the payment?", "Your bank or the biller")
        for p in apps.prefix(12) {
            let l = label(p)
            ac.addAction(UIAlertAction(title: l, style: .default) { [weak self] _ in
                Bills.shared.setApp(b, p, l)                      // goes to the Android now if linked
                self?.toast(AndroidLink.shared.linked ? "Sent to your Android: it checks the payments" : "Your Android checks it once linked (or send it as a file)")
                then?()
            })
        }
        ac.addAction(UIAlertAction(title: "Later", style: .cancel) { _ in then?() })
        present(ac, animated: true)
    }

    // ------------------------------------------------------------------ a picture of the receipt (no photo-library permission needed)
    private static var picFor = ""

    func billPicture(_ b: Bills.Bill) {
        ViewController.picFor = b.id
        var cfg = PHPickerConfiguration()
        cfg.filter = .images
        cfg.selectionLimit = 1
        let p = PHPickerViewController(configuration: cfg)
        p.delegate = self
        present(p, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let r = results.first, let b = Bills.shared.find(ViewController.picFor) else { return }
        r.itemProvider.loadDataRepresentation(forTypeIdentifier: "public.image") { [weak self] data, _ in
            DispatchQueue.main.async {
                guard let d = data else { self?.toast("Couldn't read the picture"); return }
                let name = b.id + ".img"
                try? d.write(to: Bills.dir.appendingPathComponent(name))
                self?.toast(Bills.shared.claim(b, pic: name))
                self?.deliverPending()
            }
        }
    }

    // ------------------------------------------------------------------ sharing
    func billShare(_ b: Bills.Bill) {
        let me = defaults.string(forKey: "bill_name") ?? ""
        if me.isEmpty {
            let a = UIAlertController(title: "Your name", message: "It goes in the bill files you share.", preferredStyle: .alert)
            a.addTextField { $0.placeholder = "Your name, as friends know you"; $0.autocapitalizationType = .words }
            a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            a.addAction(UIAlertAction(title: "OK", style: .default) { [weak self, weak a] _ in
                let n = (a?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\t", with: " ")
                if n.isEmpty { return }
                self?.defaults.set(n, forKey: "bill_name")
                self?.billShare(b)
            })
            present(a, animated: true)
            return
        }
        let files = b.kind == "help" ? Bills.shared.shareReceipt(b, me) : Bills.shared.shareBill(b, me)
        if let f = files { share(f) } else { toast("Couldn't make the file (this phone's key)") }
    }

    // ------------------------------------------------------------------ files arriving
    func billReceived(_ f: Data) {
        if BillCore.classOf(f) == BillCore.clsPaid {                // the Android's confirmation, sent as a file
            toast(Bills.shared.paid(f, viaLink: false) ?? "Already counted")
            deliverPending()
            return
        }
        let s = BillCore.read(f)
        if s.ok && s.cls == BillCore.clsJourney { billJourneyReceived(s); return }
        let v = Bills.shared.look(s)
        if !v.0 { toast(v.1); return }
        if s.cls == BillCore.clsBill {
            let full = Int64(s.get("bill|cents")) ?? 0
            let a = UIAlertController(title: "Help pay a bill", message: v.1 + "\n\nHow much will you pay (" + s.get("bill|currency") + ")?", preferredStyle: .alert)
            a.addTextField { t in t.keyboardType = .decimalPad; t.text = BillCore.money(full, "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "") }
            a.addAction(UIAlertAction(title: "Not now", style: .cancel))
            a.addAction(UIAlertAction(title: "I'll help", style: .default) { [weak self, weak a] _ in
                let c = BillCore.cents(a?.textFields?.first?.text ?? "")
                if c <= 0 || c > full { self?.toast("Between 0.01 and the bill's amount"); return }
                let h = Bills.shared.acceptBill(s, c)
                self?.billPickApp(h) { [weak self] in self?.billShow(h) }
            })
            present(a, animated: true)
        } else if s.cls == BillCore.clsHelp {
            let a = UIAlertController(title: "Did they help?", message: v.1, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "No", style: .cancel))
            a.addAction(UIAlertAction(title: "Yes, confirm", style: .default) { [weak self] _ in
                guard let files = Bills.shared.confirmHelp(s) else { self?.toast("Couldn't confirm"); return }
                self?.deliverPending()
                self?.toast("Confirmed. Now send the thank-you back to " + s.get("help|helper_name"))
                self?.share(files)
            })
            present(a, animated: true)
        } else {
            toast(Bills.shared.thanked(s))
            deliverPending()
        }
    }
}
