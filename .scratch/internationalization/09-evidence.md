# 09 实施与验证证据

状态：in-progress。源实施与最新 Debug/Release 四产品构建、26 平台测试、26+10 双语共享 renderer UI及实际图审均通过；真实 iPhone extension Small/Medium、绑定及同包语言重载已有证据。实际锁屏配置/宿主验证继续，真实 Watch 钟面验收缺口单列，尚不记 complete。以下为完整历史与最新追加。

已改源：

- `TokenPulseWidgets/QuotaWidgetContent.swift`、`QuotaWidgetIntent.swift`、`TokenPulseWidgetsBundle.swift`、`TokenPulseWatchWidgets/TokenPulseWatchWidgetsBundle.swift`。
- 新 `TokenPulseWidgets/WidgetContentPresentation.swift`：请负责人加入 main app、iPhone widget、Watch widget 三目标。Content/Intent 可同时加入 main app 给 Debug harness 复用真实 renderer；预览已移至各 WidgetBundle 文件，避免 main app 引用 extension @main。
- `TokenPulseTests/PlatformTests.swift`：既有测试不删除/skip，追加四项本地化/身份/状态/fixture family 测试。
- 资源片段 `fragments/09.json`，34 条。共享 Models/QuotaFormatting/WidgetSnapshotStore 只读，未改共享 catalog/工程。

展示行为：

- 原生 Widget/Intent 显示名、描述、参数、推荐、实体选择、占位示例、空/未配置/未同步、待更新及失败状态纳入双语。
- Entity 的 `id/name/providerName` 原字段/绑定不变；displayRepresentation 仅对已知 demo ID 的原样 sample 名和已知 Provider 旧名称进行当前语言展示，未知名称保持原文。
- 每个 family 沿用04 `WidgetAccountSnapshot.displayMetrics` 与共享额度/单位/日期/货币/计数逻辑；所有界面中的 demo 名复用 guarded helper，自定义名保持原文。
- resetCount 复用 `%lld 次` 原生 plural；百分点使用 native percent。保留 Decimal 钱包值和币种，不换汇。
- 紧凑 timing 无事件时复用 nextEventLabel/Value，持续补充/无周期不再伪称“重置 未提供”；日期精度仍共享 raw day boundary。
- 首次刷新失败区别于存在旧数据的刷新失败；quotaStatus 按 provider ownership 显示。Circular/corner 用短图标表明待更新或失败，完整状态由 VoiceOver说明；inline/rectangular 也显示紧凑状态。

已实际运行的静态检查（2026-10-11）：

- `xcrun swiftc -frontend -parse TokenPulseWidgets/*.swift TokenPulseWatchWidgets/*.swift TokenPulseTests/PlatformTests.swift` exit 0，只证明语法。
- `git diff --check -- TokenPulseWidgets TokenPulseWatchWidgets TokenPulseTests/PlatformTests.swift` exit 0。
- JSON parse + 全34条格式签名匹配；widget源应用自有中文字面量在09片段或既有catalog中均覆盖。保留的 quota window 原名称/索引身份、DEBUG user-name极值fixture不作为翻译key。
- 未独立启动 xcodebuild、模拟器或真实小组件。此时未宣称类型检查/测试/UI通过。

新增测试（尚未执行）：

1. 三种语言 zh-Hans/en/fr fallback 的三个 empty state 与 saved entity display，自定义 name/未知provider名原样和demo显示不改原字段。
2. 0/1/3 reset plural、待更新、失败原因/旧数据保留说明以及首次失败不制造旧数据。
3. 持续补充、2026-09-01 日期精度和 points 非货币余额语义。
4. DEBUG 10个场景×single/medium/large 的 entry 结构、wallet无ring、持续补充无reset、day precision不误判到时恢复。这是main-host共享逻辑测试，不是extension运行证明。

DEBUG fixture / 实际 extension 验证接口：

