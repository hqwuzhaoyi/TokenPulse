# 10 最终资源覆盖预检（ready，未正式收口）

截至本次只读复核，681 个资源 key、14 个原生复数条目与 35 处动态 key 有限域审查无遗漏或插值偏差。补漏前的真实发现保存在 `10-coverage-before-supplement-preflight.md` 与 `10-coverage-before-supplement-manual-review.json`，没有用当前 0 missing 覆盖原事实。04 补漏已经由负责人完成行为与真实可视验收；本报告只为 10 准备，不 mark 10 complete、不解除其他票依赖。

本轮只写 scratch 工具、结果与人工账本；未改产品、catalog、pbxproj，未启动 build/Simulator，未重跑行为测试。VoiceOver 实际听辨、Watch 真实触控/长名压力的未完成项单独保留，不当作资源 missing。

## 可复现检查

`python3 .scratch/internationalization/10-coverage-preflight.py > .scratch/internationalization/10-coverage-preflight-tool.log`

输入包括四产品目录的 123 个生产 Swift 文件、Localizable.xcstrings、02–09 所有片段（包括 04 supplement）、当前 pbxproj，以及 `/tmp/tokenpulse-i18n-build/Build/Intermediates.noindex/TokenPulse.build` 已有 native `.stringsdata`。按 `(source, target)` 使用最新 artifact；DEBUG 条件分支独立排除。输出 `10-coverage-preflight.json`、tool log；人工账本 `10-coverage-manual-review.json` 为每个变量调用记录 source/line/expression、可信来源边界与有限 key。

轻量 lexer 识别 comment、Swift raw/multiline/interpolation、ternary，不能替代 Swift 编译器。native compiler emit 是原生 UI/AppIntent key 的事实依据；动态 L10n 不 emit，另外检查闭合生产语义与资源。脚本检查每个语言 stringUnit 的 translated state、完整 plural one/other、printf 位置/类型、可解析 format 实参数量；新增人工账本校验会发现新变量调用、过期 source 定位、有限 key 缺失或其 format 签名偏差。

## 当前结果

| 检查 | 结果 |
| --- | --- |
| Catalog | 681 keys / 1362 language localizations / 1377 leaf stringUnits |
| 原生复数 | 14；en one/other、zh-Hans other 完整，格式与状态错误 0 |
| Native 提取 | 249 source-target artifacts / 248 production rows / 167 distinct keys |
| Native app-owned missing | 0；4 类已确认例外另列 |
| L10n | 382 production calls / 301 可解析 literal 或条件 key，missing 0 |
| 变量 key | 35 处全部人工有限域复核，manual_domain_errors 0 |
| Format | 可解析调用参数计数/类型签名偏差 0；变量数量模板也核对 |
| 片段 | 702 条片段项 / 658 distinct keys；missing 0；04-supplement 28 条完整合并 |
| 工程归属 | 四产品各 1 次引用同一 Localizable fileRef，无重复引用 |
| Source locations | native location issues 0 |
| 临时 configuration/query probes | 生产目录专项 rg 匹配 0；长期 DEBUG fixture harness 另列 |

本次 catalog SHA-256：`a6865f674b7a8bc8e6f87bb4394c896185bfaba6ddcd174309319a9485149d09`。

| Target | Artifacts | Production rows | Distinct keys | Emit sources |
| --- | ---: | ---: | ---: | ---: |
| TokenPulse | 118 | 176 | 147 | 13 |
| TokenPulseWatch | 109 | 37 | 32 | 3 |
| TokenPulseWidgets | 11 | 17 | 13 | 3 |
| TokenPulseWatchWidgets | 11 | 18 | 13 | 3 |

已有 incrementally emitted artifacts 可复用于静态预检；本轮没有重新编译。最终构建/bundle 仍应由负责人统一核实，不把 native 0 emit 当成 NotificationRuntime 或 WidgetContentPresentation 已覆盖的证明。

## 35 处动态调用的来源边界

完整逐项记录在人工账本，当前脚本逐一核对 35/35，没有未审查或过期条目。

- Widget title 仅 v0 的“账期 credits/消息限流”固定列表；currency 仅 TypeSafe 的明确 app sentinel 经 provider guard 后查资源，其他真实币种原样。
- Settings permission feedback 来源闭合 app enum；OpenAI connection notice 固定；credential label 来源固定 Provider 配置。所有应用中文 label 入库，API Key、PAT、Access Token、TeamID:ManagementKey 等技术输入格式例外保留。Provider displayName 来源已知 enum，不拿 providerPlanName 猜 key。
- QuantityUnit 为 9 case，27 个整数/精确 Decimal 完整短语 key 全入库。整数 lossless Int64 才走 native plural；非整型或大 Decimal 用完整 singular/other 短语，精确数字不因隐藏 plural classifier 丢精度。Double 原最多 2 位规则保持。
- 窗口 label/status/unit 的变量查资源受 stable id/family、明确 producer app 白名单、caller Provider、固定 enum 或固定 suffix template 守卫；未知服务 name/unit/status 返回 raw。Kiro/Notion/Warp/Chutes 仅包装自身生成的固定附加短语，真实名字/工作区/数字作为原文插值。
- Scope kind 的 key 仅 organization/project/team/user 四个 app 词；api_key 显示技术 Key。typed name 完全不作 key，isShared 只包装 app 后缀。Legacy Aixy nil metadata scope 整串原样，不 split/replace 真实 target 字符。

