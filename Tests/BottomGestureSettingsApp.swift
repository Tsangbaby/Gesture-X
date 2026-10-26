import UIKit
import CoreFoundation
import Darwin

// The hostile table keeps the original production delegate, but must not ask
// that delegate's datasource to hand one cached accessory view to two tables.
private final class BottomRootForeignDataSource: NSObject, UITableViewDataSource {
    private let target: IndexPath
    private let identifier: String
    init(target: IndexPath, identifier: String) {
        self.target = target
        self.identifier = identifier
        super.init()
    }
    func numberOfSections(in tableView: UITableView) -> Int { target.section + 1 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == target.section ? target.row + 1 : 0
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.accessibilityIdentifier = indexPath == target ? identifier : "bottom.foreign.placeholder"
        cell.textLabel?.text = "底部上划手势"
        cell.accessoryType = .disclosureIndicator
        return cell
    }
}

// Executes production controllers and their actual table-owned controls. I/O
// failure/catalog fixtures do not replace rendering, parsing, mutation or guards.
@main
final class BottomGestureSettingsApp: UIResponder, UIApplicationDelegate {
    private typealias P = BottomGesturePreferences
    var window: UIWindow?
    private var nav: UINavigationController!
    private var checks = 0
    private var backup: [String: Any]?
    private var bottom: [String: Any] = [:]
    private var actionCatalog: [String: Any] = [:]
    private let supportedBasics: [(String, TapLockPreferences.Action)] = [
        ("SYSTEM_LOCKSCREEN", .lock), ("SYSTEM_CONTROLCENTER", .controlCenter),
        ("SYSTEM_COVER", .notificationCenter), ("SYSTEM_SCREENSHOT", .screenshot),
        ("SYSTEM_SWITCHER", .appSwitcher), ("PLAYPAUSE_MEDIA", .playPause),
        ("PREVIOUS_MEDIA", .previousTrack), ("NEXT_MEDIA", .nextTrack),
        ("TOGGLE_FLASHLIGHT", .flashlight), ("SYSTEM_MUTE", .systemMute)
    ]