- Fixture renderer：`QuotaWidgetView(entry: WidgetDebugFixture.entry(scenario: ..., family: ..., date: ...), familyOverride: ...)`，familyOverride仅DEBUG可选参数。SDK widgetFamily环境key只读，不能用 `.environment` 写入。main截图可外加 `.background(.black)` 与 frame。
- Native family 对应 single/medium/large 为账户数上限1/2/4；锁屏/circular/rectangular/inline和Watch表盘family均用single。
- Scenario：`quota`, `wallet`, `empty`, `unselected`, `missing`, `stale`, `replenishment`, `dateOnly`, `longName`, `exhausted`。
- 真实extension请求：只在 DEBUG 写 App Group UserDefaults (`PlatformConstants.appGroupIdentifier`) 的 String key `debug.widget.fixture`=scenario；可写`debug.widget.expectedLanguage`记录期望。此语言字段不覆盖Bundle或翻译，实际extension语言仍由系统/应用选择。
- 添加/配置真正 WidgetKit widget、或reload其timeline；实际 extension snapshot/timeline provider调用会写 Data(JSON) key `debug.widget.runtime.<Bundle.main.bundleIdentifier>`。schema包含 `providerInvocation` (`phone.snapshot/timeline`或`watch.snapshot/timeline`)、`isWidgetExtension`、`bundleIdentifier`, `bundleName`, `preferredLocalizations`, `expectedLanguage`, `scenario`, `emptyMessage`, `summaries`, `timestamp`。
- 准入证据必须 `isWidgetExtension=true`、bundleName以`.appex`结束、实际extension bundleIdentifier正确且timestamp为此次运行，不能接受 main host调用的值。main `WidgetDebugFixture.entry`只构造entry，不写receipt。
- 完成后移除debug.widget.fixture/debug.widget.expectedLanguage并reload。Release无fixture请求/receipt路径。

待负责人完成：

- 合并09片段、target新增源后四产品 unsigned build；focused PlatformTests与相关既有widget regression。
- 对主屏幕small/medium/large、锁屏circular/rectangular/inline，以及Watchcorner/circular/rectangular/inline中英原生family做截图和可读性检查；长名字、大辅助字号、Decimal金额、失效/待更新、空态都应可理解。
- 正式extension启动receipt，两种语言分别验native Bundle资源；Watch独立extension同样验证，main截图不替代。
- 实际widget配置选择/保存/重开确认账号绑定不变，语种变化后系统允许的下一次timeline显示新语言，保留配置与凭证。

## 最新中央行为验证

`06-09-focused-recovery.log`：101 XCTest、0 failures、TEST SUCCEEDED，实际包括 NotificationTests、CopilotProviderTests、PlatformTests、WatchPresentationTests、QuotaMonitorTests、DemoModeTests。已有四个旧文本断言修复确认通过。对应产品 UI 缺口继续独立记录，行为通过不等同于完整可视验收。

## 2026-10-12 真实 iPhone WidgetKit QA（进行中）

独立设备：`0CEB475B-F3D3-4EE1-9538-570A67477423`，TokenPulse-09-Widget-QA，iPhone Air/iOS26.5。仅该设备改系统 AppleLanguages/AppleLocale，未动主QA Phone/Watch、Mac或实体设备。

独立runner：`09WidgetHarness/Acceptance.xcodeproj`，derivedData `/tmp/tokenpulse-widget09-harness`。只build此最小UI runner，不独立build主工程。真正SpringBoard触控：长按/编辑→添加小组件→搜索TokenPulse→原生gallery→页码切换→添加→完成。图与AX树均保留，核心图已view_image。

已成立的真实证据：

- `09-ui/add-small-en.xcresult`：实际1test通过；真正Small安装后 `receipt-en-quota-after-add.json` 是 `TokenPulseWidgets.appex`、`isWidgetExtension=true`、`phone.timeline`、native `en`。
- `09-ui/verified-native-en.xcresult`：实际2test通过，页码切换并断言 `Widget, Medium` 后真正Medium添加。`verified-en-current.png`已查看，数字63%单行/secondary对比度修复有效；该阶段reset单位仍截断，不记最终footer通过。
- `09-ui/final-native-widgets-zh.xcresult`：实际2test通过；Small/Medium新组件与原生页码均真实，`final-native-widgets-zh.png`已查看，63%、1/0次reset、compact日期及更新信息完整。`receipt-final-signed-quota-zh.json` 是真正extension `phone.timeline`、native `zh-Hans`，两个账号中文summary。
- `config-select-en.xcresult`/`config-final-signed-zh.xcresult`：各实际1test的系统entity选择操作通过，picker/已选字段截图已查看；**仅UI操作与选中展示，不算实际widget绑定数据通过**。

真实可视问题与修复链：

1. native英文Small把63与%拆两行，black backdrop下secondary变暗：数字单行缩放与.white opacity后在真正Small/Medium重验确认。
2. 英文footer reset单位截断：reset文本minScale/priority；Small时间复用既有compact，保留day/cross-year/continuous语义。ZH最终图通过，EN最终foot仍待同源重验。

