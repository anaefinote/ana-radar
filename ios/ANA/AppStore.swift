import UIKit

/// APPify on iOS: what iOS won't tell an app about other apps (their icons, names, categories), looked up by
/// bundle ID on Apple's public App Store directory (itunes.apple.com/lookup?bundleId=...), once per app, and
/// kept on the phone. The bundle IDs come from the notifications ANA on Android relays back (AndroidLink).
///
/// OPEN: iOS only opens another app through a link address it knows (whatsapp:// ...). Known ones are below;
/// any other app opens on its App Store page (one more tap: Open).
final class AppStore {
    static let shared = AppStore()

    /// Called on the main queue when an app's icon has arrived (APPify draws it then).
    var onIcon: ((String) -> Void)?
    private var busy = Set<String>()
    private let d = UserDefaults.standard

    private var dir: URL {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("appicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func file(_ bundle: String) -> URL {
        let safe = bundle.replacingOccurrences(of: "/", with: "_")
        return dir.appendingPathComponent(safe + ".img")
    }

    /// The icon as a data: URL, or "" (and the lookup starts; onIcon says when it's here).
    func iconData(_ bundle: String) -> String {
        if let data = try? Data(contentsOf: file(bundle)), !data.isEmpty {
            let png = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
            return "data:image/" + (png ? "png" : "jpeg") + ";base64," + data.base64EncodedString()
        }
        lookup(bundle)
        return ""
    }

    func category(_ bundle: String) -> String { d.string(forKey: "as_cat_" + bundle) ?? "" }
    func name(_ bundle: String) -> String? { d.string(forKey: "as_name_" + bundle) }

    private func lookup(_ bundle: String) {
        guard !bundle.isEmpty, !busy.contains(bundle) else { return }
        // looked up already: again only after a day (it may not be on the App Store, e.g. Apple's own apps)
        let last = d.double(forKey: "as_at_" + bundle)
        if last > 0 && Date().timeIntervalSince1970 - last < 86_400 { return }
        busy.insert(bundle)
        let region = (Locale.current.regionCode ?? "US").lowercased()
        query(bundle, countries: region == "us" ? ["us"] : [region, "us"])
    }

    private func query(_ bundle: String, countries: [String]) {
        guard let country = countries.first else { finish(bundle); return }
        var c = URLComponents(string: "https://itunes.apple.com/lookup")!
        c.queryItems = [URLQueryItem(name: "bundleId", value: bundle), URLQueryItem(name: "country", value: country)]
        guard let url = c.url else { finish(bundle); return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let results = obj["results"] as? [[String: Any]], let r = results.first else {
                self.query(bundle, countries: Array(countries.dropFirst()))
                return
            }
            if let n = r["trackName"] as? String { self.d.set(n, forKey: "as_name_" + bundle) }
            if let g = r["primaryGenreName"] as? String { self.d.set(g, forKey: "as_cat_" + bundle) }
            if let s = r["trackViewUrl"] as? String { self.d.set(s, forKey: "as_url_" + bundle) }
            let art = (r["artworkUrl512"] as? String) ?? (r["artworkUrl100"] as? String) ?? ""
            guard let au = URL(string: art) else { self.finish(bundle); return }
            URLSession.shared.dataTask(with: au) { img, _, _ in
                if let img = img, !img.isEmpty {
                    try? img.write(to: self.file(bundle))
                    DispatchQueue.main.async { self.onIcon?(bundle) }
                }
                self.finish(bundle)
            }.resume()
        }.resume()
    }

    private func finish(_ bundle: String) {
        DispatchQueue.main.async {
            self.busy.remove(bundle)
            self.d.set(Date().timeIntervalSince1970, forKey: "as_at_" + bundle)
        }
    }

    // ------------------------------------------------------------------------------------------ OPEN
    /// Link addresses of well-known apps (iOS opens an app only through one of these).
    static let schemes: [String: String] = [
        "net.whatsapp.WhatsApp": "whatsapp://",
        "com.burbn.instagram": "instagram://",
        "com.facebook.Facebook": "fb://",
        "com.facebook.Messenger": "fb-messenger://",
        "com.atebits.Tweetie2": "twitter://",
        "ph.telegra.Telegraph": "tg://",
        "com.google.Gmail": "googlegmail://",
        "com.google.ios.youtube": "youtube://",
        "com.spotify.client": "spotify://",
        "com.apple.MobileSMS": "sms:",
        "com.apple.mobilemail": "message:",
        "com.apple.mobilecal": "calshow:",
        "com.apple.Maps": "maps:",
    ]

    /// Opens the app if iOS lets us, else its App Store page (else an App Store search for its name).
    func open(_ bundle: String, label: String) {
        let store: () -> Void = {
            if let s = self.d.string(forKey: "as_url_" + bundle), let u = URL(string: s) {
                UIApplication.shared.open(u)
            } else if let q = label.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let u = URL(string: "https://apps.apple.com/search?term=" + q) {
                UIApplication.shared.open(u)
            }
        }
        if let s = AppStore.schemes[bundle], let u = URL(string: s) {
            UIApplication.shared.open(u, options: [:]) { ok in if !ok { store() } }
        } else {
            store()
        }
    }
}
