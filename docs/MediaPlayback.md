# 播放/暂停：单动作候选边界与固定接口依据

## 产品范围

- 从已验收0.1.9追加一个互斥动作，沿用主屏幕空白处双击、默认关闭、竖屏/解锁/前台/非编辑/VoiceOver过滤、偏好域和通知。
- 保留原68项目录、中文「播放/暂停」、`PLAYPAUSE_MEDIA`、slot 19、reference action 37和`playpause`图标；只将此行改为可选。Siri取消、切歌不在本轮。
- Settings只保存 `{"kind":"playPause"}` 并返回。缺失偏好仍默认锁屏，损坏偏好不回退为任何动作；升级不主动改变已有选择或开关。
- `MediaPlayPauseAction.toggle()`要求主线程及原解锁门。首次合格调用才按固定系统路径`dlopen(RTLD_NOW | RTLD_LOCAL)`、`dlsym("MRMediaRemoteSendCommand")`；解析成功的handle保持进程生命周期，缺符号则关闭handle，失败也缓存。不重试、换入口、模拟按键或查询播放状态。
- 仅发送一次`2, nil`，不发送play和pause两条猜测命令。原生返回非零只是函数的提交结果，不证明服务、播放器或实际播放状态改变。无媒体会话时效果由系统/播放器决定，不自行启动播放器。

## 已由父会话重新读取并核验Git blob的声明

1. Theos headers，commit `13c1f17176d7efe6871551cd69a75b71ac4eeaf1`，`MediaRemote/MediaRemote.h`，blob `fb772c2d6d5fd5829538b9584b9641e9596dacb0`：L74–118普通C enum从Play=0、Pause=1到TogglePlayPause=2；L76明确“Use nil for userInfo”；L120声明`Boolean MRMediaRemoteSendCommand(MRMediaRemoteCommand command, NSDictionary *userInfo)`。
   固定来源：https://github.com/theos/headers/blob/13c1f17176d7efe6871551cd69a75b71ac4eeaf1/MediaRemote/MediaRemote.h
2. 固定SDK commit `0222fd5413cf4b9af096f37b4621afa2688572f7`，`iPhoneOS15.6.sdk/usr/include/MacTypes.h`，blob `135fad0fd28e27bc415dab8075d2fdde658d6eb9`：L303明确`sizeof(Boolean)==1`，L309为`typedef unsigned char Boolean`。因此返回绑定`UInt8`，不把它冒充Swift `Bool`或Objective-C `BOOL`。
   固定来源：https://github.com/theos/sdks/blob/0222fd5413cf4b9af096f37b4621afa2688572f7/iPhoneOS15.6.sdk/usr/include/MacTypes.h
3. WebKit commit `d878117d5b773fb1151dabcb11e8617390f3c74d`，`Source/WebCore/PAL/pal/spi/mac/MediaRemoteSPI.h`，blob `986737ee0b85ba79477f94cbfef5103fa2a2f4a1`：L39–70相同命令序列并明确`typedef uint32_t MRMediaRemoteCommand`。生产绑定`@convention(c) (UInt32, AnyObject?) -> UInt8`，只传nil对象，不能推导非nil参数的所有权规则。此WebKit文件声明的是`SendCommandToApp`而非目标函数，故只作为命令类型交叉证据，不称为iOS15目标函数的原厂头；普通C enum声明没有独立明确符号性，向32位寄存器传常量2也不证明signed/unsigned。
   固定来源：https://github.com/WebKit/WebKit/blob/d878117d5b773fb1151dabcb11e8617390f3c74d/Source/WebCore/PAL/pal/spi/mac/MediaRemoteSPI.h
4. 同一固定SDK的`iPhoneOS16.5.sdk/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote.tbd`，blob `a419b6430413f45d7e4fe48b1bbff873e525416f`：固定install-name为`/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote`，arm64/arm64e目标导出`_MRMediaRemoteSendCommand`（L1162）。SDK符号表不是目标设备的加载或调用证明；动态解析失败必须直接结束，不强链接或猜备用入口。
   固定来源：https://github.com/theos/sdks/blob/0222fd5413cf4b9af096f37b4621afa2688572f7/iPhoneOS16.5.sdk/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote.tbd

以上声明支持候选的单次调用形状，未执行原参考二进制。主线程与解锁要求是本项目的行为边界，不是这些头文件证明的API前置条件。

## 验证分层

- 本地Python：目录/单值/调用接线、精确delta及原有25个生产输入、旧fixture未改、guard正反例、目标归属和包隔离合同；不计为Swift执行。
- macOS实际Swift：同一harness让原0.1.9偏好产生精确缺功能断言；当前真实生产偏好、PrivateAPI、LockAction及loader只在一次性副本重绑一个类名和固定加载路径，并反演到逐字节相等。独立Objective-C/C dylib提供unsigned-byte返回；实际运行缺库、缺符号、失败缓存、先拒绝后可加载、0/1/255、command2/nil/exactly-once、线程/锁态/错误锁ABI及七动作存储回归。不连接系统MediaRemote服务。
- iOS Simulator实际UIKit：旧0.1.9原行禁用/强制delegate无副作用；当前两路构造、六个基础动作+App的保存返回、摘要/重入/互斥、媒体搜索、禁用项、图标/旧导航及资源fail-closed。完整优化tweak启动/Hook回归与完整Preferences编译仍必需。
- 产物：同一exact SHA的Apple arm64/arm64e编译、原始RootHide包的版本/路径/资源、两个切片的媒体查找足迹、Preferences无提供者、逐切片签名结构与代码页哈希。原包不包含测试库或诊断采集。
- 设备尚未验收：安装本轮原始功能包，启用双击，选择「播放/暂停」。已有媒体播放时回桌面双击暂停，再双击继续；设置选择本身不得执行。切回一个已通过旧动作作对照，关闭开关须不触发。无活动会话时不承诺效果；不要求导出无关日志，不把CI成功外推为所有iOS15+兼容。
