# 实现边界与依据

## 入口与所有权

- 动态解析 `SBIconListView`，仅在类可转换为 UIView 且 `didMoveToWindow` 是 `void(self, _cmd)` 的情况下启用 Orion Hook。
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

必须满足 `SBHomeScreenWindow`、根 `iconLocation == SBIconLocationRoot`、直接手指命中列表自身，以及窗口重新 hitTest 仍命中该列表。缺失/不匹配任一项均拒绝。

同时要求主界面确实显示桌面、多任务没有显示、图标管理器不在编辑中，锁屏管理器报告 UI 未锁、锁屏不可见且不在解锁。
这些私有能力和根列表实际类型/位置值需要在目标设备验证；这是有意保守的适配门，不是“只设 deployment target 即兼容所有 iOS 15+”。

## 锁屏接口

选择 `SBLockScreenManager.sharedInstanceIfExists` 和 `lockUIFromSource:withOptions:`。
仅接受已核对的固定 `void(self, selector, Int32, object)` ABI，即 `v@:i@` 的组件；不把旧头文件中的 NSUInteger 当成等价类型，不对未知类型宽度强转。请求 source=1、options=nil，只有一次调用。

这是直接锁屏请求，不沿实体按钮模拟链，不 Hook 锁屏状态更新器，不用黑色视图、亮度或显示遮罩假装锁屏。返回 void，因此源码不把“调用返回”当作“设备已锁定”。设备是否进入锁定状态、屏幕行为与 Face ID 后续解锁必须单独验收。

## 设置契约

PreferenceLoader 原始源码的 `controllerForSpecifier:` 检查 PSViewController 继承关系，优先调用 `initForContentSize:`，随后写入 root/parent/specifier。不能只用同名 UITableViewController 替代。

本项目的 Swift 控制器直接继承真实系统 PSViewController，用 UIKit UITableView 渲染一行开关。声明头导入其 initializer，子类所有存储属性均有默认值且不自定义 initializer，以保留继承的创建路径。原生父类继续承担 loader 的其余 setters；没有伪造继承关系或动态替换 isa。

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
- source=1 锁屏调用的公开源码用例（用例不是本项目真机证据）：
  https://github.com/minh-ton/NineLS/blob/main/NineLS.xm
- 已有 Actra 参考分析中：`gestureRecognizer:shouldReceiveTouch:` @0x17dec 使用主屏幕窗口与精确列表命中；`_ActraSupportsDeviceLockBridge` @0x3cf40 检查 `v28@0:8i16@20` 锁屏签名。反编译结果只作为带地址的线索，本项目没有复制其动作系统或把它描述为原始源码。

公开旧版 SBLockScreenManager 头文件将 source 声明为 NSUInteger，与参考二进制的 Int32 签名存在差异。本实现明确选择 Int32 能力门；目标运行时不满足时不调用，而非隐式兼容或冒险猜测。
