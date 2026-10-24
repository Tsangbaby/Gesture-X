# 验证分层记录

## 当前基线：打开控制中心 0.1.5（用户反馈通过）

- 用户对已交付的 0.1.5 RootHide 功能包反馈“测试已通过”。绑定源码 `1b6615b46242abeb5b8ef0f0bf4afba14db18e2a`、成功 Actions `39958293096`、原包 SHA-256 `88e113be9368c491b5ad4df11bfb6c9c09c105e06a36b3fdfe2218c324798d90`；环境沿用此前报告的 iOS 15.4.1 / RootHide。这是用户实机反馈，不是助手独立设备复测，不自动把未逐项反馈的检查标为执行，也不外推到其他系统。
- 经用户授权，main 纳入本次通过源码并追加验收文档；原候选分支与 `/home/ubuntu/Gesture-X-artifacts/0.1.5-1b6615b/` 的原始包、源码标记、CI / 独立核验报告均保留。文档提交跳过重复 CI，不重编 0.1.5，不创建 Tag / Release；旧 0.1.4 回退点不变。以下是本次交付前记录。

- 用户授权先固化 0.1.4，再只增加“打开控制中心”。main 已纳入已验收源码，追加纯验收文档提交 `b8ea00fb82ca82302447ddd4bd501258f6a1e58d`；main 与 `fix/native-app-launch-icons` 的运行时代码相同，文档提交未触发重复 CI。原始 0.1.4 `.deb` 已按 artifact ZIP、SOURCE_COMMIT、内层校验和及包结构独立核验并留存于 `/home/ubuntu/Gesture-X-artifacts/0.1.4-b8d6994/`，不是重新构建。
- 新功能仅在 `feat/open-control-center`：原单指双击、默认关闭开关与所有原有触摸/场景/横屏/VoiceOver 过滤不变；只新增一个互斥动作、严格单值偏好记录和第三个设置行。设置选择只保存，不调用系统动作；升级保留已有动作，缺失配置仍默认锁屏，损坏记录不执行其他动作。
- 原生入口依据 immutable `kissalexandra/Runtime-Headers@f15f8ebf05b6da366045a4eec985c9dda7c5f456` 的 `iOS/15/15.2.tar.gz`，Git blob `a7302432fdcb66c93aa448fec72359ce510d0016`；已下载到内存并校验原始 blob。`15.2/System/Library/PrivateFrameworks/SpringBoard.framework/SpringBoard/SBControlCenterController.h` 的 SHA-256 为 `d6449dde8cc3e5e7a2fcef08e3b3b2781b6800940ff7105465ccb21bea1f8ddb`，声明 `+sharedInstance` 返回对象，`-isPresentedOrDismissing` / `-canBePresented` 返回 BOOL，`-presentAnimated:` 返回 void、参数 BOOL。头文件只是版本化接口依据，不是本机接收者或设备成功证据。
- `ControlCenterAction.open` 只在主线程且现有锁屏状态读取器确认已解锁时取得原生控制器；校验单例实际类型、两个 BOOL 状态与 `void(BOOL)` 精确 ABI，再仅调用一次 `presentAnimated:true`。已展示/正在关闭、系统不允许、对象/selector/ABI 不支持均拒绝；不切换关闭，不重试、换入口、调用其他动作或添加生产诊断。
- 20 个 0.1.4 生产/资源/构建输入受冻结 SHA-256 保护；仅 6 个授权旧路径的 14 个精确计数/顺序 hunk 可逆变换。旧历史摘要及 before/after fixture 不变，新候选逆变换须显式开启；两阶段各自执行缺失/重复/错序/无关漂移反例，CI 不依赖本地完整历史。
- 本地新切片在实现前观察到 6 项源码合同 RED；当前完整 Python 源码/资源/历史保护检查已通过，另完成 shell 语法、plist/版本一致性与真实 Debian 升级顺序检查。本机未安装 Swift，未在本地执行 Swift parse / 编译；真实 Swift 证据必须由已授权云端产生。这些本地检查不是原生动作执行或设备展示证明。
- 云端必须执行同一实际 Swift harness：冻结的 0.1.4 在不支持新动作的偏好解析行为断言失败，当前源通过原生 receiver、BOOL/void ABI、系统拒绝、锁定/解锁中、单次调用及错误线程测试。测试只重绑定唯一类名查找常量，逆替换后生产源须逐字节相等。另用同一 UIKit harness 证明实际 0.1.4 缺少第三行，再验证当前真实设置页选中、保存、重进、摘要、互斥和旧动作/图标回归。
- 优化后的 Swift 短字符串可能不作为连续字节出现，已在 0.1.4 原包观察到 `isUILocked` / `isUIUnlocking` 缺少连续文字而长 selector 存在。包级足迹门仅对确定的长查找名称逐架构核验；短 getter 的 ABI / 逻辑由实际 Swift harness 独立验证，不为保留字符串改生产代码。
- 交付时 exact-SHA Actions `39958293096` 已成功，执行 65 项源码合同、控制中心 44 项真实 Swift 断言及 10 轮 UIKit 控制中心设置往返，保留旧动作与图标回归。tweak / Preferences 的 arm64、arm64e 编译和独立内层原包、逐切片签名结构、代码页哈希核验均通过；这些属于云端/产物证据，设备通过只依据本节开头的用户反馈。

