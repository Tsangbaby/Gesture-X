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
        UIView.setAnimationsEnabled(false)
        var constructions = 0
        var homeEntries = 0
        var actionTrips = 0
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
                let navigation = UINavigationController(rootViewController: controller)
                window.rootViewController = navigation
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
                require(cell.textLabel?.text == "主屏幕的手势", "root must link to 主屏幕的手势")
                require(cell.accessoryType == .disclosureIndicator && cell.accessoryView == nil,
                        "root must navigate, not duplicate the gesture switch")
                constructions += 1

                table.delegate?.tableView?(table, didSelectRowAt: IndexPath(row: 0, section: 0))
                guard let home = navigation.topViewController as? TapLockSettingsController,
                      home !== controller else {
                    require(false, "home category did not push its real controller")
                    return false
                }
                home.loadViewIfNeeded()
                home.viewWillAppear(false)
                home.view.layoutIfNeeded()
                guard let homeTable = home.view as? UITableView else {
                    require(false, "home table missing")
                    return false
                }
                require(home.title == "主屏幕的手势", "wrong home title")
                require(home.tableView(homeTable, numberOfRowsInSection: 0) == 2,
                        "home must expose only its switch and current action")
                let switchCell = home.tableView(homeTable, cellForRowAt: IndexPath(row: 0, section: 0))
                guard let toggle = switchCell.accessoryView as? UISwitch else {
                    require(false, "real setting switch missing")
                    return false
                }
                require(switchCell.textLabel?.text == "启用主屏双击", "wrong switch title")
                let original = TapLockPreferences.readEnabled()
                require(toggle.isOn == original, "moving the setting reset its saved value")
                toggle.setOn(!original, animated: false)
                toggle.sendActions(for: .valueChanged)
                require(TapLockPreferences.readEnabled() == !original, "real switch did not persist")
                homeEntries += 1
                let actionCell = home.tableView(homeTable, cellForRowAt: IndexPath(row: 1, section: 0))
                require(actionCell.textLabel?.text == "选择双击动作" &&
                        actionCell.detailTextLabel?.text == "系统锁屏" &&
                        actionCell.accessoryType == .disclosureIndicator,
                        "current action summary/navigation missing")

                homeTable.delegate?.tableView?(homeTable, didSelectRowAt: IndexPath(row: 1, section: 0))
                guard let action = navigation.topViewController as? TapLockSettingsController,
                      action !== home else {
                    require(false, "action page did not push")
                    return false
                }
                action.loadViewIfNeeded()
                guard let actionTable = action.view as? UITableView else {
                    require(false, "action table missing")
                    return false
                }
                require(action.title == "选择双击动作" &&
                        action.tableView(actionTable, numberOfRowsInSection: 0) == 1,
                        "unimplemented actions must not be exposed")
                let selected = action.tableView(actionTable, cellForRowAt: IndexPath(row: 0, section: 0))
                require(selected.textLabel?.text == "系统锁屏" && selected.accessoryType == .checkmark,
                        "accepted lock action must remain selected")
                actionTable.delegate?.tableView?(actionTable, didSelectRowAt: IndexPath(row: 0, section: 0))
                require(navigation.topViewController === home, "selecting current action must return home")
                require(TapLockPreferences.readEnabled() == !original, "action navigation changed enable state")
                actionTrips += 1

                navigation.popToRootViewController(animated: false)
                table.delegate?.tableView?(table, didSelectRowAt: IndexPath(row: 0, section: 0))
                guard let reopened = navigation.topViewController as? TapLockSettingsController,
                      reopened !== home else {
                    require(false, "home must be reconstructed on reentry")
                    return false
                }
                reopened.loadViewIfNeeded()
                reopened.viewWillAppear(false)
                guard let reopenedTable = reopened.view as? UITableView,
                      let savedToggle = reopened.tableView(reopenedTable,
                          cellForRowAt: IndexPath(row: 0, section: 0)).accessoryView as? UISwitch else {
                    require(false, "reopened switch missing")
                    return false
                }
                require(savedToggle.isOn == !original, "reentry lost the persisted gesture value")
                homeEntries += 1
                savedToggle.setOn(original, animated: false)
                savedToggle.sendActions(for: .valueChanged)
                require(TapLockPreferences.readEnabled() == original, "switch could not restore its value")
                window.isHidden = true
                self.window = nil
                print("PASS: \(preferLegacy ? "legacy" : "default") constructor + full Settings round trip #\(iteration)")
            }
        }
        print("FIXED_CONSTRUCTION_PASS: \(constructions) UIKit constructions; \(homeEntries) home entries with real preference writes; \(actionTrips) action round trips; iOS Simulator \(UIDevice.current.systemVersion); fixture boundary only")
        fflush(stdout)
        exit(0)
    }
}
