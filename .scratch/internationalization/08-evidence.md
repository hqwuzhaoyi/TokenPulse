# 08 Watch完整流程实施证据

状态：in-progress；Watch源、40条翻译、新行为测试ready，待中央构建/XCTest/真实WatchSimulator可视与操作验收。未提交、推送或发布，未独立启动xcodebuild/模拟器，未声称实机验收。

## 实施范围

- `TokenPulseWatch/WatchAccountPagesView.swift` 本地化导航、空状态、Demo动作、表盘账号设置、选择状态、额度与钱包、缓存错误、刷新与设备授权入口。
- Demo名字仅使用共享 `L10n.demoAccountName`；用户账号名原样显示，并移除单行截断，允许在小屏按内容换行。
- 窗口名/scope、状态与单位复用票04 `L10n.windowDisplayName`、`QuotaFormatting.quotaStatus` 和 `count(value, window:)`。未知服务单位、品牌、组织名与model名不作为翻译键。
- Decimal counts沿用Decimal完整精度，不转Double；总量/预算标签复用 `QuotaFormatting.totalLabel`，不把普通Token/request总量写成预算。
- Gauge百分比用原生percent格式；VoiceOver读取完整本地化窗口名与usage（exhausted/unlimited等状态），不拼硬编码百分号。刷新中有可读的“正在刷新”状态与本设备查询提示；账号选择checkmark不单独朗读，行包含selected/unselected状态。
- 采集时间为完整本地化短语、仍按本机日期格式；下次事件复用共享date-only精度处理，不补午夜、不更换时区语义。
- `TokenPulseWatch/WatchNousAuthorizationView.swift` 补本机授权指导、等待、动作和辅助提示。授权码和URL原样；码具有“授权码”label与原值。没有新增复制按钮或账号管理能力。
- `fragments/08.json` 40条zh-Hans/en；已有共享条目采用当前catalog canonical英文。没有写catalog、工程、sharedModels、QuotaFormatting或WidgetSnapshotStore。

## 新外部行为测试

新文件 `TokenPulseTests/WatchPresentationTests.swift`，需负责人仅加入iOS XCTest target；无新产品target文件。

1. `testWatchCacheUsesItsLanguageWithoutRewritingAccountsCountsOrDateOnlyBoundary`：LocalAccountStateStore保存/恢复同一服务状态，zh-Hans/en界面读取本机资源，完整Decimal值、date-only边界、accountID/name、窗口id与未知模型/scope/unit/原文状态保持原样；原持久化archive不被显示语言改写。
2. `testDifferentPhoneAndWatchLanguagesPreserveIndependentNousAuthorizationChains`：phone zh-Hans、watch en的同一用户/组织仍是同一logical identity，但access/refresh Token与ownerDeviceID链独立；Watch拒绝phone授权链，切换Watch为zh-Hans后凭证编码不变。仅复用Nous现有校验，不更换请求、回调或授权架构。
3. `testWatchDemoRefreshAndFavoriteSelectionRemainLocalAcrossLanguages`：Demo monitor本地刷新在两语言下成功，无真实凭证，维持服务账号身份和isWatchFavorite；重启后cache与关注设置正确恢复。

已有NousPortalTests、JetBrainsProviderTests、DemoModeTests、QuotaDatePrecisionTests及票04的共享格式化测试继续承担原行为回归。PlatformTests由票09独占，本票没有编辑。

## 已执行检查

- 修改的3个Watch Swift文件和新测试 `swiftc -frontend -parse`通过。
- `git diff --check -- TokenPulseWatch TokenPulseTests/WatchPresentationTests.swift`通过。
- 片段JSON解析与Watch中文应用字符串比对：40条、无遗漏；混合语种长fixture账号名按用户输入边界排除。
- 这些检查不等于XCTest/typecheck或Watch UI验收，后续真实结果由负责人记录。

## 无秘密真实WatchSimulator验收方案

负责人创建独立专用小屏WatchSimulator（新watchOS26.5 runtime），不擦除用户旧设备数据；中央串行build/install/launch。

Bundle：`com.tokenpulse.app.watchkitapp`。

Debug-only启动参数：`-TokenPulseWatchFixture demo|empty|long|error|nous|jetbrains`。

- `demo`：Claude、DeepSeek钱包、Codex、Nous、JetBrains与ZeroGPU sample账号；左右分页、滚动、Refresh、Complication Settings、选择账号、返回都使用真实产品View。手动Refresh仍通过DemoQuotaClient，不发Provider HTTP。
- `empty`：专用runtime suite没有真实账号；查看空状态，点击Try Demo进入本机样本。后续Exit Demo回到原空runtime，云同步关闭。
- `long`：第一Claude账号名字固定为“我的工作账号 / My very long Claude workspace Ω · 研究团队”，必须两语言保持原样并能多行显示。
- `error`：同样cached data + invalidCredential；检查本机错误恢复指导与旧缓存可读，点击Refresh后Demo查询恢复成功。
- `nous`：直接sheet显示真实WatchNousAuthorizationView，点击Start Authorization后真实NousDeviceLoginModel走Watch-local纯内存HTTP stub，TEST-CODE / portal.nousresearch.com / waiting；OpenURLAction处理原生Link，实际无外网；Cancel关闭，保持原账号未保存。
- `jetbrains`：直接sheet显示共享JetBrainsImportView，只有指导与空SecureField，导入动作禁用。不要输入真实export。