    private func checkpoint(_ stage: String) {
        print("BOTTOM_UIKIT_CHECKPOINT: \(stage); assertions=\(checks)")
        fflush(stdout)
    }
    private func finish(_ error: String? = nil) -> Never {
        if let backup = backup { replacePreferences(backup) }
        if let error = error { print("BOTTOM_GESTURE_UIKIT_FAIL: " + error) }
        else { print("BOTTOM_GESTURE_UIKIT_PASS: assertions=\(checks)") }
        fflush(stdout)
        exit(error == nil ? 0 : 1)
    }
    private func require(_ predicate: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !predicate() { finish(message) }
    }
    private func preferences() -> [String: Any] {
        _ = CFPreferencesSynchronize(TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return CFPreferencesCopyMultiple(nil, TapLockPreferences.domain as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any] ?? [:]
    }
    private func replacePreferences(_ values: [String: Any]) {
        for key in preferences().keys {
            CFPreferencesSetValue(key as CFString, nil, TapLockPreferences.domain as CFString,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        for (key, value) in values {
            CFPreferencesSetValue(key as CFString, value as CFPropertyList, TapLockPreferences.domain as CFString,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        _ = CFPreferencesSynchronize(TapLockPreferences.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    private func samePreferences(_ values: [String: Any]) -> Bool {
        NSDictionary(dictionary: preferences()).isEqual(to: values)
    }
    private func settle() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
        nav.view.layoutIfNeeded()
    }
    private func waitFor(_ message: String, _ predicate: () -> Bool) {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !predicate() && ProcessInfo.processInfo.systemUptime < deadline { settle() }
        require(predicate(), message)
    }
    private func show(_ root: UIViewController) {
        nav.setViewControllers([root], animated: false)
        root.loadViewIfNeeded()
        settle()
    }
    private func table(_ controller: UIViewController? = nil) -> UITableView {
        let controller = controller ?? nav.topViewController!
        controller.loadViewIfNeeded()
        settle()
        guard let table = controller.view as? UITableView else { finish("production controller lacks table") }
        // UIKit can wrap a UITableViewController's datasource. Prove the public
        // controller-owned table identity instead of identifying that adapter.
        // The legacy PS controller still has to be its datasource directly.
        let ownsDataSource = table.dataSource === controller ||
            ((controller as? UITableViewController)?.tableView === table && table.dataSource != nil)
        require(table.delegate === controller && ownsDataSource,
                "wrong table owner: controller=\(controller); delegate=\(String(describing: table.delegate)); dataSource=\(String(describing: table.dataSource)); assertions=\(checks)")
        return table
    }
    private func paths(_ table: UITableView) -> [IndexPath] {
        guard let source = table.dataSource else { finish("missing datasource") }
        return (0..<(source.numberOfSections?(in: table) ?? 1)).flatMap { section in
            (0..<source.tableView(table, numberOfRowsInSection: section)).map { IndexPath(row: $0, section: section) }
        }
    }
    // Discover through the table's actual cells. A direct datasource request
    // creates shadow cells that can steal a production cached UISwitch and
    // make both cells repeatedly reparent it during Core Animation layout.
    private func find(_ table: UITableView, _ id: String) -> IndexPath {
        for path in paths(table) {
            table.scrollToRow(at: path, at: .middle, animated: false)
            table.layoutIfNeeded()
            if table.cellForRow(at: path)?.accessibilityIdentifier == id { return path }
        }
        finish("missing row: " + id)
    }
    private func ownedCell(_ table: UITableView, _ path: IndexPath) -> UITableViewCell {
        table.scrollToRow(at: path, at: .middle, animated: false)
        table.layoutIfNeeded()
        settle()
        guard let cell = table.cellForRow(at: path) else { finish("row is not table-owned/visible") }
        require(table.indexPath(for: cell) == path && table.visibleCells.contains(where: { $0 === cell }), "detached event target")
        return cell
    }
    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
    private func control<T: UIControl>(_ table: UITableView, id: String, type: T.Type) -> T {
        let path = find(table, id)
        let cell = ownedCell(table, path)
        guard let result = descendants(cell).compactMap({ $0 as? T }).first else { finish("missing real control: " + id) }
        return result
    }
    private func tap(_ table: UITableView, _ id: String) {
        let path = find(table, id)
        _ = ownedCell(table, path)
        table.delegate?.tableView?(table, didSelectRowAt: path)
        settle()
    }
    private func bar(_ id: String) {
        guard let item = nav.topViewController?.navigationItem.rightBarButtonItems?.first(where: { $0.accessibilityIdentifier == id }),
              let action = item.action else { finish("missing real bar control: " + id) }
        require(UIApplication.shared.sendAction(action, to: item.target, from: item, for: nil), "bar action not delivered")
        settle()
    }
    private func toggle(_ id: String, _ value: Bool) {
        let toggle = control(table(), id: id, type: UISwitch.self)
        toggle.setOn(value, animated: false)
        toggle.sendActions(for: .valueChanged)
        settle()
    }
    private func entry(_ id: String, _ text: String, expectingError: Bool = false) {
        let root = nav.topViewController!
        waitFor("previous modal still owns numeric editor: " + id) { root.presentedViewController == nil }
        let button = control(table(), id: id, type: UIButton.self)
        button.sendActions(for: .touchUpInside)
        waitFor("numeric editor not ready: " + id + "; input=" + text) {
            guard let alert = root.presentedViewController as? UIAlertController else { return false }
            return alert.textFields?.first != nil && !alert.isBeingPresented && !alert.isBeingDismissed
        }
        guard let alert = root.presentedViewController as? UIAlertController,
              let field = alert.textFields?.first else {
            finish("numeric editor did not present: id=\(id); input=\(text); control=\(String(describing: button.accessibilityIdentifier)); presented=\(String(describing: root.presentedViewController)); assertions=\(checks)")
        }
        guard let key = P.NumericKey(rawValue: id) else { finish("invalid test numeric key") }
        require(field.text == String(format: "%.2f", P.readSnapshot().number(key)), "entry prefill must preserve two decimals")
        field.text = text
        // Same production commit as Save, through the text field's actual Return
        // event (also supports an external keyboard with the decimal input pad).
        field.sendActions(for: .editingDidEndOnExit)
        if expectingError {
            waitFor("numeric failure lacks a ready error alert: " + id + "; input=" + text) {
                guard let alert = root.presentedViewController as? UIAlertController else { return false }
                return alert.title == "无法保存" && alert.textFields?.isEmpty != false &&
                    !alert.isBeingPresented && !alert.isBeingDismissed
            }
        } else {
            waitFor("saved numeric editor did not dismiss: " + id) { root.presentedViewController == nil }
        }
    }
    private func dismissError() {
        let root = nav.topViewController!
        waitFor("error alert not ready for dismissal") {
            guard let alert = root.presentedViewController as? UIAlertController else { return false }
            return alert.title == "无法保存" && alert.textFields?.isEmpty != false &&
                !alert.isBeingPresented && !alert.isBeingDismissed
        }
        var completed = false
        root.presentedViewController?.dismiss(animated: false) { completed = true }
        waitFor("error alert dismissal did not complete") { completed && root.presentedViewController == nil }
    }
    private func root(io: BottomGestureSettingsIO? = nil) {
        if let io = io { show(BottomGestureSettingsController(io: io)) }
        else { show(BottomGestureSettingsController()) }
    }
    private func side(_ name: String) {
        tap(table(), name == "left" ? "bottomLeftOptions" : "bottomRightOptions")
        require(nav.topViewController is BottomGestureSettingsController, "side did not push production page")
        let t = table()
        require(paths(t).count == 9, "each side must expose nine controls even when disabled")
        let sides = bottom["sides"] as! [String: [String: Any]]
        let sections = sides[name]!["sections"] as! [[String: Any]]
        for (s, section) in sections.enumerated() {
            for (r, row) in (section["rows"] as! [[String: Any]]).enumerated() {
                let cell = ownedCell(t, IndexPath(row: r, section: s))
                require(cell.accessibilityIdentifier == row["id"] as? String && cell.textLabel?.text == row["title"] as? String,
                        "side controls must preserve original titles/order")
            }
        }
    }
    private func list(_ id: P.GestureID) {
        root()
        side(id.rawValue.hasPrefix("bottomLeft") ? "left" : "right")
        tap(table(), id.rawValue)
    }
    private func chooseBasic(_ kind: String, editing: Int? = nil) {
        if let editing = editing { tap(table(), "bottom.action.\(editing)") }
        else { bar("bottom.add") }
        tap(table(), "BASIC_ACTION")
        guard let rows = actionCatalog["basicActions"] as? [[String: Any]],
              let item = rows.first(where: { $0["actionKind"] as? String == kind }),
              let id = item["id"] as? String else { finish("missing basic oracle kind " + kind) }
        tap(table(), id)
    }
    private func testMainQueueProgress() {
        var progressed = false
        DispatchQueue.main.async { progressed = true }
        settle()
        require(progressed, "UIKit harness nested run loop did not service the main queue")
    }
    private func testRootEntryAdmission() {
        let originalRoot = TapLockSettingsController()
        show(originalRoot)
        let rootTable = table(originalRoot)
        let originalSwitchCell = ownedCell(rootTable, IndexPath(row: 0, section: 0))
        guard let cachedRootToggle = originalSwitchCell.accessoryView as? UISwitch else {
            finish("root ownership fixture must use the actual production cached toggle")
        }
        require(cachedRootToggle.isDescendant(of: originalSwitchCell), "root toggle fixture lacks its cell owner")
        _ = find(rootTable, "enabled")
        require(cachedRootToggle.isDescendant(of: originalSwitchCell), "row discovery stole a production cached control")
        let path = find(rootTable, "bottomOptions")
        let retainedCell = ownedCell(rootTable, path)
        let rootDelegate = rootTable.delegate
        let before = preferences()
        require(rootDelegate === originalRoot && rootTable.window != nil &&
                rootTable.window === nav.view.window,
                "root admission fixture must use the production in-window delegate")

        func reject(_ eventTable: UITableView, _ context: String) {
            let stack = nav.viewControllers
            rootDelegate?.tableView?(eventTable, didSelectRowAt: path)
            require(nav.viewControllers.count == stack.count &&
                    zip(nav.viewControllers, stack).allSatisfy({ $0.0 === $0.1 }),
                    "rejected root event changed navigation object stack: " + context)
            require(samePreferences(before), "rejected root event wrote preferences: " + context)
        }

        // A foreign table has a genuine owned, visible, matching row, but never
        // owns this controller's admission authority.
        let foreignTable = UITableView(frame: rootTable.frame, style: .insetGrouped)
        let foreignSource = BottomRootForeignDataSource(target: path, identifier: "bottomOptions")
        let originalSwitchOwner = cachedRootToggle.superview
        foreignTable.dataSource = foreignSource
        foreignTable.delegate = originalRoot
        withExtendedLifetime(foreignSource) {
            nav.view.addSubview(foreignTable)
            foreignTable.reloadData()
            let foreignCell = ownedCell(foreignTable, path)
            require(foreignCell.accessibilityIdentifier == retainedCell.accessibilityIdentifier &&
                    foreignCell.window === rootTable.window, "foreign table fixture must otherwise match")
            require(cachedRootToggle.superview === originalSwitchOwner, "foreign fixture stole a production cached control")
            reject(foreignTable, "foreign-table")
            foreignTable.removeFromSuperview()
        }

        let cellFrame = retainedCell.frame
        guard let cellOwner = retainedCell.superview else { finish("retained cell lacks real owner") }
        for target in ["hidden-cell", "disabled-cell", "zero-alpha-cell", "clipped-out-cell",
                       "detached-cell", "hidden-table", "disabled-table", "zero-alpha-table"] {
            require(rootTable.cellForRow(at: path) === retainedCell &&
                    rootTable.visibleCells.contains(where: { $0 === retainedCell }),
                    "event target must start as the retained table-owned visible cell")
            switch target {
            case "hidden-cell": retainedCell.isHidden = true
            case "disabled-cell": retainedCell.isUserInteractionEnabled = false
            case "zero-alpha-cell": retainedCell.alpha = 0
            case "clipped-out-cell":
                retainedCell.frame = cellFrame.offsetBy(dx: rootTable.bounds.width + cellFrame.width, dy: 0)
                require(!rootTable.bounds.intersects(rootTable.convert(retainedCell.bounds, from: retainedCell)),
                        "clipped-out fixture must be outside the table viewport")
            case "detached-cell": retainedCell.removeFromSuperview()
            case "hidden-table": rootTable.isHidden = true
            case "disabled-table": rootTable.isUserInteractionEnabled = false
            default: rootTable.alpha = 0
            }
            reject(rootTable, target)
            if retainedCell.superview == nil { cellOwner.addSubview(retainedCell) }
            retainedCell.frame = cellFrame
            retainedCell.isHidden = false
            retainedCell.isUserInteractionEnabled = true
            retainedCell.alpha = 1
            rootTable.isHidden = false
            rootTable.isUserInteractionEnabled = true
            rootTable.alpha = 1
        }

        let other = UIViewController()
        nav.pushViewController(other, animated: false)
        settle()
        require(nav.topViewController === other && rootTable.cellForRow(at: path) === retainedCell,
                "stale fixture must retain the original root table-owned cell after push")
        reject(rootTable, "stale-after-push")

        // Independent of the detached-window case: deliberately retain the old
        // root in this very navigation window while another controller is top.
        rootTable.frame = nav.view.bounds
        nav.view.addSubview(rootTable)
        rootTable.layoutIfNeeded()
        require(rootTable.window != nil && rootTable.window === nav.view.window &&
                retainedCell.window === rootTable.window &&
                rootTable.cellForRow(at: path) === retainedCell &&
                rootTable.visibleCells.contains(where: { $0 === retainedCell }) &&
                nav.topViewController === other, "in-window-non-top fixture must defeat a window-only guard")
        reject(rootTable, "in-window-non-top")
        rootTable.removeFromSuperview()
        _ = nav.popViewController(animated: false)
        settle()
        _ = ownedCell(rootTable, path)

        guard let rootOwner = rootTable.superview else { finish("restored root lacks navigation view owner") }
        let rootFrame = rootTable.frame
        rootTable.removeFromSuperview()
        require(nav.topViewController === originalRoot && rootTable.window == nil,
                "detached-root fixture must keep the original root as navigation top")
        reject(rootTable, "detached-root")
        rootOwner.addSubview(rootTable)
        rootTable.frame = rootFrame
        settle()
        _ = ownedCell(rootTable, path)
        require(nav.topViewController === originalRoot && rootTable.window === nav.view.window,
                "valid root fixture did not recover its original owner/window")
        rootDelegate?.tableView?(rootTable, didSelectRowAt: path)
        settle()
        require(nav.viewControllers.count == 2 && nav.viewControllers.first === originalRoot &&
                nav.topViewController is BottomGestureSettingsController,
                "restored visible root must push exactly one concrete bottom controller")
        require(samePreferences(before), "valid root navigation must not write preferences")
        reject(rootTable, "duplicate-after-valid-push")
    }
    private func testRootEntry() {
        let old = TapLockSettingsController()
        show(old)
        let rootTable = table(old)
        tap(rootTable, "bottomOptions")
        require(nav.viewControllers.count == 2 && nav.topViewController is BottomGestureSettingsController,
                "old root must push the real bottom controller at the same level")
        require(nav.topViewController?.title == bottom["title"] as? String, "wrong original root title")
        let rootTable2 = table()
        let sections = bottom["sections"] as! [[String: Any]]
        require(rootTable2.numberOfSections == sections.count, "original root section count")
        for (s, section) in sections.enumerated() {
            let rows = (section["rows"] as! [[String: Any]]).filter { $0["visibleWhen"] == nil }
            require(rootTable2.numberOfRows(inSection: s) == rows.count, "original row count/order")
            require(rootTable2.dataSource?.tableView?(rootTable2, titleForHeaderInSection: s) == section["header"] as? String,
                    "original section header")
            require(rootTable2.dataSource?.tableView?(rootTable2, titleForFooterInSection: s) == section["footer"] as? String,
                    "original section footer")
            for (r, row) in rows.enumerated() {
                let cell = ownedCell(rootTable2, IndexPath(row: r, section: s))
                require(cell.accessibilityIdentifier == row["id"] as? String, "original root row identity")
                let labels = descendants(cell).compactMap { ($0 as? UILabel)?.text }
                require(labels.contains(row["title"] as! String), "must use exact original label, not shared short title")
            }
        }
        for id in P.GestureID.allCases {
            let selection = P.readSnapshot().selection(id)
            require(!selection.enabled && !selection.flowEnabled && selection.actions.isEmpty, "bottom defaults must not inherit old lock")
        }
    }
    private func testNumbers() {
        root()
        toggle("bottomUpOnLandscapeEnabled", true)
        require(P.readSnapshot().boolean(.bottomUpOnLandscapeEnabled), "landscape enable did not persist")
        let allRows = (bottom["sections"] as! [[String: Any]]).flatMap { $0["rows"] as! [[String: Any]] }
        let numbers = allRows.filter { $0["kind"] as? String == "slider" }
        require(numbers.count == 12, "twelve original parameters")
        for row in numbers {
            let id = row["id"] as! String
            let key = P.NumericKey(rawValue: id)!
            let slider = control(table(), id: id, type: UISlider.self)
            require(slider.minimumValue == Float(row["minimum"] as! Double) && slider.maximumValue == Float(row["maximum"] as! Double), "original individual bounds")
            slider.value = 3.25
            slider.sendActions(for: .valueChanged)
            require(P.readSnapshot().number(key) == 3.25, "fractional slider save")
            let button = control(table(), id: id, type: UIButton.self)
            require(button.title(for: .normal) == String(format: "%.1f", 3.25), "value label must use one decimal")
            entry(id, "2.37")
            require(P.readSnapshot().number(key) == 2.37, "fractional numeric entry save")
            entry(id, "999.75")
            require(P.readSnapshot().number(key) == key.maxValue, "upper bound clamps only this key")
            entry(id, "-1.25")
            require(P.readSnapshot().number(key) == key.minValue, "lower bound clamps only this key")
        }
        for invalid in ["not a number", "NaN", "inf", "-inf", "1e9999"] {
            let before = preferences()
            entry("bottomTriggerPosition", invalid, expectingError: true)
            require(samePreferences(before), "invalid/nonfinite input wrote preferences")
            require(nav.topViewController?.presentedViewController is UIAlertController, "invalid input lacks error")
            dismissError()
        }
        entry("bottomTriggerSensitivity", "9.15")
        entry("bottomTriggerArea", "1.25")
        entry("bottomTriggerExtraArea", "0.5")
        require(P.readSnapshot().number(.bottomTriggerSensitivity) == 9.15 &&
                P.readSnapshot().number(.bottomTriggerArea) == 1.25 &&
                P.readSnapshot().number(.bottomTriggerExtraArea) == 0.5, "UI must not sort or cross-clamp thresholds")
        let landscape = P.NumericKey.allCases.filter { $0.rawValue.hasSuffix("Landscape") }
        let before = landscape.map { P.readSnapshot().number($0) }
        let oldSlider = control(table(), id: "bottomTriggerPositionLandscape", type: UISlider.self)
        toggle("bottomUpOnLandscapeEnabled", false)
        require(table().numberOfRows(inSection: 5) == 0, "landscape off must hide six rows")
        oldSlider.value = 12
        oldSlider.sendActions(for: .valueChanged)
        require(landscape.map { P.readSnapshot().number($0) } == before, "hidden/stale control wrote or reset values")
        toggle("bottomUpOnLandscapeEnabled", true)
        require(table().numberOfRows(inSection: 5) == 6, "landscape did not reappear")
        require(landscape.map { P.readSnapshot().number($0) } == before, "landscape hide/show lost values")
        root()
        require(P.readSnapshot().number(.bottomTriggerArea) == 1.25, "reentry lost number")
    }
    private func testSixIndependentLists() {
        var expected: [P.GestureID: [TapLockPreferences.Action]] = [:]
        for id in P.GestureID.allCases {
            root()
            side(id.rawValue.hasPrefix("bottomLeft") ? "left" : "right")
            toggle(id.enabledKey, true)
            toggle(id.flowKey, true)
            require(P.readSnapshot().selection(id).enabled && P.readSnapshot().selection(id).flowEnabled, "independent tier toggles not saved")
            toggle(id.enabledKey, false)
            require(paths(table()).count == 9, "disabling tier must not hide action/flow controls")
            tap(table(), id.rawValue)
            require(paths(table()).isEmpty, "missing list must start empty")
            chooseBasic("lock")
            chooseBasic("screenshot")
            require(P.readSnapshot().selection(id).actions == [.lock, .screenshot], "append must preserve order")
            bar("bottom.edit")
            let listTable = table()
            let source = IndexPath(row: 0, section: 0)
            let destination = IndexPath(row: 1, section: 0)
            _ = ownedCell(listTable, source)
            listTable.dataSource?.tableView?(listTable, moveRowAt: source, to: destination)
            settle()
            require(P.readSnapshot().selection(id).actions == [.screenshot, .lock], "real reorder did not persist")
            bar("bottom.edit")
            chooseBasic("playPause", editing: 0)
            require(P.readSnapshot().selection(id).actions == [.playPause, .lock], "edit must replace the selected slot")
            let current = table()
            let remove = IndexPath(row: 1, section: 0)
            _ = ownedCell(current, remove)
            current.dataSource?.tableView?(current, commit: .delete, forRowAt: remove)
            settle()
            expected[id] = [.playPause]
            for other in P.GestureID.allCases {
                require(P.readSnapshot().selection(other).actions == (expected[other] ?? []), "one tier changed another tier's list")
            }
            list(id)
            require(paths(table()).count == 1, "saved list did not survive controller reentry")
        }
        // Exercise every available mapping through a real picker, not a model.
        list(.bottomLeftUp)
        for (id, expectedAction) in supportedBasics {
            let beforeActions = P.readSnapshot().selection(.bottomLeftUp).actions
            bar("bottom.add")
            tap(table(), "BASIC_ACTION")
            tap(table(), id)
            require(P.readSnapshot().selection(.bottomLeftUp).actions == beforeActions + [expectedAction],
                    "exact original ID must store its original action: " + id)
        }
        // A stale list view must not delete a new externally replaced list.
        let staleTable = table()
        let stalePath = IndexPath(row: 0, section: 0)
        _ = ownedCell(staleTable, stalePath)
        require(P.writeActions([.nextTrack], for: .bottomLeftUp), "stale-list fixture save")
        staleTable.dataSource?.tableView?(staleTable, commit: .delete, forRowAt: stalePath)
        require(P.readSnapshot().selection(.bottomLeftUp).actions == [.nextTrack], "stale list overwrote newer state")
    }
    private func testDisabledAndStaleNumericEntry() {
        root()
        let button = control(table(), id: "bottomTriggerPosition", type: UIButton.self)
        button.sendActions(for: .touchUpInside)
        settle()
        guard let alert = nav.topViewController?.presentedViewController as? UIAlertController,
              let field = alert.textFields?.first else { finish("numeric ownership fixture not presented") }
        let before = preferences()
        field.text = "4.625"
        field.isEnabled = false
        field.sendActions(for: .editingDidEndOnExit)
        require(samePreferences(before), "forced disabled numeric entry wrote")
        field.isEnabled = true
        alert.dismiss(animated: false)
        settle()
        field.sendActions(for: .editingDidEndOnExit)
        require(samePreferences(before), "dismissed numeric editor retained write authority")
    }
    private func testDisabledAndSearch() {
        list(.bottomLeftUp)
        bar("bottom.add")
        let categories = table()
        for id in ["APP_ACTION", "SHORTCUTS", "OPEN_URL", "PRESET_URLS"] {
            let path = find(categories, id)
            let cell = ownedCell(categories, path)
            require(!cell.isUserInteractionEnabled && cell.accessibilityTraits.contains(.notEnabled), "deferred category looks enabled")
            let before = preferences()
            let depth = nav.viewControllers.count
            categories.delegate?.tableView?(categories, didSelectRowAt: path)
            require(nav.viewControllers.count == depth && samePreferences(before), "forced deferred category navigated/wrote")
        }
        tap(categories, "BASIC_ACTION")
        let basics = table()
        let rows = actionCatalog["basicActions"] as! [[String: Any]]
        require(paths(basics).count == 68, "basic catalog lost unavailable original rows")
        for (index, item) in rows.enumerated() {
            let cell = ownedCell(basics, IndexPath(row: index, section: 0))
            require(cell.accessibilityIdentifier == item["id"] as? String && cell.textLabel?.text == item["title"] as? String, "68-item catalog order/labels")
            require(cell.imageView?.image != nil || item["image"] as? String == nil, "catalog icon missing")
            let id = item["id"] as! String
            let expectedAvailable = supportedBasics.contains(where: { $0.0 == id })
            require(item["available"] as? Bool == expectedAvailable &&
                    cell.isUserInteractionEnabled == expectedAvailable &&
                    cell.accessibilityTraits.contains(.notEnabled) == !expectedAvailable,
                    "only the ten original supported IDs may be interactive")
            if !expectedAvailable {
                let before = preferences()
                let depth = nav.viewControllers.count
                basics.delegate?.tableView?(basics, didSelectRowAt: IndexPath(row: index, section: 0))
                require(nav.viewControllers.count == depth && samePreferences(before), "forced unavailable basic action wrote/navigated")
            }
        }
        let picker = nav.topViewController as! BottomGestureSettingsController
        let search = picker.navigationItem.searchController!
        search.searchBar.text = "截屏"
        picker.updateSearchResults(for: search)
        settle()
        require(paths(basics).count > 0 && paths(basics).count < 68, "localized search did not filter")
        search.searchBar.text = "__not_a_real_action__"
        picker.updateSearchResults(for: search)
        require(paths(basics).isEmpty, "search must return empty rather than stale rows")
    }
    private func testAppSnapshot() {
        var io = BottomGestureSettingsIO()
        var enumerations = 0
        var validations = 0
        var installed = true
        // Deterministic external catalog I/O; production still uses actual
        // InstalledApplications/LaunchServices and ApplicationIcons unchanged.
        let choice = InstalledApplications.Choice(identifier: "com.example.bottom-tests", name: "测试应用")
        io.applications = { enumerations += 1; return [choice] }
        io.application = { id in validations += 1; return installed && id == choice.identifier ? choice : nil }
        root(io: io)
        side("right")
        tap(table(), "bottomRightUp")
        bar("bottom.add")
        tap(table(), "OPEN_APPLICATION")
        let appTable = table()
        require(enumerations == 1, "one picker must establish exactly one app snapshot")
        let cell = ownedCell(appTable, find(appTable, choice.identifier))
        require(cell.textLabel?.text == choice.name && cell.detailTextLabel?.text == choice.identifier, "App name/BundleID not displayed")
        require(cell.imageView?.image?.size == CGSize(width: 32, height: 32), "App icon must use the actual normalized icon owner")
        let picker = nav.topViewController as! BottomGestureSettingsController
        for query in ["测试", "com.example", "__none__", ""] {
            picker.navigationItem.searchController?.searchBar.text = query
            picker.updateSearchResults(for: picker.navigationItem.searchController!)
            _ = table()
        }
        picker.viewWillAppear(false)
        require(enumerations == 1, "search/appearance/render re-enumerated installed apps")
        installed = false
        let before = preferences()
        tap(appTable, choice.identifier)
        require(validations > 0 && samePreferences(before), "uninstalled App was not revalidated before save")
        dismissError()
        installed = true
        tap(appTable, choice.identifier)
        require(P.readSnapshot().selection(.bottomRightUp).actions.last == .openApp(choice.identifier), "App selection not appended")
        let selectedTable = table()
        let lookups = validations
        for _ in 0..<20 {
            for path in paths(selectedTable) { _ = selectedTable.dataSource?.tableView(selectedTable, cellForRowAt: path) }
        }
        require(validations == lookups && enumerations == 1, "selected-list rendering repeated App metadata lookup/enumeration")
        require(TapLockPreferences.readAction() == .systemMute && TapLockPreferences.readEnabled(), "bottom picker modified old double-tap state")
    }
    private func assertRejectedResource(_ name: String, _ malformed: [String: Any], _ context: String,
                                        exercisePickers: Bool = false) {
        guard let payload = try? JSONSerialization.data(withJSONObject: malformed),
              (try? JSONSerialization.jsonObject(with: payload)) != nil else {
            finish("malformed-resource fixture is not decodable JSON: " + context)
        }
        var io = BottomGestureSettingsIO()
        let read = io.data
        var broken = false
        var writes = 0
        io.data = { resource in broken && resource == name ? payload : read(resource) }
        io.writeBoolean = { _, _ in writes += 1; return false }
        io.writeNumber = { _, _ in writes += 1; return false }
        io.writeEnabled = { _, _ in writes += 1; return false }
        io.writeFlowEnabled = { _, _ in writes += 1; return false }
        io.writeActions = { _, _ in writes += 1; return false }
        let before = preferences()

        // Start with genuinely table-owned controls, then replace only resource
        // I/O. These events must revalidate rather than trust the old rendering.
        root(io: io)
        let t = table()
        let link = find(t, "bottomLeftOptions")
        let slider = control(t, id: "bottomTriggerPosition", type: UISlider.self)
        let input = control(t, id: "bottomTriggerPosition", type: UIButton.self)
        let toggle = control(t, id: "ignoreEdgeProtect", type: UISwitch.self)
        broken = true
        toggle.setOn(!toggle.isOn, animated: false)
        toggle.sendActions(for: .valueChanged)
        slider.value = 4.25
        slider.sendActions(for: .valueChanged)
        input.sendActions(for: .touchUpInside)
        t.delegate?.tableView?(t, didSelectRowAt: link)
        settle()
        require(writes == 0 && samePreferences(before) && nav.viewControllers.count == 1 &&
                nav.topViewController?.presentedViewController == nil, "stale malformed-resource events escaped: " + context)
        require(t.backgroundView is UILabel && paths(t).isEmpty && t.visibleCells.isEmpty,
                "whole malformed resource must remove every live root control: " + context)
        root(io: io)
        let fresh = table()
        require(fresh.backgroundView is UILabel && paths(fresh).isEmpty, "fresh malformed resource stayed usable: " + context)
        fresh.delegate?.tableView?(fresh, didSelectRowAt: IndexPath(row: 0, section: 0))
        require(writes == 0 && samePreferences(before) && nav.viewControllers.count == 1,
                "fresh malformed-resource forced delegate escaped: " + context)
        guard exercisePickers else { return }

        broken = false
        root(io: io)
        side("left")
        let sideTable = table()
        let actionsPath = find(sideTable, "bottomLeftUp")
        let flow = control(sideTable, id: "bottomLeftUpFlowEnabled", type: UISwitch.self)
        let enabled = control(sideTable, id: "bottomLeftUpEnabled", type: UISwitch.self)
        broken = true
        enabled.setOn(!enabled.isOn, animated: false)
        enabled.sendActions(for: .valueChanged)
        flow.setOn(!flow.isOn, animated: false)
        flow.sendActions(for: .valueChanged)
        sideTable.delegate?.tableView?(sideTable, didSelectRowAt: actionsPath)
        settle()
        require(paths(sideTable).isEmpty && sideTable.backgroundView is UILabel &&
                nav.viewControllers.count == 2 && writes == 0 && samePreferences(before),
                "malformed resource left a side switch/actions/flow usable: " + context)

        broken = false
        root(io: io)
        side("left")
        tap(table(), "bottomLeftUp")
        let listController = nav.topViewController!
        let listTable = table()
        require(!paths(listTable).isEmpty, "malformed list fixture needs a real saved action")
        let listPath = IndexPath(row: 0, section: 0)
        _ = ownedCell(listTable, listPath)
        let buttons = listController.navigationItem.rightBarButtonItems ?? []
        broken = true
        listController.viewWillAppear(false)
        settle()
        let cell = ownedCell(listTable, listPath)
        require(!cell.isUserInteractionEnabled && cell.accessibilityTraits.contains(.notEnabled),
                "invalid resource did not disable the retained list row: " + context)
        require(buttons.count == 2, "missing real list buttons")
        for item in buttons {
            require(!item.isEnabled, "invalid resource did not disable list buttons: " + context)
            if let action = item.action { _ = UIApplication.shared.sendAction(action, to: item.target, from: item, for: nil) }
        }
        listTable.delegate?.tableView?(listTable, didSelectRowAt: listPath)
        listTable.dataSource?.tableView?(listTable, commit: .delete, forRowAt: listPath)
        listController.setEditing(true, animated: false)
        listTable.dataSource?.tableView?(listTable, moveRowAt: listPath, to: listPath)
        require(writes == 0 && samePreferences(before) && nav.viewControllers.count == 3,
                "disabled malformed list accepted a forced mutation/navigation: " + context)

        broken = false
        root(io: io)
        side("left")
        tap(table(), "bottomLeftUp")
        bar("bottom.add")
        tap(table(), "BASIC_ACTION")
        let picker = table()
        let lockPath = find(picker, "SYSTEM_LOCKSCREEN")
        _ = ownedCell(picker, lockPath)
        let depth = nav.viewControllers.count
        broken = true
        picker.delegate?.tableView?(picker, didSelectRowAt: lockPath)
        picker.delegate?.tableView?(picker, didSelectRowAt: IndexPath(row: 0, section: 0))
        require(picker.backgroundView is UILabel && paths(picker).isEmpty && writes == 0 &&
                samePreferences(before) && nav.viewControllers.count == depth,
                "malformed basic picker accepted a forced selection: " + context)
    }
    private func testBasicIdentityResources() {
        let originalRows = actionCatalog["basicActions"] as! [[String: Any]]
        guard let lock = originalRows.firstIndex(where: { $0["id"] as? String == "SYSTEM_LOCKSCREEN" }),
              let clipboard = originalRows.firstIndex(where: { $0["id"] as? String == "HI_CLIPBOARD" }),
              let screenshot = originalRows.firstIndex(where: { $0["id"] as? String == "SYSTEM_SCREENSHOT" }) else {
            finish("missing independent identity mutation targets")
        }
        let originalIDs = originalRows.map { $0["id"] as! String }
        let originalKinds = Set(originalRows.compactMap { $0["actionKind"] as? String })
        for mutation in ["availability-alias", "supported-kind-swap", "id-order-swap"] {
            var malformed = actionCatalog
            var rows = originalRows
            switch mutation {
            case "availability-alias":
                rows[lock]["available"] = false
                rows[lock]["actionKind"] = NSNull()
                rows[clipboard]["available"] = true
                rows[clipboard]["actionKind"] = "lock"
            case "supported-kind-swap":
                rows[lock]["actionKind"] = "screenshot"
                rows[screenshot]["actionKind"] = "lock"
            default:
                rows[0]["id"] = originalIDs[1]
                rows[1]["id"] = originalIDs[0]
            }
            // Each payload decodes as the normal schema and defeats the former
            // counts/sets/slots validation, rather than failing JSON parsing.
            require(rows.count == 68 && Set(rows.map { $0["id"] as! String }).count == 68 &&
                    rows.map({ $0["referenceSlot"] as! Int }) == Array(0..<68) &&
                    rows.filter({ $0["available"] as? Bool == true }).count == 10 &&
                    Set(rows.compactMap { $0["actionKind"] as? String }) == originalKinds,
                    "identity mutation must preserve old cardinality/slots/kind-set checks")
            if mutation != "id-order-swap" {
                require(rows.map({ $0["id"] as! String }) == originalIDs, "mapping mutation must preserve all original IDs/order")
            }
            malformed["basicActions"] = rows
            assertRejectedResource("SettingsReference", malformed, mutation, exercisePickers: true)
        }
    }
    private func testIllegalVisibilityResources() {
        let conditions = ["notADeclaredBooleanKey", "bottomUpOnLandscapeEnabled"]
        for sideName in ["left", "right"] {
            for sectionIndex in 0..<3 {
                for rowIndex in 0..<3 {
                    for condition in conditions {
                        var malformed = bottom
                        var sides = malformed["sides"] as! [String: [String: Any]]
                        var side = sides[sideName]!
                        var sections = side["sections"] as! [[String: Any]]
                        var rows = sections[sectionIndex]["rows"] as! [[String: Any]]
                        rows[rowIndex]["visibleWhen"] = condition
                        sections[sectionIndex]["rows"] = rows
                        side["sections"] = sections
                        sides[sideName] = side
                        malformed["sides"] = sides
                        assertRejectedResource("BottomGestureReference", malformed,
                            "\(sideName)/\(sectionIndex)/\(rowIndex):\(condition)",
                            exercisePickers: sideName == "left" && sectionIndex == 0 && condition == conditions[0])
                    }
                }
            }
        }
        for index in 0..<2 {
            for condition in conditions {
                var malformed = bottom
                var sections = malformed["sections"] as! [[String: Any]]
                var rows = sections[index]["rows"] as! [[String: Any]]
                rows[0]["visibleWhen"] = condition
                sections[index]["rows"] = rows
                malformed["sections"] = sections
                assertRejectedResource("BottomGestureReference", malformed, "root-link/\(index):\(condition)")
            }
        }
    }
    private func testInvalidResources() {
        for name in ["BottomGestureReference", "SettingsReference"] {
            var io = BottomGestureSettingsIO()
            let read = io.data
            var broken = false
            io.data = { resource in broken && resource == name ? Data("{}".utf8) : read(resource) }
            root(io: io)
            let rootTable = table()
            let path = find(rootTable, "bottomLeftOptions")
            _ = ownedCell(rootTable, path)
            let toggle = control(rootTable, id: "ignoreEdgeProtect", type: UISwitch.self)
            let before = preferences()
            broken = true
            toggle.setOn(!toggle.isOn, animated: false)
            toggle.sendActions(for: .valueChanged)
            rootTable.delegate?.tableView?(rootTable, didSelectRowAt: path)
            require(samePreferences(before) && nav.viewControllers.count == 1, "corrupt resource allowed synthetic event/navigation")
            require(rootTable.backgroundView is UILabel, "corrupt resource lacks clear notice")
            // A newly constructed page must also be inert, not only stale rows.
            root(io: io)
            let disabled = table()
            disabled.delegate?.tableView?(disabled, didSelectRowAt: IndexPath(row: 0, section: 0))
            require(samePreferences(before) && nav.viewControllers.count == 1, "forced invalid-resource delegate wrote/navigated")
        }
        root()
        let t = table()
        let path = find(t, "ignoreEdgeProtect")
        let freshButDetached = t.dataSource!.tableView(t, cellForRowAt: path)
        let before = preferences()
        let detached = freshButDetached.accessoryView as! UISwitch
        detached.setOn(!detached.isOn, animated: false)
        detached.sendActions(for: .valueChanged)
        require(samePreferences(before), "datasource-created but non-table-owned switch wrote")
        let actual = control(t, id: "ignoreEdgeProtect", type: UISwitch.self)
        actual.isEnabled = false
        actual.setOn(!actual.isOn, animated: false)
        actual.sendActions(for: .valueChanged)
        require(samePreferences(before), "forced disabled switch wrote")
        let saved = preferences()
        var malformed = saved
        malformed["bottomTriggerPosition"] = "not-a-number"
        replacePreferences(malformed)
        root()
        let unavailable = table()
        let invalidBefore = preferences()
        let unavailableSwitch = control(unavailable, id: "ignoreEdgeProtect", type: UISwitch.self)
        require(!unavailableSwitch.isEnabled, "malformed persisted configuration did not disable controls")
        unavailableSwitch.sendActions(for: .valueChanged)
        tap(unavailable, "bottomLeftOptions")
        require(samePreferences(invalidBefore) && nav.viewControllers.count == 1, "malformed preferences allowed writes/navigation")
        replacePreferences(saved)
    }
    private func testSaveFailure() {
        var io = BottomGestureSettingsIO()
        var writes = 0
        io.writeBoolean = { _, _ in writes += 1; return false }
        io.writeNumber = { _, _ in writes += 1; return false }
        io.writeEnabled = { _, _ in writes += 1; return false }
        io.writeFlowEnabled = { _, _ in writes += 1; return false }
        io.writeActions = { _, _ in writes += 1; return false }
        root(io: io)
        let persisted = P.readSnapshot().boolean(.ignoreEdgeProtect)
        toggle("ignoreEdgeProtect", !persisted)
        require(writes == 1 && P.readSnapshot().boolean(.ignoreEdgeProtect) == persisted, "failed write changed persisted value")
        let restored = control(table(), id: "ignoreEdgeProtect", type: UISwitch.self)
        require(restored.isOn == persisted, "failed write did not restore fresh state")
        require(nav.topViewController?.presentedViewController is UIAlertController, "failed write silently ignored")
        dismissError()
        let oldNumber = P.readSnapshot().number(.bottomTriggerPosition)
        entry("bottomTriggerPosition", "4.75", expectingError: true)
        require(P.readSnapshot().number(.bottomTriggerPosition) == oldNumber, "failed number write was not restored")
        dismissError()
        side("left")
        let beforeEnabled = P.readSnapshot().selection(.bottomLeftUp).enabled
        toggle("bottomLeftUpEnabled", !beforeEnabled)
        require(P.readSnapshot().selection(.bottomLeftUp).enabled == beforeEnabled, "failed tier write was not restored")
        dismissError()
        let beforeFlow = P.readSnapshot().selection(.bottomLeftUp).flowEnabled
        toggle("bottomLeftUpFlowEnabled", !beforeFlow)
        require(P.readSnapshot().selection(.bottomLeftUp).flowEnabled == beforeFlow, "failed flow write was not restored")
        dismissError()
        tap(table(), "bottomLeftUp")
        let beforeActions = P.readSnapshot().selection(.bottomLeftUp).actions
        chooseBasic("screenshot")
        require(P.readSnapshot().selection(.bottomLeftUp).actions == beforeActions, "failed action write changed list")
        require(nav.topViewController?.presentedViewController is UIAlertController, "failed action save lacks error")
        require(writes == 5, "failure fixtures must exercise all five production writers")
        dismissError()
    }
    private func testNarrowDynamicType() {
        root()
        let controller = nav.topViewController!
        nav.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge), forChild: controller)
        window?.frame.size.width = 280
        nav.view.frame.size.width = 280
        controller.view.frame.size.width = 280
        let t = table()
        let path = find(t, "bottomTriggerExtraPlusArea")
        let cell = ownedCell(t, path)
        require(t.bounds.width <= 280, "narrow-width fixture did not reach the production table")
        require(!cell.hasAmbiguousLayout && !cell.contentView.hasAmbiguousLayout, "narrow Dynamic Type layout ambiguous")
        require(descendants(cell).compactMap { $0 as? UIStackView }.contains(where: { $0.axis == .vertical }), "number controls must use constraints/stack layout")
    }
    @objc private func run() {
        checkpoint("run entered")
        guard let bottomData = BottomGestureSettingsIO().data("BottomGestureReference"),
              let actionData = BottomGestureSettingsIO().data("SettingsReference"),
              let bottom = try? JSONSerialization.jsonObject(with: bottomData) as? [String: Any],
              let actions = try? JSONSerialization.jsonObject(with: actionData) as? [String: Any] else { finish("test resources missing") }
        self.bottom = bottom
        actionCatalog = actions
        backup = preferences()
        replacePreferences([TapLockPreferences.enabledKey: true, TapLockPreferences.actionKey: ["kind": "systemMute"]])
        checkpoint("before testMainQueueProgress")
        testMainQueueProgress()
        checkpoint("before testRootEntryAdmission")
        testRootEntryAdmission()
        checkpoint("before testRootEntry")
        testRootEntry()
        checkpoint("before testNumbers")
        testNumbers()
        checkpoint("before testDisabledAndStaleNumericEntry")
        testDisabledAndStaleNumericEntry()
        checkpoint("before testSixIndependentLists")
        testSixIndependentLists()
        checkpoint("before testDisabledAndSearch")
        testDisabledAndSearch()
        checkpoint("before testAppSnapshot")
        testAppSnapshot()
        checkpoint("before testIllegalVisibilityResources")
        testIllegalVisibilityResources()
        checkpoint("before testBasicIdentityResources")
        testBasicIdentityResources()
        checkpoint("before testInvalidResources")
        testInvalidResources()
        checkpoint("before testSaveFailure")
        testSaveFailure()
        checkpoint("before testNarrowDynamicType")
        testNarrowDynamicType()
        require(TapLockPreferences.readEnabled() && TapLockPreferences.readAction() == .systemMute, "old double-tap must remain byte-independent")
        finish()
    }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        checkpoint("didFinishLaunching")
        UIView.setAnimationsEnabled(false)
        let window = UIWindow(frame: UIScreen.main.bounds)
        nav = UINavigationController()
        window.rootViewController = nav
        self.window = window
        window.makeKeyAndVisible()
        // Enter from a native RunLoop timer, not one long main-queue block.
        // Nested settle() loops must be able to service UIKit's queued work.
        perform(#selector(run), with: nil, afterDelay: 0)
        return true
    }
}
