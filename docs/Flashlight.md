# 0.1.12：开关手电，单个互斥动作候选

## 范围与基线

- 从已固化的 main `925df18141606b75f71c77ddd998ad2baa237efe` 新建 `feat/toggle-flashlight`。其生产输入与已获用户通过反馈的 0.1.11 原包源码 `9f942e8abad9c04835a189aadb5ec8526609596f` 相同；原分支、原包和 main 保留。
- 只解禁原目录 `TOGGLE_FLASHLIGHT`，中文「开关手电」、图标 `flashlight.on.fill`、reference slot 16、reference action33 均不变。slot/action number 不是系统亮度或调用参数。
- 继续使用已验收的默认关闭开关、主屏空白单指双击、命中/锁态/方向/生命周期门。设置里只保存一个动作，不试亮、不加载手电 provider、不增加手势、串行动作或日志。
- 持久化仅接受单键 `{kind: flashlight}`；多余字段、App 目标、大小写或空白变体均拒绝。旧动作和 App 与新动作互斥替换，enable 独立。
- 当前是功能验证候选，不是诊断包。设计部署下限 iOS 15.0 不是所有 iOS 15+ 的兼容证明；新动作需对应原包设备验收后才晋级 main。没有创建 Tag／Release。

## 原包消费者与父代理复核

对用户提供的 SquidGesture Pro 2.7.6-1 原包静态追踪，不执行该二进制，不移植其混淆、反馈或授权模块。

- 原 deb SHA-256：`240362fc1846f697025122e4788d04bbd1920b8f5102bcfc5642a9a14b62837a`。
- 注入库 FAT 成员 SHA-256：`36d40ef72649cf2530a5948371bc255e232782e752591d8ccef7afea4e41c267`。
- 选定 arm64e 切片 SHA-256：`1925f96a0b187d8084b9de0d1a9acbcc35cf2504c02f2aaba5c04f2ca2ef7f6d`。以下 VA 只适用于这个切片。
- 分派入口 IMP `0x39028`，action33 比较 `0x3d574` 原字节 `1f8500f1`；`0x3e43c` 调用动作 IMP `0x15658` 对应 selector `l21c229287274511a7a124090c59609b`，原元数据返回 void。
- `0xfdcd0` 是 **Class 缓存**，不是实例；冷路径 `objc_getClass("SBUIFlashlightController")`，冷/热均汇入 `+sharedInstance`。`0x15964` 的 retain-autoreleased-return 消费与末尾 release 支持按普通 +0 getter 取出后局部强持有，不采用 retained-family getter。
- `0x15974` 读取 `level`；`0x15978` 字节 `1f0000f1` 比较零。非零分支 `0x159a0` 调用零显式参数 `_turnPowerOff`。零分支 `0x159b4` 调用 `_loadFlashlightLevel`，`0x159b8` 字节 `e20300aa` 将返回寄存器原样转作参数，`0x159c8` 调用 `setLevel:`。
- 不是固定亮度 1，不把残留 x2 当 `_turnPowerOff` 参数，不把原包 void 入口反编译成原生 BOOL 成功。反馈辅助方法的返回值会覆盖，不能当手电状态。

调查证据保留在工程外 `Gesture-X-artifacts/0.1.12-flashlight-research/`。`ORIGINAL_CONSUMER.json` SHA-256 `b13a3f3aa4bf8a091752aac3997fb87e184b6ee39d539cecdae3c2dd032db687` 含完整分派轨迹和指令。父代理从原 deb 重新核对三层摘要，独立解析 15,498 个 format12 chained slots、方法元数据、7 个 selector literal、分支表及全部保留指令字节，并重放类名解密。完整平坦化传播轨迹来自独立调查，父核的是保留字节和关键分支，不冒充另写完整模拟器的第二次全量证明。

## 系统声明证据及缺口

版本固定的原文/Git blob 经父代理再次读取和重算，系统侧 ABI 依据如下：

