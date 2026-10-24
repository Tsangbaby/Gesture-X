# 0.1.11 — 下一首 / 上一首（已获用户通过反馈）

用户已对原始 RootHide 功能包反馈「测试已通过」，随后授权纯验收文档固化到 main。原始构建 SHA `9f942e8abad9c04835a189aadb5ec8526609596f`、Actions `40099002702` / attempt 1、原包 SHA-256 `b06cbb986684430fa95585de6960ca77f4cdd7581d2833dfc36a21f7ec4eddc6` 保持不变；本文件余下为当时实现与交付门。整体反馈不逐项代勾，不扩展其他系统；保留已测分支／原包，不重编、不创建Tag／Release，文档提交不冒充新测试包。

## 授权与保护边界

- 用户在 0.1.10 播放/暂停原包反馈「测试已通过」后，明确要求下一首、上一首两项一起做；本轮是两项互斥动作，不是同时执行两条命令。
- 基于受保护的 `cd480bfe09c7080b0523e1c73910b8af617edb01` 新建 `feat/media-track-navigation`；保留 `feat/media-play-pause` 与 0.1.10 原包。实施与交付时 main 为 `1e2b7ef11a5f743b8db122c02d9a5478d2f20bfa`，当时不自动合并或发布；后续仅在本页开头的用户验收和固化授权后纳入main，不创建Tag／Release。
- 0.1.10 原包 SHA-256：`8200d10651224f3e517fd7a37a1beabad912a4e554547bda295ba096ae0a1d60`。用户反馈单独记录于 Acceptance；此前交付记录中的未实机状态是交付时事实，不回写伪造为当时已测试。

## 原目录与接口证据

