# 实现边界与依据

## 入口与所有权

- 保留的 Swift C 函数指针位于 `__DATA,__mod_init_func`，由 dyld 自动调用后投递主队列；不是等待首次访问的普通全局闭包，也不依赖未被调用的导出函数。
- 动态解析 `SBIconListView`，仅在类可转换为 UIView 且 `didMoveToWindow` 是 `void(self, _cmd)` 的情况下通过 `MSHookMessageEx` 安装唯一 Hook；原生声明模块无业务实现，Hook 后端由越狱环境提供。
- Hook 先原样调用一次原方法，再处理本项目识别器。不替换 UIApplication 事件路由、原生识别器 delegate 或 hitTest。
- 主队列启动时补扫现有主屏幕窗口，后续依靠桌面视图移入/移出窗口及应用生命周期通知；无定时补扫。
- 每个精确匹配的列表视图最多一个双击识别器，视图持有识别器，进程级 owner 只保留弱引用。移出窗口立即移除。
- owner 是进程生命周期单例，Darwin 通知的非持有 observer 指针对应这个固定生命周期；没有可卸载会话或每次出现都重新注册的 observer。

## 原生操作优先

- 系统 UITapGestureRecognizer 负责双击间隔、移动容限和一次结束回调，不另造计时器/双击状态机。
- 不取消、不延迟原始触摸；不向原生手势添加失败依赖。只允许本项目识别器与原生手势共存，不改原生/原生规则。
- 在触摸接收、识别开始和动作执行前分别检查条件；动作为同步的一次请求，带重入保护，无重试/异步补发。
- 原生滚动、长按等连续手势已经开始时拒绝锁屏。原生手势也可能使本项目不触发，这是安全取舍，不保证胜过系统手势。

## 空白区与必需状态

必须满足 `SBHomeScreenWindow`、根 `iconLocation` 精确为 `SBIconLocationRoot` 或 `SBIconLocationRootWithWidgets`、直接手指命中列表自身，以及窗口重新 hitTest 仍命中该列表。缺失/不匹配任一项均拒绝。多任务状态由 `SBMainSwitcherViewController.sharedInstanceIfExists` 读取，不向 UIApplication 发送缺乏 iOS 15 声明依据的 `_switcherController` getter。

同时要求主界面确实显示桌面、多任务没有显示、图标管理器不在编辑中，锁屏管理器报告 UI 未锁、锁屏不可见且不在解锁。
这些私有能力和根列表实际类型/位置值需要在目标设备验证；这是有意保守的适配门，不是“只设 deployment target 即兼容所有 iOS 15+”。

## 锁屏接口

动作入口改为实际 `SpringBoard.sharedApplication` 对象的 `_simulateLockButtonPress`，仅接受固定 `void(self, selector)` ABI，即 `v@:` 的组件，只有一次同步调用。先验证接收对象的类，再检查返回值、隐式参数和零个显式参数；接口缺失/签名不符时不调用，不回退到旧 UI 锁定接口。

`SBLockScreenManager.sharedInstanceIfExists` 仅作为原有安全状态读取者，仍要求 UI 未锁、锁屏不可见、未在解锁中，避免再次短按将已锁设备唤醒；不再要求它实现已停用的 `lockUIFromSource:withOptions:`。不 Hook 实体按键，不发送 HID，不另造动画、黑色视图、亮度或显示遮罩。灭屏和过渡交给系统入口处理，但返回 void 不能证明设备已经灭屏或动画等同硬件短按。

最低部署版本为 iOS 15.0，不设硬编码系统版本上限。私有类/selector/签名按运行时能力检查，不按 `majorVersion == 15` 选择；iOS 15.2 与 17.0 头文件均声明该按钮模拟入口，但头文件不证明实际实现和未来版本兼容。设备锁定、灭屏/系统过渡及唤醒/Face ID 必须分开验收。

## 设置契约

