# TapLock — Swift + UIKit 分阶段实现

**状态：0.1.2 设置分层包已有用户实机通过反馈；当前 0.1.3 为“打开指定App”功能验证候选，编译、产物与设备结果分别记录，尚未合入 main。**

源码仓库：[Tsangbaby/Gesture-X](https://github.com/Tsangbaby/Gesture-X)。仓库名为 Gesture-X，当前首个最小功能模块仍叫 TapLock。本仓库不自动创建 Tag 或正式 Release。

暂定名称 TapLock，源码版本 0.1.3，包标识 `com.tsangbaby.taplock`。
这是一份新工程，不改动 Actra、SquidGesture 或其他既有项目；不包含其二进制、反编译输出或授权逻辑。

## 一条手势链，二选一动作

`一个默认关闭的开关 → 主屏幕空白处单指双击 → 系统锁屏 / 打开指定App（二选一）`

动作使用实际 SpringBoard 单例的 `_simulateLockButtonPress`，不再先直接锁定 UI 或自行拼灭屏/动画。支持目标为 iOS 15.0 起，不写死版本上限；按运行时对象、selector 与准确 ABI 判断能力。最低部署值不等于所有未来系统已验证。

- 只在已解锁、前台主屏幕、主显示器且界面为竖屏时允许识别。
- 只接受根桌面列表自身命中的直接手指触摸；图标、文件夹、小组件、搜索控件、Dock 不在允许范围。
- 编辑桌面、原生滚动/长按/拖动正在进行、VoiceOver 开启时不触发。
- 不注入普通 App，不接管底部/状态栏/实体按键，不增加全屏触摸罩。
- 关闭开关、桌面视图离开窗口或系统离开活跃状态时取消等待中的识别。
- 不加入通用动作引擎、多动作串联、主题、轮询、授权模块或后台日志采集。锁屏实现保持已接受版本的字节，App 动作通过固定的 LaunchServices 接口执行，不走 URL Scheme。

设置分层基线 `7f35f9e51aa9d61d8bd052f0ab6b85127313d326` 已收到用户“测试已通过”反馈，不将其外推到新 App 动作或其他系统。无法读取必需状态、对象不存在或 ABI 不匹配时，拒绝识别/调用，不猜备用接口。

## 当前设置入口

```text
设置首页
└─ 主屏幕的手势
   ├─ 启用主屏双击
   └─ 选择双击动作（显示当前选择）
      ├─ 系统锁屏（升级默认）
      └─ 打开指定App
         └─ 选择App（名称 + Bundle ID，选中后保存）
```

按 SquidGesture Pro 的对应分类及中文选项组织，当前不声称完整 UI 或功能复刻。原开关的存储域、key、默认值及已保存值保留。新增动作与 Bundle ID 存入同一个 CFPreferences 属性列表值；保存成功才发 Darwin 通知。未配置动作继续锁屏，损坏配置或已卸载/禁止启动的目标不执行其他动作。列表每次进入建立一次快照，不按行扫描全部 App；设置页只选择，不当场执行动作。

## 源码结构

```text
Sources/Bootstrap.swift              保留的 dyld 初始化指针与主队列启动
Sources/NativeHook.swift             原生 MSHookMessageEx 及原方法转发
Sources/HomeDoubleTap.swift          识别器、生命周期、触摸/场景过滤
Sources/PrivateAPI.swift             已使用的固定类型私有调用与 ABI 检查
Sources/LockAction.swift             一次系统锁屏请求
Shared/Preferences.swift             Settings/SpringBoard 共用开关与动作读写
Shared/Applications.swift            已安装 App 快照、目标校验与一次启动
Preferences/SettingsController.swift UIKit 设置首页 / 主屏幕手势 / 动作及 App 选择
Interfaces/TapLockPreferencesHost/    系统 PSViewController 声明及 module map
Preferences/Resources/Info.plist     设置 bundle 身份
layout/Library/PreferenceLoader/     设置入口
Tests/test_source.py                可在当前主机执行的源码/资源检查
Tests/PrivateAPIRuntimeTests.swift   供后续 macOS 执行的真实 Swift runtime 测试
```

所有业务实现、启动入口和 Hook 回调均为 Swift。生产 `.h` 只声明系统 `PSViewController` 及越狱环境已有的 `MSHookMessageEx` ABI；没有手写 `.m/.mm/.c/Logos` 业务实现，也不再使用 Orion。`Tests/SettingsConstructionFixture.{h,m}` 与 `Tests/NativeHookFixture.{h,m}` 仅为模拟器提供缺失的原生父类/工厂和 Hook 安装测试替身，不参与 Theos 目标、不进入安装包。Substrate 兼容 Hook 后端、Swift/Objective-C runtime 和 UIKit 仍是底层依赖。

## 已执行的本地检查

```sh
python3 -B -m unittest discover -s Tests -p 'test_*.py' -v
```

这是源码/资源合同检查，覆盖默认值、偏好通知、ABI 检查接线、单一调用、手势过滤和取消、设置加载身份、完整源文件目标归属与元数据。
**Python 通过不证明 Swift 语法/类型正确，不证明 SpringBoard 注入、Settings 加载或锁屏有效。**

最终本地检查结果及工具情况见 `docs/Validation.md`。

## 云端 Mac 构建与验证

`.github/workflows/build.yml` 在 `main` 的源码变更或手动触发时执行单个标准 `macos-15` RootHide 任务：

1. 执行 Python 源码/CI 合同检查。
2. 用 Xcode 16.4 的 Swift 编译并执行真实 `Sources/PrivateAPI.swift` runtime harness，并对旧版/当前生产 LockAction 执行同一按钮动作回归；另执行当前动作存储、App 筛选/去重/排序、准确 Bundle ID 传递、恰好一次启动及错误 ABI/不可用目标拒绝测试。系统服务是测试替身，不证明设备灭屏/动画或 App 切换；失败就停止。
3. 用真实生产设置页 Swift 与 UIKit 执行旧构造器预期失败、旧版缺少设置层级及 0.1.2 缺少 App 动作的预期失败；当前版实际进入模拟器应用列表、选择/持久保存、刷新选中与摘要并切回锁屏，保留开关和构造器回归。在同一临时模拟器实际加载优化后的完整 tweak dylib，检查 dyld 自动启动与 Hook 转发、挂载/移除和重复启动。Preferences 父类和 Hook 安装器是明确的测试替身，不冒充设备 SpringBoard/Settings。
4. 安装打包/签名工具，按固定 commit 获取 `roothide/theos`、其子模块及 SDK；不修改用户本机工具链。
5. 完整编译 tweak 和 Preferences，架构为 arm64 + arm64e、部署下限 iOS 15.0，再生成原始 RootHide `.deb`。
6. 检查包内路径、版本、设置入口、Substrate 运行库链接、Orion 依赖不存在、每个架构的启动表/最低系统版本及嵌入签名结构。
7. 上传原始 `.deb`、SHA-256、源码仓库/commit 标记、工具链记录、初始化回归记录和完整构建日志。产物名包含完整源码 SHA，保留 14 天。

实际成功/失败以 [Actions](https://github.com/Tsangbaby/Gesture-X/actions) 的对应源码 SHA 运行和下载产物核验为准；添加 workflow 不等于构建通过。默认 Makefile 仍采用 rootless scheme，当前云端仅验证 RootHide，不能由此宣称普通 Rootless 包或任何机型已通过。

`ci/verify_package.py <package.deb>` 可在有 `dpkg-deb` 的 macOS/Linux 独立复核下载包；结构签名检查不等于开发者身份验证，也不等于设备允许加载。

最后按 `docs/Acceptance.md` 做当前变更的设备验收。已通过的系统按钮锁屏实现保持源码字节不变；“打开指定App”、选择持久化/即时生效与锁屏切回回归仍需用户真机确认。云端执行不等于设备验收。