未计通过的情况：

- 首轮native gallery行错误当Button、Add Widget有前导空格、StaticText不可直接hittable、旧零frame icon ghosts，均为scratch driver问题；日志/xcresult全保留。
- `add-medium-en.xcresult`虽然动作test通过，实际仍Small，图与receipt发现后不计Medium验收。后续原生PageIndicator及Widget,Medium断言明确修正。
- `config-open-en.xcresult`一次执行0tests（runner缓存），不计通过；只卸载自己的runner重装后实际执行。
- unsigned最终app安装后get_app_container groups为空；原AppGroup后来重建为EBB...，旧绑定链因此受环境变动影响，不能据此判语言破坏ID。signed包已恢复项目既有entitlements，未手改权限。

绑定诊断仍在进行，不宣称complete：

- 当前同一signed probe包 Main无AppIntent metadata；正式extension的schema是optional array WidgetAccountEntity、正确1/2/4 family sizes及TokenPulseWidgets.WidgetAccountQuery。
- freshSmall配置重开仍显示“演示 · Claude”，实际UI值持久。
- extension configuration probe收到过空array/后来的nil，同时可见82个合成快照(含Claude DE...002)。不过标准log显示多个已缓存/移除widget intentHash都在public reload时调用timeline，单一last receipt可能被旧空配置覆盖，不能未经关联判当前实例。
- `native-tokenpulse-system.log`只取该模拟器chronod/appintents相关TokenPulse消息；精确schema/serialize/decode/resolve匹配0。主要模拟器proactive.infoSuggestion缺服务4099与正常reload/throttle，并无证据足以改业务。
- 临时DEBUG精准probe标签 `DEBUG-widget09-config` / `DEBUG-widget09-query`，同AppGroup bool `debug.widget.traceConfiguration`；只记录DE/090合成UUID、数量/Bundle/locale/timestamp，不記名称或真实IDs。后续查query入参/结果、fresh snapshot/timeline及公共reload，诊断后须删两临时probe并中央final build。
- 最終EN footer、同包跨语绑定、真实配置结果，以及剩余Phone锁屏/Watch各family actualruntime验收尚未全部完成。main renderer截图/测试不能替代extension实际运行。

隔离重装记录（2026-10-12 02:19–02:24，自己 0CEB 模拟器）：

- 授权范围仅自己的 TokenPulse / own QA runner；同 `/tmp/tokenpulse-i18n-widget-query-probe.app` 重装，未修改产品 schema、权限或其他模拟器。卸载前 `before-isolated-reinstall.png` / `before-isolated-reinstall-receipts.json` 保存；旧系统日志保留。
- 新 AppGroup `34C6809D-ABFB-48AA-A55A-90145263B5C9`，native Demo 实际重写 82 个全部 DE UUID 合成快照。
- 系统在重装后恢复旧组件位置；早先 cleanup test 返回 1 pass 却没移除实际组件，截图发现后不计为清除通过。
- 新 scratch selector 使用 native icon 实际 value（中文“小组件”），`isolated-actual-cleanup-zh.xcresult` 实际 1 test 通过；`isolated-actual-no-widgets-zh.png` 已查看，主屏确无 TokenPulse 组件。此后只新建一个 Small，再核验 commit、query 和 fresh timeline。
- `isolated-single-select-zh.xcresult` 仅 native selection 动作通过；`isolated-after-selection-receipts.json` 显示 suggested query 在 extension 读取 82/解析 82，entities 没被调用，不归因解析失败；此轮未收到 post-commit timeline，不宣称绑定通过。

- `isolated-one-before-selection-zh.png` 已查看，native cleanup 后只新增一个 Small；`isolated-one-commit-zh.xcresult` 实际 1 test 选择/关闭通过。公共 reload 后 `isolated-one-after-public-reload-zh.xcresult` 实际 1 test / 1 failure（组件仍未显示 Claude），保留失败。
- 最新关联前 probe 为 02:25:05 empty array / configurationWasNil=false；`isolated-native-system.log` 显示 02:25:26–29 公共 reload 仍调用旧 3 个 intentHash / Medium，说明本隔离模拟器卸载与 native 删除并未清除这些 cached timeline contexts。不能将单一 last nil 或 empty trace 直接归当前实例，也没有 entities(for:) 实际调用证据。
- 同一 query-probe 安装包，仅自己 0CEB 语言切换 en；随后 DEBUG quota visual fixture 用于 EN 最终 footer 与实际 extension locale 验证，不能代替正常账号绑定通过。

