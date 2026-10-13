当前状态：complete。中央focused/producer-backed原生两语可视与最终credit追加验证已完成，下文ready/待执行为历史。

# 04 补漏实施（来自 10 只读 preflight，非 10 收口）

状态：源码、资源、既有文件新增外部测试 ready，等待负责人签名整合 build/focused tests/必要的真实截图。VoiceOver 音频 runtime gap 单列，未阻止本次可授权补漏，未正式执行或标记 10 complete。

## 已先交付只读发现

`10-coverage-preflight.md` / `.py` / `.json` / 手工边界账本保存了补漏前事实。按父代理随后明确授权转为 04 源补漏；没有覆盖基线报告或重跑已完成的无关行为审查。

## 生产源与共享边界

- Domain 仅兼容扩展 typed optional presentation。`QuotaScopePresentation(kind, name, isShared)` 保留第三方/user target 的完整原文字节；`QuotaPlanPresentation.payAsYouGo/team(identifier)` 将 app 描述与真实 plan/brand 区分。旧 QuotaWindow/QuotaSnapshot/WidgetAccountSnapshot 缺字段解为 nil，显示回退原文，不清缓存、不改账号、凭证、币种、额度、重置或告警身份。
- `QuotaFormatting` 是唯一数量/单位/scope/plan 展示边界。把既有 requests/messages/GPU 数量逻辑收敛为一个闭合 QuantityUnit selector，补 fixed characters/Orb hours/未知类型与明确 app 额度单位；真实整型 native plural，不能无损用 Int64 表达的 Decimal 仍用完整 quantity phrase 分支。Double 仍最多2位，Decimal仍0...38位；现有 region/翻译语言分离 formatter 不改。
- ElevenLabs `elevenlabs.characters` + app unit `字符`、Amp `amp.orb` + app unit `小时` 仅按稳定生产 identity 识别；unknown服务/model units 与技术真实单位原样。未知类型不造 Token、币种或钱包语义。
- Manus 增加固定 app fallback“恢复额度”，不伪称 daily 或已确认重置。现有 Kiro/Notion/Warp/Bifrost/Chutes/Minimax/Aixy 等 app suffix/固定名字已沿原闭合规则复核，不扩大第三方文字匹配。
- Antigravity app 固定 amount sentinel 新标 `unspecifiedUnitType`，legacy该固定id/unit也可信解析；真实 model name用现有 presentationLabel enum 的 providerModel/modelDisabled 两个生产标记。只有明确 disabled 的最后一段 app-added“（未启用）”被包装；enabled 的真实名字即使本来同字结尾仍原样。旧 nil annotation 不猜其来源，保持原文。
- DevPass producer 新标 `.payAsYouGo`、xAI producer新标 `.team(identifier:原teamID)`，原 `providerPlanName` 字符串/窗口id/金额不变。DevPass 同时有 Key cap 时仍 `isNoPlan=nil`，没有为翻译改“无上限”语义。
- 真实 Aixy producer 用独立 typed kind/原target_name/shared 标记；raw scope 原构造完全保留。原名即使包含“共享 · 团队”也不 replace/split/查字典。明确 Demo Aixy scope与Demo Gemini模型组直接加metadata，real/legacy raw名字不全局匹配。
- QuotaViews/AccountSettingsView/WatchAccountPagesView 只把 plan 显示接共享 formatter；WidgetSnapshotStore 新存 providerPlanPresentation 并完整携带 windows descriptors，raw providerPlanName不改。
- ProviderIntegration 仅把遗漏的 app-owned web-flow操作指导改为 native key“请使用该账号专用的网页登录界面”；不改请求或控制流。
- 经父代理逐行授权，`NotificationPlanner.renderedSchedule` 的 name-semantics缓存复制增加 `presentationScope:$0.presentationScope`。随后新增升级边界授权：同time/window/identity分支在正文不变时仍把最小新notificationWindows写回ledger，不产生schedule操作；未扩大stale/missing retain资格，不改observation fence、去重、权限或周期规则。原 presentationLabel转发自动携带新的模型来源标记。

## 资源交付

`fragments/04-supplement.json` 25 个条目，其中3完整 native plural：characters、unknown-type units、明确app allowance units。Orb hours复用当前已验证的 `%lld 小时`，其非整型精确数量采用新的完整 quantity phrase。所有新增格式签名检查通过；catalog/pbxproj未改。

## 外部结果测试

在既有 `WalletPresentationTests.swift` 追加 `QuotaPresentationSupplementTests` 10 项 Swift Testing，用真实production parser、存储、planner/controller外部结果；不新增target file、不镜像内部实现、不弱化已有断言。