每种mode只清理和写入固定`com.tokenpulse.tests.watch-i18n.<mode>.runtime/demo/widgets`三个专用suite。Root绕过真实通知授权与runtime.start自动查询，只加载monitor.start(refresh:false)；activation自动刷新在fixture关闭。WatchWidgetSelectionStore也注入专用widgets suite，不写标准或真实app-group选择值。

语言与区域可通过原生launch参数设置：`-AppleLanguages '(en)' -AppleLocale en_US`或`-AppleLanguages '(zh-Hans)' -AppleLocale zh_CN`。没有自建语言选择器或从Phone同步语言。

可加`-TokenPulseWatchLargeType`，仅Debug fixture View使用native `.dynamicTypeSize(.accessibility5)`，不改Watch系统偏好。无fixture参数时生产启动、通知请求、后台刷新与默认selection store完全沿用原行为。

建议两语言至少查看首页/额度/钱包、空状态、长名字与大字号、设置/选择、Nous等待与取消、JetBrains指导，检查scroll与tap目标、可见长英文是否断行及VoiceOver labels/values。截图应使用实际WatchSimulator画面，不用iPhone模拟Watch外观，也不将屏幕截图代替真实触控验证。

## 待中央验收

负责人添加新test target文件、合并40条资源、构建Watch/全产品；运行3新XCTest与已有Watch独立授权/缓存回归；记录专用WatchSimulator screenshots、操作与辅助功能检查。通过前保持08 in-progress。

## 2026-10-12 真实WatchSimulator补充

专用SE3 40mm/watchOS26.5设备8FE5402A...实际安装和launch/screenshot成功。两语12个baseline fixture截图及初始demo/Nous图均经view_image查看，详见`08-ui/README.md`、`capture-results.json`与png。真实图发现Gauge名称截断/贴边、英文empty动作位于viewport下方，已最小源修（标签换行/8pt边距、empty native ScrollView），中央重编后需重拍确认。DEBUG增加nous-waiting和error初始视口定位，仅state可视，不算真实触控。

本机未提供可用Watch tap工具；native HID所有发送返回machPortInvalid，无点击成功，并在端口连接试探观察到服务中断后立即停止。只boot恢复自身Watch，无其他设备擦除/停机/权限变更。触控、VoiceOver听辨与完整树检查仍是明确待验收缺口；不能用model测试或截图冒充。已给出不依赖机器私有接口的可复现人工步骤，原失败保留。

新版`/tmp/tokenpulse-i18n-watch-verified.app`成功安装后，14条实际launch/screenshot均0返回并全部view_image检查。Gauge完整名称/圈边距修复确认，中英同36%；Nouswaiting code/OpenAuthorizationPage/host确认真实model+stub状态。另两项未过：outerDebugReader未定位穿过TabView到error footer；waiting modal normal/large字体同尺寸，不能计modal大字号通过。`08-ui/README.md`及`capture-verified-results.json`详录，source未进一步改变，待负责人决定最小fixture修正/验收缺口处理。手动tap/scroll、AX树和VoiceOver听辨仍未完成。

## DEBUG fixture最小修正ready

在负责人明确授权后，仅改两个Watch文件：`WatchAccountPagesView.swift`添加#if DEBUG accountFixture factory，直接复用原私有WatchAccountPage与原monitor.refresh，没有复制业务/文案；`TokenPulseWatchApp.swift`的error fixture使用观察同一monitor的直接page+内层ScrollViewReader，移除无法穿过TabView的外层定位。Nous/JetBrains Debug sheet Group显式应用与root相同的fixtureTypeSize；无flag仍系统字号，无fixture/Release仍原production启动。

3个Watch源swiftc -frontend -parse通过，Watch diff --check通过。未启动build/simulator/HID，新source已冻结交中央重编，真实footer/modal大字结果仍待新版截图，未提前标过。

## 最新中央行为验证

`06-09-focused-recovery.log`：101 XCTest、0 failures、TEST SUCCEEDED，实际包括 NotificationTests、CopilotProviderTests、PlatformTests、WatchPresentationTests、QuotaMonitorTests、DemoModeTests。已有四个旧文本断言修复确认通过。对应产品 UI 缺口继续独立记录，行为通过不等同于完整可视验收。

最终包00:33:41包含DEBUG两项修正，6条实际launch/screenshot均0并全部view_image看过：两语errorFooter/采集时间/刷新按钮确认可见；普通/最大Nous等待modal的字级差异确认生效。最大字code字符未丢但跨行，负责人批准新增单行minimumScaleFactor(0.5)，仅WatchNousAuthorizationView原Text展示，不改原码/a11yValue/授权链；源parse/diff绿，等待中央下一包重拍极大字。没有新HID/触控尝试，manual触控/scroll、AX树及VoiceOver听辨缺口仍如实保留。

## 最后验证码极大字复验与报告冻结

中央提供`/tmp/tokenpulse-i18n-watch-code-final.app`（dylib00:50:34），本代理仅专用Watch安装并两语maximumType Nouswaiting launch/screenshot，2项各0返回；两图均实际view_image看过，TEST-CODE完整单行无截断。路径：`08-ui/code-final-en-nous-waiting-large.png`、`08-ui/code-final-zh-Hans-nous-waiting-large.png`；命令/进程证据：`capture-code-final-results.json`。最终可视确认Gauge名称/圈边距、两语errorFooter、modal大字、code单行缩放修复。报告已冻结，未再build/私有HID。

触控、crown/swipe/真实scroll、选账号/Demo切换/刷新/打开/取消实际动作、完整AX树及VoiceOver听辨仍明确未过；真实图与programmatic viewport不冒充这些验收。中央决定08/10票状态，本代理未自行将08标complete或抹去原失败。
