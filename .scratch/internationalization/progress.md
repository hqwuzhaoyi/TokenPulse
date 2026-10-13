## 最终状态：10/10 complete（2026-10-13）

国际化原范围实施与验收完成：简体中文/英文覆盖iPhone、Watch、两端组件及通知。按用户偏好保留API Key、Token、OAuth等英文术语；Codex无预告隐藏行为保留。

最后Computer Use实际发现并修复Watch设置入口不可见、Corner不显示数字、Rectangular/SmartStack钱包金额遗漏及英文窄标题截断。两语Watch四种支持family与SmartStack、中文iPhone原锁屏均已在真实模拟器系统宿主查看；最新长金额两语OCR图像回归2/2通过。

最新四产品Debug签名/Release无签名构建成功，29项Platform/WatchPresentation focused回归通过，资源681键/14复数/387调用/35动态域0错误，diffcheck通过。此前798 XCTest+33 SwiftTesting完整回归及后续针对性验证保留，未把旧失败、0-test或中断日志计为通过。

VoiceOver听辨是用户明确豁免；水平swipe未获可靠工具输入、完整Watch App AX树不能导出的限制继续明确，不能声称通过。原票未将每种手势/完整树导出列为独立交付门槛；代表性跨账号、触控/滚动、设置、授权、错误恢复、大字号路径已完成。全部为模拟器证据，未作真实设备验收。

最终资料：[验收摘要](10-final-acceptance-summary.md)、[最新构建与回归](final-rect-validation.md)、[Watch真宿主](09-watch-final-host-check.md)。未提交Git、推送、安装真机、上传或发布TestFlight。

以下各阶段记录为历史，旧in-progress/未验状态不代表当前结论。

## 最终验收收敛（2026-10-13 18:59）

01—08 complete。09全部新增Watch两语真宿主已补齐：Circular/Rectangular/Corner/Inline与SmartStack；实际发现的Corner丢数字、矩形钱包缺金额及英文标题截断已修复并真宿主通过。中文iPhone锁屏已在前轮通过。最终四产品Debug/Release构建与29项Platform/WatchPresentation focused回归通过；最后两语长金额OCR可视回归正在独立776运行。09/10待此最后结果收口。证据见 [Watch最终宿主](09-watch-final-host-check.md)，此前未验描述作为历史保留。

## 最新原范围验收（2026-10-13）

08已按原票范围关闭，当前01—08 complete（8/10）。已通过真实不同账号页/刷新/设置/授权/长名大字等路径；水平swipe未测和完整App AX树不可导出仍如实单列，但原票未要求逐种手势或完整树导出，不增设额外阻塞。09正修复真实Watch Corner和SmartStack遗漏，10的静态汇总已完成，正式收口等09。

## 当前补验状态（2026-10-13 14:02）

Computer Use 已完成更多真实模拟器交互：修复Watch设置gear不可见（显式topBarTrailing），两语设置/账号选择/退出演示、错误恢复及最大字号纵向滚动均通过。中文iPhone原锁屏三family已通过；Watch真实系统模块表盘Circular/Rectangular中文显示已通过。详情见 [本轮续验](08-09-cua-continuation.md)。Watch真实表盘亦已观测正常快照从36%更新到54%。工具栏修复的Debug签名/Release无签名Watch专用构建通过。横向分页、App完整内部AX及Watch其他语言/形状宿主仍缺证据，VoiceOver继续按用户豁免。当前仍7/10 complete，不把模拟器测试称为实机测试。

## Computer Use 已部分恢复（2026-10-13）

本轮补验 Watch 两语空状态→演示、滚动→刷新、两语设备码授权开始/打开（无网络fixture）/取消返回，均实际点击并查看结果。详情见 [重试记录](08-cua-recheck.md)。分页/设置/表盘、完整内部AX和中文锁屏仍未通过，VoiceOver继续豁免。当前仍7/10 complete；以下历史“完全无触控能力”描述被本轮证据部分更新，不能视为最新状态。

## 最新状态（2026-10-13 用户豁免）

2026-10-13 用户明确指示“跳过这个”，豁免本轮 iPhone 与 Watch 的 VoiceOver 实际听辨及语音导航验收。此项记为用户豁免，未执行、未声称测试通过。已完成的辅助功能标签/AX 检查保留；不豁免普通 Watch 触控、Crown、滚动、表盘宿主或最终中文锁屏复验。