## 历史基线：原生 App 启动与图标修正 0.1.4（用户反馈通过）

- 用户对已交付的 0.1.4 反馈“测试已通过”。绑定源码 `b8d6994be7defcc37ceac3bb158c5526c952ac3a`、成功 Actions `39949290095` 和该运行的原始 RootHide 安装包；环境为用户此前报告的 iOS 15.4.1 / RootHide。这是用户设备反馈，不是助手独立设备复测，不外推到其他系统或未逐项说明的测试。
- 经用户授权，main 纳入该源码并以独立文档提交记录验收。`fix/native-app-launch-icons` 和已验收原包保持不变；文档提交跳过重复 CI，不重编相同功能，不新增 Tag / Release。下一项功能必须在新候选分支完成，未获设备验收不合入 main。下列实现范围和交付前检查保留为历史记录。

- 用户报告 `cb3f53b27e102b74cea93bf9a44d476cb873477a` 对应 0.1.3 在 iOS 15.4.1 / RootHide 选择 115 网盘后，双击导致整机按键无响应，只能强制重启；同时 App 列表缺图标。该版为严重实机失败，不再要求重复触发。没有现场线程栈，不能把同步调用嫌疑写成已确诊的死锁或内核故障，也不归咎于目标 App / 越狱。
- 授权范围仅为原生单次启动与设置真实图标，不新增诊断采集、延时、重试、备用启动入口或通用动作引擎。新分支 `fix/native-app-launch-icons` 基于该失败源码；main 和旧分支保留，不自动合并或发布正式 Release。
- SpringBoard 编译图完全移除 `Shared/Applications.swift`。手势既有通过门之后只调用 `AppAction.open`：校验主线程和 Bundle ID 语法，取得实际 SpringBoard 单例，要求启动方法归属于 SpringBoard / 其实际子类而非继承 UIKit 客户端方法，并检查返回 BOOL / 对象 + BOOL 参数的精确 ABI 后仅调用一次 `launchApplicationWithIdentifier:suspended:`，固定 suspended=false。此路径不再做任何 LaunchServices 目标查询或启动；目标可用性由原生系统接收者处理，不声称能在触发前保证 App 仍可启动。
- LaunchServices 列表/状态校验只留在设置目标，并移除旧 `openApplicationWithBundleID:` 实现。设置 App 行按需加载真实 UIKit 图标，严格检查 int32 format / CGFloat scale ABI，等比画入 32pt 透明画布，按控制器缓存；拿不到图标才用同尺寸占位图，不逐行扫描 App 列表。
- `PrivateAPI`、`LockAction`、`NativeHook`、`Bootstrap`、共享偏好存储保持失败版/已接受链的字节；手势 owner 只有一处 App 派发调用替换。历史基线哈希及全部 before-hunk 保持不变，仅更新授权 after-hunk 的精确逆变换，缺失/重复/错序/无关漂移仍必须被拒绝。
- 本地已观察新原生入口/编译图和图标接线在实现前失败；这只是源码合同 RED，不是复现设备卡死。云端必须另对冻结的 0.1.3 启动代码执行同一 Swift harness，使其在“触及 LaunchServices”断言失败，当前入口须通过实际 receiver/ABI/父类入口拒绝/单次调用/错误线程测试；类名重绑定必须可逐字节还原。
- 同一 UIKit harness 另对真实 0.1.3 设置源复现缺图标断言失败，再以当前设置源验证实际模拟器 App 图标加载、32pt 画布、缓存复用、占位及原有全部导航/持久化回归。仍使用明确的 Preferences 父类替身；模拟器不是用户 iOS 15.4.1 / RootHide。
- 原始 RootHide 双架构包增加二进制边界门：tweak 必须包含原生启动 selector，且不含 LS catalog/client selector 或图标 loader；图标 loader 仅存在于 Preferences。实际构建结果由 exact-SHA Actions、`NATIVE_APP_TESTS.txt`、UIKit / 启动记录和原包核验报告决定，不能预先宣告成功。
- 以上实现与门禁是交付时记录；后续设备通过以本节开头的用户反馈为准。仍没有旧版冻结线程证据，不能追溯确诊 0.1.3 的具体卡点，也不把 CI / 二进制门本身等同真机修复。

