# 10 国际化覆盖只读预检

状态：preflight，仅准备与只读审查；不代表正式执行 10、解除 07/08/09 依赖或完成收口。VoiceOver runtime gap、真实配置/extension 运行、最终 Release build 与全量回归仍由负责人另行验收。未改产品、catalog 或工程；未启动 build/Simulator，未重跑无关行为测试。

## 可复现工具与审查口径

执行：`python3 .scratch/internationalization/10-coverage-preflight.py`。

- 输入：当前 `TokenPulse/Resources/Localizable.xcstrings`（653 keys）、四产品目录的 123 个生产 Swift 文件、当前 `/tmp/tokenpulse-i18n-build/Build/Intermediates.noindex/TokenPulse.build` 下已有 native `.stringsdata`、所有 02–09 独立翻译片段、当前 pbxproj。
- 输出仅写 scratch：`10-coverage-preflight.json` / `10-coverage-preflight-tool.log`；人工边界账本 `10-coverage-manual-review.json` 与本报告。
- native artifacts 采用 `(source, target)` 最新产物，避免旧 x86_64 ContentView 的旧 Codex 空态/拼接 key 混入最新 arm64 提取结果。已有增量产物日期早不等于失效；最终 10 仍需从最终构建确认，并与源定位复核。
- DEBUG 条件分支不当作生产 UI；原生源码提取是 SwiftUI/AppIntents 可提取 key 的事实依据，动态 L10n 另做字面与有限域边界审查。工具有 Swift raw/multiline string、comment、interpolation 和 ternary 的轻量 lexer，但不是 Swift 编译器或运行时证明。
- 全 catalog 逐语言遍历 stringUnit / plural；检查 en/zh-Hans、translated state、other、英文 one、printf 位置/类型。L10n.format 调用同时核对可解析的模板 placeholder 与 CVarArg 参数数量，不把 `language:`/`locale:` 当作插值。
- 复用此前 06/08/09 的 39 个 app-owned native keys、91 条动态片段审查；这次扩展到所有生产 UI/presentation/auth/errors/notification 路径，而不是重复其行为测试。

## 汇总

| 检查面 | 当前只读结果 |
| --- | --- |
| Catalog | 653 keys / 1306 language localizations / 1317 leaf stringUnits |
| Native plural | 10 keys；英文 one/other、中文 other 均完整，签名/状态检查无异常 |
| 最新 native 产物 | 249 source-target artifacts，248 production rows，167 distinct keys |
| native 真正缺 app UI key | 0；4 个例外 key 见下一节 |
| 动态 L10n | 375 处生产调用，307 个可解析字面/条件 key；1 个真正未入库的 app guidance |
| format 参数签名/数量 | 可解析调用无偏差；有限域 key 变量另人工核对 |
| 02–09 fragments | 674 条片段项、630 个不同 key；全部在 catalog；6 处 canonical 英文差异，无资源签名问题 |
| 工程资源 | 四产品 Resources phase 各一次引用，同一 Localizable fileRef |
| DEBUG | fixture/receipt/configuration probes 当前仅 DEBUG；交付前应清理临时 probe 与 App Group 请求标记 |

按 target 的最新 native artifacts / production rows / distinct key / 有 emit 的 sources：

| Target | Artifacts | Rows | Keys | Sources |
| --- | ---: | ---: | ---: | ---: |
| TokenPulse | 118 | 176 | 147 | 13 |
| TokenPulseWatch | 109 | 37 | 32 | 3 |
| TokenPulseWidgets | 11 | 17 | 13 | 3 |
| TokenPulseWatchWidgets | 11 | 18 | 13 | 3 |

native 不会 emit `L10n.text/format` 的 key，NotificationRuntime/WidgetContentPresentation 等 0 emit 不能算覆盖已完成；其动态调用与片段已另核对。

## 已确认的 app-owned 覆盖缺口

这些结论来自当前 producer→presentation 的静态路径；没有凭不存在的 screenshot 宣称可视失败，也没有因 catalog 结构正常就忽略未入库/未映射的 app 文案。