PreferenceLoader 原始源码的 `controllerForSpecifier:` 检查 PSViewController 继承关系，优先调用 `initForContentSize:`，随后写入 root/parent/specifier。不能只用同名 UITableViewController 替代。

本项目的 Swift 控制器直接继承真实系统 PSViewController，用 UIKit UITableView 渲染一行开关。声明头只声明真实基类，不再把旧版 `initForContentSize:` 声明为其可用方法。Swift 子类显式拥有 `@objc(initForContentSize:)` convenience initializer，转入 UIKit 支持的 `init(nibName:bundle:)`，不向缺少该接口的父类转发。原生父类继续承担 loader 的其余 setters；没有伪造继承关系或动态替换 isa。

0.1.0 在 iOS 15.4.1 的 Settings 崩溃已将失效路径定位到自动生成的 `initForContentSize:` → `objc_msgSendSuper2`。因此不能再以 Theos 头文件存在该声明作为设备实现证明。CI 会从固定 0.1.0 SHA 编译真实旧控制器，在缺失旧接口的原生 UIKit 父类测试替身上复现异常，再用同一替身执行修复后控制器的 legacy/default 两种工厂路径及实际表格/开关创建。该替身只验证初始化回归，不证明设备 Preferences 的完整 factory/setter 链，也不进入安装包。

两进程共用唯一 CFPreferences domain、Enabled key、current-user/any-host scope，严格读取 CFBoolean，缺失/损坏/同步失败均默认关闭。只有设置持久保存成功才发送 Darwin 通知；接收方在主队列先取消部分识别，再加载最新值。没有在每次触摸时读偏好文件。

## 可核对的一手资料与参考证据

- Theos Orion Tweak/Hook 规范：
  https://orion.theos.dev/protocols/Tweak.html
  https://raw.githubusercontent.com/theos/orion/master/Sources/Orion/ClassHook.swift
- Theos 模板与运行库依赖 `${ORION}`：
  https://raw.githubusercontent.com/theos/templates/master/ios/tweak_swift/control
  https://raw.githubusercontent.com/theos/templates/master/ios/preference_bundle/Makefile
- 系统 Preferences 声明：
  https://raw.githubusercontent.com/theos/headers/master/Preferences/PSViewController.h
- PreferenceLoader 创建/继承检查的实际实现：
  https://raw.githubusercontent.com/DHowett/preferenceloader/master/prefs.xm
- rootless scheme 与架构边界：
  https://theos.dev/docs/rootless
- 旧 source=1 UI 锁定入口的历史对照（本项目已停用）：
  https://github.com/minh-ton/NineLS/blob/main/NineLS.xm
- 系统按钮模拟入口的固定版本声明：Runtime-Headers commit `f15f8ebf05b6da366045a4eec985c9dda7c5f456` 中 `iOS/15/15.2.tar.gz` 与 `iOS/17/17.0.tar.gz` 的 SpringBoard.h，均声明 `- (void)_simulateLockButtonPress`。
  https://github.com/kissalexandra/Runtime-Headers/tree/f15f8ebf05b6da366045a4eec985c9dda7c5f456/iOS
- 直接调用按钮入口的开源手势实现（只作调用模式参考，不是真机结果）：
  https://github.com/Nosskirneh/ProperLockGestures/blob/c4aacb914e68b6ace59cd593ae535e4ccc47e30e/Tweak.xm
- 已有 Actra 参考分析中：`gestureRecognizer:shouldReceiveTouch:` @0x17dec 使用主屏幕窗口与精确列表命中；`_ActraSupportsDeviceLockBridge` @0x3cf40 检查 `v28@0:8i16@20` 锁屏签名。反编译结果只作为带地址的线索，本项目没有复制其动作系统或把它描述为原始源码。

旧 UI 锁定入口的 NSUInteger/Int32 声明差异属于历史证据，不再参与当前动作能力门；未知按钮 ABI 仍拒绝调用，不冒险强转或补发其他锁定路径。
