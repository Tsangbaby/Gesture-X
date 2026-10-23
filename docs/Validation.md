# 验证分层记录

## 当前阶段：设置分层候选 0.1.2

- 用户已对 `94b384d64ce44705e754f4695c98661110db76ff` 对应 RootHide 系统按钮锁屏包反馈“测试已通过”。这是用户报告的本次验收，不外推到未测试系统或新设置页。
- 经用户授权，main 已快进到该 exact SHA；两个旧修复分支的提交均保留在 main 中，确认无 PR/Tag/Release 依赖后只删除分支指针。新 UI 在独立候选分支开发，未获设备验收前不合入 main。
- 唯一运行时代码变更范围为 Preferences/SettingsController.swift：设置首页 → 主屏幕的手势 → 启用主屏双击 / 选择双击动作 → 系统锁屏。包和 bundle 版本更新为 0.1.2，包标识与偏好域保持不变。
- 已接受的 Sources、Shared、Interfaces、Makefile 及 loader/filter 共 14 个文件保持字节一致，手势、按钮调用、启动和 CFPreferences 存储/通知链不变。设置写入失败提示及旧构造器修复保留。
- 新布局的源码接线合同已观察缺失层级时失败，再实现为通过；既有历史 UI 哈希通过精确、计数的候选逆变换保留，并有缺失/重复 hunk 和无关漂移的反例检查。
- 云端同一 UIKit harness 必须分别复现旧版构造器异常、已接受版本缺少新层级的失败，并在当前生产 Swift 上执行两条工厂路径、逐级导航、真实开关写入、动作返回及重新进入保留值。该测试使用明确的 Preferences 父类替身，不证明完整设备 factory/setter 链或视觉一致性；实际结果以当前 exact-SHA 运行与原始报告为准。
- 新设置 UI、升级保留值、开关即时生效和原生锁屏回归仍待用户实机确认；无新增生产日志采集。
- 首次设置候选运行 `39917439743` 在编译共用 harness 对照旧控制器时失败：测试静态调用了旧版没有实现的 didSelectRowAt 方法。尚未进入当前版 UIKit 执行或打包。改为通过真实 UITableView.delegate 的可选协议方法派发导航，保留旧版 RED 和当前版 GREEN 断言，生产源码未因此修改；增加对应源码回归防止再依赖新类方法编译旧基线。

## 历史：系统按钮修复阶段（以下为当时记录）

本地源码/资源、CI 合同及 Mach-O 解析器夹具检查 **31 项通过**；执行结果与云端 Swift/UIKit 结果分开记录。

本轮基线为已交付 RootHide 包对应源码 `fa26d99a0642aad0ed0e9abf7c73d7883bf5ee65`。用户报告双击已可锁定，但屏幕仍亮且过渡生硬；这只接受了手势到 UI 锁定的路径，不接受灭屏和锁屏键效果，也不外推到其他系统。

唯一生产修改为 `Sources/LockAction.swift`：从直接 UI 锁定改为实际 SpringBoard 单例上的一次 `_simulateLockButtonPress`，检查 `v@:` 精确 ABI，并保留未锁/锁屏不可见/未在解锁及主线程门。手势、启动、Hook、设置页、共享偏好、包标识/版本/部署下限和生产编译图保持基线字节不变；无自制动画、亮度改写、重试或生产日志采集。

新增云端 macOS harness 对真实旧版/当前版 LockAction 和 PrivateAPI 执行相同用例：旧版必须在“调用一次系统按钮入口而非直接 UI 锁定”断言失败，当前版须通过正常调用、恰好一次、已锁/锁屏可见/解锁中拒绝、对象缺失/错误类型、入口缺失/错误返回 ABI、非主线程拒绝及恢复。类是明确的测试替身，不进入安装包，不证明真实灭屏/动画。对应运行状态以 exact-SHA Actions 日志和 `LOCK_BUTTON_TESTS.txt` 为准。