真正正常配置绑定通过（全新 iOS 26.4）：

- 新独立设备 `DE11EC10-DE2C-4619-82E5-B60D7A06810B` / iPhone Air / iOS 26.4，旧09已 shutdown；同稳定 `/tmp/tokenpulse-i18n-widget-supplement-signed.app`，Main无intent metadata，extension正式metadata/native双语catalog在。新AppGroup 32DA65F7…。首次迁移报告失败/灰占位，重启仅该新sim后应用启动正常，未修改任何产品 schema或权限。
- `fresh264-reboot-one-small-zh.xcresult` / `fresh264-commit-one-small-zh.xcresult` 各实际 1 test / 0 failure；单个native Small、系统picker选择Claude自动返回参数页、tap outside关闭，无DEBUG fixtureoverride。
- `fresh264-one-after-commit.png` 已 `view_image` 查看，真实Small显示“演示 · Claude”45%/80%/33%、3额度窗口、3个compact reset日期与“更新于2:34”。
- `fresh264-after-commit-receipts.json` 真正 extension preferredLocalizations=zh-Hans；entities(for:) requestedSyntheticIDs=resolvedSyntheticIDs=[DE…002]，available=82；configuration.selected 独立 key 的 configurationIDs=resolvedSyntheticIDs=[DE…002]、configurationWasNil=false/count1、providerInvocation=phone.timeline/isWidgetExtension=true。正常数据绑定成立，不能再用旧26.5 latestempty盖过这条明确链。
- 旧26.5失败作为环境/历史context诊断链保留；不同runtime与freshOS同时改变，不能由新通过反推唯一根因是26.5。接续公共reload与同包EN/ZH保持ID验证。

- `fresh264-public-reload-binding-zh.xcresult` 实际 1 test / 0 failure，公共reload后的独立selected receipt `fresh264-post-public-reload-receipts-zh.json` 02:36:46 nativezh/DE…002不变。
- 同 installed supplement signed 包切系统EN，`fresh264-samepack-binding-en.xcresult` 实际 1 test / 0 failure；`fresh264-binding-en.png` 已查看真实“Demo · Claude”/5-Hour Quota/Weekly Quota/Sonnet Weekly Quota/Next Reset/Updated英文。`fresh264-samepack-binding-receipts-en.json` 新fresh02:39:06、nativeen、phone.timeline、selected/resolved DE…002完全相同，无fixtureoverride。
- 实际英文Small长Sonnet标题挤掉33%显示省略号，源仅把HorizontalMetric.homeScreenSmall无count行的layoutPriority(1)从title移至value，title保留2lines；normal/MainDEBUG parse与diffcheck通过，尚待中央最终包native重验。不能计该旧图为完全布局通过。

- 回ZH同包 `fresh264-samepack-binding-returnzh.xcresult` 实际 1 test / 0 failure；`fresh264-binding-returnzh.png` 已查看实际Claude45/80/33%、中文窗口/timing/Updated；`fresh264-samepack-binding-receipts-returnzh.json` 02:42:06 nativezh，phone.timeline/isWidgetExtension=true，selected/resolved DE…002不变。ZH→EN→ZH不换包/不变schema，正常系统语言与选择身份保留链成立。
- 诊断已完成：temporary `DEBUG-widget09-config` / `DEBUG-widget09-query` 的函数、provider/query调用和key/traceflag字符串全部源删除（widget目录rg 0）；原DEBUG fixture/runtime hook保留。此cleanup与EN Small value priority修都通过normal/DEBUG/MainDEBUG parser及diffcheck，源码冻结供中央签名最终包。
- 最终native EN Sonnet33%优先级修复可视、quota fixture Small/Medium英文完整reset footer仍需新最后包重验。Phone锁屏/Watch各family的实际runtime/系统界面证据与mainrenderer证据仍需分别记录，不能将mainpreview代替extension。

真实EN重置次数footer补验（同 supplement 包，footer源与冻结最终源相同）：

