import UIKit

// Only I/O is injectable. The simulator harness runs the same renderer, event
// admission, numeric parsing and ordered-list mutations as the shipped page.
struct BottomGestureSettingsIO {
    typealias P = BottomGesturePreferences
    var data: (String) -> Data? = { name in
        let bundle = Bundle(for: BottomGestureSettingsController.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }
    var readSnapshot = { P.readSnapshot() }
    var writeNumber = { (value: Double, key: P.NumericKey) in P.writeNumber(value, for: key) }
    var writeBoolean = { (value: Bool, key: P.BooleanKey) in P.writeBoolean(value, for: key) }
    var writeEnabled = { (value: Bool, id: P.GestureID) in P.writeEnabled(value, for: id) }
    var writeFlowEnabled = { (value: Bool, id: P.GestureID) in P.writeFlowEnabled(value, for: id) }
    var writeActions = { (actions: [TapLockPreferences.Action], id: P.GestureID) in P.writeActions(actions, for: id) }
    var applications = { InstalledApplications.choices() }
    var application = { (identifier: String) in InstalledApplications.choice(identifier: identifier) }
}

private struct BottomUIReference: Decodable {
    struct Row: Decodable {
        let id: String
        let title: String
        let kind: String
        let key: String?
        let destination: String?
        let defaultBoolean: Bool?
        let minimum: Double?
        let maximum: Double?
        let defaultNumber: Double?
        let visibleWhen: String?
    }
    struct Section: Decodable {
        let id: String
        let header: String?
        let footer: String?
        let rows: [Row]
    }
    struct Side: Decodable { let title: String; let sections: [Section] }
    let schemaVersion: Int
    let referencePackageSHA256: String
    let referenceBinarySHA256: String
    let title: String
    let sections: [Section]
    let sides: [String: Side]

