# TapLock — Swift + UIKit 首版源码

**状态：首版源码已完成，已配置 GitHub Actions 云端 Mac / RootHide 构建；编译、产物与设备结果分别记录，不以静态检查代替。**

源码仓库：[Tsangbaby/Gesture-X](https://github.com/Tsangbaby/Gesture-X)。仓库名为 Gesture-X，当前首个最小功能模块仍叫 TapLock。本仓库不自动创建 Tag 或正式 Release。

暂定名称 TapLock，源码版本 0.1.1，包标识 `com.tsangbaby.taplock`。
这是一份新工程，不改动 Actra、SquidGesture 或其他既有项目；不包含其二进制、反编译输出或授权逻辑。

## 首版只有一条功能链

`一个默认关闭的开关 → 主屏幕空白处单指双击 → 发出一次系统锁屏请求`

- 只在已解锁、前台主屏幕、主显示器且界面为竖屏时允许识别。
- 只接受根桌面列表自身命中的直接手指触摸；图标、文件夹、小组件、搜索控件、Dock 不在允许范围。
- 编辑桌面、原生滚动/长按/拖动正在进行、VoiceOver 开启时不触发。
- 不注入普通 App，不接管底部/状态栏/实体按键，不增加全屏触摸罩。
- 关闭开关、桌面视图离开窗口或系统离开活跃状态时取消等待中的识别。
- 不加入通用动作引擎、动作列表、手势配置、主题、轮询、授权模块或后台日志采集。

上述是**实现约束和验收目标，不是已经取得的真机通过结论**。无法读取必需状态、对象不存在或 ABI 不匹配时，拒绝识别/调用，不猜备用接口。

## 源码结构

```text
Sources/Tweak.x.swift                 Orion 入口与唯一的桌面类 Hook
Sources/HomeDoubleTap.swift          识别器、生命周期、触摸/场景过滤
Sources/PrivateAPI.swift             已使用的固定类型私有调用与 ABI 检查
Sources/LockAction.swift             一次系统锁屏请求
Shared/Preferences.swift             Settings/SpringBoard 共用开关读写
Preferences/SettingsController.swift UIKit 设置页：一个开关
Interfaces/TapLockPreferencesHost/    系统 PSViewController 声明及 module map
Preferences/Resources/Info.plist     设置 bundle 身份
layout/Library/PreferenceLoader/     设置入口
Tests/test_source.py                可在当前主机执行的源码/资源检查
Tests/PrivateAPIRuntimeTests.swift   供后续 macOS 执行的真实 Swift runtime 测试
```

所有业务实现和 Hook 定义均为 Swift。生产 `.h` 只声明现有系统 `PSViewController`，让 Swift 正确继承 PreferenceLoader 要求的系统基类；生产目标没有手写 `.m/.mm/.c/Logos` 实现。`Tests/SettingsConstructionFixture.{h,m}` 是独立模拟器回归用的原生父类/工厂替身，只供测试，不参与 Theos 目标、不进入安装包。Orion/Theos 是外部工具/运行库，其正常预处理和互操作产物不等于“零底层依赖”。

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
2. 用 Xcode 16.4 的 Swift 编译并执行真实 `Sources/PrivateAPI.swift` runtime harness；失败就停止。
3. 用真实生产设置页 Swift 与 UIKit 执行旧 SHA 预期失败、当前 SHA 通过的初始化回归；原生父类/工厂为刻意缺少旧接口的测试替身，不冒充设备 Preferences。
4. 安装打包/签名工具，按固定 commit 获取 `roothide/theos`、其子模块及 SDK；不修改用户本机工具链。
5. 完整编译 tweak 和 Preferences，架构为 arm64 + arm64e、部署下限 iOS 15.0，再生成原始 RootHide `.deb`。
6. 检查包内路径、版本、设置入口、Orion 依赖、每个架构的最低系统版本及嵌入签名结构。
7. 上传原始 `.deb`、SHA-256、源码仓库/commit 标记、工具链记录、初始化回归记录和完整构建日志。产物名包含完整源码 SHA，保留 14 天。

实际成功/失败以 [Actions](https://github.com/Tsangbaby/Gesture-X/actions) 的对应源码 SHA 运行和下载产物核验为准；添加 workflow 不等于构建通过。默认 Makefile 仍采用 rootless scheme，当前云端仅验证 RootHide，不能由此宣称普通 Rootless 包或任何机型已通过。

`ci/verify_package.py <package.deb>` 可在有 `dpkg-deb` 的 macOS/Linux 独立复核下载包；结构签名检查不等于开发者身份验证，也不等于设备允许加载。

最后按 `docs/Acceptance.md` 集中做设备验收。尚无设备通过结论。
