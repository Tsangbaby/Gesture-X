import UIKit
import TapLockPreferencesHost

/// Real Preferences base class, with an owned legacy factory entry point.
@objc(TapLockSettingsController)
final class TapLockSettingsController: PSViewController, UITableViewDataSource, UITableViewDelegate {
    private enum Page { case root, homeScreen, doubleTapAction, applicationPicker }
    private var page: Page = .root
    private let enabledSwitch = UISwitch()
    private var action: TapLockPreferences.Action = .lock
    private var applicationName: String?
    private var applications: [InstalledApplications.Choice] = []
    private let applicationIcons = ApplicationIcons()

    // Some Settings factories prefer this selector. It must not call a missing
    // PSViewController implementation; use the supported UIKit initializer.
    @objc(initForContentSize:)
    convenience init(contentSize: CGSize) {
        self.init(nibName: nil, bundle: nil)
    }

    private convenience init(page: Page) {
        self.init(nibName: nil, bundle: nil)
        self.page = page
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
        switch page {
        case .root:
            title = "TapLock"
        case .homeScreen:
            title = "主屏幕的手势"
            enabledSwitch.accessibilityLabel = "启用主屏双击"
            enabledSwitch.addTarget(self, action: #selector(changeEnabled(_:)), for: .valueChanged)
        case .doubleTapAction:
            title = "选择双击动作"
        case .applicationPicker:
            title = "选择App"
            // One render snapshot, never enumerate LaunchServices per table cell.
            applications = InstalledApplications.choices()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if page == .homeScreen {
            enabledSwitch.isOn = TapLockPreferences.readEnabled()
        }
        action = TapLockPreferences.readAction()
        applicationName = nil
        if case .openApp(let identifier) = action {
            applicationName = InstalledApplications.choice(identifier: identifier)?.name
        }
        (view as? UITableView)?.reloadData()
    }

    private var actionSummary: String {
        switch action {
        case .lock: return "系统锁屏"
        case .openApp: return "打开指定App · " + (applicationName ?? "App不可用")
        case .controlCenter: return "打开控制中心"
        case .unavailable: return "配置不可用，请重新选择"
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int { return 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch page {
        case .root: return 1
        case .homeScreen: return 2
        case .doubleTapAction: return 3
        case .applicationPicker: return applications.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell
        if page == .applicationPicker {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        } else {
            cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        }
        for label in [cell.textLabel, cell.detailTextLabel] {
            label?.font = .preferredFont(forTextStyle: .body)
            label?.adjustsFontForContentSizeCategory = true
            label?.numberOfLines = 0
        }
        switch (page, indexPath.row) {
        case (.root, _):
            cell.textLabel?.text = "主屏幕的手势"
            cell.accessoryType = .disclosureIndicator
        case (.homeScreen, 0):
            cell.textLabel?.text = "启用主屏双击"
            cell.selectionStyle = .none
            cell.accessoryView = enabledSwitch
        case (.homeScreen, _):
            cell.textLabel?.text = "选择双击动作"
            cell.detailTextLabel?.text = actionSummary
            cell.accessoryType = .disclosureIndicator
        case (.doubleTapAction, 0):
            cell.textLabel?.text = "系统锁屏"
            cell.accessoryType = action == .lock ? .checkmark : .none
        case (.doubleTapAction, 1):
            cell.textLabel?.text = "打开指定App"
            if case .openApp = action {
                cell.detailTextLabel?.text = applicationName ?? "App不可用"
                cell.accessoryType = .checkmark
            } else {
                cell.detailTextLabel?.text = "选择App"
                cell.accessoryType = .disclosureIndicator
            }
        case (.doubleTapAction, 2):
            cell.textLabel?.text = "打开控制中心"
            cell.accessoryType = action == .controlCenter ? .checkmark : .none
        case (.applicationPicker, let row):
            let choice = applications[row]
            cell.textLabel?.text = choice.name
            cell.detailTextLabel?.text = choice.identifier
            cell.imageView?.image = applicationIcons.image(identifier: choice.identifier)
            cell.imageView?.contentMode = .scaleAspectFit
            cell.accessoryType = action == .openApp(choice.identifier) ? .checkmark : .none
        default:
            break
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch (page, indexPath.row) {
        case (.root, 0):
            navigationController?.pushViewController(TapLockSettingsController(page: .homeScreen), animated: true)
        case (.homeScreen, 1):
            navigationController?.pushViewController(TapLockSettingsController(page: .doubleTapAction), animated: true)
        case (.doubleTapAction, 0):
            guard TapLockPreferences.writeAction(.lock) else { showSaveError(); return }
            navigationController?.popViewController(animated: true)
        case (.doubleTapAction, 1):
            navigationController?.pushViewController(TapLockSettingsController(page: .applicationPicker), animated: true)
        case (.doubleTapAction, 2):
            guard TapLockPreferences.writeAction(.controlCenter) else { showSaveError(); return }
            navigationController?.popViewController(animated: true)
        case (.applicationPicker, let row):
            guard applications.indices.contains(row) else { return }
            let choice = applications[row]
            guard InstalledApplications.choice(identifier: choice.identifier) != nil else {
                let alert = UIAlertController(title: "App不可用", message: "该App已卸载或不允许启动，请重新进入列表选择。", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "好", style: .default))
                present(alert, animated: true)
                return
            }
            guard TapLockPreferences.writeAction(.openApp(choice.identifier)) else { showSaveError(); return }
            navigationController?.popViewController(animated: true)
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch page {
        case .root:
            return "当前开放主屏幕双击手势，其他手势将在逐项实现和验证后加入。"
        case .homeScreen:
            return "默认关闭。开启后，仅在已解锁、竖屏的主屏幕空白处双击执行所选动作。" +
                "图标、文件夹、小组件、Dock 及应用内不触发；编辑桌面或启用 VoiceOver 时不触发。修改立即生效，无需注销。"
        case .doubleTapAction:
            return "升级保留已保存动作，未配置时使用系统锁屏。选择动作只保存设置，不会立即执行。目标App或系统入口不可用时不执行其他动作。"
        case .applicationPicker:
            return applications.isEmpty ? "未找到可选App。请确认App已安装且当前系统允许读取应用列表。" :
                "仅列出已安装、允许启动且未隐藏的系统或用户App。选择后立即保存，不会在此处打开。"
        }
    }

    @objc private func changeEnabled(_ sender: UISwitch) {
        guard TapLockPreferences.writeEnabled(sender.isOn) else {
            sender.isOn = TapLockPreferences.readEnabled()
            showSaveError()
            return
        }
    }

    private func showSaveError() {
        let alert = UIAlertController(title: "未能保存设置",
                                      message: "设置未能持久保存，请稍后再试。",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}