    var isValid: Bool {
        typealias P = BottomGesturePreferences
        guard schemaVersion == 1, !title.isEmpty,
              referencePackageSHA256 == BottomActionCatalog.packageHash,
              referenceBinarySHA256 == BottomActionCatalog.binaryHash,
              sections.map({ $0.id }) == ["left", "right", "policy", "portrait", "landscape-enable", "landscape-parameters"],
              Set(sides.keys) == Set(["left", "right"]) else { return false }
        let rows = sections.flatMap { $0.rows }
        guard rows.count == 17, Set(rows.map { $0.id }).count == 17,
              sections[0].rows.count == 1, sections[1].rows.count == 1,
              sections[2].rows.map({ $0.key }) == ["ignoreEdgeProtect", "disableBottomWhenLocked"],
              sections[3].rows.map({ $0.key }) == P.NumericKey.allCases.prefix(6).map({ Optional($0.rawValue) }),
              sections[4].rows.map({ $0.key }) == ["bottomUpOnLandscapeEnabled"],
              sections[5].rows.map({ $0.key }) == P.NumericKey.allCases.suffix(6).map({ Optional($0.rawValue) }) else { return false }
        for (index, side) in ["left", "right"].enumerated() {
            guard rows[index].kind == "link", rows[index].destination == side,
                  rows[index].visibleWhen == nil,
                  !rows[index].title.isEmpty else { return false }
        }
        for row in rows.dropFirst(2) {
            guard !row.title.isEmpty, row.id == row.key else { return false }
            if let key = P.NumericKey(rawValue: row.key ?? "") {
                guard row.kind == "slider", row.minimum == key.minValue,
                      row.maximum == key.maxValue, row.defaultNumber == key.defaultValue,
                      row.visibleWhen == (key.rawValue.hasSuffix("Landscape") ? "bottomUpOnLandscapeEnabled" : nil) else { return false }
            } else if let key = P.BooleanKey(rawValue: row.key ?? "") {
                guard row.kind == "switch", row.defaultBoolean == key.defaultValue,
                      row.visibleWhen == nil else { return false }
            } else { return false }
        }
        for sideName in ["left", "right"] {
            guard let side = sides[sideName], !side.title.isEmpty else { return false }
            let ids = P.GestureID.allCases.filter { $0.rawValue.hasPrefix(sideName == "left" ? "bottomLeft" : "bottomRight") }
            guard side.sections.map({ $0.id }) == ids.map({ $0.rawValue }) else { return false }
            for (section, id) in zip(side.sections, ids) {
                guard section.rows.map({ $0.id }) == [id.enabledKey, id.rawValue, id.flowKey],
                      section.rows.map({ $0.kind }) == ["switch", "actions", "switch"],
                      section.rows.allSatisfy({ $0.visibleWhen == nil && !$0.title.isEmpty && $0.id == $0.key }),
                      section.rows[0].defaultBoolean == false,
                      section.rows[2].defaultBoolean == false else { return false }
            }
        }
        return true
    }
}

// A narrow projection, deliberately independent of the old private renderer.
private struct BottomActionCatalog: Decodable {
    static let packageHash = "240362fc1846f697025122e4788d04bbd1920b8f5102bcfc5642a9a14b62837a"
    static let binaryHash = "a3e95d0028907909bc521a687934fa362cef18c4c813a787ff2a4b9e0eba6586"
    static let supportedKinds: Set<String> = ["lock", "screenshot", "controlCenter", "notificationCenter", "appSwitcher", "playPause", "previousTrack", "nextTrack", "flashlight", "systemMute"]
    // Independent accepted identities: never derive this validation oracle from
    // the resource being decoded. Unsupported rows cannot borrow a known kind.
    static let acceptedBasicIDs = [
        "HI_CLIPBOARD", "HI_FULLSCREEN_OCR", "HI_FULLSCREEN_TRANSLATE",
        "SHOW_COPYVAULT", "SHOW_COPYVAULT_HISTORY", "SHOW_COPYVAULT_ARCHIVE",
        "SYSTEM_SCREENSHOT", "SYSTEM_SCREENSHOT_COPYONLY", "SYSTEM_SCREENSHOT_ANDEDIT",
        "SYSTEM_CONTROLCENTER", "SYSTEM_COVER", "SYSTEM_SPOTLIGHT",
        "SYSTEM_RECORDSCREEN", "SYSTEM_RECORDSCREEN_WITHMIC", "SYSTEM_LOCKSCREEN",
        "TOGGLE_VPN", "TOGGLE_FLASHLIGHT", "SYSTEM_REACHABILITY", "ROTATION_LOCK",
        "PLAYPAUSE_MEDIA", "PREVIOUS_MEDIA", "NEXT_MEDIA", "APP_LIBRARY",
        "KILL_BACKGROUND", "REOPEN_CURRENT_APP", "RESPRING_ALL", "RESPRING_SB",
        "REBOOT_USERSPACE", "REBOOT", "SHUTDOWN", "SAFEMODE", "REBUILD_UICACHE",
        "SYSTEM_MUTE", "VOLUME_MUTE", "SYSTEM_LOWPOWER", "SYSTEM_LOCATION",
        "SYSTEM_DARKMODE", "SYSTEM_SIRI", "SYSTEM_APAY", "SYSTEM_ACCESSIBILITY",
        "SYSTEM_SWITCHER", "SYSTEM_HOME", "SNAPPER_INSTANT", "SNAPPER_COMMON",
        "SNAPPER_FREEZE", "SNAPPER_HISTORY", "SNAPPER_CLOSE_ALL", "SNAPPER_OPEN_LAST",
        "SHOW_KAYOKO", "SHOW_COPYLOG", "AUDIORECORDERXS_MEMO", "AUDIORECORDERXS_UI",
        "REVERIE_SLEEP", "SHOW_CARDCULATOR", "TROLLRECORD_START", "TROLLRECORD_STOP",
        "TROLLRECORD_TOGGLE", "ZETSU_WINDOW_MODE", "PULLOVER_MINIVIEW", "SVP_MINIVIEW",
        "FV_MINIVIEW", "SVP_ARCMENU", "FV_LEFT_ARCMENU", "FV_RIGHT_ARCMENU",
        "WECHAT_SCAN", "WECHAT_QRCODE", "ALIPAY_SCAN", "ALIPAY_QRCODE"
    ]
    static let supportedKindsByID: [String: String] = [
        "SYSTEM_SCREENSHOT": "screenshot", "SYSTEM_CONTROLCENTER": "controlCenter",
        "SYSTEM_COVER": "notificationCenter", "SYSTEM_LOCKSCREEN": "lock",
        "TOGGLE_FLASHLIGHT": "flashlight", "PLAYPAUSE_MEDIA": "playPause",
        "PREVIOUS_MEDIA": "previousTrack", "NEXT_MEDIA": "nextTrack",
        "SYSTEM_MUTE": "systemMute", "SYSTEM_SWITCHER": "appSwitcher"
    ]
    struct Category: Decodable {
        let id: String; let title: String; let available: Bool; let destination: String?
    }
    struct Basic: Decodable {
        let id: String; let title: String; let image: String?
        let referenceSlot: Int; let available: Bool; let actionKind: String?
        var action: TapLockPreferences.Action? {
            guard available else { return nil }
            switch actionKind {
            case "lock": return .lock
            case "screenshot": return .screenshot
            case "controlCenter": return .controlCenter
            case "notificationCenter": return .notificationCenter
            case "appSwitcher": return .appSwitcher
            case "playPause": return .playPause
            case "previousTrack": return .previousTrack
            case "nextTrack": return .nextTrack
            case "flashlight": return .flashlight
            case "systemMute": return .systemMute
            default: return nil
            }
        }
    }
    let schemaVersion: Int
    let referencePackageSHA256: String
    let referenceBinarySHA256: String
    let titles: [String: String]
    let actionCategories: [Category]
    let basicActions: [Basic]
    var isValid: Bool {
        guard schemaVersion == 1, referencePackageSHA256 == Self.packageHash,
              referenceBinarySHA256 == Self.binaryHash,
              ["actions", "basic", "application", "selected", "choose"].allSatisfy({ !(titles[$0] ?? "").isEmpty }),
              actionCategories.map({ $0.id }) == ["BASIC_ACTION", "OPEN_APPLICATION", "APP_ACTION", "SHORTCUTS", "OPEN_URL", "PRESET_URLS"],
              actionCategories.allSatisfy({ !$0.title.isEmpty }),
              actionCategories[0].available, actionCategories[0].destination == "basic",
              actionCategories[1].available, actionCategories[1].destination == "application",
              actionCategories.dropFirst(2).allSatisfy({ !$0.available && $0.destination == nil }),
              basicActions.count == 68, Set(basicActions.map { $0.id }).count == 68,
              basicActions.map({ $0.id }) == Self.acceptedBasicIDs,
              basicActions.map({ $0.referenceSlot }) == Array(0..<68),
              basicActions.allSatisfy({ item in
                  let expectedKind = Self.supportedKindsByID[item.id]
                  return !item.title.isEmpty && item.available == (expectedKind != nil) &&
                      item.actionKind == expectedKind && (expectedKind == nil || item.action != nil)
              }),
              basicActions.filter({ $0.available }).count == 10 else { return false }
        return Set(basicActions.filter { $0.available }.compactMap { $0.actionKind }) == Self.supportedKinds
    }
}

private final class BottomNumberCell: UITableViewCell {
    let caption = UILabel()
    let valueButton = UIButton(type: .system)
    let slider = UISlider()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        caption.font = .preferredFont(forTextStyle: .body)
        caption.adjustsFontForContentSizeCategory = true
        caption.numberOfLines = 0
        valueButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        valueButton.titleLabel?.adjustsFontForContentSizeCategory = true
        valueButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        let heading = UIStackView(arrangedSubviews: [caption, valueButton])
        heading.spacing = 12
        heading.alignment = .center
        let stack = UIStackView(arrangedSubviews: [heading, slider])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            valueButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        selectionStyle = .none
    }
    required init?(coder: NSCoder) { return nil }
}