| 范围 | 证据与用户会看到的结果 | 修复边界建议（此预检未实施） |
| --- | --- | --- |
| 授权 operation guidance | `ProviderIntegration.swift:607` 调用 `L10n.text("Use the account-isolated web login view")`，key 不在 catalog。`.unsupportedLogin` 理由能沿 `DeviceLoginModel` 被直接显示；可能是保护性的异常路径，但仍属应用操作指导，不能当品牌/技术术语例外。 | 添加明确中英 key；不翻译未知服务错误、URL、验证码。 |
| ElevenLabs 字符单位 | `ElevenLabsProvider.swift:56` 为固定 `elevenlabs.characters` 写 `unit="字符"`，`QuotaLabelPresentation.unit` 无该分支，usage/details 返回原单位，所以英文计数带“字符”。 | 以该稳定 id + app-owned unit 解析；保留实际字符维度、0/1/many、Double/Decimal 的原精度。 |
| Amp Orb 小时单位 | `AmpProvider.swift:99` 从实际 Orb hour 数量产生 `amp.orb unit="小时"`；共享单位 resolver 无映射，英文余额/用量仍带“小时”。 | 仅信任 amp.orb/app 原 unit；不能把 Orb 物理小时变成美元或模型 Token。 |
| Antigravity amount sentinel | `AntigravityProvider.swift:175` 在 amount 存在时明确写 app 自有 `单位（类型未提供）`，并非读取未知 server tokenType；共享 resolver 无映射，剩余数量英文带该中文。 | 对该生产 namespace 的固定 sentinel 安全解析；仍不猜测真实单位、币种或翻译模型/bucket 名。 |
| Manus 非 daily 恢复池 | `ManusProvider.swift:97` 非 daily 的固定 `manus.refresh` label 为“恢复额度”，当前 family 白名单与 catalog 均缺。 | 增加 app-only 完整标签，不伪称每日或已确认重置。 |
| DevPass 按量计费描述 | `DevPassProvider.swift:63` 将 app 生成“按量计费”放入 `providerPlanName`；iPhone `QuotaViews.swift:226`、Watch `WatchAccountPagesView.swift:336` 作为原始品牌/套餐直接展示。 | 明确 fallback provenance 或稳定语义 seam；未知真实套餐名保留。不要为改标签把 `isNoPlan=true`，因为同账号可能仍有 Key 累计上限。 |
| xAI team 描述 | `XAIAPIProvider.swift:85` 将 app 生成“团队 <teamID>”放入 `providerPlanName`（**不是 scope**），同样沿品牌/套餐原文路径显示，英文带“团队”。 | 由 xAI 专属生产 identity/metadata 包装本地化 Team；teamID 每个字节原样，真实套餐/组织名不猜译。 |
| 明确 Demo Antigravity 标签 | `DemoMode.swift:392` 固定 app demo 写“Gemini 模型组”，但它走 real Antigravity 原文保护分支，无 trusted presentation marker。 | Demo producer 标明 app 自有 descriptor；不能给 real third-party Gemini/model/bucket 名加全局文字匹配翻译。 |

另有需要明确范围的既有边界：`AixyProvider.swift:79–82` 将 app scope kind / 共享标记与 raw `target_name` 拼接；现显示层保留整个 raw scope，防止猜译未知 target。`DemoMode.swift:380` 的“团队 · 共享”则完全由 app 写入，但也没有可识别的 scope marker。旧缓存不能安全拆出哪些块是用户/服务文字，这项已在 04 与负责人确认保守保留；完整新查询/明确 Demo 的 app-prefix 覆盖仍应单独决定 typed provenance，不应做盲目 replace/split。

## Native 例外与术语规则

native 未入库的 4 个 key 都有明确例外，而不是漏翻译：

- `%@`：`QuotaWidgetIntent.swift:14/15` 的 user/demo account title 与 Provider subtitle 原文插值；wrapper 由现有 guarded helpers 处理，不能把姓名、未知 Provider 变成机器翻译。
- `central-…`：`JetBrainsImportView.swift:29` 的官方 login-export 结构示例/前缀，不是动作说明。
- `Apple Watch`：产品品牌，保留原样。
- `https://gateway.example.com/v1`：服务器地址示例，保留 URL、协议、路径。

44 个 credential label 的有限集合中，所有含中文的应用 label 都在 catalog。28 个无 catalog 的 label 是品牌 + API Key/Access Token、PAT、TeamID:ManagementKey、AccessKeyID:SecretAccessKey 等技术名称/输入格式；按用户明确英文术语偏好保留，不把它们列成“中文不完整”。Source 显示的普通“登录/配置/复制/错误/恢复指导”仍必须译。

Provider search aliases 保留中文/英文/旧品牌拼写，用于查找，不是 UI 正文遗漏。ISO currency、points、HC、Bobcoins、DIEM、compute points、tokens 等真实单位不通过语言改变定义，不推导币种、不換汇、不合并钱包与预算。

## 动态 key 的边界复核

轻量工具剩余 29 处变量/不可解析 first argument，已人工沿有限域检查，不能以“文本没被 compiler emit”忽略：

- Widget v0 的 `title` 是固定“账期 credits/消息限流”列表；`currency` 只在 TypeSafe 固定 app sentinel `credits（币种未提供）` 且 provider 匹配时调用 L10n，其余币种原样。
- Settings `feedback.message` 来自 NotificationPermissionFeedback 的 app enum；`OpenAIAPIProviderClient.connectionNotice` 为固定 app notice，当前 catalog 完整。Credential label 来源为上文固定 controller mapping，中文项资源完整，品牌/技术格式例外。
- QuotaFormatting 的 `raw/name/label/key/window.name` 不直接对未知 Provider 文字猜 key：有稳定 id namespace、明确 app 文案白名单、MiniMax caller provider、闭合后缀 template、或固定 optional fallback enum；unknown 原文分支返回原始 name/unit/scope。`demo.` 受既有 app-owned ID 生产路径，真实 custom account 名另受 sample UUID+原 demo phrase guard。
- 实际 Kiro bonus/Xiaomi name/Gemini unit 的 raw field 与 app fallback 同字时，旧档无 provenance 保持原样；新 fallback 的 optional presentation enum 被生产端标记。上表未覆盖 producer 不应借语言选择更改 raw persistence/identity。
- Account provider `displayName` 来源于已知 Provider enum；真实 providerPlanName、scope、用户账号名、Codex source text/forecastWindow 没有套普通字符串字典猜译。已确认 plan fallback 漏项正是需要局部语义界限的例外，不应全局翻译这些字段。