01—07 complete（7/10）；02、05仅因实际 VoiceOver 验收未完成而保留的阻塞已解除。08仍需 Watch 普通交互/完整AX验证，09仍需 Watch 表盘及最终中文锁屏复验，10等待这些剩余验收。产品代码未因本次豁免更改，没有新增测试执行、提交或发布。以下收尾摘要和历史记录以本段范围更新为准。

## 当前摘要（2026-10-12 收尾）

01、03、04、06、07 complete。02 添加/保存/索引与大字号界面、05设置开关/取消/原生正文滚动两语均有真实UI通过及图/AX证据；实际VoiceOver听辨单列待设备。07已实施，70 XCTest+12 SwiftTesting函数全绿；原Home两语7场景共14 UI已分轮全部通过，14图已全部查看，最大字公告/预测4 UI通过、8图全部实际检查。08全部可视修（Gauge、footer、modal大字、验证码单行）已重验，真实Watch tap/crown/scroll/完整AX/VoiceOver待设备。

09真实extension EN/ZH Small/Medium与native资源receipt已确认；最终中文footer数字/单位/compact日期完整。完全新iOS26.4自有环境实际组件正常绑定Claude，entities requested/resolved与selected配置DE2一致、真实phone.timeline；同一补漏signed包ZH→EN→ZH实际显示与ID保留全过。旧26.5 cached contexts环境失败保留，不归因未证OS唯一原因或改默认账号。DEBUG Main多余Intent/provider metadata已剔除，仍不归因未证因果；临时query/config probes已清（rg0），剩余DEBUG原生fixture/receipt与正式Release边界已验证。

09最终英文真实Small绑定1 UI/0fail已确认Claude45/80/33%完整；可视边界发现的small标题/持续补充与inline fit最小修复已冻结，已重建通过；26原生renderer UI0fail，逐张图审确认inline/continuous修复，但wallet长Decimal/USD、EN exhausted标签与failure footer已最小修复并10 UI/10图实查全部通过。真实Watch钟面与VoiceOver听辨缺口仍单列。

真实锁屏Circle/Rect选择Claude并保存激活后45%及window/reset已实际查看；inline宿主HStack只显示name的新缺陷已改singleText，最新Debug/Release构建及2双语renderer UI/2图全绿，actualinline最后包复验2UI/2图已通过，真实顶部Demo · Claude 45%完整。

最新资源681 key（04最后credit补漏已合并），signed/unsigned四产品构建均曾成功。全量旧行为781 XCTest+18SwiftTesting全绿；06–09后续4断言修复获focused101全绿；07后续70 XCTest+12SwiftTesting全绿。原失败、0-test、打断日志全保留不计绿。10仅按父代理新指示做只读完整性预检准备，未伪标正式验收/complete；独立可执行工作继续。未提交、推送、发布、测试实机或TestFlight。

以下为按时间保留的历史记录，旧 in-progress / failed 条目不代表当前状态。

# 实施进度

01、03、04 complete。06（通知）与09（两端Widget）已按依赖 in-progress；02、03、05 源实施与翻译 ready，行为测试通过，补充可视验证 in-progress。首次集中四目标build通过；02中英真实UI路径通过。全量行为回归已通过：781 XCTest +18 SwiftTesting，签名宿主0失败；源码与native资源构建通过，票02—05剩补充可视验收，尚不宣称02—05 complete。负责人：Sol 国际化实施代理。

文件归属：负责人独占 Localizable.xcstrings、共享 Localization 支持、project.pbxproj、ContentView 首页基础、工单索引与集成验证。01 完成后按依赖分派：02 Provider/API Key；03 授权；04 共享额度展示；05 设置同步。各代理只写分派的源文件，翻译条目提交独立 JSON 片段由负责人合并，禁止修改工程和共享资源。06/07、08、09 在各自依赖完成后领取。

保留开始时全部未提交改动，尤其 Codex 无有效预告隐藏整块。未提交或发布。

## 01 证据（进行中）

- `01-build.log`：四个产品目标无签名 Simulator 构建成功，四目标均有 CompileXCStrings。
- `01-tests-retry.log`：DemoMode 场景5项通过，包含 zh-Hans/en/fr fallback、账号与窗口身份和36%演示值不变；首次测试被手动停止以串行重启模拟器（日志保留）。
- `01-tests-final.log`：增加显示名与自定义名称边界后重跑。
- 术语：zh-Hans 操作/指导中文，API Key/Token/OAuth/Provider、品牌/模型、用户输入原样。使用原生 Bundle / String Catalog；L10n 仅为现有共享展示的查询适配，不存储/同步语言。
- 可视截图仍在等待测试完成后重新获取，启动空白画面不计通过。