final class BottomGestureSettingsController: UITableViewController, UISearchResultsUpdating {
    private typealias P = BottomGesturePreferences
    private enum Page {
        case root, side(String), list(P.GestureID), categories, basic, applications
    }
    private let page: Page
    private let io: BottomGestureSettingsIO
    private var reference: BottomUIReference?
    private var catalog: BottomActionCatalog?
    private var referenceData: Data?
    private var catalogData: Data?
    private var snapshot = P.Snapshot.unavailable
    private var appSnapshot: [InstalledApplications.Choice] = []
    private var applicationNames: [String: String] = [:]
    private var missingApplicationNames = Set<String>()
    private var loadedApps = false
    private let icons = ApplicationIcons()
    private var activationObserver: NSObjectProtocol?
    private var pick: ((TapLockPreferences.Action) -> Bool)?
    private var pickerReturn: BottomGestureSettingsController?
    private var pageTitle: String?
    private var numberCommit: ((UITextField) -> Void)?

    init() {
        page = .root
        io = BottomGestureSettingsIO()
        super.init(style: .insetGrouped)
    }
    // Internal test seam changes I/O, never the production event/renderer body.
    init(io: BottomGestureSettingsIO) {
        page = .root
        self.io = io
        super.init(style: .insetGrouped)
    }
    private init(page: Page, io: BottomGestureSettingsIO, title: String? = nil) {
        self.page = page
        self.io = io
        pageTitle = title
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { return nil }
    deinit { if let observer = activationObserver { NotificationCenter.default.removeObserver(observer) } }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.allowsSelectionDuringEditing = true
        definesPresentationContext = true
        switch page {
        case .basic, .applications:
            let search = UISearchController(searchResultsController: nil)
            search.obscuresBackgroundDuringPresentation = false
            search.searchResultsUpdater = self
            navigationItem.searchController = search
        default: break
        }
        activationObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in self?.reloadPersistedState() }
        reloadPersistedState()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadPersistedState()
    }
    private func loadResources() -> Bool {
        guard let bottom = io.data("BottomGestureReference"), let actions = io.data("SettingsReference"),
              let ref = try? JSONDecoder().decode(BottomUIReference.self, from: bottom), ref.isValid,
              let cat = try? JSONDecoder().decode(BottomActionCatalog.self, from: actions), cat.isValid else {
            reference = nil; catalog = nil; referenceData = nil; catalogData = nil
            return false
        }
        reference = ref; catalog = cat; referenceData = bottom; catalogData = actions
        return true
    }
    private var usable: Bool { reference != nil && catalog != nil && snapshot.available }
    private func reloadPersistedState() {
        let valid = loadResources()
        snapshot = io.readSnapshot()
        switch page {
        case .root: title = reference?.title ?? "底部上划手势"
        case .side(let side): title = reference?.sides[side]?.title
        case .list: title = pageTitle ?? catalog?.titles["selected"]
        case .categories: title = catalog?.titles["actions"]
        case .basic: title = catalog?.titles["basic"]
        case .applications:
            title = catalog?.titles["application"]
            if valid && snapshot.available && !loadedApps {
                appSnapshot = io.applications()
                for app in appSnapshot { applicationNames[app.identifier] = app.name }
                loadedApps = true
            }
        }
        if case .list = page {
            if navigationItem.rightBarButtonItems == nil {
                let edit = UIBarButtonItem(title: "编辑", style: .plain, target: self, action: #selector(toggleEditing(_:)))
                edit.accessibilityIdentifier = "bottom.edit"
                navigationItem.rightBarButtonItems = [
                    UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addAction(_:))), edit]
                navigationItem.rightBarButtonItems?.first?.accessibilityIdentifier = "bottom.add"
                // Preserve the native Back item; do not replace it with an edit button.
            }
            navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = usable }
        }
        if !usable {
            let notice = UILabel()
            notice.text = valid ? "偏好配置不可用，未保存任何更改" : "配置资源不可用，所有设置已停用"
            notice.numberOfLines = 0
            notice.font = .preferredFont(forTextStyle: .body)
            notice.adjustsFontForContentSizeCategory = true
            notice.textAlignment = .center
            tableView.backgroundView = notice
        } else { tableView.backgroundView = nil }
        tableView.reloadData()
    }
    // Revalidate resources and persistence even for forced delegate calls and
    // synthetic UIControl events. A previously rendered view grants no authority.
    private func admitInteraction() -> Bool {
        guard isViewLoaded, view.window != nil, navigationController?.topViewController === self,
              usable, io.data("BottomGestureReference") == referenceData,
              io.data("SettingsReference") == catalogData else {
            if isViewLoaded { reloadPersistedState() }
            return false
        }
        let fresh = io.readSnapshot()
        guard fresh.available else { reloadPersistedState(); return false }
        if case .list(let id) = page,
           fresh.selection(id).actions != snapshot.selection(id).actions {
            reloadPersistedState()
            return false
        }
        snapshot = fresh
        return true
    }
    private var sections: [BottomUIReference.Section] {
        let source: [BottomUIReference.Section]
        switch page {
        case .root: source = reference?.sections ?? []
        case .side(let side): source = reference?.sides[side]?.sections ?? []
        default: return []
        }
        return source.map { section in
            BottomUIReference.Section(id: section.id, header: section.header, footer: section.footer,
                rows: section.rows.filter { row in
                    guard let condition = row.visibleWhen else { return true }
                    guard let key = P.BooleanKey(rawValue: condition) else { return false }
                    return snapshot.boolean(key)
                })
        }
    }
    private func row(at path: IndexPath) -> BottomUIReference.Row? {
        guard sections.indices.contains(path.section), sections[path.section].rows.indices.contains(path.row) else { return nil }
        return sections[path.section].rows[path.row]
    }
    private var query: String { navigationItem.searchController?.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    private var basics: [BottomActionCatalog.Basic] {
        (catalog?.basicActions ?? []).filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) }
    }
    private var apps: [InstalledApplications.Choice] {
        appSnapshot.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.identifier.localizedCaseInsensitiveContains(query) }
    }
    private var selectedActions: [TapLockPreferences.Action] {
        guard case .list(let id) = page else { return [] }
        return snapshot.selection(id).actions
    }
    override func numberOfSections(in tableView: UITableView) -> Int {
        switch page { case .root, .side: return sections.count; default: return 1 }
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch page {
        case .root, .side: return sections.indices.contains(section) ? sections[section].rows.count : 0
        case .list: return selectedActions.count
        case .categories: return catalog?.actionCategories.count ?? 0
        case .basic: return basics.count
        case .applications: return apps.count
        }
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections.indices.contains(section) ? sections[section].header : nil
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if sections.indices.contains(section) { return sections[section].footer }
        if case .list = page { return "点按编辑动作；编辑模式可删除和拖动排序。选择动作仅保存设置，不会立即执行。" }
        if case .categories = page { return "灰色动作类别尚未实现，不能选择。选择动作仅保存设置。" }
        return nil
    }
    private func configure(_ cell: UITableViewCell, id: String, title: String, enabled: Bool) {
        cell.accessibilityIdentifier = id
        cell.textLabel?.text = title
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.numberOfLines = 0
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.isUserInteractionEnabled = enabled
        cell.selectionStyle = enabled ? .default : .none
        if !enabled { cell.accessibilityTraits.insert(.notEnabled); cell.textLabel?.textColor = .tertiaryLabel }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        switch page {
        case .root, .side:
            guard let row = row(at: path) else { return cell }
            if row.kind == "slider", let key = P.NumericKey(rawValue: row.key ?? "") {
                let numeric = BottomNumberCell(style: .default, reuseIdentifier: nil)
                configure(numeric, id: row.id, title: "", enabled: usable)
                numeric.caption.text = row.title
                numeric.slider.minimumValue = Float(key.minValue)
                numeric.slider.maximumValue = Float(key.maxValue)
                numeric.slider.value = Float(snapshot.number(key))
                numeric.slider.isEnabled = usable
                numeric.slider.accessibilityLabel = row.title
                numeric.slider.accessibilityIdentifier = row.id + ".slider"
                numeric.slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
                numeric.valueButton.setTitle(String(format: "%.1f", snapshot.number(key)), for: .normal)
                numeric.valueButton.accessibilityLabel = row.title + "，输入数值"
                numeric.valueButton.accessibilityIdentifier = row.id + ".input"
                numeric.valueButton.isEnabled = usable
                numeric.valueButton.addTarget(self, action: #selector(numberTapped(_:)), for: .touchUpInside)
                return numeric
            }
            configure(cell, id: row.id, title: row.title, enabled: usable)
            if row.kind == "switch" {
                let toggle = UISwitch()
                toggle.accessibilityIdentifier = row.id + ".switch"
                toggle.accessibilityLabel = row.title
                toggle.isOn = boolean(for: row.key ?? "")
                toggle.isEnabled = usable
                toggle.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
                cell.accessoryView = toggle
                cell.selectionStyle = .none
            } else {
                cell.accessoryType = .disclosureIndicator
                if row.kind == "actions", let id = P.GestureID(rawValue: row.key ?? "") {
                    cell.detailTextLabel?.text = "\(snapshot.selection(id).actions.count) 个动作"
                }
            }
        case .list:
            guard selectedActions.indices.contains(path.row) else { return cell }
            let action = selectedActions[path.row]
            configure(cell, id: "bottom.action.\(path.row)", title: actionTitle(action), enabled: usable)
            cell.accessoryType = .disclosureIndicator
            cell.showsReorderControl = true
            if case .openApp(let identifier) = action {
                cell.detailTextLabel?.text = identifier
                cell.imageView?.image = icons.image(identifier: identifier)
            } else if let item = catalog?.basicActions.first(where: { $0.action == action }), let image = item.image {
                cell.imageView?.image = ApplicationIcons.normalized(UIImage(systemName: image))
            }
        case .categories:
            guard let categories = catalog?.actionCategories, categories.indices.contains(path.row) else { return cell }
            let category = categories[path.row]
            configure(cell, id: category.id, title: category.title, enabled: usable && category.available)
            cell.accessoryType = category.available ? .disclosureIndicator : .none
        case .basic:
            guard basics.indices.contains(path.row) else { return cell }
            let item = basics[path.row]
            configure(cell, id: item.id, title: item.title, enabled: usable && item.action != nil)
            if let name = item.image { cell.imageView?.image = ApplicationIcons.normalized(UIImage(systemName: name)) }
        case .applications:
            guard apps.indices.contains(path.row) else { return cell }
            let app = apps[path.row]
            configure(cell, id: app.identifier, title: app.name, enabled: usable)
            cell.detailTextLabel?.text = app.identifier
            cell.imageView?.image = icons.image(identifier: app.identifier)
        }
        return cell
    }
    private func boolean(for raw: String) -> Bool {
        if let key = P.BooleanKey(rawValue: raw) { return snapshot.boolean(key) }
        for id in P.GestureID.allCases {
            if raw == id.enabledKey { return snapshot.selection(id).enabled }
            if raw == id.flowKey { return snapshot.selection(id).flowEnabled }
        }
        return false
    }
    private func ownedCell(at path: IndexPath) -> UITableViewCell? {
        guard let cell = tableView.cellForRow(at: path), tableView.indexPath(for: cell) == path,
              tableView.visibleCells.contains(where: { $0 === cell }), cell.isUserInteractionEnabled,
              !cell.accessibilityTraits.contains(.notEnabled) else { return nil }
        return cell
    }
    private func ownedControl(_ sender: UIControl) -> (UITableViewCell, IndexPath, BottomUIReference.Row)? {
        guard sender.isEnabled, sender.isUserInteractionEnabled, admitInteraction() else { return nil }
        for cell in tableView.visibleCells {
            let matches: Bool
            if let numeric = cell as? BottomNumberCell { matches = sender === numeric.slider || sender === numeric.valueButton }
            else { matches = cell.accessoryView === sender }
            guard matches, let path = tableView.indexPath(for: cell), ownedCell(at: path) === cell,
                  let row = row(at: path), cell.accessibilityIdentifier == row.id else { continue }
            return (cell, path, row)
        }
        return nil
    }
    @objc private func switchChanged(_ sender: UISwitch) {
        guard let (_, _, row) = ownedControl(sender), row.kind == "switch" else { return }
        let raw = row.key ?? ""
        let saved: Bool
        if let key = P.BooleanKey(rawValue: raw) { saved = io.writeBoolean(sender.isOn, key) }
        else if let id = P.GestureID.allCases.first(where: { $0.enabledKey == raw }) { saved = io.writeEnabled(sender.isOn, id) }
        else if let id = P.GestureID.allCases.first(where: { $0.flowKey == raw }) { saved = io.writeFlowEnabled(sender.isOn, id) }
        else { return }
        didSave(saved)
    }
    @objc private func sliderChanged(_ sender: UISlider) {
        guard let (cell, _, row) = ownedControl(sender), row.kind == "slider",
              let key = P.NumericKey(rawValue: row.key ?? "") else { return }
        let value = Double(sender.value)
        guard value.isFinite else { reloadPersistedState(); return }
        let clamped = min(key.maxValue, max(key.minValue, value))
        let saved = io.writeNumber(clamped, key)
        if saved, let numeric = cell as? BottomNumberCell {
            snapshot = io.readSnapshot()
            numeric.valueButton.setTitle(String(format: "%.1f", snapshot.number(key)), for: .normal)
        } else { didSave(false) }
    }
    @objc private func numberTapped(_ sender: UIButton) {
        guard let (cell, path, row) = ownedControl(sender), row.kind == "slider",
              let key = P.NumericKey(rawValue: row.key ?? ""), presentedViewController == nil else { return }
        let alert = UIAlertController(title: row.title, message: "\(key.minValue) – \(key.maxValue)", preferredStyle: .alert)
        alert.addTextField { field in
            field.keyboardType = .decimalPad
            field.text = String(format: "%.2f", self.snapshot.number(key))
            field.accessibilityIdentifier = "bottom.number.entry"
            field.returnKeyType = .done
            field.addTarget(self, action: #selector(self.numberSubmitted(_:)), for: .editingDidEndOnExit)
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in self?.numberCommit = nil })
        numberCommit = { [weak self, weak cell, weak sender, weak alert] field in
            guard let self = self, let sender = sender, let cell = cell,
                  field.isEnabled, field.isUserInteractionEnabled,
                  self.presentedViewController === alert,
                  alert?.textFields?.first === field,
                  self.admitInteraction(), self.ownedCell(at: path) === cell,
                  self.ownedControl(sender)?.2.id == row.id else { return }
            self.numberCommit = nil
            guard let text = field.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let value = Double(text), value.isFinite else {
                alert?.dismiss(animated: false)
                self.reloadPersistedState()
                self.showError("请输入有限数值")
                return
            }
            let saved = self.io.writeNumber(min(key.maxValue, max(key.minValue, value)), key)
            alert?.dismiss(animated: false)
            self.didSave(saved)
        }
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let field = alert?.textFields?.first else { return }
            self?.numberCommit?(field)
        })
        present(alert, animated: true)
    }
    @objc private func numberSubmitted(_ sender: UITextField) { numberCommit?(sender) }
    private func didSave(_ saved: Bool) {
        reloadPersistedState()
        if !saved { showError("保存失败，已恢复已保存的设置") }
    }
    private func showError(_ message: String) {
        // UIAlertAction handlers run while their alert is dismissing. Queue the
        // error presentation rather than dropping it behind the numeric editor.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.view.window != nil,
                  self.navigationController?.topViewController === self else { return }
            if let current = self.presentedViewController {
                current.dismiss(animated: false) { [weak self] in self?.showError(message) }
                return
            }
            let alert = UIAlertController(title: "无法保存", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            self.present(alert, animated: true)
        }
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        guard tableView === self.tableView, admitInteraction(), let cell = ownedCell(at: path) else { return }
        tableView.deselectRow(at: path, animated: true)
        switch page {
        case .root, .side:
            guard let row = row(at: path), cell.accessibilityIdentifier == row.id else { return }
            if row.kind == "link", let side = row.destination, reference?.sides[side] != nil {
                push(.side(side))
            } else if row.kind == "actions", let id = P.GestureID(rawValue: row.key ?? "") {
                push(.list(id), title: row.title)
            }
        case .list(let id):
            guard !isEditing, snapshot.selection(id).actions.indices.contains(path.row),
                  cell.accessibilityIdentifier == "bottom.action.\(path.row)" else { return }
            openPicker(editing: path.row)
        case .categories:
            guard let categories = catalog?.actionCategories, categories.indices.contains(path.row) else { return }
            let item = categories[path.row]
            guard item.available, item.id == cell.accessibilityIdentifier else { return }
            if item.destination == "basic" { pushPicker(.basic) }
            else if item.destination == "application" { pushPicker(.applications) }
        case .basic:
            guard basics.indices.contains(path.row), basics[path.row].id == cell.accessibilityIdentifier,
                  let action = basics[path.row].action else { return }
            finishPicking(action)
        case .applications:
            guard apps.indices.contains(path.row), apps[path.row].identifier == cell.accessibilityIdentifier else { return }
            let app = apps[path.row]
            guard let fresh = io.application(app.identifier), fresh.identifier == app.identifier else {
                showError("应用已不可用，请返回后重新选择")
                return
            }
            finishPicking(.openApp(fresh.identifier))
        }
    }
    private func push(_ page: Page, title: String? = nil) {
        let controller = BottomGestureSettingsController(page: page, io: io, title: title)
        navigationController?.pushViewController(controller, animated: true)
    }
    private func actionTitle(_ action: TapLockPreferences.Action) -> String {
        if case .openApp(let identifier) = action {
            if let name = applicationNames[identifier] { return name }
            if missingApplicationNames.contains(identifier) { return "应用不可用" }
            if let app = io.application(identifier) {
                applicationNames[identifier] = app.name
                return app.name
            }
            missingApplicationNames.insert(identifier)
            return "应用不可用"
        }
        return catalog?.basicActions.first(where: { $0.action == action })?.title ?? "动作不可用"
    }
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        navigationItem.rightBarButtonItems?.first(where: { $0.accessibilityIdentifier == "bottom.edit" })?.title = editing ? "完成" : "编辑"
    }
    @objc private func toggleEditing(_ sender: UIBarButtonItem) {
        guard admitInteraction(), sender.isEnabled,
              navigationItem.rightBarButtonItems?.contains(where: { $0 === sender }) == true,
              case .list = page else { return }
        setEditing(!isEditing, animated: true)
    }
    @objc private func addAction(_ sender: UIBarButtonItem) {
        guard admitInteraction(), sender.isEnabled,
              navigationItem.rightBarButtonItems?.first === sender, case .list = page else { return }
        if isEditing { setEditing(false, animated: false) }
        openPicker(editing: nil)
    }
    private func openPicker(editing index: Int?) {
        guard case .list(let id) = page else { return }
        let controller = BottomGestureSettingsController(page: .categories, io: io)
        controller.pickerReturn = self
        let editingIndex = index
        let expectedActions = snapshot.selection(id).actions
        controller.pick = { [weak self] action in
            guard let self = self, self.loadResources() else { return false }
            let fresh = self.io.readSnapshot()
            guard fresh.available, fresh.selection(id).actions == expectedActions else {
                self.reloadPersistedState()
                return false
            }
            var actions = expectedActions
            if let index = editingIndex {
                guard actions.indices.contains(index) else { return false }
                actions[index] = action
            } else { actions.append(action) }
            let saved = self.io.writeActions(actions, id)
            self.reloadPersistedState()
            return saved
        }
        navigationController?.pushViewController(controller, animated: true)
    }
    private func pushPicker(_ page: Page) {
        let controller = BottomGestureSettingsController(page: page, io: io)
        controller.pick = pick
        controller.pickerReturn = pickerReturn
        navigationController?.pushViewController(controller, animated: true)
    }
    private func finishPicking(_ action: TapLockPreferences.Action) {
        guard let pick = pick, let target = pickerReturn,
              navigationController?.viewControllers.contains(where: { $0 === target }) == true else { return }
        guard pick(action) else { reloadPersistedState(); showError("保存失败，列表已变化或偏好不可用"); return }
        navigationItem.searchController?.isActive = false
        navigationController?.popToViewController(target, animated: true)
    }
    override func tableView(_ tableView: UITableView, canEditRowAt path: IndexPath) -> Bool {
        tableView === self.tableView && usable && selectedActions.indices.contains(path.row)
    }
    override func tableView(_ tableView: UITableView, canMoveRowAt path: IndexPath) -> Bool {
        self.tableView(tableView, canEditRowAt: path)
    }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt path: IndexPath) {
        guard tableView === self.tableView, editingStyle == .delete, admitInteraction(),
              ownedCell(at: path) != nil, case .list(let id) = page,
              selectedActions.indices.contains(path.row) else { return }
        var actions = selectedActions
        actions.remove(at: path.row)
        didSave(io.writeActions(actions, id))
    }
    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard tableView === self.tableView, isEditing, admitInteraction(),
              ownedCell(at: sourceIndexPath) != nil, case .list(let id) = page,
              sourceIndexPath.section == 0, destinationIndexPath.section == 0,
              selectedActions.indices.contains(sourceIndexPath.row),
              selectedActions.indices.contains(destinationIndexPath.row) else { reloadPersistedState(); return }
        var actions = selectedActions
        let moved = actions.remove(at: sourceIndexPath.row)
        actions.insert(moved, at: destinationIndexPath.row)
        didSave(io.writeActions(actions, id))
    }
    func updateSearchResults(for searchController: UISearchController) {
        guard searchController === navigationItem.searchController else { return }
        tableView.reloadData()
    }
}
