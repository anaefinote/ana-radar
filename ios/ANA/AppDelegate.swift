import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.overrideUserInterfaceStyle = .dark
        w.rootViewController = ViewController()
        w.makeKeyAndVisible()
        window = w
        return true
    }

    /// Back to the front: catch up on the relay (anything that came while away).
    func applicationDidBecomeActive(_ application: UIApplication) {
        AndroidLink.shared.refresh()
        ChatNet.shared.start()                     // CHATNOTE: listen over Wi-Fi / the Internet while ANA is open
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        ChatNet.shared.stop()
    }

    /// A .pngmesh or .sha256 opened with ANA (from Files, AirDrop, Mail, WhatsApp's "Open in…").
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        (window?.rootViewController as? ViewController)?.importURLs([url])
        return true
    }
}