## 04 补漏与缓存升级已闭合

原报告的 auth guidance、字符/小时/未知单位、Manus 恢复池、DevPass/xAI plan、Demo Gemini group 与 Aixy app scope 均已处理；最后实际 UI 发现 Manus `1 credits` 的信用单位语法也已修复。不是把旧缺口改名为例外。

- Models 的 presentationLabel/presentationUnit/presentationScope/providerPlanPresentation 都是可选语义字段，默认 nil，旧 Codable JSON 可读。原 id/name/unit/scope/providerPlanName、actual count/currency/周期身份不作翻译或持久化替换。
- DevPass 仅 `devPlan == none` producer 标 payAsYouGo，不改变 Key cap/isNoPlan；xAI 仅自身 teamID producer 标 team(identifier)，identifier 原字节插值。未知服务套餐、旧 nil rawplan 保持原文。
- Aixy 根据 API 的 scope discriminator/shared boolean 记录 typed descriptor，target_name 不译；Demo 的固定 scope 显式标记。WidgetSnapshotStore 保存并恢复 plan/scope provenance。
- Antigravity enabled providerModel 名保持原文；disabled 标记只包装实际 app 附加最后 suffix。Legacy nil suffix 无法证明来源保持原文。固定 Demo Gemini group 单独标记，不泛匹配真实 Gemini 模型或 tokenType。
- Manus native credit 仅非钱包且 exact id `manus.refresh/manus.monthly`、raw unit `credits`；0/1/2 原生复数与 18 位 Decimal 外部断言覆盖。Unknown namespace credits、wallet vendor currency code 保持原始展示。中文保留技术单位 credits。
- NotificationPlanner 的 renderedSchedule 转发 presentationScope；同 identity/time 正文相同但 metadata 不同的旧中文 pending cache 仍经既有 Runtime 空操作提交路径保存。重启后 snapshot=nil、既有较新 fence 保护的英文重绘保留原 target/shared、ID/time/history，不扩大 stale retain 资格。

负责人已报告 04 补漏验证：125 XCTest + 22 Swift Testing focused 通过；此前完整 798 XCTest + 33 Swift Testing 通过；最后 credit 追加后 74 XCTest + 19 Swift Testing 通过。producer-backed 双语 16 UI/16 图实际通过并查看，Manus 又 2 UI/2 图查看确认英文 1 credit。以上运行与图查看属于中央验收证据，本轮只读未自行运行。

## Native 例外、术语与原文保护

4 类未入 catalog 的 native key 都是已确认非翻译对象：`%@` 实体原名/Provider 插值、`central-…` 官方导出结构示例、Apple Watch 产品品牌、`https://gateway.example.com/v1` URL 示例。未把它们加普通翻译 key。

当前 Chinese literal review queue 为 92 项：原 producer 的 immutable label/suffix 和 shared resolver 比较文本、Demo 既有 raw fixture、Provider search aliases、以及 QwenCloud 的“请求已经过期”server-error matching token。前者通过闭合 presentation 翻译而 raw 字段保留；后者是搜索/协议判别，不是用户正文。API Key/Token/OAuth/Provider、模型/品牌/真实 currency 与服务单位继续保留；没有全文中文猜译、币种推导或单位换算。

6 个片段与 catalog canonical 英文差异仍记录于 JSON（无签名差异）：MiniMax (China)/MiniMax China、Sign in/Sign In、Manual resets/Manual Resets、Delete account?/Delete Account?、Update Pending/Needs Update、Updated at/Updated。catalog 是本次合并后的 canonical，04-supplement full entries 无偏差。09 测试先前的旧文案预期由中央验收已处理，本轮未为 casing 重新写资源或弱化断言。

## 四目标与 DEBUG 清理

Resources phase build file `1A18…0002/0003/0004/0005` 都指向唯一 `1A1800000000000000000001`，路径 `TokenPulse/Resources/Localizable.xcstrings`。developmentRegion=en、knownRegions=en/Base/zh-Hans；各产品 Debug/Release `SWIFT_EMIT_LOC_STRINGS=YES`。Main Debug 仍有 TOKENPULSE_APP renderer 验收复用，Main Release 排除 QuotaWidgetContent/QuotaWidgetIntent/WidgetContentPresentation；main-host renderer 不是实际 extension 证明。

专项检查 `DEBUG-widget09-config|debug.widget.traceConfiguration|debug.widget.configuration|queryprobe|queryProbe|QueryProbe` 在四生产目录匹配 0，临时配置/查询 probe 源已移除。仍有明确 DEBUG 的 ContentView/Watch acceptance routes、WidgetDebugFixture 与 `debug.widget.fixture/expectedLanguage/runtime` 请求/receipt；这是保留的验收 harness，不能声称所有 DEBUG 已删除。QA 完成后的 App Group fixture request 清除是实际运行状态，静态 rg 无法证明；本轮不操作容器/Simulator。scratch schema、截图与诊断不是产品翻译对象，不加入生产 target。

## 10-ready 的边界

资源、producer→presentation 原文保护、legacy provenance 升级与当前提取结果可供正式 10 使用；未发现新的 app-owned resource missing。正式收口仍等待其他票完整验收、必要最终产物确认和中央全量结果。VoiceOver 实际听辨与 Watch 触控/长名压力单独列 gap，不映射为资源缺失，也不以本预检代替其 runtime 证据。
