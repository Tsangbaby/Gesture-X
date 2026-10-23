# 验证分层记录

## 当前验证层级

本地源码/资源与 CI 合同检查 **21 项通过**，Shell 语法及 `git diff --check` 通过。新增的初始化合同在旧代码上先失败，修正导入声明/显式 convenience initializer 后通过；这仍是本地源码合同，不是 Swift 执行结果。

本轮 0.1.1 只修设置页初始化：去掉基类的过时 initializer 声明，在 Swift 子类实现旧工厂 selector 并转入 UIKit 的 `init(nibName:bundle:)`。固定 SHA-256 回归确认 4 个 `Sources` 文件、共享偏好源码、两个 Makefile、module map 及设置页从 `loadView` 起的业务代码字节未变。版本元数据同步更新，不增加生产日志或手势功能。

云端新增独立 iOS Simulator 构造回归：从固定旧 SHA `72826b2a558b03e20a7dd5e98047dfdecc489202` 提取真实旧源码，要求复现 `NSInvalidArgumentException` / `initForContentSize:`；当前源码在相同的原生 UIKit 父类测试替身上分别创建 legacy/default 路径各 5 次，并检查真实表格/开关。测试替身明确缺少旧接口，只用于测试、不进入 Theos 目标/安装包，不能替代设备 Preferences 的完整链路。

云端执行状态须查看 Actions 的对应 SHA 及 `SETTINGS_CONSTRUCTION_TESTS.txt`，不因脚本存在而认定通过。目标设备对 0.1.0 已报告 Settings 崩溃；0.1.1 的设备复测尚未执行。

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
