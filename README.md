# TapLock — Swift + UIKit 分阶段实现

**状态：0.1.5“打开控制中心”已获用户反馈通过并固化到 main。当前独立候选 0.1.6 只增加“打开通知中心”，待 exact-SHA 云端构建与实机验收，未合入 main。验收基线环境为 iOS 15.4.1 / RootHide，不外推其他系统；0.1.3 的整机卡死仍为失败历史。**

源码仓库：[Tsangbaby/Gesture-X](https://github.com/Tsangbaby/Gesture-X)。仓库名为 Gesture-X，当前首个最小功能模块仍叫 TapLock。本仓库不自动创建 Tag 或正式 Release。

暂定名称 TapLock，源码版本 0.1.6，包标识 `com.tsangbaby.taplock`。
这是一份新工程，不改动 Actra、SquidGesture 或其他既有项目；不包含其二进制、反编译输出或授权逻辑。

## 一条手势链，四选一动作

`一个默认关闭的开关 → 主屏幕空白处单指双击 → 系统锁屏 / 打开指定App / 打开控制中心 / 打开通知中心（四选一）`

锁屏动作使用实际 SpringBoard 单例的 `_simulateLockButtonPress`，不再先直接锁定 UI 或自行拼灭屏/动画。支持目标为 iOS 15.0 起，不写死版本上限；按运行时对象、selector 与准确 ABI 判断能力。最低部署值不等于所有未来系统已验证。

- 只在已解锁、前台主屏幕、主显示器且界面为竖屏时允许识别。
- 只接受根桌面列表自身命中的直接手指触摸；图标、文件夹、小组件、搜索控件、Dock 不在允许范围。
- 编辑桌面、原生滚动/长按/拖动正在进行、VoiceOver 开启时不触发。
- 不注入普通 App，不接管底部/状态栏/实体按键，不增加全屏触摸罩。
- 关闭开关、桌面视图离开窗口或系统离开活跃状态时取消等待中的识别。
- 不加入通用动作引擎、多动作串联、主题、轮询、授权模块或后台日志采集。锁屏实现保持已接受版本的字节，App 动作通过实际 SpringBoard 对象上归属于该类链、精确 ABI 检查后的原生单次入口执行；SpringBoard 目标不再包含 LaunchServices 目录或客户端启动代码。不走 URL Scheme，不重试或换入口。

当前已验收原包绑定源码 `1b6615b46242abeb5b8ef0f0bf4afba14db18e2a`、成功 Actions `39958293096`、SHA-256 `88e113be9368c491b5ad4df11bfb6c9c09c105e06a36b3fdfe2218c324798d90`。`feat/open-control-center` 与原包保留；main 纳入该源码并仅追加验收文档，不重编相同功能或自动发布 Release。0.1.4 回退分支及原包也保持不变。无法读取必需状态、对象不存在或 ABI 不匹配时，拒绝识别/调用，不猜备用接口。

## 当前设置入口

```text
设置首页
└─ 主屏幕的手势
   ├─ 启用主屏双击
   └─ 选择双击动作（显示当前选择）
      ├─ 系统锁屏（未配置时默认）
      ├─ 打开指定App
      │  └─ 选择App（真实图标 + 名称 + Bundle ID，选中后保存）
      ├─ 打开控制中心
      └─ 打开通知中心
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
Sources/AppAction.swift              SpringBoard 原生单次启动；拒绝继承的 UIKit 客户端入口
Sources/ControlCenterAction.swift    SpringBoard 原生单次打开控制中心；不切换、重试或回退
Sources/NotificationCenterAction.swift 解锁态 Cover Sheet 单次打开；BOOL/Block ABI 与转场门
Shared/Applications.swift            仅设置目标：已安装 App 快照与选择时校验，无启动方法
Preferences/ApplicationIcons.swift   仅设置目标：按需真实图标、32pt 等比画布和缓存
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
2. 用 Xcode 16.4 的 Swift 编译并执行真实 `Sources/PrivateAPI.swift` runtime harness，并对旧版/当前生产 LockAction 执行同一按钮动作回归；另执行动作存储和设置 App 筛选，以及旧 LS 启动触及禁用服务边界的预期失败 / 当前原生单次启动的 receiver、ABI、继承客户端方法与非主线程拒绝测试。系统服务是测试替身，不证明设备灭屏/动画、App 切换或卡死已修复；失败就停止。
3. 用真实生产设置页 Swift 与 UIKit 执行旧构造器、旧版缺少层级 / App 动作及真实 0.1.3 缺图标的预期失败；当前版实际进入模拟器应用列表，检查真实图标、32pt 画布、缓存和占位，并验证选择/持久保存、选中与摘要刷新、切回锁屏和原有开关回归。在同一临时模拟器实际加载优化后的完整 tweak dylib，检查 dyld 自动启动与 Hook 转发、挂载/移除和重复启动。Preferences 父类和 Hook 安装器是明确的测试替身，不冒充设备 SpringBoard/Settings。
4. 安装打包/签名工具，按固定 commit 获取 `roothide/theos`、其子模块及 SDK；不修改用户本机工具链。
5. 完整编译 tweak 和 Preferences，架构为 arm64 + arm64e、部署下限 iOS 15.0，再生成原始 RootHide `.deb`。
6. 检查包内路径、版本、设置入口、Substrate 运行库链接、Orion 依赖不存在、每个架构的启动表/最低系统版本及嵌入签名结构。
7. 上传原始 `.deb`、SHA-256、源码仓库/commit 标记、工具链记录、初始化回归记录和完整构建日志。产物名包含完整源码 SHA，保留 14 天。

实际成功/失败以 [Actions](https://github.com/Tsangbaby/Gesture-X/actions) 的对应源码 SHA 运行和下载产物核验为准；添加 workflow 不等于构建通过。默认 Makefile 仍采用 rootless scheme，当前云端仅验证 RootHide，不能由此宣称普通 Rootless 包或任何机型已通过。

`ci/verify_package.py <package.deb>` 可在有 `dpkg-deb` 的 macOS/Linux 独立复核下载包；结构签名检查不等于开发者身份验证，也不等于设备允许加载。

最后按 `docs/Acceptance.md` 做本次通知中心动作和旧动作保护项的集中设备验收。锁屏、原生 App 启动、控制中心、图标、Hook 与过滤保持 0.1.5 的已接受实现；0.1.5 的用户反馈不覆盖新通知中心功能，云端执行也不等于设备验收。