## 01 complete

四目标build成功，5项DemoMode测试成功，中英文首页/详情/空状态与最大辅助字号UI测试均有真实点击和截图证据，详见01票。清理只涉及本代理启动的挂起xcodebuild/simctl；未动其他用户进程。

## 下一批文件归属

- 02：UI/AddAccountView.swift、Domain/Models.swift **Provider/Region段落**、Provider选择相关既有测试。Models.swift整体写入由02代理负责，其他代理不编辑该文件。
- 03：UI/ProviderSignInView.swift、GoogleNativeOAuthLoginView.swift、StepFunSessionLoginView.swift、CursorSessionLoginView.swift、JetBrainsImportView.swift、Application/NousDeviceLoginModel.swift，以及授权流程相关文件和测试；不编辑Models/AccountSettings/AddAccount/Watch视图。
- 04：UI/QuotaFormatting.swift（保留L10n原接口）、UI/QuotaViews.swift、Platform/WidgetSnapshotStore.swift、DemoMode仅展示支持与额度展示相关测试；不编辑Models/Providers查询或持久化身份。
- 05：UI/AccountSettingsView.swift、Application/AppRuntime.swift、QuotaMonitor.swift与设置/同步相关应用自有错误展示；保留Codex现有改动。
- 负责人：xcstrings/pbxproj、所有片段合并、ContentView主页/Codex票整合、scratch UI harness、串行构建/模拟器验收。代理提交fragments/<ticket>.json键值中英条目，不直接写共享资源；新增Swift文件由负责人加入目标。

## 03 in-progress

负责人：授权流程实施代理。覆盖设备码、Google OAuth、Claude/通用网页组织选择、Cursor、StepFun 和 JetBrains 导入。源文案与翻译片段进行中；整合测试与可视验收前不标完成。

## 05 in-progress

负责人：设置与同步实施代理。AccountSettingsView/AppRuntime/QuotaMonitor/CloudAccountSyncStore 源与93条翻译片段 ready；扩展既有设置恢复、凭证清理及同步失败重试场景覆盖 zh-Hans/en。已做语法/片段检查，实际构建/测试与两语 UI 验收待负责人串行整合，见 `05-evidence.md`。保持原有 Codex 无预告隐藏与演示/真实数据隔离。

## 集中验证当前状态

- `02-05-integration-build-final.log`：四产品build成功。
- `02-ui-en.log`/`02-ui-zh.log`：各真实执行1 UI test并通过，Provider目录/中文别名/Key表单/用户原文；截图已导出查看。index拖动尚待增强验收。
- `02-05-behavior-tests.log`：TEST FAILED，测试尚未运行；CopilotProviderTests async非Sendable闭包跨隔离边界编译错误。已由04将withLanguage async方法修为继承caller actor，独立typecheck `04-isolation-typecheck.log`成功；全量重跑待启动（与03 UI串行）。
- 03 Debug-only auth fixture路由已整合，无真实网络；Google初始页英文UI验收进行中。
- 共享原生catalog当前563 key，native xcstringstool compile成功。

- `02-05-behavior-tests-retry.log`：TEST FAILED仍在编译；负责人新增DEBUG只读quota fixture错误赋值let resetsAt，已移除，保留源timestamp、仅日期precision。正在第三轮全量重跑；未计任何测试成功。

- `02-05-behavior-tests-final.log`：TEST FAILED在DEBUG fixture另一let字段resetDatePrecision赋值；负责人已改为QuotaWindow initializer完整构造只读日期精度fixture，不改Domain mutability。第四轮`02-05-behavior-tests-verified.log`启动。前三轮都未计测试成功。

## 全量行为验证通过

`02-05-behavior-tests-signed.log`：781 XCTest +18 Swift Testing、0 failures，TEST SUCCEEDED。签名Simulator正确Keychain entitlements，不删/skip既有测试。03新增JSON请求测试按解码全字段严格比较修复无序bytes脆弱断言；04 native Locale.Components分离翻译语言/区域，96条runtime烟测与新矩阵通过。原失败日志均保留。

## 04 complete

最新18 XCTest+11 Swift Testing focused通过。14中英quota真实UI test通过，图/树已看；可视发现的Demo Xiaomi遗漏metadata修复后1个hybrid UI重验通过。04依赖已解除，06与09可领取；08等待03完成。资源/工程继续负责人独占；06 Notifications文件，09两Widget目录。