- [仓库标称 iOS 15.5 的 SBUIFlashlightController.h](https://github.com/lechium/iPhone_OS_15.5/blob/0f4def7da3cad33a6ea5a4224f4ec3526f3e73f8/System/Library/PrivateFrameworks/SpringBoardUI/SBUIFlashlightController.h)，blob `308ef40a911d8403e69a0537ab644e65fa739442`：`+sharedInstance` 返回 id，`level` 属性及 `_loadFlashlightLevel` 返回 unsigned long long，`_turnPowerOff` 返回 void。
- [真实开源调用者 FlashlightSettings](https://github.com/wrp1002/FlashlightSettings/tree/c263e4c5ce4935503fcd88b745731e1a29251674)：`Tweak.x` blob `a0f4ee4ec8b2125200e16379c68fab13a86ded10`；`Tweak.h` blob `34c2976a04d66442fd25da905c834a56621d18b8` 交叉提供 `- (void)setLevel:(unsigned long long)level`。

这是相邻版本声明与调用者佐证，**不是目标 iOS 15.4.1 或 iOS 16 设备运行时测量**。SDK `.tbd` 的类符号不能证明方法 ABI；未取得目标版本这五个方法的完整声明，不把资料缺失解释成系统无此类。dump 未证明系统所有权注解、完整合法亮度范围、默认值或钳制策略。调用者使用 4 不证明系统合法域是 0…4。

## 当前 Swift 路径与失败语义

`HomeDoubleTap.recognized` 原全部门后，`.flashlight` 仅调用一次 `FlashlightAction.toggle()`。新 provider 仅属于 tweak 的完整编译图，Settings 编译图没有它。`PrivateAPI`、`LockAction`、媒体 loader/ABI/失败缓存、Hook 和生命周期实现保留原字节。

1. 再次要求主线程且 `LockAction.unlockedManager()` 可确认解锁；不满足时不查询手电单例。
2. 查询真实系统 Class，沿现有 `PrivateAPI.object` 要求 `sharedInstance` 准确对象返回、零显式参数及隐式参数 ABI；取非 nil 且属于该类链的真实对象。
3. 对 receiver 的运行时类**先核全部四个方法**：`level → Q`、`_loadFlashlightLevel → Q`、`_turnPowerOff → v`、`setLevel: → v(Q)`；包括 arity、self 和 _cmd。缺失或不匹配均在任何亮度读取/效果调用前拒绝，不尝试 q、BOOL、float 等备用形态。
4. UInt64 读取 level 恰好一次。非零：无参数 `_turnPowerOff` 恰好一次，不读保存亮度。零：读取保存亮度一次，将完整 UInt64 原样传 `setLevel:` 一次，不设固定值、不钳制、不补发；保存值若为零仍传零，不把它伪称实际点亮。
5. 本地 Bool false 表示未提交效果；true **只表示调用一个 void 效果入口**，不是系统受理、光源实际改变或可见效果。Objective-C 内部异常不由这些元数据检查捕获。

没有 AVFoundation 替代、reason/强制最大亮度入口、硬件事件模拟、反馈震动、延时、轮询、重试或失败回退。下一次有效手势可再尝试，但 provider 本身不安排后续工作。

## 验证协议

源码门、Apple 执行、原始包核验、设备反馈分列，当前精确结果见 `Validation.md`，设备清单见 `Acceptance.md`。

- 独立历史字节合同：冻结 26 既有生产输入；七既有输入的授权变更用精确计数/顺序 inverse 恢复到 0.1.11，新 provider 摘要单独保护。历史 helper 默认仍严格，旧合同显式 newest→oldest 还原；缺历史 Git 对象不能跳过字节验证。
- 真实 Swift harness：同一测试对未改 0.1.11 偏好 `{kind: flashlight}` 的不可用结果要求特定行为 RED；当前编译生产偏好、PrivateAPI、LockAction、FlashlightAction，独立唯一 ObjC 类名 fixture 仅重绑两处 literal，inverse 字节必须还原。覆盖完整 UInt64、零/非零和 exactly-once 分支、线程/锁态/对象/ABI 拒绝、拒绝后恢复，以及完整互斥存储矩阵。宽值用于验证传输宽度，不声明真实设备的合法亮度域。
- UIKit：原三个历史 RED 保留；新增 0.1.11 原手电行禁用且强制 delegate 不写入/导航的 RED。当前九基础+App保存、唯一勾选、返回/重入/Home摘要、搜索/禁用项/图标/损坏资源及完整生产启动回归一起执行。
- exact-source 报告把 source/fixture attestation 和 completion 分开；必须匹配 exact SHA、case次序、返回码和正断言数。编译失败、零退出空输出、错/重复/混合 marker 不计 RED 或 GREEN。
- 同一最终 SHA 在授权云 Mac 构建 RootHide arm64/arm64e，独立下载原包核 metadata、来源、资源、目标编译证据及逐切片嵌入签名；这些不等于设备接受或运行成功。