既有 11 项 PrivateAPI runtime、设置页初始化及优化生产 dyld 启动/Hook/挂载回归继续执行。源码检查先观察旧动作合同失败，再修改为通过；Linux 本地不具备 Apple Objective-C runtime，不能把 Python GREEN 写作 Swift 行为通过。

首次云端运行 `39911383704`（源码 `bacef65d57806cccf3f34eb3b3b90b9cd4e9ead1`）实际通过 11 项 PrivateAPI、旧动作预期失败/新动作 13 项执行检查及 10 次 UIKit 设置页构造，但 NativeStartup 测试未返回完成标记，未进入打包。后续仅为 CI 测试 App 增加已刷新输出的启动/dlopen 检查点，并在失败时输出退出码及该模拟器测试进程的崩溃/日志线索；不降低通过门、不修改生产源码，不把首次失败臆断为设备启动问题或模拟器偶发问题。

兼容目标为 iOS 15.0 起，无写死的版本上限；每个包内 Mach-O 的实际最低版本必须独立验证为 15.0。版本化头文件中的 selector 存在、CI 编译成功与一台设备结果，都不能证明所有 iOS 15+ 的兼容性。新功能验证包仍待真实锁屏键效果、灭屏及正常唤醒/解锁验收。

以下是首次源码阶段保留的历史记录，描述的是增加 Git 与 CI 之前的状态：

## 实际执行

命令：`python3 -B -m unittest discover -s Tests -p 'test_*.py' -v`

- 14 项运行，14 项通过，0 失败。
- 检查包括偏好默认值/存储域/通知顺序、固定 ABI 检查接线、一次锁屏请求、根桌面/空白命中/方向/编辑/交互状态门、弱引用与取消、Settings 创建身份、完整 Swift 目标归属、版本/最低部署值与注入过滤。
- 各源码接线切片先运行缺失实现的失败，再补实现并运行通过；这是源码合同 RED/GREEN，不是实际 Swift 行为 TDD。
- 对全部现有文件执行 `git diff --no-index --check /dev/null <file>`，未发现空白错误。未初始化 Git 仓库，也未进行提交。
- 未发现手写 OC/C/Logos 实现、安装包、编译输出或源码网络访问代码。

当前生产 Swift 文件：6 个，440 行（含空行/注释，不含测试及声明头）。

生产源码摘要（依相对路径排序，逐项拼接 `path UTF-8 + NUL + file bytes + NUL`，然后 SHA-256）：

`6638331dccdc25ff004b7a15b2b773c7d65f7a524b487009d7df3a5953e6cc1f`

此摘要只标识生产 Swift 文件，不是安装包或全工程摘要。

## 未执行与原因

- 当前主机未找到 `swift`、`swiftc`、`xcodebuild` 或 Theos，未安装任何工具。
- `Tests/PrivateAPIRuntimeTests.swift` 已编写，使用真实生产 PrivateAPI；尚未编译/执行，不能计入以上通过数。
- 未对 Swift/Orion 做实际语法/类型检查；Python 检查不能替代编译器。
- 未运行 Theos/Xcode、签名、打包、安装、注销或任何云端构建。
- 未推送远程仓库，未创建 Git 提交/分支，未修改配置、原始参考包或既有项目。
- 设置页实际加载、SpringBoard 注入、私有能力门、真正锁定及原生交互兼容性，全部等待下一阶段验证。
- 独立只读源码核对已结束，指出手势集合泛型比原生 peer/delegate 参数窄。主会话回查源码及 Apple 官方 `contains(_ anObject: ObjectType?)` 声明确认后，只将集合改为 `NSHashTable<UIGestureRecognizer>`，保留弱引用、安装和回调行为；新增参数类型回归合同，观察失败后修正并全套通过。该核对及修正不等于实际 Swift 编译通过。

完成本轮源码交付后即停在此阶段，下一步由用户决定。
