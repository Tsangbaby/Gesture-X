import UIKit
import TapLockPreferencesHost

// Reference IDs identify rows only. They are never preference keys.
private struct SettingsReference: Decodable {
    struct Row: Decodable {
        let id: String
        let title: String
        let kind: String
        let available: Bool
        let defaultValue: Bool?
        let destination: String?
        let phoneOnly: Bool?
    }
    struct Section: Decodable {
        let id: String
        let header: String?
        let footer: String?
        let rows: [Row]
    }
    struct Category: Decodable {
        let id: String
        let title: String
        let available: Bool
        let destination: String?
    }
    struct BasicAction: Decodable {
        let id: String
        let title: String
        let image: String?
        let referenceSlot: Int
        let available: Bool
        let actionKind: String?

        var action: TapLockPreferences.Action? {
            guard available else { return nil }
            switch actionKind {
            case "screenshot": return .screenshot
            case "controlCenter": return .controlCenter
            case "notificationCenter": return .notificationCenter
            case "lock": return .lock
            case "appSwitcher": return .appSwitcher
            case "playPause": return .playPause
            default: return nil
            }
        }
    }
    let schemaVersion: Int
    let referencePackageSHA256: String
    let referenceBinarySHA256: String
    let titles: [String: String]
    let rootSections: [Section]
    let homeSections: [Section]
    let actionCategories: [Category]
    let basicActions: [BasicAction]
    let originalSelectedFooter: String
    let phaseNotice: String
    let excludedReferenceSurfaces: [String]

    static func load() -> SettingsReference? {
        let bundle = Bundle(for: TapLockSettingsController.self)
        guard let url = bundle.url(forResource: "SettingsReference", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let reference = try? JSONDecoder().decode(SettingsReference.self, from: data),
              reference.isValid else { return nil }
        return reference
    }

    private var isValid: Bool {
        let rootRows = rootSections.flatMap { $0.rows }
        let homeRows = homeSections.flatMap { $0.rows }
        let requiredTitles = ["root", "home", "actions", "basic", "application", "selected", "choose"]
        guard schemaVersion == 1,
              referencePackageSHA256 == "240362fc1846f697025122e4788d04bbd1920b8f5102bcfc5642a9a14b62837a",
              referenceBinarySHA256 == "a3e95d0028907909bc521a687934fa362cef18c4c813a787ff2a4b9e0eba6586",
              requiredTitles.allSatisfy({ !(titles[$0] ?? "").isEmpty }),
              !phaseNotice.isEmpty, !originalSelectedFooter.isEmpty else { return false }
        guard rootRows.contains(where: { $0.id == "homescreenOptions" && $0.kind == "link" }),
              homeRows.count == 21, Set(homeRows.map { $0.id }).count == 21,
              Set(rootRows.map { $0.id }).count == rootRows.count,
              homeRows.contains(where: { $0.id == "homescreenDoubleTapEnabled" && $0.kind == "switch" }),
              homeRows.contains(where: { $0.id == "homescreenDoubleTap" && $0.kind == "link" }),
              (rootRows + homeRows).allSatisfy({ ["switch", "link", "button"].contains($0.kind) }) else { return false }
        guard actionCategories.count == 6, Set(actionCategories.map { $0.id }).count == 6,
              basicActions.count == 68, Set(basicActions.map { $0.id }).count == 68,
              basicActions.map({ $0.referenceSlot }) == Array(0..<68),
              basicActions.compactMap({ $0.action }).count == 6 else { return false }
        return Set(basicActions.filter { $0.available }.compactMap { $0.actionKind }) ==
            Set(["screenshot", "controlCenter", "notificationCenter", "lock", "appSwitcher", "playPause"])
    }
}

/// Real Preferences base class, with an owned legacy factory entry point.
@objc(TapLockSettingsController)
final class TapLockSettingsController: PSViewController, UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating {
    private enum Page { case root, homeScreen, doubleTapAction, basicActions, applicationPicker }
    private var page: Page = .root
    private var reference = SettingsReference.load()
    private var switches: [String: UISwitch] = [:]
    private var action: TapLockPreferences.Action = .unavailable
    private var applicationName: String?
    private var applications: [InstalledApplications.Choice] = []
    private let applicationIcons = ApplicationIcons()
    private var searchController: UISearchController?