## 历史：打开指定App 功能候选 0.1.3（实机失败）

- 用户报告 0.1.2 设置分层包测试通过，绑定已交付源码 `7f35f9e51aa9d61d8bd052f0ab6b85127313d326` 和成功运行 `39919548688`。这是用户报告的该阶段验收，不外推到新 App 功能。
- 新候选在 `feat/open-selected-app` 开发，保留已接受分支和 main；仅增加“系统锁屏 / 打开指定App”二选一、已安装 App 选择、单值原子动作配置与一次 LaunchServices 启动。无通用动作引擎、URL Scheme 回退或生产日志。
- 锁屏、PrivateAPI、启动、Hook、触摸/场景/编辑/VoiceOver 过滤保持已接受 owner。手势 owner 只增加偏好重载时缓存动作，以及既有通过门之后的二选一派发。
- 缺失动作配置保持锁屏；损坏配置、错误 Bundle ID、未安装/隐藏/禁止启动目标、接口或 ABI 不支持都拒绝执行，不回退为另一个动作。App 列表一页只创建一次快照，名称单条查询不重扫全部 App。
- 本地新切片已观察缺失实现时的源码合同 RED，再实现 GREEN；完整 Python 源码/资源/历史逆变换及解析器检查为 50 项通过。历史哈希未替换；只允许精确计数、顺序的候选逆变换，并执行缺失/重复/错序及无关漂移反例。
- 云端门：执行真实 Shared/Preferences、PrivateAPI、Shared/Applications 的 Swift 测试（OS 服务替身）；同一个 UIKit harness 先使原始 0.1.2 在“缺少 App 动作行”行为断言失败，再执行当前版真实模拟器 App 选择/持久化/摘要/选中和锁屏切回。随后编译优化后的完整启动图及 Theos 双架构目标，核验最终原始 RootHide 包。实际结果由 exact-SHA Actions、OPEN_APP_TESTS.txt、SETTINGS_CONSTRUCTION_TESTS.txt 和包核验报告记录，不由本文件预先宣告。
- 新 App 动作及升级/切回回归仍待本轮原始安装包的真机验收；CI 与结构签名不能替代。没有新增诊断采集或设备操作。
- 首次运行 `39927657753` 的 macOS 测试替身与系统已有 LSApplicationProxy/LSApplicationWorkspace 重名，真实 Swift 编译成功但目录行为测试失败，未进入 UIKit 或打包。测试替身改用独立名称；CI 临时源副本只按精确计数重绑定这两个类名，逆替换后必须与生产源字节一致，方法体/ABI 检查不变。生产文件无修改，断言不降低。
- 运行 `39928295728` 已通过 App 生产 Swift 的 69 项断言、PrivateAPI 11 项与按钮 13 项；随后旧构造器基线 App 未输出终止标记，不能判定为预期失败，更未进入新 UI 或打包。为 CI 测试 App 加入刷新后的回调检查点、失败时的临时模拟器进程报告/日志读取；保持非零传输或缺失精确标记必失败，不把不明启动失败归咎于生产逻辑，不增加生产诊断。
- 后续运行 `39929234497` 与 `39930309699` 均完成三个旧版预期失败断言，当前版真实 UIKit 列表暴露为空；后者实际读取到 142 个 OS proxy，但 proxy 没有 isLaunchProhibited/appTags 的实现，严格门全部拒绝。按 iOS 15.3.1 头文件快照 `yuzhouheike/iOS15.3.1-Runtime-Headers@44a5b62df41f5f20d8af6dead3b426a7b401e118` 的 LSApplicationProxy.correspondingApplicationRecord → LSApplicationRecord.isLaunchProhibited/appTags 实现修正状态读取，另核对 record/proxy Bundle ID。隐藏 tag 包含 hidden 亦拒绝。并以同一真实 Swift harness 执行旧 proxy-only 实现的行为 RED 和当前 record-backed 实现的 GREEN，拒绝缺失/错误类型/不匹配 record。旧锁屏实现不变，当前真机行为仍未验证。

