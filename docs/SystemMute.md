# 0.1.13：系统静音，单个互斥动作候选

## 范围与已测保护

从已固化 0.1.12 main `0cc50fbd3e82c336f89394f80cb298aa150a1c70` 开始；原始已测包源码 `d31faa0febfd24d7b438ac900a4003930a8d4386`、原分支和原包保留。仅解禁原目录 `SYSTEM_MUTE`（slot 32 / action 50）为 `systemMute`。这指铃声静音，不是媒体静音、音量置零或勿扰。设置只保存一个动作，不改启用值；既有双击资格、拒绝条件、生命周期、Hook 和旧 provider 不变。

## 原包证据与声明边界

- SquidGesture Pro 2.7.6-1 原 deb SHA-256 `240362fc1846f697025122e4788d04bbd1920b8f5102bcfc5642a9a14b62837a`；runtime member `36d40ef72649cf2530a5948371bc255e232782e752591d8ccef7afea4e41c267`；arm64e 切片 `1925f96a0b187d8084b9de0d1a9acbcc35cf2504c02f2aaba5c04f2ca2ef7f6d`。父代理从原包独立重核并重新 LLVM 反汇编 216 条关键原指令及 8 个 selector 槽，分发 action50 与 49/51/61 负控分离。
- 原包 action50 方法为本地 `void`，receiver 是由两个 initializer Hook 返回对象写入的 `SBRingerControl` 缓存，不存在已证实的 `SBRingerControl.sharedInstance`。读 `isRingerMuted`，反转低位；旧系统调用 `setRingerMuted:`；随后 `activateRingerHUDFromMuteSwitch:` 传旧状态。iOS17 availability 的四参 setter 不纳入本轮。
- 声明来源：[donato-fiore/iOS-Runtime-Headers 固定 SHA](https://github.com/donato-fiore/iOS-Runtime-Headers/tree/031ec3a8b25d1751646143551d2ea630bbb04cf9)，目录 15.0 与 16.0。两者的 `SBRingerControl.h` 声明可写 `BOOL` 属性（getter `isRingerMuted`），HUD 方法为 `void(int)`，不是 `void(BOOL)`。setter 的声明形状从可写 property 推得，不冒充单独取得的 raw method encoding。
- 15.0 的 `SBMainWorkspace.ringerControl` 及 `sharedInstanceIfExists`、16.0 的 `SpringBoard.ringerControl` 有实际 getter 声明。没有取得 15.4.1/16.0.3 精确补丁版本系统 metadata，声明与运行时能力门不能视作这些版本已验证兼容。

## 最小移植路线

不复刻 initializer Hook 缓存：在主线程且已通过现有解锁检查后，以 checked `SpringBoard.sharedApplication` 获得并验证实际 application。若其 runtime instance class **存在** `ringerControl` 方法，仅使用该 checked 对象 getter；返回 nil、ABI 不符或对象类型错误时不回退。只有该方法**完全不存在**时，才尝试已声明的 `SBMainWorkspace.sharedInstanceIfExists → ringerControl`，并验证 owner 和最终 `SBRingerControl` 实例。

这是有声明依据、保持系统对象所有权的 getter 移植策略，不宣称原包采用相同获取链。不猜 singleton、KVC 或创建控制器，也不增加 Hook、缓存或计时器。

对最终实例先完整验证：

- `isRingerMuted`：返回 `B`，无显式参数。
- `setRingerMuted:`：返回 `v`，参数 `B`。
- `activateRingerHUDFromMuteSwitch:`：返回 `v`，参数 `i`，Swift C ABI 使用 `Int32`。

全部匹配后，严格一次读旧值、一次设置 `!old`、一次 HUD `Int32(old ? 1 : 0)`，不重试、不换效果入口。任何前置拒绝均不读状态、不提交效果。返回 `true` 只说明两个 void 调用已尝试，不是系统接受、实际静音或 HUD 可见的证明。精确 ABI 门不能捕获系统方法内部 Objective-C 异常。

## 验证状态

生产 Swift、历史字节逆变换、source/CI 协议、真实 Apple Swift/UIKit、完整双架构编译、原包核验和设备反馈分别记录于 `Validation.md`。尚未实际执行的阶段不得写为通过；Linux/source/synthetic 协议检查不冒充 Apple 或设备执行。最终仅交付核验过的原始 RootHide 功能验证包，不附加诊断采集，不自动合并或创建 Tag/Release。
