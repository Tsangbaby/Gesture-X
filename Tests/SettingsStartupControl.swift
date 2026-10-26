import UIKit
import Darwin

// Disposable startup control only; never included in a production Makefile.
@MainActor
final class SettingsStartupControlApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        TLSDRecord("didFinishLaunching")
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        self.window = window
        window.makeKeyAndVisible()
        TLSDRecord("control-ui-attached")
        DispatchQueue.main.async {
            TLSDRecord("control-pass")
            print("SETTINGS_STARTUP_CONTROL_PASS")
            fflush(stdout)
            exit(0)
        }
        return true
    }
}
