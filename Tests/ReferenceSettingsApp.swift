import UIKit
import ObjectiveC.runtime
import CoreFoundation
import Darwin

// The same executable is compiled against frozen 0.1.8/9/10/11/12 and the candidate.
// Observe only UIKit datasource/delegate and existing Shared APIs: never new
// renderer/model internals. The JSON oracle is independently pinned by CI.
@main
final class ReferenceSettingsApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var originalPreferences: [String: Any]?
    private var resourceBackup: (URL, Data)?
    private var oracle: [String: Any] = [:]
    private var titles: [String: String] = [:]
    private var checks = 0

    private func checkpoint(_ name: String) {
        print("REFERENCE_SETTINGS_CHECKPOINT: " + name)
        fflush(stdout)
    }

    private func preferences() -> [String: Any] {
        _ = CFPreferencesSynchronize(TapLockPreferences.domain as CFString,
                                     kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return CFPreferencesCopyMultiple(nil, TapLockPreferences.domain as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any] ?? [:]
    }

    private func restorePreferences(_ values: [String: Any]) {
        for key in preferences().keys {
            CFPreferencesSetValue(key as CFString, nil, TapLockPreferences.domain as CFString,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        for (key, value) in values {
            CFPreferencesSetValue(key as CFString, value as CFPropertyList,
                TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        _ = CFPreferencesSynchronize(TapLockPreferences.domain as CFString,
                                     kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private func finish(_ message: String, status: Int32) -> Never {
        if let (url, data) = resourceBackup { try? data.write(to: url, options: .atomic) }
        if let original = originalPreferences { restorePreferences(original) }
        print(message)
        fflush(stdout)
        exit(status)
    }

    private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { finish("REFERENCE_SETTINGS_FAIL: " + message, status: 1) }
    }

    private func seed(enabled: CFPropertyList? = nil, action: CFPropertyList? = nil) {
        CFPreferencesSetValue(TapLockPreferences.enabledKey as CFString, enabled,
            TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSetValue(TapLockPreferences.actionKey as CFString, action,
            TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        require(CFPreferencesSynchronize(TapLockPreferences.domain as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost), "preference seed failed")
    }

    private func samePreferences(_ snapshot: [String: Any]) -> Bool {
        NSDictionary(dictionary: preferences()).isEqual(to: snapshot)
    }

    private func array(_ key: String) -> [[String: Any]] {
        guard let result = oracle[key] as? [[String: Any]] else {
            finish("REFERENCE_SETTINGS_FAIL: malformed oracle collection " + key, status: 1)
        }
        return result
    }

    private func visibleSections(_ key: String) -> [[String: Any]] {
        array(key).map { section in
            var result = section
            result["rows"] = (section["rows"] as? [[String: Any]] ?? []).filter {
                ($0["phoneOnly"] as? Bool) != true || UIDevice.current.userInterfaceIdiom == .phone
            }
            return result
        }
    }

    private func construct(_ legacy: Bool) -> TapLockSettingsController {
        let result = TLConstructDetail(TapLockSettingsController.self, legacy)
        require(result["path"] as? String == (legacy ? "legacy" : "default"), "wrong construction path: \(result)")
        guard let controller = result["controller"] as? TapLockSettingsController else {
            finish("REFERENCE_SETTINGS_FAIL: construction failed: \(result)", status: 1)
        }
        return controller
    }

    private func table(_ controller: UIViewController) -> UITableView {
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)
        controller.view.layoutIfNeeded()
        guard let result = controller.view as? UITableView else {
            finish("REFERENCE_SETTINGS_FAIL: controller has no UIKit table", status: 1)
        }
        require(result.dataSource === controller && result.delegate === controller, "table ownership changed")
        return result
    }

    private func paths(_ table: UITableView) -> [IndexPath] {
        guard let source = table.dataSource else { finish("REFERENCE_SETTINGS_FAIL: missing datasource", status: 1) }
        return (0..<(source.numberOfSections?(in: table) ?? 1)).flatMap { section in
            (0..<source.tableView(table, numberOfRowsInSection: section)).map { IndexPath(row: $0, section: section) }
        }
    }

    private func cell(_ table: UITableView, _ path: IndexPath) -> UITableViewCell {
        guard let source = table.dataSource else { finish("REFERENCE_SETTINGS_FAIL: missing datasource", status: 1) }
        return source.tableView(table, cellForRowAt: path)
    }

    private func tap(_ table: UITableView, _ path: IndexPath) {
        table.delegate?.tableView?(table, didSelectRowAt: path)
    }

    private func find(_ table: UITableView, id: String) -> IndexPath {
        guard let result = paths(table).first(where: { cell(table, $0).accessibilityIdentifier == id }) else {
            finish("REFERENCE_SETTINGS_FAIL: missing row " + id, status: 1)
        }
        return result
    }

    private func push(_ table: UITableView, _ path: IndexPath, _ nav: UINavigationController,
                      title: String) -> UIViewController {
        let old = nav.topViewController
        let depth = nav.viewControllers.count
        tap(table, path)
        guard let next = nav.topViewController else { finish("REFERENCE_SETTINGS_FAIL: empty navigation", status: 1) }
        require(next !== old && next is TapLockSettingsController && nav.viewControllers.count == depth + 1,
                "navigation did not push " + title)
        _ = self.table(next)
        require(next.title == title, "wrong destination title: \(next.title ?? "nil") expected \(title)")
        return next
    }

    private func checkInert(_ table: UITableView, _ path: IndexPath, _ nav: UINavigationController) {
        let target = cell(table, path)
        require(!target.isUserInteractionEnabled && target.selectionStyle == .none &&
                target.accessibilityTraits.contains(.notEnabled), "disabled row looks enabled")
        let before = preferences()
        let stack = nav.viewControllers
        let presented = nav.topViewController?.presentedViewController
        if let toggle = target.accessoryView as? UISwitch {
            require(!toggle.isEnabled, "disabled switch is enabled")
            toggle.setOn(!toggle.isOn, animated: false)
            toggle.sendActions(for: .valueChanged)
        }
        // Bypass UIKit's normal disabled-row delivery guard deliberately.
        tap(table, path)
        require(samePreferences(before), "disabled row wrote preferences")
        require(nav.viewControllers.count == stack.count &&
                zip(nav.viewControllers, stack).allSatisfy { $0.0 === $0.1 }, "disabled row navigated")
        require(nav.topViewController?.presentedViewController === presented, "disabled row presented a controller")
    }

    private func layoutMatches(_ table: UITableView, sections: [[String: Any]]) -> Bool {
        guard let source = table.dataSource,
              (source.numberOfSections?(in: table) ?? 1) == sections.count else { return false }
        for (s, section) in sections.enumerated() {
            let rows = section["rows"] as? [[String: Any]] ?? []
            guard source.tableView(table, numberOfRowsInSection: s) == rows.count else { return false }
            for (r, row) in rows.enumerated() {
                let rendered = cell(table, IndexPath(row: r, section: s))
                guard rendered.textLabel?.text == row["title"] as? String else { return false }
            }
        }
        return true
    }

    private func checkSections(_ table: UITableView, key: String, nav: UINavigationController,
                               allowed: Set<String>) {
        let sections = visibleSections(key)
        require(layoutMatches(table, sections: sections), key + " order/count/title differs from oracle")
        for (s, section) in sections.enumerated() {
            let header = table.dataSource?.tableView?(table, titleForHeaderInSection: s)
            require(header == section["header"] as? String, key + " header differs")
            if let expected = section["footer"] as? String, !expected.isEmpty {
                require((table.dataSource?.tableView?(table, titleForFooterInSection: s) ?? "").contains(expected),
                        key + " original footer missing")
            }
            for (r, row) in (section["rows"] as? [[String: Any]] ?? []).enumerated() {
                let path = IndexPath(row: r, section: s)
                let id = row["id"] as? String ?? ""
                let rendered = cell(table, path)
                require(rendered.accessibilityIdentifier == id, "row identity differs")
                if row["kind"] as? String == "switch" {
                    require(rendered.accessoryView is UISwitch, "switch rendered as non-switch: " + id)
                }
                if allowed.contains(id) {
                    require(rendered.isUserInteractionEnabled, "implemented row disabled: " + id)
                } else { checkInert(table, path, nav) }
            }
        }
    }

    private func checkBasic(_ table: UITableView, entries: [[String: Any]], nav: UINavigationController,
                            selected: TapLockPreferences.Action) {
        require(paths(table).count == entries.count, "basic search count differs")
        for (r, entry) in entries.enumerated() {
            let path = IndexPath(row: r, section: 0)
            let rendered = cell(table, path)
            require(rendered.textLabel?.text == entry["title"] as? String, "basic order/title differs")
            require(rendered.accessibilityIdentifier == entry["id"] as? String, "basic row identity differs")
            if let symbol = entry["image"] as? String, let expected = UIImage(systemName: symbol) {
                require(rendered.imageView?.image?.isEqual(expected) == true, "basic reference symbol differs: " + symbol)
            } else { require(rendered.imageView?.image == nil, "invented basic icon") }
            let kind = entry["actionKind"] as? String
            let available = entry["available"] as? Bool == true
            let action = kind.flatMap { actionForKind($0) }
            require((rendered.accessoryType == .checkmark) == (available && action == selected), "basic checkmark not exclusive/current")
            if available { require(rendered.isUserInteractionEnabled && action != nil, "implemented basic row disabled") }
            else { checkInert(table, path, nav) }
        }
    }

    private func actionForKind(_ kind: String) -> TapLockPreferences.Action? {
        switch kind {
        case "screenshot": return .screenshot
        case "controlCenter": return .controlCenter
        case "notificationCenter": return .notificationCenter
        case "lock": return .lock
        case "appSwitcher": return .appSwitcher
        #if !MEDIA_PLAY_PAUSE_UNAVAILABLE
        case "playPause": return .playPause
        #endif
        #if !MEDIA_PLAY_PAUSE_UNAVAILABLE && !MEDIA_TRACKS_UNAVAILABLE
        case "previousTrack": return .previousTrack
        case "nextTrack": return .nextTrack
        #endif
        #if REFERENCE_SETTINGS_CURRENT || SYSTEM_MUTE_BASELINE
        case "flashlight": return .flashlight
        #endif
        #if REFERENCE_SETTINGS_CURRENT
        case "systemMute": return .systemMute
        #endif
        default: return nil
        }
    }

    private func openActions(home: UIViewController, nav: UINavigationController) -> UIViewController {
        let homeTable = table(home)
        return push(homeTable, find(homeTable, id: "homescreenDoubleTap"), nav, title: titles["actions"]!)
    }

    private func checkSelected(_ controller: UIViewController, title: String?, action: TapLockPreferences.Action) {
        let current = table(controller)
        require(current.dataSource?.numberOfSections?(in: current) == 2, "action picker needs two sections")
        require(current.dataSource?.tableView(current, numberOfRowsInSection: 0) == 1, "selected action must be single-valued")
        let chosen = cell(current, IndexPath(row: 0, section: 0))
        if let title = title { require(chosen.textLabel?.text == title, "selected action summary differs") }
        require((chosen.accessoryType == .checkmark) == (action != .unavailable), "selected checkmark differs")
        require(TapLockPreferences.readAction() == action, "rendering changed stored action")
        require(controller.navigationItem.rightBarButtonItem?.isEnabled == false, "edit button missing or enabled")
        let footer = current.dataSource?.tableView?(current, titleForFooterInSection: 0) ?? ""
        for word in ["多选", "编辑", "排序", "尚未实现", "原版说明"] {
            require(footer.contains(word), "action capability disclosure missing: " + word)
        }
        require(footer.contains(oracle["originalSelectedFooter"] as? String ?? "MISSING"), "original action footer missing")
        for path in paths(current) {
            require(current.dataSource?.tableView?(current, canEditRowAt: path) == false, "row permits editing")
            require(current.dataSource?.tableView?(current, canMoveRowAt: path) == false, "row permits sorting")
        }
    }

    private func runRoundTrip(_ legacy: Bool) {
        checkpoint(legacy ? "legacy constructor roundtrip" : "default constructor roundtrip")
        seed()
        require(!TapLockPreferences.readEnabled() && TapLockPreferences.readAction() == .lock, "missing defaults changed")
        let root = construct(legacy)
        let nav = UINavigationController(rootViewController: root)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = nav
        self.window = window
        window.makeKeyAndVisible()
        let rootTable = table(root)
        let baseline = ProcessInfo.processInfo.arguments.contains("--expect-reference-baseline-failure")
        let matches = layoutMatches(rootTable, sections: visibleSections("rootSections"))
        if baseline {
            require(!matches, "baseline unexpectedly satisfies reference root")
            finish("REFERENCE_SETTINGS_BASELINE_EXPECTED_FAILURE: root navigation differs from reference", status: 0)
        }
        require(matches, "root navigation differs from reference")
        require(root.title == titles["root"], "root identity changed")
        checkpoint("reference root matched")
        #if REFERENCE_SETTINGS_CURRENT
        checkSections(rootTable, key: "rootSections", nav: nav, allowed: ["homescreenOptions", "bottomOptions"])
        #else
        checkSections(rootTable, key: "rootSections", nav: nav, allowed: ["homescreenOptions"])
        #endif
        let fullRoot = array("rootSections").flatMap { $0["rows"] as? [[String: Any]] ?? [] }
        let rootNavigationIDs = ["dockOptions", "statusBarOptions", "homescreenOptions", "bottomOptions",
            "reachabilityOptions", "hardwareButtonOptions", "advanceOptions", "editPresetURLs", "customInterface"]
        require(fullRoot.compactMap { $0["id"] as? String }.filter { rootNavigationIDs.contains($0) } == rootNavigationIDs,
                "oracle must describe nine original root entries in order")
        require(fullRoot.filter { $0["phoneOnly"] as? Bool == true }.compactMap { $0["id"] as? String } ==
                ["bottomOptions", "reachabilityOptions"], "oracle phone-only contract differs")
        let home = push(rootTable, find(rootTable, id: "homescreenOptions"), nav, title: titles["home"]!)
        let homeTable = table(home)
        require(paths(homeTable).count == 21, "Home must always show 21 controls")
        checkSections(homeTable, key: "homeSections", nav: nav,
                      allowed: ["homescreenDoubleTapEnabled", "homescreenDoubleTap"])
        let enablePath = find(homeTable, id: "homescreenDoubleTapEnabled")
        guard let toggle = cell(homeTable, enablePath).accessoryView as? UISwitch else {
            finish("REFERENCE_SETTINGS_FAIL: Home switch missing", status: 1)
        }
        require(!toggle.isOn && toggle.isEnabled, "default enable switch must be off and usable")
        toggle.setOn(true, animated: false)
        toggle.sendActions(for: .valueChanged)
        require(TapLockPreferences.readEnabled(), "Home switch did not save")
        require(paths(homeTable).count == 21, "enabling hid reference controls")
        var actions = openActions(home: home, nav: nav)
        let actionTable = table(actions)
        checkSelected(actions, title: "系统锁屏", action: .lock)
        require(actionTable.dataSource?.tableView?(actionTable, titleForHeaderInSection: 0) == titles["selected"], "selected header differs")
        require(actionTable.dataSource?.tableView?(actionTable, titleForHeaderInSection: 1) == titles["choose"], "choose header differs")
        let categories = array("actionCategories")
        require(categories.count == 6 && actionTable.dataSource?.tableView(actionTable, numberOfRowsInSection: 1) == 6,
                "six reference categories missing")
        checkInert(actionTable, IndexPath(row: 0, section: 0), nav)
        for (r, category) in categories.enumerated() {
            let path = IndexPath(row: r, section: 1)
            require(cell(actionTable, path).textLabel?.text == category["title"] as? String, "category order/title differs")
            if r >= 2 { checkInert(actionTable, path, nav) }
        }
        let entries = array("basicActions")
        checkpoint("Home and action categories matched")
        #if MEDIA_PLAY_PAUSE_UNAVAILABLE
        let expectedBasicCount = 5
        #elseif MEDIA_TRACKS_UNAVAILABLE
        let expectedBasicCount = 6
        #elseif FLASHLIGHT_BASELINE
        let expectedBasicCount = 8
        #elseif SYSTEM_MUTE_BASELINE
        let expectedBasicCount = 9
        #else
        let expectedBasicCount = 10
        #endif
        let implementedEntries = entries.filter { $0["available"] as? Bool == true }
        require(entries.count == 68 && implementedEntries.count == expectedBasicCount, "oracle basic scope differs")
        #if REFERENCE_SETTINGS_CURRENT
        let currentBasicIdentities: Set<String> = [
            "SYSTEM_SCREENSHOT", "SYSTEM_CONTROLCENTER", "SYSTEM_COVER", "SYSTEM_LOCKSCREEN",
            "SYSTEM_SWITCHER", "PLAYPAUSE_MEDIA", "PREVIOUS_MEDIA", "NEXT_MEDIA", "TOGGLE_FLASHLIGHT", "SYSTEM_MUTE"]
        require(Set(implementedEntries.compactMap { $0["id"] as? String }) == currentBasicIdentities,
                "current ten basic identities differ")
        let currentBasicKinds: [String: String] = [
            "SYSTEM_SCREENSHOT": "screenshot", "SYSTEM_CONTROLCENTER": "controlCenter",
            "SYSTEM_COVER": "notificationCenter", "SYSTEM_LOCKSCREEN": "lock",
            "SYSTEM_SWITCHER": "appSwitcher", "PLAYPAUSE_MEDIA": "playPause",
            "PREVIOUS_MEDIA": "previousTrack", "NEXT_MEDIA": "nextTrack",
            "TOGGLE_FLASHLIGHT": "flashlight", "SYSTEM_MUTE": "systemMute"]
        require(implementedEntries.allSatisfy { entry in
            guard let id = entry["id"] as? String, let kind = entry["actionKind"] as? String else { return false }
            return currentBasicKinds[id] == kind
        }, "current ten basic action mappings differ or alias")
        guard let systemMuteEntry = entries.first(where: { $0["id"] as? String == "SYSTEM_MUTE" }) else {
            finish("REFERENCE_SETTINGS_FAIL: original system-mute entry missing", status: 1)
        }
        require(systemMuteEntry["referenceSlot"] as? Int == 32 &&
                systemMuteEntry["referenceActionNumber"] as? Int == 50 &&
                systemMuteEntry["title"] as? String == "系统静音" &&
                systemMuteEntry["image"] as? String == "bell.slash", "original system-mute identity changed")
        #endif
        let basic = push(actionTable, IndexPath(row: 0, section: 1), nav, title: titles["basic"]!)
        let basicTable = table(basic)
        if ProcessInfo.processInfo.arguments.contains("--expect-media-baseline-failure") {
            let media = find(basicTable, id: "PLAYPAUSE_MEDIA")
            require(!cell(basicTable, media).isUserInteractionEnabled, "baseline unexpectedly supports play/pause")
            let before = preferences()
            tap(basicTable, media)
            require(samePreferences(before) && nav.topViewController === basic, "disabled baseline media row had side effects")
            finish("MEDIA_SETTINGS_BASELINE_EXPECTED_FAILURE: original play/pause row is disabled", status: 0)
        }
        if ProcessInfo.processInfo.arguments.contains("--expect-track-baseline-failure") {
            for id in ["PREVIOUS_MEDIA", "NEXT_MEDIA"] {
                let track = find(basicTable, id: id)
                checkInert(basicTable, track, nav)
                require(nav.topViewController === basic, "disabled baseline track left basic picker")
            }
            finish("MEDIA_TRACKS_SETTINGS_BASELINE_EXPECTED_FAILURE: original previous/next rows are disabled", status: 0)
        }
        if ProcessInfo.processInfo.arguments.contains("--expect-flashlight-baseline-failure") {
            let flashlight = find(basicTable, id: "TOGGLE_FLASHLIGHT")
            require(cell(basicTable, flashlight).textLabel?.text == "开关手电", "baseline flashlight identity differs")
            checkInert(basicTable, flashlight, nav)
            require(nav.topViewController === basic, "disabled baseline flashlight left basic picker")
            finish("FLASHLIGHT_SETTINGS_BASELINE_EXPECTED_FAILURE: original flashlight row is disabled", status: 0)
        }
        if ProcessInfo.processInfo.arguments.contains("--expect-system-mute-baseline-failure") {
            let systemMute = find(basicTable, id: "SYSTEM_MUTE")
            require(cell(basicTable, systemMute).textLabel?.text == "系统静音", "baseline system-mute identity differs")
            checkInert(basicTable, systemMute, nav)
            require(nav.topViewController === basic, "disabled baseline system-mute left basic picker")
            finish("SYSTEM_MUTE_SETTINGS_BASELINE_EXPECTED_FAILURE: original system-mute row is disabled", status: 0)
        }
        checkBasic(basicTable, entries: entries, nav: nav, selected: .lock)
        guard let search = basic.navigationItem.searchController,
              let updater = search.searchResultsUpdater else {
            finish("REFERENCE_SETTINGS_FAIL: real search controller/updater missing", status: 1)
        }
        let searchSnapshot = preferences()
        for query in ["hammerit", "HAMMERIT", "系统", "播放/暂停", "上一首", "下一首", "开关手电", "系统静音", "no-such-reference-action", ""] {
            search.searchBar.text = query
            updater.updateSearchResults(for: search)
            let expected = query.isEmpty ? entries : entries.filter {
                ($0["title"] as? String ?? "").range(of: query, options: .caseInsensitive) != nil
            }
            checkBasic(basicTable, entries: expected, nav: nav, selected: .lock)
            require(samePreferences(searchSnapshot), "search mutated preferences")
        }
        // Refresh while this exact controller survives: never cache stale selection.
        seed(enabled: kCFBooleanTrue, action: ["kind": "controlCenter"] as CFDictionary)
        search.searchBar.text = "中心"
        updater.updateSearchResults(for: search)
        checkBasic(basicTable, entries: entries.filter { ($0["title"] as? String ?? "").contains("中心") },
                   nav: nav, selected: .controlCenter)
        search.searchBar.text = ""
        updater.updateSearchResults(for: search)
        checkBasic(basicTable, entries: entries, nav: nav, selected: .controlCenter)
        nav.popViewController(animated: false)
        for entry in implementedEntries {
            guard let kind = entry["actionKind"] as? String, let action = actionForKind(kind),
                  let name = entry["title"] as? String, let id = entry["id"] as? String else {
                finish("REFERENCE_SETTINGS_FAIL: oracle basic mapping missing", status: 1)
            }
            let picker = push(table(actions), IndexPath(row: 0, section: 1), nav, title: titles["basic"]!)
            let pickerTable = table(picker)
            tap(pickerTable, find(pickerTable, id: id))
            require(nav.topViewController === actions, "basic selection did not return to action manager")
            require(TapLockPreferences.readEnabled(), "basic action reset enable state")
            checkSelected(actions, title: name, action: action)
            let persisted = preferences()[TapLockPreferences.actionKey] as? [String: String]
            require(persisted == ["kind": kind], "basic selection did not replace the single value")
            let reopened = push(table(actions), IndexPath(row: 0, section: 1), nav, title: titles["basic"]!)
            checkBasic(table(reopened), entries: entries, nav: nav, selected: action)
            nav.popViewController(animated: false)
            nav.popViewController(animated: false)
            require(nav.topViewController === home, "action manager did not pop home")
            require(cell(table(home), find(table(home), id: "homescreenDoubleTap")).detailTextLabel?.text == name,
                    "Home summary did not refresh")
            let rebuilt = openActions(home: home, nav: nav)
            require(rebuilt !== actions, "action manager was not reconstructed")
            checkSelected(rebuilt, title: name, action: action)
            // Keep the original actions instance for the next category trip.
            nav.popViewController(animated: false)
            nav.pushViewController(actions, animated: false)
        }
        let beforeApp = preferences()
        checkpoint("basic search and ten single-value replacements matched")
        let app = push(table(actions), IndexPath(row: 1, section: 1), nav, title: titles["application"]!)
        let appTable = table(app)
        let appPaths = paths(appTable)
        require(!appPaths.isEmpty, "real installed simulator App catalog is empty")
        let expectedApps = InstalledApplications.choices()
        require(appPaths.count == expectedApps.count, "App snapshot differs from real installed catalog")
        for (r, choice) in expectedApps.enumerated() {
            let rendered = cell(appTable, IndexPath(row: r, section: 0))
            require(rendered.textLabel?.text == choice.name && rendered.detailTextLabel?.text == choice.identifier,
                    "App snapshot order/name/identifier differs")
        }
        // Choose an App whose actual UIKit private icon loader succeeds, not a placeholder.
        guard let targetPath = appPaths.first(where: {
            guard let id = cell(appTable, $0).detailTextLabel?.text else { return false }
            return ApplicationIcons.load(identifier: id) != nil
        }) else { finish("REFERENCE_SETTINGS_FAIL: no real installed App icon available", status: 1) }
        let target = cell(appTable, targetPath)
        guard let id = target.detailTextLabel?.text, let name = target.textLabel?.text,
              let icon = target.imageView?.image else {
            finish("REFERENCE_SETTINGS_FAIL: real App cell incomplete", status: 1)
        }
        require(icon.size == CGSize(width: 32, height: 32) && target.imageView?.contentMode == .scaleAspectFit,
                "App icon must be real 32pt aspect-fit canvas")
        let renderedPNG = icon.pngData()
        let loadedPNG = ApplicationIcons.normalized(ApplicationIcons.load(identifier: id))?.pngData()
        require(renderedPNG != nil && renderedPNG == loadedPNG,
                "App icon differs from actual UIKit loaded image")
        for _ in 0..<20 {
            require(cell(appTable, targetPath).imageView?.image === icon, "App cell did not reuse cached icon")
        }
        require(samePreferences(beforeApp), "App rendering changed preferences")
        nav.popViewController(animated: false)
        require(samePreferences(beforeApp), "App cancel changed preferences")
        nav.pushViewController(app, animated: false)
        tap(table(app), targetPath)
        require(nav.topViewController === actions && TapLockPreferences.readAction() == .openApp(id),
                "App selection did not save and return")
        require(TapLockPreferences.readEnabled(), "App action reset enable state")
        require(preferences()[TapLockPreferences.actionKey] as? [String: String] ==
                ["kind": "openApp", "bundleIdentifier": id], "App selection is not a single record")
        checkSelected(actions, title: "打开应用 · " + name, action: .openApp(id))
        let reopenedApp = push(table(actions), IndexPath(row: 1, section: 1), nav, title: titles["application"]!)
        let savedTable = table(reopenedApp)
        for path in paths(savedTable) {
            let rendered = cell(savedTable, path)
            require((rendered.accessoryType == .checkmark) == (rendered.detailTextLabel?.text == id),
                    "App saved checkmark missing or not exclusive")
        }
        nav.popViewController(animated: false)
        nav.popViewController(animated: false)
        require(nav.topViewController === home, "App action manager did not return home")
        let appHomeTable = table(home)
        require(cell(appHomeTable, find(appHomeTable, id: "homescreenDoubleTap")).detailTextLabel?.text ==
                "打开应用 · " + name, "Home App summary did not refresh")
        let previousActions = actions
        actions = openActions(home: home, nav: nav)
        require(actions !== previousActions, "App action manager was not reconstructed")
        checkSelected(actions, title: "打开应用 · " + name, action: .openApp(id))
        // Every basic action must replace an App, and the App must replace
        // every basic action. Reuse the complete candidate identity set; never
        // keep a hand-written old-action subset that omits a newly added row.
        for enabled in [false, true] {
            seed(enabled: enabled ? kCFBooleanTrue : kCFBooleanFalse,
                 action: ["kind": "openApp", "bundleIdentifier": id] as CFDictionary)
            for entry in implementedEntries {
                guard let kind = entry["actionKind"] as? String, let action = actionForKind(kind),
                      let basicName = entry["title"] as? String, let basicID = entry["id"] as? String else {
                    finish("REFERENCE_SETTINGS_FAIL: replacement oracle mapping missing", status: 1)
                }
                let replace = push(table(actions), IndexPath(row: 0, section: 1), nav, title: titles["basic"]!)
                checkBasic(table(replace), entries: entries, nav: nav, selected: .openApp(id))
                tap(table(replace), find(table(replace), id: basicID))
                require(nav.topViewController === actions, "App-to-basic replacement did not return")
                require(TapLockPreferences.readEnabled() == enabled, "App replacement changed enable state")
                require(preferences()[TapLockPreferences.actionKey] as? [String: String] == ["kind": kind],
                        "App-to-basic replacement is not a single value")
                checkSelected(actions, title: basicName, action: action)
                let verifyBasic = push(table(actions), IndexPath(row: 0, section: 1), nav, title: titles["basic"]!)
                checkBasic(table(verifyBasic), entries: entries, nav: nav, selected: action)
                nav.popViewController(animated: false)
                nav.popViewController(animated: false)
                require(nav.topViewController === home, "replacement did not return Home")
                require(cell(table(home), find(table(home), id: "homescreenDoubleTap")).detailTextLabel?.text == basicName,
                        "Home replacement basic summary did not refresh")
                actions = openActions(home: home, nav: nav)
                checkSelected(actions, title: basicName, action: action)
                let replaceApp = push(table(actions), IndexPath(row: 1, section: 1), nav, title: titles["application"]!)
                let replaceAppTable = table(replaceApp)
                for path in paths(replaceAppTable) {
                    require(cell(replaceAppTable, path).accessoryType != .checkmark,
                            "basic-to-App picker retained an old App checkmark")
                }
                guard let appPath = paths(replaceAppTable).first(where: {
                    cell(replaceAppTable, $0).detailTextLabel?.text == id
                }) else { finish("REFERENCE_SETTINGS_FAIL: replacement App disappeared", status: 1) }
                tap(replaceAppTable, appPath)
                require(nav.topViewController === actions, "basic-to-App replacement did not return")
                require(TapLockPreferences.readEnabled() == enabled, "App replacement changed enable state")
                require(preferences()[TapLockPreferences.actionKey] as? [String: String] ==
                        ["kind": "openApp", "bundleIdentifier": id], "basic-to-App replacement is not a single record")
                checkSelected(actions, title: "打开应用 · " + name, action: .openApp(id))
                let verifyApp = push(table(actions), IndexPath(row: 1, section: 1), nav, title: titles["application"]!)
                let verifyAppTable = table(verifyApp)
                for path in paths(verifyAppTable) {
                    let rendered = cell(verifyAppTable, path)
                    require((rendered.accessoryType == .checkmark) == (rendered.detailTextLabel?.text == id),
                            "replacement App checkmark missing or not exclusive")
                }
                nav.popViewController(animated: false)
                nav.popViewController(animated: false)
                require(nav.topViewController === home, "replacement App did not return Home")
                require(cell(table(home), find(table(home), id: "homescreenDoubleTap")).detailTextLabel?.text ==
                        "打开应用 · " + name, "Home replacement App summary did not refresh")
                actions = openActions(home: home, nav: nav)
                checkSelected(actions, title: "打开应用 · " + name, action: .openApp(id))
            }
        }
        nav.popToRootViewController(animated: false)
        let reentered = push(table(root), find(table(root), id: "homescreenOptions"), nav, title: titles["home"]!)
        let reenteredTable = table(reentered)
        let savedToggle = cell(reenteredTable, find(reenteredTable, id: "homescreenDoubleTapEnabled")).accessoryView as? UISwitch
        require(savedToggle?.isOn == true, "Home reentry lost enable value")
        require(paths(reenteredTable).count == 21, "Home reentry hid disabled controls")
        // Malformed existing preference values fail closed, never substitute lock.
        let malformedValues: [CFPropertyList] = ["broken" as CFString,
            ["kind": "Siri"] as CFDictionary, ["kind": "lock", "extra": "bad"] as CFDictionary,
            ["kind": "openApp", "bundleIdentifier": "bad/id"] as CFDictionary]
        for malformed in malformedValues {
            seed(enabled: "not-a-bool" as CFString, action: malformed)
            require(!TapLockPreferences.readEnabled() && TapLockPreferences.readAction() == .unavailable,
                    "malformed preference did not fail closed")
            let invalidActions = openActions(home: reentered, nav: nav)
            checkSelected(invalidActions, title: "配置不可用，请重新选择", action: .unavailable)
            let invalidBasic = push(table(invalidActions), IndexPath(row: 0, section: 1), nav, title: titles["basic"]!)
            checkBasic(table(invalidBasic), entries: entries, nav: nav, selected: .unavailable)
            nav.popViewController(animated: false)
            nav.popViewController(animated: false)
        }
        seed()
        let missingActions = openActions(home: reentered, nav: nav)
        checkSelected(missingActions, title: "系统锁屏", action: .lock)
        window.isHidden = true
        self.window = nil
        checkpoint("App save/reentry and malformed preference roundtrip completed")
    }

    private func checkUnavailableResources() {
        let bundle = Bundle(for: TapLockSettingsController.self)
        guard let url = bundle.url(forResource: "SettingsReference", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            finish("REFERENCE_SETTINGS_FAIL: cannot locate packaged test resource", status: 1)
        }
        // Mutate only this disposable simulator app's resource, never source.
        resourceBackup = (url, data)
        for missing in [true, false] {
            do {
                if missing { try FileManager.default.removeItem(at: url) }
                else { try Data("{malformed".utf8).write(to: url, options: .atomic) }
                for legacy in [false, true] {
                    let unavailable = construct(legacy)
                    let nav = UINavigationController(rootViewController: unavailable)
                    let current = table(unavailable)
                    require(paths(current).count == 1, "unavailable resource must show safe status only")
                    require(cell(current, IndexPath(row: 0, section: 0)).textLabel?.text == "设置不可用", "missing safe unavailable message")
                    checkInert(current, IndexPath(row: 0, section: 0), nav)
                }
                try data.write(to: url, options: .atomic)
            } catch { finish("REFERENCE_SETTINGS_FAIL: disposable resource probe failed: \(error)", status: 1) }
        }
        resourceBackup = nil
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        let modes = ["--expect-reference-baseline-failure", "--expect-media-baseline-failure", "--expect-track-baseline-failure", "--expect-flashlight-baseline-failure", "--expect-system-mute-baseline-failure", "--expect-reference-fixed"]
        require(modes.filter { arguments.contains($0) }.count == 1, "choose exactly one reference test mode")
        guard let host = NSClassFromString("PSViewController") else {
            finish("REFERENCE_SETTINGS_FAIL: native Preferences fixture missing", status: 1)
        }
        let legacySelector = NSSelectorFromString("initForContentSize:")
        require(class_getInstanceMethod(host, legacySelector) == nil, "fixture unexpectedly implements legacy initializer")
        require(class_getInstanceMethod(TapLockSettingsController.self, legacySelector) != nil, "controller legacy factory missing")
        let image = class_getImageName(host).map { String(cString: $0) } ?? ""
        require(image.contains(".app/Frameworks/Preferences.framework/Preferences"), "wrong native fixture image: " + image)
        guard let url = Bundle.main.url(forResource: "SettingsReference", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let reference = object as? [String: Any], let titleMap = reference["titles"] as? [String: String] else {
            finish("REFERENCE_SETTINGS_FAIL: independent JSON oracle missing or malformed", status: 1)
        }
        oracle = reference
        titles = titleMap
        for key in ["root", "home", "actions", "basic", "application", "selected", "choose"] {
            require(!(titles[key] ?? "").isEmpty, "oracle title missing: " + key)
        }
        originalPreferences = preferences()
        restorePreferences([:])
        UIView.setAnimationsEnabled(false)
        // Do not run the full assertion matrix inside UIApplication's launch
        // callback. Return to the native lifecycle before exercising navigation.
        DispatchQueue.main.async {
            self.runRoundTrip(true)
            self.runRoundTrip(false)
            self.checkpoint("resource fail-closed probes")
            self.checkUnavailableResources()
            self.finish("REFERENCE_SETTINGS_UIKIT_PASS: \(self.checks) assertions; both native constructors; reference root/Home/categories; inert controls; 68-row search; ten single-value replacements; installed App snapshot/real 32pt icon/save/reentry; defaults/malformed/resource fail-closed; simulator fixture boundary only", status: 0)
        }
        return true
    }
}
