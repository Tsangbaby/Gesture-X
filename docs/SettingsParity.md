# 0.1.9 — 原版设置展示层还原合同

## 验收固化状态

本轮原始RootHide包（源码 `486e82e47e420ff5db647f03dcde58f40a0fc053`）已获用户“测试已通过”反馈，并获授权纳入main；原分支、原包及0.1.8回退点保留，不重编或自动发布。通过范围仅为本合同的设置展示与已实现动作保持正常，不包括多动作、Siri或所有原版功能。下文保留实现/交付前合同，原“实机待验收/不合main”门由本段明确的后续用户验收与授权取代；源码、云端、产物及设备证据见Validation/Acceptance。

## 授权与保护基线

用户明确选择：只恢复原版页面层级、文案、顺序和控件；未实现项禁用。保留当前单动作存储和执行；多动作机制、Siri 分开推进。

- main 文档固化点：`3a63f2c25b30da1c882428de9b85def045c1e250`。
- 已实机通过运行源码：`f3a2e138fa9ac93d250645e9c66226b074d429ee`（0.1.8，iOS 15.4.1 / RootHide，用户反馈）。
- 原包：SquidGesture Pro 2.7.6-1，SHA-256 `240362fc1846f697025122e4788d04bbd1920b8f5102bcfc5642a9a14b62837a`。
- 原版所选 arm64e Preferences 薄片：SHA-256 `a3e95d0028907909bc521a687934fa362cef18c4c813a787ff2a4b9e0eba6586`。
- 静态证据目录：`/home/ubuntu/Gesture-X-artifacts/SquidGesturePro-2.7.6-1-reference-240362fc/`。已由父会话复核导航 verifier、实际指令、68 个标题槽、动作编号数组和包内中文映射；没有执行原包，不声明真机像素一致。

## 本轮验收范围

1. 根页恢复原版功能设置的分组与九个导航入口相对顺序。仅“主屏幕的手势”可进入；其他入口保留原位置、明确标为尚未实现并禁用。独立总开关和杂项管理按钮尚未实现，显示为禁用控件，不能写入旧开关或伪装可用。
2. 主屏页恢复七组三行及原尾注，共21个控件。顺序为主屏双击、主屏三击、锁定界面双击、锁定界面三击、左/中/右下划。每组是启用、选择动作、动作流。仅第一组的前两个控件接入既有读写；其余禁用且不写任何偏好。保持全部行可见，不自行增加依赖隐藏。
3. 动作页恢复“已选择 / 选择动作”两节。类别按原顺序为基础动作、打开应用、快捷方式、快捷指令、打开链接、预设链接；仅前两类可进入。已选项保持单个，编辑/删除/排序按钮禁用，并明确说明本阶段限制，不把原版多动作说明伪装为已实现。
4. 基础动作独立可搜索页：按已恢复的原版68项主目录顺序显示文案及已识别图标。仅系统截屏、控制中心、通知中心、系统锁屏、应用切换界面可选择；其他均灰色禁用。原版设备/外部插件条件过滤与四个条件追加条目不在本阶段实现，不把68项构造数组说成原包所有设备固定可见行数。
5. 基础动作选择保持现有单值替换，返回动作管理页；打开应用进入原有快照/真实图标选择器，选择只保存并返回，不在设置执行。
6. 保留 TapLock 身份、包ID、Preferences detail/initForContentSize: 合同、已有开关与动作、默认关闭/缺失默认锁屏/损坏不回退的语义。原版作者授权、购买、捐赠、联系和推广入口不移植到独立工程；不处理原授权代码。
7. 生产 Sources、Shared、ApplicationIcons、接口、原注入过滤及主 Makefile 保持0.1.8字节。唯一修改的生产Swift是 Preferences/SettingsController.swift；新增声明式设置资源；control/Info版本同步0.1.9。不加通用引擎、动作数组、其他手势、系统入口、诊断或网络逻辑。

## 资源接口（父会话 → UI实现者）

`Preferences/Resources/SettingsReference.json`：
- `schemaVersion`, `referencePackageSHA256`, `referenceBinarySHA256`。
- `titles`: root/home/actions/basic/application/selected/choose 等标题。
- `rootSections`, `homeSections`: section包含 `id`, 可选header/footer, `rows`；row包含 `id`, `title`, `kind`(switch/link/button), `available`, 可选defaultValue/destination/phoneOnly。
- `actionCategories`: id/title/available/destination，六项原顺序。
- `basicActions`: id/title/image/referenceSlot/available/actionKind；五个可用kind为screenshot/controlCenter/notificationCenter/lock/appSwitcher。
- `originalSelectedFooter`, `phaseNotice`, `excludedReferenceSurfaces`。

所有原版id只是UI身份，不能直接作为当前域的新偏好key。只有 `homescreenDoubleTapEnabled` 映射 `TapLockPreferences.Enabled`；`homescreenDoubleTap` 映射现有 `DoubleTapAction`。可用应用选择仍调用既有 `InstalledApplications` / `ApplicationIcons`。

## 组件所有权

- **父会话 / 集成者**：本合同、声明式资源及不可变来源oracle、资源合同测试、候选冻结manifest、metadata、CI runner/包核验/workflow、文档、所有Git/远程/构建操作、最终整合。
- **UI实现者**：仅 `Preferences/SettingsController.swift`、新 `Tests/ReferenceSettingsApp.swift`、新 `Tests/test_reference_settings_rendering.py`。不得修改 Sources/Shared/ApplicationIcons/Makefile/metadata/历史测试/CI。先写源码接线RED，再实现；云端相同 UIKit harness 必须使原0.1.8在新导航断言失败、当前版通过。harness只依赖公开UIKit/同一控制器/原生父类fixture，不能依赖新私有类型而让旧版无法编译。
- **历史保护适配者**：仅新 `Tests/settings_layout_baseline.py`、新 `Tests/test_settings_layout_baseline.py`、新 `Tests/release_contract.py`，以及既有 `Tests/test_*.py`（不含 `test_reference_settings.py` / `test_reference_settings_rendering.py`）。不改旧normalizer模块或历史JSON；在历史断言入口显式先还原本轮授权UI/metadata，再运行原有逆变换，旧阶段变异须在还原后的输入上进行。父会话独占 `Tests/settings_layout_baseline.json` 并在最终UI完成后填写实际after摘要。

实现者不得提交、切分支、推送、触发CI、安装工具、改配置或覆盖其他所有者文件。遇到跨组件需要，返回明确需求，由父会话集成。新测试名称各自唯一。两个实现者不能将混合工作树的失败误报成自己的已完成或修改他人文件来消除。

## 验证与交付门

- 资源合同先RED→GREEN；新UI接线合同先RED→GREEN，不能声称是Swift运行测试。
- 冻结的原0.1.8生产字节受保护；本轮UI全文件重写单独以精确before文本/after摘要作可逆授权边界，不替换历史任何摘要。对缺失、重复、无关漂移做反例。
- 原有UIKit历史回归继续对明确冻结的0.1.8执行，不将其当作新UI通过；新UI另用相同新harness执行旧0.1.8行为RED及当前GREEN，覆盖两路构造、根页/Home/类别/搜索/禁用项不写、五基础+App保存返回重入、真实图标、默认和损坏配置。
- 全套Python、shell/内嵌Python/plist/JSON检查后，单独做规格复核再做质量复核；实际Apple执行和Theos arm64/arm64e构建由已授权云端完成。
- exact-SHA CI成功、内层原始RootHide包独立核验与资源/源码标记/逐切片签名检查后才交付；不合入main、不创建Tag/Release，实机仍待用户验收。
