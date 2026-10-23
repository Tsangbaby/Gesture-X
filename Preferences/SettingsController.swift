import UIKit
import TapLockPreferencesHost

/// Inherits the real Preferences host contract (including initForContentSize:).
/// Stored properties have defaults and no custom initializer hides that ABI.
@objc(TapLockSettingsController)
final class TapLockSettingsController: PSViewController, UITableViewDataSource, UITableViewDelegate {
    private let enabledSwitch = UISwitch()

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
        title = "TapLock"
        enabledSwitch.accessibilityLabel = "启用桌面双击锁屏"
        enabledSwitch.addTarget(self, action: #selector(changeEnabled(_:)), for: .valueChanged)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enabledSwitch.isOn = TapLockPreferences.readEnabled()
    }

    func numberOfSections(in tableView: UITableView) -> Int { return 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return 1 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = "启用桌面双击锁屏"
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.textLabel?.numberOfLines = 0
        cell.selectionStyle = .none
        cell.accessoryView = enabledSwitch
        return cell
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "默认关闭。开启后，仅在已解锁、竖屏的主屏幕空白处双击锁屏。" +
        "图标、文件夹、小组件、Dock 及应用内不触发；编辑桌面或启用 VoiceOver 时不触发。修改立即生效，无需注销。"
    }

    @objc private func changeEnabled(_ sender: UISwitch) {
        guard TapLockPreferences.writeEnabled(sender.isOn) else {
            sender.isOn = TapLockPreferences.readEnabled()
            let alert = UIAlertController(title: "未能保存设置",
                                          message: "设置未能持久保存，请稍后再试。",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
            return
        }
    }
}