## 06 in-progress

通知实施代理已完成本地化文案、未来pending内容变更替换与激活前缓存重排；17条片段和既有NotificationTests中10项新双语/恢复场景 ready。语法与diff检查通过；中央签名构建/行为测试及UI验收待执行，详见 `06-evidence.md`。保留07 Codex既有逻辑与所有通知ID/ledger去重身份。

## 03 complete

所有授权behavior范围包括799全量绿。Google/JetBrains两語各1UI成功，设备码错误native测试定位后两语2UI绿并真实copy/open/recovery/cancel；6代表图/树全部已看，原失败轮保留未计绿。08依赖03/04已解除，可领取Watch。

## 08 in-progress

Watch完整流程实施代理负责TokenPulseWatch源、独立Watch展示行为测试及fragments/08.json；共享资源/工程/Simulator由负责人串行整合。复用03授权、04共享展示，保持Watch独立查询与本机语言，未提交/发布。

## 当前依赖进展

03/04 complete；06 source17条+10 tests、08 source40条+3tests、09 source34条+4tests ready，629 catalog keys合并。06保护旧计划的generic fallback不放宽取消门槛，future pending身份/history不变。02两語index真实tap C/drag Z断言+alias/input均过（02-ui-index.log 2tests0fail）；还补隔离mockClient UI form Save成功以完善动作证据。05 settings UI待收尾。`06-09-integration-build.log` 无签名四目标正在构建。

## 最新原生 UI 进展

02 原生中英 direct/gateway 4 个 Save 成功场景通过，4 张图已看。05 原生 Switch 行包含内部 Switch，确认页为系统 compact Sheet、没有单独 Cancel，按真实控件继续强断言重验；只读核查未发现配置写入丢失。06 中文真实通知中心标题/完整正文成功且图已看；英文系统合并多条自动 Demo 告警，示例提醒藏于组内，当前仍未通过，不以通知提交反馈替代真实通知证据。

## 06 complete / 07 in-progress

06行为101 focused全绿，两语真实系统payload实际查看；中文demo通知UI绿，英文quota通知图完整title/body已看，英语demo-specific系统group定位失败保留为自动化限制。07已正式分配原04实施代理，仅Codex source/preview/wrapper/tests；禁止改06其他通知与ContentView DEBUG fixtures，共享资源负责人整合。02最大字header发现挤压，已做 accessibilitySize竖排最小改；首次增量build Swift typecheck复杂表达式失败，已拆私有label/layout，修后build进行中；旧失败保留。

## 07 checkpoint / 最新真实大字证据

07产品source parse绿已冻结，24条资源整合后catalog653，`07-widget-entitlements-build.log` signed Simulator四产品BUILD SUCCEEDED。09用新带AppGroup包重验绑定，旧unsigned无AppGroup关联不计产品失败。02中英最大字provider目录/form源码修后图与AX已实际看，中文最终`02-ui-large-zh-final.log` 1test0fail。05最大字原生popover真实scroll后正文最后句可读；English actual quota独立UI58.780秒过且系统图/完整payload已看。普通字号已恢复large；actualVoiceOver音频仍未做。08最终两语最大码单行已实际看，真实Watch tap/crown/scroll/AX/VoiceOver仍未过，08与10继续保留待验收。

## 07 / 09 最新证据

07 `07-native-behavior-verified.log` 70 XCTest+12 SwiftTesting函数全部绿；原Home实际14 UI中公告/预测/empty/history/expired两语10case绿，10张图已全部看，4刷新动作正重验（保持原失败）。09真正appex中文small/medium最终文字2 UI绿；configuration trace证明实际收到空accounts数组、82份synthetic快照可用，不是共享数据缺失或仅文案未刷新，继续native配置提交诊断。DEBUG Main metadata多余intents/providers已剔除，不归因未经证明；整个工作树保留。

## 覆盖预检发现并修复中

653资源自身译文/签名与plural完整，但生产字符串来源仍有遗漏：ElevenLabs字符/Amp小时/Antigravity未知类型unit、Manus恢复额度、DevPass按量计费与xAI app-owned团队<ID>、Demo自有Gemini模型组/Aixy共享scope、ProviderIntegration错误key。04重新in-progress补漏，不把原14 UI通过当全Provider覆盖；typed可选provenance保护真实brand/model/raw input，原name/unit/scope/IDs不改，旧JSON兼容。10仍只读预检准备，未知值/第三方原文不全球replace。Release四产品预检BUILD SUCCEEDED，后续补漏后再复验。

