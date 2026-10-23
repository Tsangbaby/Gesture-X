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

    #if OPEN_APP_FEATURE
    // Inspect only the disposable simulator when a real OS integration gate
    // fails. These probes never enter either production target or the package.
    private func inspectEmptyCatalog() {
        func signature(_ receiver: AnyObject, _ name: String) -> String {
            guard let type = object_getClass(receiver),
                  let method = class_getInstanceMethod(type, NSSelectorFromString(name)),
                  let encoding = method_getTypeEncoding(method) else { return "missing" }
            return String(cString: encoding)
        }
        for name in ["LSApplicationWorkspace", "LSApplicationProxy"] {
            print("LS_PROBE: class \(name) = \(String(describing: NSClassFromString(name)))")
        }
        guard let workspaceType = NSClassFromString("LSApplicationWorkspace") else { fflush(stdout); return }
        print("LS_PROBE: defaultWorkspace \(signature(workspaceType as AnyObject, "defaultWorkspace"))")
        guard let workspace = PrivateAPI.object(workspaceType as AnyObject, "defaultWorkspace") else { fflush(stdout); return }
        print("LS_PROBE: allApplications \(signature(workspace, "allApplications")); open \(signature(workspace, "openApplicationWithBundleID:"))")
        let proxies = PrivateAPI.object(workspace, "allApplications") as? [NSObject] ?? []
        print("LS_PROBE: raw catalog \(proxies.count); filtered catalog \(InstalledApplications.choices().count)")
        for proxy in proxies.prefix(6) {
            print("LS_PROBE: proxy \(type(of: proxy))")
            for selector in ["isInstalled", "isLaunchProhibited", "applicationType", "bundleIdentifier", "localizedName", "appTags"] {
                let value = selector.hasPrefix("is") ? String(describing: PrivateAPI.bool(proxy, selector)) :
                    String(describing: PrivateAPI.object(proxy, selector))
                print("LS_PROBE: \(selector) ABI=\(signature(proxy, selector)) value=\(value)")
            }
            if let record = PrivateAPI.object(proxy, "correspondingApplicationRecord") {
                for selector in ["isLaunchProhibited", "appTags", "bundleIdentifier"] {
                    let value = selector.hasPrefix("is") ? String(describing: PrivateAPI.bool(record, selector)) :
                        String(describing: PrivateAPI.object(record, selector))
                    print("LS_PROBE: record \(type(of: record)) \(selector) ABI=\(signature(record, selector)) value=\(value)")
                }
            }
        }
        fflush(stdout)
    }
    #endif

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        print("SETTINGS_CHECKPOINT: didFinishLaunching \(ProcessInfo.processInfo.arguments)")
        fflush(stdout)
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
                #if OPEN_APP_ROWS
                let expectedActionRows = 2
                #else
                let expectedActionRows = 1
                #endif
                require(action.title == "选择双击动作" &&
                        action.tableView(actionTable, numberOfRowsInSection: 0) == expectedActionRows,
                        "unimplemented actions must not be exposed")
                let selected = action.tableView(actionTable, cellForRowAt: IndexPath(row: 0, section: 0))
                require(selected.textLabel?.text == "系统锁屏" && selected.accessoryType == .checkmark,
                        "accepted lock action must remain selected")
                #if OPEN_APP_FEATURE
                let appAction = action.tableView(actionTable, cellForRowAt: IndexPath(row: 1, section: 0))
                require(appAction.textLabel?.text == "打开指定App", "App action row missing")
                actionTable.delegate?.tableView?(actionTable, didSelectRowAt: IndexPath(row: 1, section: 0))
                guard let picker = navigation.topViewController as? TapLockSettingsController,
                      picker !== action else { require(false, "App picker did not push"); return false }
                picker.loadViewIfNeeded()
                picker.viewWillAppear(false)
                guard let pickerTable = picker.view as? UITableView else {
                    require(false, "App picker table missing"); return false
                }
                require(picker.title == "选择App", "wrong App picker title")
                if picker.tableView(pickerTable, numberOfRowsInSection: 0) == 0 { inspectEmptyCatalog() }
                require(picker.tableView(pickerTable, numberOfRowsInSection: 0) > 0,
                        "installed simulator exposes no selectable Apps")
                let target = picker.tableView(pickerTable, cellForRowAt: IndexPath(row: 0, section: 0))
                guard let identifier = target.detailTextLabel?.text, let name = target.textLabel?.text else {
                    require(false, "App picker lost name/Bundle ID"); return false
                }
                #if APP_ICONS
                require(target.imageView?.image != nil, "App picker icon missing")
                require(target.imageView?.image?.size == CGSize(width: 32, height: 32),
                        "App picker icon canvas must be 32 points")
                require(target.imageView?.contentMode == .scaleAspectFit, "App icon must preserve aspect ratio")
                let firstIcon = target.imageView?.image
                for _ in 0..<20 {
                    let cell = picker.tableView(pickerTable, cellForRowAt: IndexPath(row: 0, section: 0))
                    require(cell.imageView?.image === firstIcon,
                            "repeated App cell rendering must reuse the cached icon")
                }
                #endif
                #if APP_ICON_LOADER_TESTS
                // Real UIKit icon selector, not a UIImage fixture or symbol-only replacement.
                require(ApplicationIcons.load(identifier: identifier) != nil,
                        "actual UIKit loader did not return the installed App icon")
                let iconCache = ApplicationIcons()
                let icon = iconCache.image(identifier: identifier)
                require(icon != nil && iconCache.image(identifier: identifier) === icon,
                        "real icon loader/cache failed")
                require(iconCache.image(identifier: "bad/id") == nil, "invalid icon identifier accepted")
                let missingIcon = iconCache.image(identifier: "com.tsangbaby.taplock.not-installed")
                require(missingIcon?.size == CGSize(width: 32, height: 32),
                        "missing App icon must use a fixed-size placeholder")
                require(ApplicationIcons.normalized(nil) == nil, "nil image cannot be rendered")
                let wide = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40)).image { context in
                    UIColor.red.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
                }
                require(ApplicationIcons.normalized(wide)?.size == CGSize(width: 32, height: 32),
                        "wide image was not fitted to the icon canvas")
                print("APP_ICON_UIKIT_PASS: actual installed-App icon + cache + placeholder + 32pt renderer")
                #endif
                // Rendering cells uses the cached snapshot. It must not reset selection.
                for _ in 0..<20 { _ = picker.tableView(pickerTable, cellForRowAt: IndexPath(row: 0, section: 0)) }
                require(TapLockPreferences.readAction() == .lock, "entering/cancelling picker changed the action")
                pickerTable.delegate?.tableView?(pickerTable, didSelectRowAt: IndexPath(row: 0, section: 0))
                require(navigation.topViewController === action, "App selection did not return to action page")
                require(TapLockPreferences.readAction() == .openApp(identifier), "App choice did not persist")
                action.viewWillAppear(false)
                let chosenApp = action.tableView(actionTable, cellForRowAt: IndexPath(row: 1, section: 0))
                require(chosenApp.accessoryType == .checkmark && chosenApp.detailTextLabel?.text == name,
                        "selected App checkmark/summary missing")
                require(action.tableView(actionTable, cellForRowAt: IndexPath(row: 0, section: 0)).accessoryType == .none,
                        "lock remained selected alongside App")
                home.viewWillAppear(false)
                require(home.tableView(homeTable, cellForRowAt: IndexPath(row: 1, section: 0)).detailTextLabel?.text ==
                        "打开指定App · " + name, "home App summary did not refresh")
                require(TapLockPreferences.readEnabled() == !original, "App selection changed the enable switch")
                print("PASS: real simulator App picker/selection/checkmark/summary #\(iteration)")
                #endif
                actionTable.delegate?.tableView?(actionTable, didSelectRowAt: IndexPath(row: 0, section: 0))
                require(navigation.topViewController === home, "selecting current action must return home")
                require(TapLockPreferences.readEnabled() == !original, "action navigation changed enable state")
                #if OPEN_APP_FEATURE
                require(TapLockPreferences.readAction() == .lock, "could not switch back from App to lock")
                #endif
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
