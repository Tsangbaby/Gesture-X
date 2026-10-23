import UIKit
import ObjectiveC.runtime
import Darwin

// The real production controller + preference reader run against a native
// UIKit superclass fixture that deliberately lacks the obsolete initializer.
// This is constructor regression coverage, NOT a real-device Settings test.
@main
final class SettingsConstructionApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            print("SETTINGS_CONSTRUCTION_FAIL: \(message)")
            fflush(stdout)
            exit(1)
        }
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let selector = NSSelectorFromString("initForContentSize:")
        guard let host = NSClassFromString("PSViewController") else {
            require(false, "fixture class missing")
            return false
        }
        require(class_getInstanceMethod(host, selector) == nil,
                "test superclass must not implement the legacy selector")
        let hostImage = class_getImageName(host).map { String(cString: $0) } ?? ""
        require(hostImage.contains(".app/Frameworks/Preferences.framework/Preferences"),
                "must run against the declared test fixture, not system Preferences: \(hostImage)")
        require(class_getInstanceMethod(TapLockSettingsController.self, selector) != nil,
                "detail class must publish the legacy factory selector")

        if ProcessInfo.processInfo.arguments.contains("--expect-legacy-failure") {
            let result = TLConstructDetail(TapLockSettingsController.self, true)
            require(result["exception"] as? String == "NSInvalidArgumentException",
                    "baseline did not reproduce the expected exception: \(result)")
            require((result["reason"] as? String)?.contains("initForContentSize:") == true,
                    "baseline failed for an unrelated reason: \(result)")
            print("BASELINE_EXPECTED_FAILURE: \(result["reason"] ?? "")")
            fflush(stdout)
            exit(0)
        }

        require(ProcessInfo.processInfo.arguments.contains("--expect-fixed"), "missing test mode")
        for preferLegacy in [true, false] {
            for iteration in 1...5 {
                let result = TLConstructDetail(TapLockSettingsController.self, preferLegacy)
                guard let controller = result["controller"] as? TapLockSettingsController else {
                    require(false, "construction failed: \(result)")
                    return false
                }
                require(result["path"] as? String == (preferLegacy ? "legacy" : "default"),
                        "factory did not take the requested path")
                let window = UIWindow(frame: UIScreen.main.bounds)
                window.rootViewController = UINavigationController(rootViewController: controller)
                self.window = window
                window.makeKeyAndVisible()
                controller.loadViewIfNeeded()
                controller.viewWillAppear(false)
                controller.view.layoutIfNeeded()
                guard let table = controller.view as? UITableView else {
                    require(false, "settings did not create its real table")
                    return false
                }
                require(table.dataSource === controller, "wrong table data source")
                require(controller.numberOfSections(in: table) == 1, "unexpected section count")
                require(controller.tableView(table, numberOfRowsInSection: 0) == 1, "unexpected row count")
                let cell = controller.tableView(table, cellForRowAt: IndexPath(row: 0, section: 0))
                require(cell.accessoryView is UISwitch, "real setting switch missing")
                print("PASS: \(preferLegacy ? "legacy" : "default") constructor + real table/switch #\(iteration)")
            }
        }
        print("FIXED_CONSTRUCTION_PASS: 10 UIKit constructions; iOS Simulator \(UIDevice.current.systemVersion); fixture boundary only")
        fflush(stdout)
        exit(0)
    }
}
