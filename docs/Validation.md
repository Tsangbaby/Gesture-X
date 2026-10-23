# 验证分层记录

## 当前验证层级

本地源码/资源、CI 合同及 Mach-O 解析器夹具检查 **28 项通过**；执行结果与云端 Swift/UIKit 结果分开记录。

本轮修复 SpringBoard 启动入口：移除 Orion 入口/链接/包依赖，以保留的 Swift dyld 初始化指针在主队列启动，并通过原生 `MSHookMessageEx` Hook 桌面列表。多任务状态改由 `SBMainSwitcherViewController.sharedInstanceIfExists` 获取，根位置精确接受 `SBIconLocationRoot` 与 `SBIconLocationRootWithWidgets`。未知状态仍拒绝，不放宽空白区或手势安全门，不增加生产诊断。

用户已报告 0.1.1 设置页在 iOS 15.4.1 修复，但开启后双击桌面无效。该已接受的设置页、其基类声明、共享偏好和锁屏请求源码在本轮保持字节不变。重新解析原交付包确认两个架构都没有 dyld 初始化表；这是静态启动缺口证据，不是手机上注入状态的观察。

云端在原有临时 UIKit 模拟器中继续执行设置页旧 SHA 预期失败/当前 SHA 通过回归，并加载优化、dead-strip 后的完整生产 tweak 源码 dylib，验证自动启动、主队列投递、原方法恰好一次、挂载/移除和重复启动。系统列表类与 Hook 安装器为明确的测试替身；它们不进入 Theos 目标或包，不证明真实 SpringBoard 注入、Substrate 后端或设备锁屏。

云端执行状态须查看对应 SHA 的 Actions、`NATIVE_STARTUP_TESTS.txt` 和 `SETTINGS_CONSTRUCTION_TESTS.txt`；脚本存在不等于运行通过。新的功能验证包仍须设备复测，不能继承设置页通过为整条功能链通过。

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