可解析的 307 个 literal/ternary keys 除上表授权提示外均在 catalog。格式调用的第一个参数即使含比较字符串（例如 `window.unit=="次"`）也只把 ternary 的 branch template 作为 key；不会错误把 comparison raw value 当格式模板。

## Canonical 差异（无签名问题）

下列片段与当前 catalog 英文不同，应统一工具账本/测试预期，但不为 casing/既有 canonical 文案静默覆写 resource：

| 片段 | key | 片段 | Catalog |
| --- | --- | --- | --- |
| 02 | MiniMax 国内版 | MiniMax (China) | MiniMax China |
| 03 | 登录 %@ | Sign in to %@ | Sign In to %@ |
| 05 | 可手动重置 | Manual resets available | Manual Resets Available |
| 05 | 删除账号？ | Delete account? | Delete Account? |
| 09 | 待更新 | Update Pending | Needs Update |
| 09 | 更新于 %@ | Updated at %@ | Updated %@ |

09 的 `PlatformTests` 硬编码 Update Pending 已在前次只读反馈中交给负责人/09；正式 10 要确认最终 assertion 与 canonical 的处理记录，不弱化预期。

## 资源归属、DEBUG 与交付前处理

四目标 `TokenPulse/TokenPulseWatch/TokenPulseWidgets/TokenPulseWatchWidgets` 的 Resources phase 各一次 Localizable 引用：build file IDs `1A18…0002/0003/0004/0005`，均指向唯一 fileRef `1A1800000000000000000001`、路径 `TokenPulse/Resources/Localizable.xcstrings`。project 的 developmentRegion=en，knownRegions=en/Base/zh-Hans；四产品 Debug/Release 都 `SWIFT_EMIT_LOC_STRINGS=YES`。本预检没有新编译，不能替代最终 bundle/extension 的语言加载证据。

Main Debug `TOKENPULSE_APP` 支持实际 widget renderer 的验收复用；Main Release 明确排除 QuotaWidgetContent.swift/QuotaWidgetIntent.swift/WidgetContentPresentation.swift。中央 debug build 的 AppIntent metadata extraction 限制属于 harness/build 条件，不能把 main-host renderer 或 metadata 当成真正 WidgetKit extension 证明。

交付前应审阅这些范围：

- `ContentView.swift` 的 authorization/account/quota/widget/Codex routes、nested acceptanceRoutesDisabled 与纯 fixture transports；全部 DEBUG，launch参数不能残留在产品 flows。
- `TokenPulseWatchApp.swift` 的 WatchLocalizationFixture（专用三种 suite、授权 stub、长用户名字与大字号），全部 DEBUG；schema/测试账户名不是翻译 key。
- `QuotaWidgetContent.swift` 的 WidgetDebugFixture 与 `debug.widget.fixture` / `debug.widget.expectedLanguage` / `debug.widget.runtime.<bundle>` App Group receipts；Release 编译不含这些路径，QA 结束后仍要撤去 shared fixture request/expectedLanguage 并 reload，避免 Debug 用户持续拿 fixture 数据。
- 标有 `[DEBUG-widget09-config]` 的临时 configuration trace 与 `debug.widget.traceConfiguration` / `debug.widget.configuration.<bundle>`。当前只记录 synthetic IDs，不把 real name/credential 写入 schema，但这是临时诊断；正式交付应清理 probe 与开关/receipt，或明确转为长期 DEBUG harness 并记录理由。不能把它的 NSDictionary wire field 名当作产品文字去翻译。
- scratch 验收工程、导出 screenshot/JSON/schema、native smoke scripts、native UI tree dumps只作证据；不加入生产 target，不把 DEBUG/source diagnostic 字符串当用户界面完整性失败。

## 限制与下一步

本报告只证明资源结构、静态生产路径和已有 native extraction 的预检结果；不证明 VoiceOver 实际朗读、触控目标、Dynamic Type layout、语言切换 timeline 时序、真实通知/WidgetKit 配置 persistence、Release app group 签名或最终 build。保留这些独立验收 gap；没有因此停止只读覆盖工作，也没有正式标记 10 complete。

建议负责人先按所属票处理上表局部 app-owned 缺口，并补特定外部结果/fixture，再重新运行同一脚本。最终 10 用最终产物作 native extraction / bundle 检查、一次必要全量回归与未完成的 runtime 验收；无需重复此前无关测试。