- 正常账号绑定跨语链先封存后，仅新 DE11 私有AppGroup DEBUG quota fixture开启/native EN重启；真正Small既有实例更新，之后只新增一个确定page2/Widget, Medium的Medium。
- `fresh264-quota-footer-en.xcresult` 实际 2 tests / 1 failure：Medium系统gallery页码与尺寸断言通过，inspection因scratch期望旧Claude“Weekly Quota”而真实Codex typed canonical为“Weekly usage”失败，保留driver失败；无产品翻译词语修改。
- `fresh264-quota-footer-en.png` 已查看：真实Medium/Small63%均单行；Small“Available: 1 reset”完整，Medium两栏“Available: 1 reset”/“Available: 0 resets”及Updated完整，Next Reset紧凑日期完整。
- `fresh264-quota-runtime-en.json` 真实extension com.tokenpulse.app.widgets、isWidgetExtension=true、preferredLocalizations=en、phone.timeline/quota、1/0两summary。此证据非Mainrenderer、非预览、非expectedLanguage代替native语言。
- 修正scratch inspection为fixture identity后只重跑inspection，不重复添加Medium；新priority修不在这旧包，仍待最后包Sonnet33%真实重验。

最终包正常绑定与数值优先级重验：

- `/tmp/tokenpulse-i18n-final-signed.app` 只升级一次，32DA AppGroup保持、Main无intent metadata/extension正式metadata有；在自己的group清全部debug.widget keys，82 Demo保留。首次own cold launch/runner启动超时，记录未运行tests，不算产品断言失败；仅ownDE11重启后延迟launch03:06:20已由公开system log确认，focused重验实际执行。
- `final-native-small-binding-en-retry.xcresult` 实际 1 test / 0 failure，`final-native-small-binding-en-retry.png` 已view，真正Small45/80/33%全部完整（33%从省略恢复），Updated03:08和reset日期是本次真实reload；无DEBUGfixtureoverride/旧probekeys，正常Claude选择仍保留。Medium未配置空状态英文prompt正确，不记其正常账号绑定。Sonnet标题仍省略，这个图不能算新的title缩放修通过。
- Parent另在shared renderer26cases发现标题、continuous timing、inline width fit；本agent最小新增Small标题minScale.7+tightening/2lines，noevent continuous timing直接复用原完整native“持续补充”短语，timing1–2metrics最多2lines/3metrics1line。Inline ViewThatFits完整串优先，fallback原account Text与primary值/单位/↺原生count/短原生状态，value优先缩放/fullAX仍allfields。无新翻译key/ID/data变化，源冻结/parse/diffcheck通过，等待最后fit签名包。

## 最后 fit / Decimal / footer 收尾证据

`09-fit-renderer-final-ui.log` 26原生共享renderer UI/0fail；全部26图真实分工审查，保留wallet/ENexhausted/footer尚未可读的事实。随后只改生产样式：长金额完整缩放、耗尽标题/值纵向、footer重置与完整状态分行；原Decimal、货币、账号、快照/时间/状态字段和ID不变。

`09-wallet-footer-signed-build.log` Debug签名四产品与 `09-wallet-footer-release-build.log` Release无签名四产品均成功。`09-wallet-footer-final-ui.log` 10受影响原生UI/0fail；负责人实际4图确认两语金额1,234.56789012 USD、完整标题/耗尽/重置次数/日期/更新时间，见 `09-renderer-lead-review.md`。另外6footer图原05独立复核记录 `09-renderer-edge-review.md`。这些共享renderer证据不替代真实extension宿主。

实际extension最后 fit包正常ENSmall1UI/0fail：原Claude45/80/33%及WeeklyQuota、NextReset/Updated全部完整，无DEBUGoverride/临时probe；最终footer包已提供实际宿主代理继续锁屏。真正Watch钟面仍没有验收证据，不记complete。

最终源 `09-final-platform-behavior.log`：既有Platform 26 tests/0fail TEST SUCCEEDED；最新Debug签名与Release无签名四产品成功，未提交或发布。

## 真实锁屏宿主：不能用shared renderer替代

系统Choose→Claude→Close→Done与激活壁纸已完成。`fit-final-lock-three-families-host-en.xcresult` 1UIpass；实际host图已view，circle Claude图标/45%，rect 45%/5-HourQuota/NextReset完整。public chronod log记录真实accessoryCircular/Rectangular/Inline family与nonempty相同intentHash，无临时probe。

**真实失败保留：** 初版inline实际host只显示HStack首段name，45%仅AX完整；原共享renderer图不能代表宿主通过。故仅inline fallback改一个Text，full→原name+compactvalue→极长宽度仅detail三candidate，rawname字段和完整AX不改。新signed/Release与actualinline宿主正在复验，尚不提前签通过。