## 04 supplement complete / 最后构建基线

125XCTest+22Swift focused、798XCTest+33Swift全量0fail，credit追加后74XCTest+19Swift focused0fail。16 producer-backed两语UI全过（两个characters原locator失败已正确ratio重验），16图全部真实检查；Manus追加2UI/2图确认EN1credit、2/3credits。资源681，DEBUG config/query probes已清并恢复query直接body，Main无多余Intent metadata，最新final-signed稳定包交09最后Sonnet数值/foot重验。09正常绑定同包ZH→EN→ZH DE2实际显示+解析ID不变全通过，实际lock-screen families继续；main共享native renderer边界矩阵26case执行中，不冒充extension runtime。

## 最终视觉与Release

final-release-four-target-build.log 最新681资源/credit修/临时probe清理后的Release四产品BUILD SUCCEEDED。04补漏完成，最后1credit/2credits native EN图确认。09共享renderer26UI0fail、图审仍发现极窄文字fit问题：inline尾部单位、small continuous行与Exhausted标题；修复中，不用AX完整掩盖可见省略。DEBUG standalone wrapper补模拟WidgetKit home16pt margin以免无host造成圆角clip，仍不当真实extension证据。actual09最后包数字与锁屏宿主由原02代理继续，设备听辨/Watch输入缺口见device-acceptance-gaps.md。10只读ready检查681keys/14plural/35variable finite域0error，不伪标正式收口。

## 09 最小 fit 最后复验

`09-fit-final-signed-build.log` Debug签名四产品、`09-fit-final-release-build.log` Release无签名四产品均 BUILD SUCCEEDED；最终包 `/tmp/tokenpulse-i18n-fit-final-signed.app` 已交09实际宿主代理。新26场景共享renderer UI执行中，最终截图尚未判定。覆盖脚本重新运行681资源仍0error；无发布/提交。

09 第二轮26 UI全绿与全部26图已分工实查，新的wallet/exhausted/footer可视失败保留并修复中；未以完整AX或断言绿掩盖。真实final EN Small 1 UI0fail，45/80/33%、Weekly Quota、Next Reset与Updated均实际可读。

最后wallet/footer/exhausted最小样式源已冻结；`09-wallet-footer-signed-build.log` 与 `09-wallet-footer-release-build.log` 四产品再次均 BUILD SUCCEEDED。最后10受影响native UI开始复验，覆盖预检仍681keys/14plural/35有限域0error。

09最后10受影响UI0fail，负责人4wallet/exhausted图+05独立6stale/dateOnly/continuous图/AX全部通过，所有新发现可视问题关闭；实际extension锁屏继续，Watch钟面缺口单列。既有Platform行为正在最后源复核。

最终源 `09-final-platform-behavior.log`：既有Platform 26 tests/0fail TEST SUCCEEDED；最新Debug签名与Release无签名四产品成功，未提交或发布。

09实际锁屏当前已完成Circle/Rect真正Choose→Claude→Close，原生AX Demo · Claude及chosen图已实查，两轮2UI0fail；inline进入系统Choose Widget表。尚未Done/真实锁屏数据final，不提前标宿主绿。

真实iPhone锁屏圆形/矩形45%+window/reset已实查，inline发现HStack宿主仅首Text后改singleText；最新 `09-inline-native-signed-build.log`/release-build 四产品绿，2两语renderer UI/2图实查绿，actualinline宿主最后包复验继续。

## 最终可执行实施收尾

`inline-native-final-host-en.xcresult` 真宿主2UI/0fail，两图实际查看：顶部锁屏Demo · Claude45%完整，圆形与矩形保持45%/原window/reset；最后同签名包正常Small45/80/33%、WeeklyQuota、Updated完整，新footer不溢出。同contexts/AppGroup32DA/82Demo保持、没有DEBUGfixture/旧probe。已发现所有source/共享renderer/真实iPhonehost问题均修复；原失败证据保留。英文锁屏实测范围明确，中文锁屏未单独复验。

01/03/04/06/07 complete。02/05剩VoiceOver真实听辨；08剩Watch真实输入/完整AX/听辨；09剩真实Watch钟面及上述设备边界；10仅ready只读覆盖准备，不在依赖与设备证据缺口下假签。最后全部源Debug签名+Release无签名四产品成功，平台26/0fail、681资源/14plural/35动态有限域0error。最终稳定包`/tmp/tokenpulse-i18n-inline-native-final-signed.app`，未提交/推送/发布，未测试实机或TestFlight。