## 历史：设置分层候选 0.1.2（以下为当时记录）

- 用户已对 `94b384d64ce44705e754f4695c98661110db76ff` 对应 RootHide 系统按钮锁屏包反馈“测试已通过”。这是用户报告的本次验收，不外推到未测试系统或新设置页。
- 经用户授权，main 已快进到该 exact SHA；两个旧修复分支的提交均保留在 main 中，确认无 PR/Tag/Release 依赖后只删除分支指针。新 UI 在独立候选分支开发，未获设备验收前不合入 main。
- 唯一运行时代码变更范围为 Preferences/SettingsController.swift：设置首页 → 主屏幕的手势 → 启用主屏双击 / 选择双击动作 → 系统锁屏。包和 bundle 版本更新为 0.1.2，包标识与偏好域保持不变。
- 已接受的 Sources、Shared、Interfaces、Makefile 及 loader/filter 共 14 个文件保持字节一致，手势、按钮调用、启动和 CFPreferences 存储/通知链不变。设置写入失败提示及旧构造器修复保留。
- 新布局的源码接线合同已观察缺失层级时失败，再实现为通过；既有历史 UI 哈希通过精确、计数的候选逆变换保留，并有缺失/重复 hunk 和无关漂移的反例检查。
- 云端同一 UIKit harness 必须分别复现旧版构造器异常、已接受版本缺少新层级的失败，并在当前生产 Swift 上执行两条工厂路径、逐级导航、真实开关写入、动作返回及重新进入保留值。该测试使用明确的 Preferences 父类替身，不证明完整设备 factory/setter 链或视觉一致性；实际结果以当前 exact-SHA 运行与原始报告为准。
- 新设置 UI、升级保留值、开关即时生效和原生锁屏回归仍待用户实机确认；无新增生产日志采集。
- 首次设置候选运行 `39917439743` 在编译共用 harness 对照旧控制器时失败：测试静态调用了旧版没有实现的 didSelectRowAt 方法。尚未进入当前版 UIKit 执行或打包。改为通过真实 UITableView.delegate 的可选协议方法派发导航，保留旧版 RED 和当前版 GREEN 断言，生产源码未因此修改；增加对应源码回归防止再依赖新类方法编译旧基线。
- 后续运行 `39918476122` 已实际复现旧构造器异常和已接受版本缺少新层级的目标断言；simctl launch 在 App 主动 exit(1) 后仍返回 0，错误在测试驱动把传输退出码当作 App 退出码。恢复“simctl 成功且必须出现各自精确终止标记”的判定；当前版仍必须输出完整正向通过标记，缺失标记或传输失败均拒绝，并用实际驱动代码执行正反例回归。生产源码继续保持不变。

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