    // Do not invoke the absent PSViewController legacy initializer.
    @objc(initForContentSize:)
    convenience init(contentSize: CGSize) {
        self.init(nibName: nil, bundle: nil)
    }

    private convenience init(page: Page, reference: SettingsReference) {
        self.init(nibName: nil, bundle: nil)
        self.page = page
        self.reference = reference
    }

    override func loadView() {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 60
        view = table
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let reference = reference else { title = "TapLock · 设置不可用"; return }
        switch page {
        case .root: title = reference.titles["root"]
        case .homeScreen: title = reference.titles["home"]
        case .doubleTapAction:
            title = reference.titles["actions"]
            let edit = UIBarButtonItem(barButtonSystemItem: .edit, target: nil, action: nil)
            edit.isEnabled = false
            edit.accessibilityHint = "多选、编辑、删除和排序尚未实现"
            navigationItem.rightBarButtonItem = edit
        case .basicActions:
            title = reference.titles["basic"]
            let search = UISearchController(searchResultsController: nil)
            search.obscuresBackgroundDuringPresentation = false
            search.searchResultsUpdater = self
            search.searchBar.placeholder = "搜索基础动作"
            navigationItem.searchController = search
            navigationItem.hidesSearchBarWhenScrolling = false
            definesPresentationContext = true
            searchController = search
        case .applicationPicker:
            title = reference.titles["application"]
            // One render snapshot; neither reuse nor reappearance enumerates apps.
            applications = InstalledApplications.choices()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshSelection()
        (view as? UITableView)?.reloadData()
    }

    private func refreshSelection() {
        action = TapLockPreferences.readAction()
        applicationName = nil
        if case .openApp(let identifier) = action {
            applicationName = InstalledApplications.choice(identifier: identifier)?.name
        }
        switches["homescreenDoubleTapEnabled"]?.isOn = TapLockPreferences.readEnabled()
    }

    private var actionSummary: String {
        if case .openApp = action { return "打开应用 · " + (applicationName ?? "App不可用") }
        if action == .unavailable { return "配置不可用，请重新选择" }
        return reference?.basicActions.first { $0.action == action }?.title ?? "配置不可用，请重新选择"
    }

    private var sections: [SettingsReference.Section] {
        guard let reference = reference else { return [] }
        let source = page == .root ? reference.rootSections : reference.homeSections
        return source.map { section in
            SettingsReference.Section(id: section.id, header: section.header, footer: section.footer,
                rows: section.rows.filter { $0.phoneOnly != true || UIDevice.current.userInterfaceIdiom == .phone })
        }
    }

    private func row(at indexPath: IndexPath) -> SettingsReference.Row? {
        let current = sections
        guard current.indices.contains(indexPath.section),
              current[indexPath.section].rows.indices.contains(indexPath.row) else { return nil }
        return current[indexPath.section].rows[indexPath.row]
    }

    private func rowIsAvailable(_ row: SettingsReference.Row) -> Bool {
        guard reference != nil, row.available else { return false }
        switch page {
        case .root: return row.id == "homescreenOptions" && row.kind == "link"
        case .homeScreen:
            return (row.id == "homescreenDoubleTapEnabled" && row.kind == "switch") ||
                (row.id == "homescreenDoubleTap" && row.kind == "link")
        default: return false
        }
    }

    private var filteredBasicActions: [SettingsReference.BasicAction] {
        let query = searchController?.searchBar.text ?? ""
        let all = reference?.basicActions ?? []
        return query.isEmpty ? all : all.filter { $0.title.range(of: query, options: .caseInsensitive) != nil }
    }

    func updateSearchResults(for searchController: UISearchController) {
        refreshSelection()
        (view as? UITableView)?.reloadData()
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        guard reference != nil else { return 1 }
        switch page {
        case .root, .homeScreen: return sections.count
        case .doubleTapAction: return 2
        case .basicActions, .applicationPicker: return 1
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard reference != nil else { return section == 0 ? 1 : 0 }
        switch page {
        case .root, .homeScreen: return sections.indices.contains(section) ? sections[section].rows.count : 0
        case .doubleTapAction: return section == 0 ? 1 : (section == 1 ? reference!.actionCategories.count : 0)
        case .basicActions: return section == 0 ? filteredBasicActions.count : 0
        case .applicationPicker: return section == 0 ? applications.count : 0
        }
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { return false }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { return false }

    private func disable(_ cell: UITableViewCell) {
        cell.isUserInteractionEnabled = false
        cell.selectionStyle = .none
        cell.textLabel?.textColor = .tertiaryLabel
        cell.detailTextLabel?.textColor = .tertiaryLabel
        cell.imageView?.tintColor = .tertiaryLabel
        cell.accessibilityTraits.insert(.notEnabled)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: page == .applicationPicker ? .subtitle : .value1, reuseIdentifier: nil)
        for label in [cell.textLabel, cell.detailTextLabel] {
            label?.font = .preferredFont(forTextStyle: .body)
            label?.adjustsFontForContentSizeCategory = true
            label?.numberOfLines = 0
        }
        guard let reference = reference else {
            cell.textLabel?.text = "设置不可用"
            cell.detailTextLabel?.text = "设置资源缺失或损坏，未更改任何偏好。"
            disable(cell)
            return cell
        }
        switch page {
        case .root, .homeScreen:
            guard let row = row(at: indexPath) else { disable(cell); return cell }
            let available = rowIsAvailable(row)
            cell.accessibilityIdentifier = row.id
            cell.textLabel?.text = row.title
            if row.kind == "switch" {
                let toggle = switches[row.id] ?? UISwitch()
                switches[row.id] = toggle
                toggle.accessibilityIdentifier = row.id
                toggle.accessibilityLabel = row.title
                toggle.isEnabled = available
                toggle.isOn = available ? TapLockPreferences.readEnabled() : (row.defaultValue ?? false)
                toggle.removeTarget(self, action: #selector(changeEnabled(_:)), for: .valueChanged)
                toggle.addTarget(self, action: #selector(changeEnabled(_:)), for: .valueChanged)
                cell.accessoryView = toggle
                cell.selectionStyle = .none
            } else {
                cell.accessoryType = row.kind == "link" ? .disclosureIndicator : .none
                if row.id == "homescreenDoubleTap" && available { cell.detailTextLabel?.text = actionSummary }
            }
            if !available {
                cell.detailTextLabel?.text = "尚未实现"
                disable(cell)
            }
        case .doubleTapAction:
            if indexPath.section == 0 {
                cell.textLabel?.text = actionSummary
                cell.accessoryType = action == .unavailable ? .none : .checkmark
                disable(cell)
            } else if indexPath.section == 1, reference.actionCategories.indices.contains(indexPath.row) {
                let category = reference.actionCategories[indexPath.row]
                cell.accessibilityIdentifier = category.id
                cell.textLabel?.text = category.title
                cell.accessoryType = .disclosureIndicator
                if !category.available || indexPath.row > 1 {
                    cell.detailTextLabel?.text = "尚未实现"
                    disable(cell)
                }
            } else { disable(cell) }
        case .basicActions:
            let entries = filteredBasicActions
            guard indexPath.section == 0, entries.indices.contains(indexPath.row) else { disable(cell); return cell }
            let entry = entries[indexPath.row]
            cell.accessibilityIdentifier = entry.id
            cell.textLabel?.text = entry.title
            if let symbol = entry.image { cell.imageView?.image = UIImage(systemName: symbol) }
            cell.accessoryType = entry.action != nil && entry.action == action ? .checkmark : .none
            if entry.action == nil { cell.detailTextLabel?.text = "尚未实现"; disable(cell) }
        case .applicationPicker:
            guard indexPath.section == 0, applications.indices.contains(indexPath.row) else { disable(cell); return cell }
            let choice = applications[indexPath.row]
            cell.textLabel?.text = choice.name
            cell.detailTextLabel?.text = choice.identifier
            cell.imageView?.image = applicationIcons.image(identifier: choice.identifier)
            cell.imageView?.contentMode = .scaleAspectFit
            cell.accessoryType = action == .openApp(choice.identifier) ? .checkmark : .none
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let reference = reference else { return }
        switch page {
        case .root, .homeScreen:
            guard let row = row(at: indexPath), rowIsAvailable(row), row.kind == "link" else { return }
            switch row.destination {
            case "home" where page == .root: push(.homeScreen, reference: reference)
            case "actions" where page == .homeScreen: push(.doubleTapAction, reference: reference)
            default: return
            }
        case .doubleTapAction:
            guard indexPath.section == 1, reference.actionCategories.indices.contains(indexPath.row),
                  reference.actionCategories[indexPath.row].available, indexPath.row < 2 else { return }
            switch reference.actionCategories[indexPath.row].destination {
            case "basic" where indexPath.row == 0: push(.basicActions, reference: reference)
            case "application" where indexPath.row == 1: push(.applicationPicker, reference: reference)
            default: return
            }
        case .basicActions:
            let entries = filteredBasicActions
            guard indexPath.section == 0, entries.indices.contains(indexPath.row),
                  let selected = entries[indexPath.row].action else { return }
            save(selected)
        case .applicationPicker:
            guard indexPath.section == 0, applications.indices.contains(indexPath.row) else { return }
            let choice = applications[indexPath.row]
            guard InstalledApplications.choice(identifier: choice.identifier) != nil else {
                showAlert(title: "App不可用", message: "该App已卸载或不允许启动，请重新进入列表选择。")
                return
            }
            save(.openApp(choice.identifier))
        }
    }

    private func push(_ page: Page, reference: SettingsReference) {
        navigationController?.pushViewController(TapLockSettingsController(page: page, reference: reference), animated: true)
    }

    private func save(_ selected: TapLockPreferences.Action) {
        guard reference != nil else { return }
        guard TapLockPreferences.writeAction(selected) else { showSaveError(); return }
        navigationController?.popViewController(animated: true)
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let reference = reference else { return nil }
        switch page {
        case .root, .homeScreen: return sections.indices.contains(section) ? sections[section].header : nil
        case .doubleTapAction: return reference.titles[section == 0 ? "selected" : "choose"]
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let reference = reference else { return "设置资源不可用，所有设置操作已禁用。" }
        switch page {
        case .root, .homeScreen:
            guard sections.indices.contains(section) else { return nil }
            let footer = sections[section].footer
            if section == sections.count - 1 {
                return [footer, reference.phaseNotice, page == .homeScreen ?
                    "默认关闭。仅已解锁、竖屏主屏幕空白处双击执行；图标、文件夹、小组件、Dock、应用内、编辑桌面或 VoiceOver 时不触发。修改立即生效，无需注销。" : nil]
                    .compactMap { $0 }.joined(separator: "\n")
            }
            return footer
        case .doubleTapAction:
            if section == 0 {
                return reference.phaseNotice + "\n原版说明（非本阶段功能）：\n" + reference.originalSelectedFooter
            }
            return reference.phaseNotice + "\n选择动作只保存设置，不会立即执行。未配置时使用系统锁屏；损坏配置不回退。"
        case .basicActions:
            return "原版68项主目录；未实现项禁用。原版设备与外部插件条件过滤及条件追加项尚未实现。选择后替换当前单个动作并返回，不会立即执行。"
        case .applicationPicker:
            return applications.isEmpty ? "未找到可选App。请确认App已安装且当前系统允许读取应用列表。" :
                "仅列出已安装、允许启动且未隐藏的系统或用户App。选择后替换当前单个动作并返回，不会在此处打开。"
        }
    }

    @objc private func changeEnabled(_ sender: UISwitch) {
        // Disabled controls must remain inert even for direct sendActions calls.
        guard reference != nil, page == .homeScreen, sender.isEnabled,
              switches["homescreenDoubleTapEnabled"] === sender,
              let row = sections.flatMap({ $0.rows }).first(where: { $0.id == "homescreenDoubleTapEnabled" }),
              rowIsAvailable(row) else { return }
        guard TapLockPreferences.writeEnabled(sender.isOn) else {
            sender.isOn = TapLockPreferences.readEnabled()
            showSaveError()
            return
        }
    }

    private func showSaveError() {
        showAlert(title: "未能保存设置", message: "设置未能持久保存，请稍后再试。")
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}