- 独立冻结的原目录 oracle 不变：上一首为 `PREVIOUS_MEDIA` / reference slot 20 / reference action 38，下一首为 `NEXT_MEDIA` / slot 21 / reference action 39。原位解禁，不重排、重命名或用目录编号作为系统命令号。
- 版本固定声明：[theos/headers@13c1f17176d7efe6871551cd69a75b71ac4eeaf1 / MediaRemote.h](https://github.com/theos/headers/blob/13c1f17176d7efe6871551cd69a75b71ac4eeaf1/MediaRemote/MediaRemote.h)。已按 Git 对象核验 blob `fb772c2d6d5fd5829538b9584b9641e9596dacb0`；按该声明 L78 起从零递增的 enum 顺序，L82 `MRMediaRemoteCommandNextTrack` 的值为 4、L83 `MRMediaRemoteCommandPreviousTrack` 的值为 5；并非把这两个数当作头文件显式赋值。
- 原运行时消费者补证：原包成员 `SquidGesturePro.dylib` SHA-256 `36d40ef72649cf2530a5948371bc255e232782e752591d8ccef7afea4e41c267`，所选 arm64e 完整 subtype `0x80000002`、切片 SHA-256 `1925f96a0b187d8084b9de0d1a9acbcc35cf2504c02f2aaba5c04f2ca2ef7f6d`。静态分派将 action 38/39 绑定至 IMP `0x17674` / `0x173d8`；决定性原指令位于 `0x17864`（5,nil）/ `0x17568`（4,nil），均调用 `0xb2708`，authenticated stub 经 `0xd0140` 导入 `_MRMediaRemoteSendCommand`。父会话重新从上传原包内存读取，核对切片、实际 USERLAND24 链、selector literal、ObjC IMP/type、参数原字节及导入绑定；全量扁平状态机传播采用独立静态轨迹，父会话未重复全量重放。没有执行原包或将其二进制加入工程，不当作设备证明。
- 沿用 0.1.10 已核准的 `MRMediaRemoteSendCommand` C ABI：32-bit enum、nullable 对象、原生 unsigned-byte 返回值；Swift 为 `@convention(c) (UInt32, AnyObject?) -> UInt8`。BOOL/Boolean 区分、相邻 SDK 与原消费者证据边界见 `MediaPlayback.md`，不把头文件当作当前设备运行证明。

## 最小生产实现

- 只改 7 个已有生产/metadata 输入：Preferences.swift、HomeDoubleTap.swift、MediaPlayPauseAction.swift、SettingsController.swift、SettingsReference.json、control、Info.plist；没有新增生产源文件或依赖。
- 保留既有媒体 provider 名称，loader、生命周期、失败缓存、C 类型与 `toggle()` 方法体字节不变。只追加 `previousTrack()` 与 `nextTrack()` 两个直接方法，各自先过主线程和原解锁门，再共享同一 loader，分别同步发送一次 `(5, nil)` / `(4, nil)`。
- 无状态查询、曲目信息读取、跳进度、强制播放、HID/实体按键模拟、延时、重试、备用入口、播放器特判或诊断采集。返回 `true` 仅说明原生返回非零，不证明切歌完成；系统/当前播放器决定具体行为及列表边界。
- 原偏好域、key、默认值、开关和通知链不变；新动作严格只接受 `{"kind":"nextTrack"}` 或 `{"kind":"previousTrack"}`。目标 App/其他键、大小写或空白不修正，错误记录拒绝。设置只保存、返回和重进，不调用媒体服务。
- 保持原主屏双击、空白命中/竖屏/场景/编辑/交互/VoiceOver 过滤、Hook、启动和所有旧执行器；不开放其他手势、Siri、动作流、多动作或编辑排序。

## 分层验证门（不预先算云端/设备通过）

1. Python 源码合同已真实观察到两个原行仍禁用的 RED，再实现成 GREEN；版本与 CI 接线也观察缺失时失败。当前完整本地套件为 149 项，零失败/错误/跳过；不等于 Swift 编译或设备切歌成功。
2. 新 manifest 冻结 0.1.10 的 26 个生产输入，11 个精确计数/顺序 hunk 恢复 7 个授权路径；缺失、重复、错序、CRLF 和无关漂移必须拒绝。15 个历史 JSON/helper 字节不改；外层 helper 及 27 个调用点只增加显式 track opt-in。历史 media malformed fixture 的两条纯 kind 记录因本轮变为合法而改为带额外键的损坏记录，不删除负例；新 harness 另检查全部有效动作的双向替换。
3. 同一真实 Swift harness 编译未修改且摘要匹配的 0.1.10 偏好，下一首、上一首分别必须出现精确「persisted ... action is unavailable」行为 RED；编译错误、崩溃或传输失败不能算 RED。
4. 当前真实偏好、PrivateAPI、LockAction 与共享动态 loader 对独立 C dylib 执行三种模式。覆盖命令 4/5/2、nil 参数、UInt8=0/255/1 返回、恰好一次、缺库/缺符号共享失败缓存、非主线程/锁态/对象和 ABI 拒绝、拒绝后恢复及全部单动作替换。只在一次性测试源副本精确、可逆地重绑一个 OS 类名和一个库路径，函数体不替换；C fixture 与已通过 0.1.10 字节一致，不连接系统播放器。
5. 同一真实 UIKit harness 对原 0.1.8 根页、0.1.9 禁用播放/暂停、0.1.10 禁用上一首/下一首三路行为 RED；最后当前 UI 必须通过两路构造、原目录/搜索、八基础动作与 App 单值保存/唯一勾选/返回/重入/Home 摘要、原禁用项、真实图标及资源失效安全。旧 enum 用明确 feature flag 编译；保持一个非空 scalar 参数，兼容 Mac Bash 3.2。生产完整 dylib 启动/Hook/挂载回归保留。
6. workflow 父步骤另校验 exact-source 原生报告和四阶段 UIKit/生产启动报告，缺失、重复、乱序、错误 SHA 或空成功均失败；报告入 artifact。随后 Apple arm64 + arm64e 编译与原始 RootHide 包核验，原包独立逐切片签名代码页哈希检查通过后才交付。

## 实机验收（本轮功能验证包，不加日志包）

- 升级保留当前开关和所选动作；原目录的上一首/下一首可各自选择，只保存一个。返回、重进、勾选和主屏摘要正确，不在设置切歌。
- 使用有前后曲目的实际播放列表，分别选下一首、上一首，退出设置后在已解锁竖屏桌面空白处双击；一次请求只触发所选方向，不连跳或混入暂停、锁屏等旧动作。列表边界和播放状态按系统/播放器语义处理，不强制恢复播放或调整进度。
- 切回播放/暂停及一个旧动作验证不回退，再切回两个新动作；关闭开关与原非桌面/图标/Dock/横屏拒绝条件继续有效。集中验收一轮即可，不为切换选项重复注销，不要求无新问题时额外导出日志。

本文件保留实施与交付门；本轮实际Actions、原包及用户通过反馈绑定页首exact SHA，不能从0.1.10用户通过或本地Python GREEN外推。文档晋级不改变原包身份，也不意味着额外环境通过。
