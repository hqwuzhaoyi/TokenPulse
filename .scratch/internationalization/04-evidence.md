# 04 额度、钱包与缓存展示证据

状态：complete。原14个双语quota UI及后续额外app-owned unit/scope/plan补漏均已完成真实验证，详04-supplement-evidence.md。早期静态检查条目保留为历史。实际 VoiceOver 听辨未执行，native AX文案语义已检查，这一设备缺口单列，不冒充听辨通过。

## 已实施

- `UI/QuotaFormatting.swift` 保留 `L10n.text/format/windowName/windowDisplayName/demoAccountName` 原调用兼容性，新增可选 provider 参数、同步/异步 TaskLocal `withLanguage`、窗口 scope/unit 与 Provider 范围内的 `quotaStatus`。
- 额度、连续补充、到期、未知/无限/耗尽/超额、旧数据及部分钱包失败均走 native catalog。日期-only 原有 UTC 日历锚点保持 `yyyy-MM-dd`；没有时区移日或添加午夜。
- Decimal count 保留 0...38 位、余额保留原 0...8 位与极小量科学格式；locale 显式参数可测试，不换汇，币种/points/HC/Bobcoins/DIEM 与预算含义不变。预算总量标签与非货币额度总量区分。
- `UI/QuotaViews.swift` 详情、概览、状态、计数、钱包、VoiceOver 和刷新短语接共享展示；MiniMax 传 Provider 来源；重复的补充字段只展示一次。
- `Platform/WidgetSnapshotStore.swift` 在计算显示指标时本地化，不改缓存原文、账号、窗 ID、收集时刻、失败状态或金额。百分比采用系统 percent 格式而不是拼接 `%`。
- `Application/DemoMode.swift` Factory 样例选择从展示名比较改为现有固定样例 ID 37。演示账号译名在 presentation 层，不改变 persisted 名称。
- 逐一审查 Provider 和 MiniMax 基础设施窗口与单位生产处；记录于 `04-provider-label-audit.txt`。固定标签受稳定 ID namespace + app 自有文案白名单保护；Codex period slots 和 MiniMax 来源边界识别动态周期，Notion/Kiro/Warp/Bifrost 等只翻译其固定 app 注解，原始品牌、模型、组织、工作区与未知文字保持。
- 经负责人明确 handoff，`Domain/Models.swift` 只增 QuotaWindow 的两个可选 presentation enum 属性，旧档缺失为 nil。Xiaomi nil bucket.name、Kiro nil bonus.displayName、Gemini nil tokenType 三处 producer 写入 app fallback provenance；不改请求、凭证、ID、原文或数字。已收到的同字 provider text 不添加 metadata。

## 保守 legacy 边界

旧缓存里的 Xiaomi bucket.name、Kiro bonus.displayName、Gemini tokenType 即使与 app fallback 同字也不能证明来源，保持原文。Aixy target_name 等第三方 scope 原文不做猜译。只有新查询明确缺字段时，上述三处用可选 metadata 展示本地化 fallback。负责人已确认该边界。

## 资源

`fragments/04.json` 共 277 条（String 值或完整 xcstrings entry），其中 10 条 native plural。真实整型次数/时长/requests/messages/GPU 数量用原生复数，`String(format:locale:)` 已独立确认按区域分组（en_US `1,234` / de_DE `1.234`）。当 Decimal 不能无损用 Int64 表达时使用完整 quantity 短语单数/复数分支，不使用不可编译的隐藏 integer classifier，精确格式化数字原样插入。共享已有 key 的英文保持冻结基础用词。

## 静态验证与待集成测试