1. chars/hours 0/1/many，中英、完整Decimal精度、typed Double原2位、未知service units原样；物理小时不变现金。
2. 真实 ElevenLabs/Amp/Manus producer 的 usage/name本地化与原id/unit/count/period不变。
3. 真实 Antigravity enabled/disabled 同字 model suffix 区别、unknown amount unit，legacy无法判别原文保留、完整Codable roundtrip。
4. 真实 Aixy parser 将 app kind/shared本地化，包含“共享 · 团队 用户输入 %@”的原target原样；legacy nilscope仍 raw，金额和id不变。
5. 真实 DevPass与xAI parser typed plan；payg Key cap不变、teamID原字节、未知旧真实套餐原样与 roundtrip。
6. 真实 WidgetSnapshotStore 保存/恢复 plan/scope descriptors；旧JSON缺optional字段nil、原account/rawname/plan/windows均未改。
7. 固定 Demo Gemini/Aixy 标记的英文显示与原raw值、真实原始model不翻译。
8. 真实 ProviderAuthenticationController.continueLogin 的中英 web-flow指导、断言 transport未调用任何HTTP。
9. public NotificationPlanner 先zh生成future提醒、JSON roundtrip ledger、保护较新观测且latestSnapshot=nil时以en重绘；body仍包含原target/shared意义、identifier/date/观测fence不变，没有deliver过去quota告警。该用例真正需要cached scope provenance转发，不直接调用renderedSchedule私有函数。

10. 真实 NotificationRuntime 升级回归：旧 ledger JSON 只去掉scopeTag、typed zh新快照产生相同正文且operations为空；实际已有commit路径保存/restart，再加既有fence保护且nil snapshot，en未来通知正确包含原target/shared，ID/time/expectedReset/history/observation不变。避免只从新typed ledger开始测试而遗漏升级。

## 已执行与待中央验证

`04-supplement-parse.log`：13个生产相关文件 + WalletPresentationTests syntax parse exit0。`04-supplement-tests-parse.log` exit0；`04-supplement-diff-check.log`相关源 diff --check exit0。25资源条目的en/zh printf签名检查通过；源码未自行typecheck或build，未操作Simulator，不声称10项行为测试已执行。

请中央合并25条资源，签名整合并focused运行 QuotaPresentationSupplementTests + 已受影响的Wallet/Decimal/Date/Platform/Provider/Notification suites（含07现源）。必要真实英文chars/Orb hours/Antigravity未知单位与disabled原文、DevPass/xAI/Aixy/Demo详情截图由负责人做；不以静态检查代替。全程无提交、推送或发布。


## 最后升级边界修复

06只读审核发现同identity分支的guard会丢metadata-only变化；修改只在该分支保存 `existing != desired` 的最小语义pending缓存，仍仅为notification content变化生成schedule操作。stale/missing分支和retain资格不变，Runtime源无需改（既有apply(empty)→ledger=result→persist路径已存在）。`04-supplement-upgrade-parse.log`、`04-supplement-upgrade-diff.log`均exit0。源再次冻结，测试仍待中央执行。


## 真实 Manus 可视反馈后的最后补项

负责人实际查看两语补漏 UI 发现 English `Remaining 1 credits`（04-supplement-ui/A07803FC...），追加最小 credit quantity selector：只匹配已验证 app-owned 非钱包 `manus.refresh/manus.monthly` 且 raw unit=credits；wallet.currency与其他服务/namespace raw credits不改、不泛译。新增 `%lld credits` native one/other 与两个完整 Decimal quantity 条目，中文继续保留技术单位 credits。片段现在28条、4新增nativeplural（hours仍复用原有效资源）。

复用真实 Manus producer 用例增加 0/1/2、monthly、18位Decimal精度、unknownnamespace与非货币wallet原unit保护。`04-supplement-manus-parse.log` / `04-supplement-manus-diff.log`返回0。当前中央全量回归是追加之前版本，不能算新修复已覆盖；待下一focused验证，源冻结。

## 中央最终补漏验证

04-supplement-native-tests.log：125XCTest+22Swift函数全绿。final-signed-behavior-tests.log：798XCTest+33Swift函数全绿（credit tiny追加之前版本）；04-credit-final-focused.log：追加后74XCTest+19Swift函数全绿，未重写旧全量为包含新fix。04-supplement-ui-native.log16个场景执行，14过、characters2locator预期错误；图显示正确2/3characters，改比值预期后04-supplement-ui-characters-final.log2test0fail，合计16实际case全过。16图负责人看6、审查代理实际看10，详04-supplement-ui-review.md。随后Manus1credit grammar tiny追加：04-ui-credit-final.log2两语UI绿，2最终图负责人已看，EN1credit/2credits/3credits正确；ZH技术credits原称保持，不影响Rawunit/walletcurrency。Source/probes全部冻，actualVoiceOver音频仍单列未做。
