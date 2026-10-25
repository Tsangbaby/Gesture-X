# TapLock — Swift + UIKit 分阶段实现

**当前已验收功能基线：0.1.12 / `feat/toggle-flashlight`，用户对「开关手电」原始 RootHide 包反馈「测试已通过」，仍一次只选择一个动作。按随后授权仅补齐验收文档纳入 main；该分支保持已构建 SHA，0.1.11／0.1.10 分支及全部原包保留，不改功能、不重编、不创建 Tag／Release。用户反馈不外推未单独报告的子项、系统或越狱环境。**

**历史基线：0.1.9 原版设置展示层、0.1.10 播放/暂停及 0.1.11 两项切歌分别记录用户通过反馈，旧设置分支、原包与更早回退点保留。文档晋级不生成另一个实机测试包；多动作和 Siri 不在范围，不宣称完整产品或像素复刻。最新反馈未新增系统／越狱版本细节，不扩展此前报告的环境范围；0.1.3 整机卡死仍为失败历史。**

源码仓库：[Tsangbaby/Gesture-X](https://github.com/Tsangbaby/Gesture-X)。仓库名为 Gesture-X，当前首个最小功能模块仍叫 TapLock。本仓库不自动创建 Tag 或正式 Release。

暂定名称 TapLock，最新获用户通过反馈功能版本 0.1.12，包标识 `com.tsangbaby.taplock`。
这是一份新工程，不改动 Actra、SquidGesture 或其他既有项目；不包含其二进制、反编译输出或授权逻辑。

**当前开发候选：0.1.13 / `feat/system-mute`，仅新增「系统静音」；未获本轮设备反馈，不晋级 main。原包调用依据、BOOL/Int32 ABI 与 owner getter 移植边界见 `docs/SystemMute.md`。**

## 一条手势链，单个动作（手电已通过，系统静音待验）

`一个默认关闭的开关 → 主屏幕空白处单指双击 → 系统锁屏 / 打开应用 / 控制中心 / 通知中心 / 系统截屏 / 应用切换界面 / 播放/暂停 / 上一首 / 下一首 / 开关手电 / 系统静音（一次只选一个）`

锁屏动作使用实际 SpringBoard 单例的 `_simulateLockButtonPress`，不再先直接锁定 UI 或自行拼灭屏/动画。支持目标为 iOS 15.0 起，不写死版本上限；按运行时对象、selector 与准确 ABI 判断能力。最低部署值不等于所有未来系统已验证。

- 只在已解锁、前台主屏幕、主显示器且界面为竖屏时允许识别。
- 只接受根桌面列表自身命中的直接手指触摸；图标、文件夹、小组件、搜索控件、Dock 不在允许范围。
- 编辑桌面、原生滚动/长按/拖动正在进行、VoiceOver 开启时不触发。
- 不注入普通 App，不接管底部/状态栏/实体按键，不增加全屏触摸罩。
- 关闭开关、桌面视图离开窗口或系统离开活跃状态时取消等待中的识别。
- 0.1.7 只新增“系统截图”：设置选择只保存，桌面双击向实际 SpringBoard 对象提交一次 `takeScreenshot` 请求。不自行绘制、保存或上传截图，不加延时重试、HID 或自定义动画；本轮已获用户实机通过反馈。
- 0.1.8 只新增“打开多任务”：设置选择只保存，桌面双击向真实 `SBMainSwitcherViewController.sharedInstanceIfExists` 对象提交一次 `activateMainSwitcherNoninteractivelyWithSource:animated:`。不 toggle、不关闭、不模拟 Home 双击、滑动或 HID，不延时重试或切换入口。原生返回值只表示请求是否受理，不证明多任务界面已经展示；本轮原始包已获用户实机通过反馈，覆盖范围以该反馈为限。
- 0.1.10 仅解禁原目录的“播放/暂停”，该原包已获用户实测通过反馈：设置只保存，双击通过原门后动态解析系统 MediaRemote，单次发送 command=2、options=nil。该阶段不切歌、不判断播放状态、不模拟按键或重试，见 `docs/MediaPlayback.md`；本轮反馈独立记录于 `docs/Acceptance.md`。
- 0.1.11 同轮解禁原目录“上一首 / 下一首”，原包已获用户实测通过反馈；分别严格发送一次 command=5 / 4、options=nil；保留原 loader、失败缓存、ABI 和 toggle 方法体字节。沿用原线程/解锁/双击门，设置只保存一个；不读曲目/播放状态、不强制播放、跳进度或补发，原生非零只表示提交结果，不证明切歌完成。见 `docs/MediaTracks.md`。
- 0.1.12 只解禁原目录「开关手电」，该原始 RootHide 包已获用户「测试已通过」反馈：读取系统 level，非零则关闭，零则原样恢复系统保存亮度；全部方法精确 UInt64/void ABI 门先于状态读取。设置只保存，旧链保留；本地 true 仍只代表 void 效果调用尝试。用户反馈不等于运行时 ABI dump，也不外推其他系统；缺失/不匹配则拒绝。见 `docs/Flashlight.md`。
- 0.1.13 候选仅解禁原目录「系统静音」：通过有声明的系统 owner getter 取得 `SBRingerControl`，完整核对 BOOL 状态/void(BOOL) setter/void(Int32) HUD 后，读旧状态、写反值、HUD 传旧状态；只代表调用尝试。与媒体静音/勿扰严格分开，不增加初始化 Hook、重试或日志；本轮 Apple/产物/设备结果分开记录。
- 不加入通用动作引擎、多动作串联、主题、轮询、授权模块或后台日志采集。锁屏实现保持已接受版本的字节，App 动作通过实际 SpringBoard 对象上归属于该类链、精确 ABI 检查后的原生单次入口执行；SpringBoard 目标不再包含 LaunchServices 目录或客户端启动代码。不走 URL Scheme，不重试或换入口。

最新获用户通过反馈原包绑定源码 `d31faa0febfd24d7b438ac900a4003930a8d4386`、成功 Actions `40106758959` 第 1 次 attempt、SHA-256 `b5a982985e370f31d9f0b16d2ab02674e1ce344b931abe9ec1d2d31a41c8901d`。`feat/toggle-flashlight` 和 `feat/media-track-navigation` 均保持各自已构建 SHA，main 只追加本轮验收文档并纳入已测功能；文档提交不是新包源码或新设备测试。`feat/media-play-pause`、0.1.10 原包、0.1.9 设置分支及更早回退点均保留。无法读取必需状态、对象不存在或 ABI 不匹配时，拒绝识别/调用，不猜备用接口。

## 当前设置入口

```text
TapLock（保留自己的身份）
├─ 总开关／启用插件（原版位置保留，独立总开关未实现并禁用）
├─ Dock手势设置（禁用）
├─ 状态栏的手势（禁用）
├─ 主屏幕的手势
│  ├─ 主屏双击：启用主屏双击／选择双击动作／启用动作流模式
│  │  └─ 仅前两项可用；动作流禁用
│  ├─ 主屏三击、锁定界面双击、锁定界面三击（各三项，禁用）
│  └─ 左／中／右下划（各三项，禁用）；共21个控件始终可见
├─ 底部上划手势／便捷访问手势（原版手机条件，禁用）
├─ 实体按键手势（禁用）
├─ 自定高级设置／编辑预设链接／自定面板界面（禁用）
└─ 杂项：注销设备生效／备份所有设置／还原设置备份／重置所有设置（禁用）

选择双击动作 → 选择动作
├─ 已选择：当前单个动作（编辑、删除、排序未实现）
└─ 选择动作
   ├─ 基础动作 → 选择基础动作（可搜索，原68项主目录顺序）
   │  └─ 可用：系统截屏、控制中心、通知中心、系统锁屏、开关手电、播放/暂停、上一首、下一首、系统静音、应用切换界面（沿原目录顺序）
   ├─ 打开应用 → 选择应用（真实图标 + 名称 + Bundle ID）
   └─ 快捷方式／快捷指令／打开链接／预设链接（禁用）
```

原版页面由编译控制器构造，不用本地化表顺序代替实际行顺序。声明式资源与独立冻结的原指令/中文oracle核对；原作者授权、购买、联系及推广身份不移植。68项仅指已恢复的主目录构造数组：原版设备/外部插件条件过滤和条件追加条目尚未实现，不能称为原包所有设备固定可见数；Spotlight图标尚未解出，保留未知，不猜填。原多动作说明保留并明确标注非本阶段功能。完整范围与例外见 `docs/SettingsParity.md`。

原开关的存储域、key、默认值及已保存值保留；原版specifier ID只是UI身份，不作为新偏好key。单个动作与 Bundle ID 仍存入同一个 CFPreferences 属性列表值，保存成功才发 Darwin 通知。未配置动作继续锁屏，损坏配置或已卸载/禁止启动的目标不执行其他动作。App列表每次进入建立一次快照，不按行扫描全部 App；设置页只保存并返回，不当场执行动作。灰色行即使直接调用delegate或发送switch事件也不写偏好、不导航。

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
Sources/ScreenshotAction.swift        单次原生 takeScreenshot 请求；不自绘、保存或上传
Sources/AppSwitcherAction.swift       单次原生打开多任务；精确 BOOL/int64/BOOL ABI，无备用入口
Sources/MediaPlayPauseAction.swift    同一 loader 的单次播放/暂停、上一首、下一首；enum32/对象nil/unsigned-byte ABI
Sources/FlashlightAction.swift       单次系统手电开/关请求；UInt64状态/保存亮度、void效果、精确运行时ABI门
Sources/SystemMuteAction.swift      单次铃声反值与旧态 Int32 HUD；有声明的 owner getter、全部 ABI 前置拒绝
Shared/Applications.swift            仅设置目标：已安装 App 快照与选择时校验，无启动方法
Preferences/ApplicationIcons.swift   仅设置目标：按需真实图标、32pt 等比画布和缓存
Preferences/SettingsController.swift UIKit 设置首页 / 主屏幕手势 / 动作及 App 选择
Preferences/Resources/SettingsReference.json 原包绑定的设置展示数据（不是动作执行引擎）
Interfaces/TapLockPreferencesHost/    系统 PSViewController 声明及 module map
Preferences/Resources/Info.plist     设置 bundle 身份
layout/Library/PreferenceLoader/     设置入口
Tests/test_source.py                可在当前主机执行的源码/资源检查
Tests/PrivateAPIRuntimeTests.swift   供后续 macOS 执行的真实 Swift runtime 测试
```

所有业务实现、启动入口和 Hook 回调均为 Swift。生产 `.h` 只声明系统 `PSViewController` 及越狱环境已有的 `MSHookMessageEx` ABI；没有手写 `.m/.mm/.c/Logos` 业务实现，也不再使用 Orion。`Tests/SettingsConstructionFixture.{h,m}` 与 `Tests/NativeHookFixture.{h,m}` 仅为模拟器提供缺失的原生父类/工厂和 Hook 安装测试替身，`Tests/MediaRemoteFixture.m` 仅为 macOS loader/ABI 测试提供不连接系统播放器的 C 函数；这些均不参与 Theos 目标、不进入安装包。Substrate 兼容 Hook 后端、Swift/Objective-C runtime 和 UIKit 仍是底层依赖。

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
3. 历史UIKit harness继续对逐字节核验的0.1.8执行所有原断言。`ReferenceSettingsApp.swift` 同编旧0.1.8、0.1.9、0.1.10、0.1.11、0.1.12与当前UI：分别要求旧根页布局RED、旧播放/暂停行禁用RED、旧上一首/下一首行禁用RED、旧手电行禁用RED及旧系统静音行禁用RED，禁用行均不得有副作用；当前完成两路构造、21控件/6类别/68目录与搜索、禁用项不写入或导航、十基础+App单值保存/返回/重入、真实32pt图标、默认/损坏配置与资源失效安全。两个媒体Swift harness运行真实生产偏好/解锁/loader与不连接播放器的独立C库，覆盖旧偏好行为RED、命令2/4/5、UInt8返回、exactly-once、共享失败缓存和线程门；新增手电 harness 编译真实生产偏好/PrivateAPI/解锁/provider，以唯一 ObjC fixture 覆盖旧偏好RED、完整UInt64传递、void单次分支和失败门；系统静音 harness 编译真实偏好/PrivateAPI/解锁/provider，以唯一可逆重绑定的 ObjC fixture 覆盖旧 0.1.12 偏好行为 RED、完整十一动作替换、两路 owner／错误 direct 不回退、BOOL/Int32 ABI、old→反值→HUD 顺序与恰好次数。workflow父步骤另核验exact-source完整报告，缺失、重复、错序或错误标记均失败，不把模拟器传输成功当测试通过。在同一临时模拟器加载优化后的完整tweak dylib，保持dyld启动、Hook转发/挂载/移除回归；父类/Hook/媒体服务替身不冒充设备系统。
4. 安装打包/签名工具，按固定 commit 获取 `roothide/theos`、其子模块及 SDK；不修改用户本机工具链。
5. 完整编译 tweak 和 Preferences，架构为 arm64 + arm64e、部署下限 iOS 15.0，再生成原始 RootHide `.deb`。
6. 检查包内路径、版本、设置入口、Substrate 运行库链接、Orion 依赖不存在、每个架构的启动表/最低系统版本及嵌入签名结构。
7. 上传原始 `.deb`、SHA-256、源码仓库/commit 标记、工具链记录、初始化回归记录和完整构建日志。产物名包含完整源码 SHA，保留 14 天。

实际成功/失败以 [Actions](https://github.com/Tsangbaby/Gesture-X/actions) 的对应源码 SHA 运行和下载产物核验为准；添加 workflow 不等于构建通过。默认 Makefile 仍采用 rootless scheme，当前云端仅验证 RootHide，不能由此宣称普通 Rootless 包或任何机型已通过。

`ci/verify_package.py <package.deb>` 可在有 `dpkg-deb` 的 macOS/Linux 独立复核下载包；结构签名检查不等于开发者身份验证，也不等于设备允许加载。

0.1.9 设置展示、0.1.10 播放/暂停及 0.1.11 两项切歌按 `docs/Acceptance.md` 分别记录用户通过反馈，不将整体反馈扩展为每个子项均已单独执行。0.1.11 的149项源码合同、媒体切歌Swift三模式586/586/613断言、真实UIKit 19,557次断言、10项生产启动、双架构编译和原包独立核验属于 exact-SHA 云端／产物证据，用户反馈另列。原版未实现动作、多动作、编辑排序、其他手势和Siri仍不在范围。后续候选未获实机反馈前不纳入main。