- `04-resource-validation.log`：`xcrun xcstringstool compile --output-directory .scratch/internationalization/04-compiled .scratch/internationalization/04-validation.xcstrings` 返回 0，所有 fragment entry 编译通过。
- `04-swift-parse.log`：上述 11 个相关 Swift 源及既有测试文件 `swiftc -frontend -parse` 返回 0。
- 新 Swift Testing suite：`QuotaLocalizationPresentationTests`（8 项：旧缓存语言切换和身份、未知原文边界、0/1/many、区域与币种、状态与失败、legacy/new provenance、三个真实 producer provenance、TaskLocal 嵌套）；`DecimalLocalizationTests`（1 项精确小数/区域/序列化）；`QuotaDateLocalizationTests`（1 项中英与 fallback × 四区域 × 五时区）。
- 既有 XCTest suite 沿用：WalletPresentationTests、DecimalQuotaCountsTests、QuotaDatePrecisionTests；原固定中文预期在属内适配 native L10n。Provider producer 回归可包含 XiaomiCodingPlanProviderTests/KiroProviderTests/GeminiProviderTests；Factory DemoModeTests 需覆盖原 ID 样例行为。
- 新 source 都留在既有目标文件，无新增 Swift target source。QuotaViews 是负责人此前已登记的提取文件。
- 负责人要跑 focused suites 与四目标无签名 build；quota/wallet/预算/credits/GPU 混合账号、补充/到期、未知/旧数据、双语 VoiceOver/大字号由负责人 scratch harness 做真实 UI 验收。

没有提交、推送或发布，没有修改用户预存的 Codex 未提交改动。

## 集成编译反馈后的隔离修复

中央 test-target compile 发现 `L10n.withLanguage` async 包装丢失调用者隔离，导致 `@MainActor` XCTest fixture 的 non-Sendable 捕获 closure 报 data race。已给 async overload 增加 `isolation: isolated (any Actor)? = #isolation`，并转发到原生 TaskLocal.withValue 的 isolation 参数；不改变测试对象 Sendable、不调整断言。`04-isolation-typecheck.swift` 的 non-Sendable class + @MainActor async 真实捕获 closure 由 Swift 6 typecheck 返回 0（仅无 throw 的 try 警告），见 `04-isolation-typecheck.log`。仍需中央完整目标重跑确认。

## 真实整合测试后的跨语言复数修复

负责人全量测试真实执行后发现：英文资源 + 中文 region 时，native `String(format:locale:)` 按传入 locale 的中文 plural rule 选择 other，导致 `1 resets/requests/messages/GPU seconds`。已修复 `L10n.format`：用原生 `Locale.Components` 仅将 languageCode/script 绑定有效翻译语言（显式 language > TaskLocal > Bundle.preferredLocalizations，unsupported 回退 en），保留原区域、locale options 与原 numberingSystem。数字 FormatStyle 和日期函数仍使用原 region locale。

`04-plural-runtime.swift` 对真实 `xcstringstool` 编译出的 stringsdict 执行 runtime smoke，覆盖 en + zh_CN/de_DE/en_DE@numbers=arab/ar_EG 及 zh-Hans + en_US/de_DE 的 0/1/3/1234，共 96 条输出，均返回 0；核对 native singular 与 region 数字，包含 `1 reset`、`1 request`、`1 message`、`1 GPU second`、`1.234 resets` 与阿拉伯数字。输出见 `04-plural-runtime.log`。另增加行为测试 `nativePluralGrammarUsesTranslationLanguageAndRetainsRegionalNumbers`，覆盖 en/zh-Hans/fr fallback × 七区域 × 0/1/3/1234/1234567，保留原失败断言不改变预期。资源片段未改变，仍 277 条/10 native plural；待中央重新运行产品测试。

## Focused 回归与真实 hybrid UI 反馈

负责人最新 focused 跑 13 XCTest 成功；11 Swift Testing 中唯一失败是 Double 回归用例的无类型浮点 literal 被 Swift 解析到 non-optional Decimal overload，而非预期 Double? overload。用例已显式声明 `let amount: Double = 123.456`，保持 `123.46 messages` 原预期；真实 Double? 源分支内 `value` 是 typed Double，调用原 count(Double?) 的 2 位格式化正确，未改源码精度或预期来绕过错误。

真实双语 UI 14 项完成后，负责人检查截图发现 Demo Xiaomi 混合账号“月度 Token 额度 Details”仍中文。已给该固定 app-owned Demo producer 添加 `.presentationLabel = .monthlyTokenAllowance`；raw name、ID、quota counts 与日期均未改变，并在既有真实 producer 测试中加入 Demo assertion。Demo Kiro 只有 monthly/trial 两个固定示例，没有 bonus/额外额度项；其两个 app annotations 已在显示层识别，不新增示例或扩大标记。Gemini Demo unit nil、模型名保持。静态 parse 返回 0；待负责人再次 focused 与 English hybrid UI 验收。