真正系统锁屏宿主三family（当前fit-final包，未开启DEBUG fixture）：

- Native Notifications→长按clock→Collections Customize→Add Widgets→scroll→TokenPulse，AX明确系统Buttons value “Widget, Circular”/“Widget, Rectangular”；`fit-final-lock-add-circle-rect.png` 已view真实slot添加。未配置circular的小提示有视觉省略但AX全文，未伪造0，作为极小空状态显示边界保留。
- 动态Clock编辑/Sheet打开会把slot从y≈.79上移y≈.345，scratch坐标仅按新截图少量适配。Circle/Rect各真正Choose→Demo·Claude→Close，chosen截图与AX实际Button Demo·Claude。
- 顶部Date reticle打开系统Choose Widget，仅2次scroll找到Cell“TokenPulse, TokenPulse Quota Progress, Top Widget”，加入inline并同样选Claude，Done保存后激活同壁纸。`fit-final-lock-three-families-host-en.xcresult` 实际1test/0fail，`fit-final-lock-three-families-host-en.png` 已view真实OS锁屏：circle45%/Claudeicon；rect45%/5-Hour Quota/Next Reset。AX三family均含完整Claude45/80/33%所有窗口+日期+Updated。
- `fit-final-lock-native-extension-system.log` 是自己DE11只读public chronod log，明确accessoryCircular/Rectangular/Inline都实际调用com.tokenpulse.app.widgets/TokenPulsePhoneQuota，已配置Claude共同intentHash -659493…；hash不自行证明解码的ID数量，账号依据真实选中字段与实际数据/先前正常binding链。模拟器proactive.infoSuggestion服务4099仍出现，实际可视成功，未据此改权限或私调daemon。
- 真实inline host却只显示name，未显示primary45%，尽管main renderer HStack fallback曾全部可见：保留此host失败，不假称inline完成。最小修为ViewThatFits候选全串/单Text(name+compact primary/reset/status)/仅details单Text，raw名字字符串与fullAX不变；已parse/diffcheck冻结，并中央signed/Release四产品通过，待inline-native-final签名同contexts真实重验。

最终同contexts升级后 `inline-native-final-host-en.xcresult` 实际2UI/0fail，2图真view：顶部Demo · Claude45%完整、circle/rect原数据正常；normalSmall45/80/33%/WeeklyQuota/Updated完整、footer不溢出。无DEBUGoverride、82Demo及AppGroup不变。该最终锁屏证据为EN，ZH锁屏未独立复验；两语正常绑定/资源/共享图审另记，Watch钟面仍缺。

最后单Text签名包真实宿主重验（2026-10-12 03:50）：

- `/tmp/tokenpulse-i18n-inline-native-final-signed.app` 仅自己DE11升级、保留已有32DA group及原同壁纸/3锁屏widget/原Small contexts，无重新创建账号/widget，也未启DEBUGfixture/旧query/configprobes。中央确认Debug签名与Release四产品成功，main metadata仍排除预览多余intent。
- `inline-native-final-host-en.xcresult` 实际2tests/0failure：normal EN Small正常绑定检查及原生已保存锁屏显示。两真实图均已`view_image`：`inline-native-final-host-en-attachments/56ABC9CE-49FD-48C0-9C36-19AE6309906B.png` 的Small Sonnet Weekly Quota全文、45/80/33%及Next Reset/Updated03:50全部完整；新footer布局不溢出。`inline-native-final-lock-host-en.png` 的真正锁屏顶部“Demo · Claude 45%”全文，Circle45%/Claudeicon、Rect45%/5-Hour Quota/Next Reset同真实数据。
- 单Text fallback修复实际host曾仅显示name的失败；HStack旧host图/日志仍保留，不将Mainrenderer成功替代真host。AX仍全部Claude3个窗口/值/时间，原raw name/IDs未改。
- **准确范围：最后锁屏实际宿主只实测EN；ZH锁屏未独立复验。** 已有此前正常同包ZH→EN→ZH账号ID/实际timeline保持证明、Root两语shared renderer验证，不能混称ZH锁屏或两语全部families都真实host通过。Watch实际Clock complication缺触控验收、极小circular未配置提示有视觉省略而AX全文，两项边界继续明确保留。
- 09不假标complete；source/片段/测试与Phone上述实测已ready，ticket仍按Root保留未验证边界。工作无commit/push/publish，没有触碰父代理main776/Watch或用户设备；结束仅shutdown自己DE11（旧自己0CEB此前已shutdown）。
