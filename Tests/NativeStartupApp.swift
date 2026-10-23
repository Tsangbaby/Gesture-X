import UIKit
import Darwin

// Only the system class and Hook installer are fixtures. The loaded dylib uses
// the complete production tweak source graph, optimized with dead stripping.
@objc(SBIconListView)
class IconListFixture: UIView {
    var originalCalls = 0
    var recognizersBeforeOriginal: [Int] = []

    @objc dynamic override func didMoveToWindow() {
        originalCalls += 1
        recognizersBeforeOriginal.append(gestureRecognizers?.count ?? 0)
        super.didMoveToWindow()
    }
}

@main
final class NativeStartupApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var image: UnsafeMutableRawPointer?
    private var passed = 0

    private func checkpoint(_ name: String) {
        print("NATIVE_STARTUP_CHECKPOINT: \(name)")
        fflush(stdout)
    }

    private func check(_ value: @autoclosure () -> Bool, _ name: String) {
        guard value() else {
            print("NATIVE_STARTUP_FAIL: \(name)")
            fflush(stdout)
            exit(1)
        }
        passed += 1
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        checkpoint("application launched")
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        self.window = window
        window.makeKeyAndVisible()
        DispatchQueue.main.async { self.loadTweak() }
        return true
    }

    private func loadTweak() {
        check(NSClassFromString("SBIconListView").map { ObjectIdentifier($0) } ==
              ObjectIdentifier(IconListFixture.self), "explicit system-class fixture")
        check(TLHookInstallCount() == 0, "no test-side installation before dlopen")
        let path = Bundle.main.bundlePath + "/Frameworks/TapLockStartup.dylib"
        checkpoint("before dlopen")
        image = dlopen(path, RTLD_NOW | RTLD_LOCAL)
        checkpoint("after dlopen")
        if image == nil {
            let reason = dlerror().map { String(cString: $0) } ?? "unknown loader error"
            check(false, "dlopen: \(reason)")
        }
        check(TLHookInstallCount() == 0, "loader callback deferred to main queue")
        DispatchQueue.main.async { self.verifyHook() }
    }

    private func verifyHook() {
        checkpoint("verify hook")
        check(TLHookInstallCount() == 1, "dyld initializer automatically installed native hook")
        let host = window!.rootViewController!.view!
        let list = IconListFixture(frame: CGRect(x: 10, y: 100, width: 250, height: 350))
        host.addSubview(list)
        check(list.originalCalls == 1, "original forwarded exactly once on attachment")
        check(list.recognizersBeforeOriginal == [0], "original ran before recognizer attachment")
        let taps = (list.gestureRecognizers ?? []).compactMap { $0 as? UITapGestureRecognizer }
        check(taps.count == 1 && taps[0].numberOfTapsRequired == 2 &&
              taps[0].numberOfTouchesRequired == 1, "actual production recognizer attached")
        list.removeFromSuperview()
        check(list.originalCalls == 2 && (list.gestureRecognizers ?? []).isEmpty,
              "detach forwards once and removes recognizer")
        host.addSubview(list)
        check(list.originalCalls == 3 && list.gestureRecognizers?.count == 1,
              "reattach forwards once without duplicate recognizers")
        guard let symbol = dlsym(image, "taplock_test_reactivate") else {
            check(false, "test-only reactivation entry")
            return
        }
        let reactivate = unsafeBitCast(symbol, to: (@convention(c) () -> Void).self)
        reactivate()
        reactivate()
        check(TLHookInstallCount() == 1 && list.gestureRecognizers?.count == 1,
              "repeated activation is idempotent")
        print("NATIVE_STARTUP_PASS: \(passed) executed production-startup/hook/attachment checks")
        print("Boundary: UIKit simulator with system-class and Hook-installer fixtures; NOT handset injection or lock proof")
        fflush(stdout)
        // Never dlclose an image while its installed Hook is still reachable.
        exit(0)
    }
}
