# Kiro 冻结快照回归报告（KiroProvider / KiroCBOR / Tests）

日期：2025-10-03（冻结快照 `/tmp/tokenpulse-wave4-pi/06-kiro/snapshot`，只读）
方法：不联网。将生产源码逐字复制到 `/tmp/tokenpulse-wave4-pi/06-kiro/work/kiro-repro` 并用 `swiftc -swift-version 6`（Apple Swift 6.3.3）真实编译、真实执行（未运行 xcodebuild/simulator/XCTest，未读取任何用户凭证/环境变量/其它目录）。复现脚本源：`work/kiro-repro/src/*.swift`（KiroProvider.swift、KiroCBOR.swift、WebSessionContainer.swift（仅去除 WebKit/SwiftUI 与无关 provider 的登录分支）、ProviderHTTP.swift、AccountQuotaClient.swift、QuotaMonitor.swift、Models.swift 等全部为快照原文），可执行文件 `work/kiro-repro/repro`。

## 发现（具体、可复现）

### 1.【已执行·严重】WidgetSnapshotStore 的指标 switch 漏掉 `.kiro`，快照无法编译
- 位置：`TokenPulse/Platform/WidgetSnapshotStore.swift:56`（`baseDisplayMetrics` 内 `switch account.provider`）；该文件被 pbxproj 中 4 个 Sources 阶段编译（主 App、Watch、Widgets、Tests，见 project.pbxproj 行 1116/1319/1414/1431）。
- 最小复现（已执行）：
  ```
  cd work/widgetcheck   # 快照原文: Models.swift PlatformConstants.swift QuotaFormatting.swift AccountConfiguration.swift ReminderModels.swift WidgetSnapshotStore.swift
  swiftc -swift-version 6 -typecheck *.swift
  → WidgetSnapshotStore.swift:56:9: error: switch must be exhaustive
    note: add missing case: '.kiro'
  ```
- 预期：`.kiro` 与 `.mistral/.sakana` 等一样返回 `visible.map { WidgetQuotaMetric(...) }`（Kiro 各额度池逐项展示、不合并）。
- 实际：编译直接失败。影响：整个快照（含 App、Watch、Widgets、Tests 目标）构建不过；任何“该快照 XCTest 已通过”的宣称在本机不可复现（本报告未运行 XCTest，仅以编译器输出为准）。

### 2.【已执行·中】两笔 `overageCredits` 到期时间相同 → 整次刷新失败
- 位置：`TokenPulse/Providers/KiroProvider.swift:255`：`guard let credit = credit.object, let expiry = try date(credit, "expiresAt"), expiries.insert(expiry).inserted else { throw RefreshFailure.unreadableResponse }`。
- 最小输入（已执行，`repro` 输出 `NOTE two overageCredits with identical expiresAt: REJECTED (unreadableResponse)`）：
  `usageBreakdownList[0].overageCredits = [{currentUsage:4, usageLimit:200, expiresAt:T}, {currentUsage:5, usageLimit:300, expiresAt:T}]`（T 相同，如 `.timestamp(4_000)`）。
- 预期：同资源、同到期时刻的两笔已购 credits 应并列展示（或按稳定子键区分），至多跳过其一；到期时间并非唯一键。对照：两笔不同 `expiresAt`（4_000/4_050）→ 3 个窗口，正常（已执行 PASS）。
- 实际：整个 snapshot 抛 `unreadableResponse`，账号显示“无法读取额度响应”，连本可正常解析的订阅月池一并丢失。用户影响：一次购买多包同时刻到期的 credits（常见于同次发放）后，Kiro 账号完全无额度展示。

### 3.【已执行·低】ACTIVE 试用缺少 `freeTrialExpiry` 时仍生成“无到期时间”的试用窗口
- 位置：`TokenPulse/Providers/KiroProvider.swift:233-238`：`expiry.map({ $0 > collectedAt }) != false` 在 `expiry == nil` 时为真，继续 `window(..., expiry: nil, ...)`。
- 最小输入（已执行）：`freeTrialInfo = {freeTrialStatus:"ACTIVE", currentUsage:1, usageLimit:9}`（无 `freeTrialExpiry`）。
- 预期：缺失到期时间的 ACTIVE 试用应拒绝（unreadableResponse）或显式标注“到期时间未知”。实际：产出 `kiro.CREDIT.trial` 窗口，`expiresAt = nil`、`resetSemantics = nonResettingAllowance`，UI 呈现为不会到期的额度。用户影响：试用到期提醒/到期隐藏逻辑对该窗口永不触发。

### 4.【静态推断·低】bootstrap 硬编码两枚 profile ARN，忽略页面 `profile-arn`
- 位置：`TokenPulse/Providers/KiroProvider.swift:169-172`（`KiroPortalIdentity.parse` 尾部映射），而 meta 允许名单 `TokenPulse/Providers/KiroProvider.swift:151` 已包含 `"profile-arn"` 却从不使用。
- 推断：一旦官方站点返回新的 profile ARN（或企业 SSO 账号返回非社交映射的 ARN），`refresh` 仍会用硬编码 ARN 调 `GetUserUsageAndLimits`，服务端拒绝 → `unreadableResponse`；且 `quota()` 中 `identity.profileArn == credential.metadata["kiroProfileArn"]` 恒用常量比对，无法发现漂移。未联网无法验证线上 ARN，故仅列为静态风险。

## 实际检查 / 命令结果（全部已执行，除非注明静态）

- 复现工程编译：`swiftc -swift-version 6 -O work/kiro-repro/src/*.swift -o repro` 成功（源码均为快照原文的子集，剔除项见 work 目录 README 式注释于 IntegrationSubset.swift 顶部）。
- `./repro` 全量结果：**0 FAIL，exit 0**，共 100+ 断言，覆盖任务点：
  - 官方 portal 请求链：GET bootstrap（HTML meta：stage/user-status/user-id/idp/csrf-token）→ POST `/service/KiroWebPortalService/operation/GetToken` → `/GetUserUsageAndLimits`；断言 `Cookie`、`X-CSRF-Token`、`smithy-protocol: rpc-v2-cbor`、`Authorization: Bearer …`（GetToken 不带）、`httpShouldHandleCookies == false`、usage body 为 CBOR map `{profileArn, origin:"KIRO_IDE", isEmailRequired:true}` 且无 `resourceType`。
  - refresh：usage 401 → 恰一次 `RefreshToken`（旧 csrf 在 header+body），重试用新 csrf+新 bearer，共 5 请求无循环；GetToken 401 → refresh + `Set-Cookie` 轮换后持久化的新凭证不含 csrf/transient token，`remoteAccountID` 保持 `fixture-user`；刷新回包 profileArn 不符/缺 csrf/带换行 token 均被拒（含测试同款 3×3 场景在客户端路径的行为由这些守卫保证）。
  - 拒绝面：跨用户 bootstrap（1 请求后 `invalidCredential`）、跨源重定向、429→`rateLimited`、非 CBOR Content-Type→`unreadableResponse`、过期 cookie 请求前置拒绝。
  - 有界 CBOR：官方 wire fixture（map/array/bool/null/epoch tag 1/half-float/float32/double）解码正确；**34/34 个截断前缀全部拒绝**；定长/不定长重复键拒绝；NaN/Inf（fb/fa/f9 各型）拒绝；`-0.0`（f98000/fb8000…）按有限数接受（正确）；bool 不数值化、|整数|>2^53-1 不数值化；UTF-8 非法、尾部字节、超长字符串/map 计数、深度>12、节点>4096、1MB 上限全部拒绝；encode/decode 往返一致；越界 timestamp `date` 为 nil 不崩溃。
  - 配额池不乱相加：CREDIT（月池+试用+bonus+credit）与 CHAT_REQUESTS 并存 → 5 个独立窗口，totals `[40,50,100,100.5,200]` 无聚合；precision 字段优先（10.125/100.5，ratio、Decimal exactCounts 正确）；仅 used/仅 total→未知不归零；limit=0→耗尽且不视为无限；空列表→“服务未提供可显示的额度池”。
  - cookie 逐 name 轮换：双 cookie 仅轮换 `beta` → header `alpha=one; beta=renewed`、表 `{"alpha":1200,"beta":1800}`、`expiresAt` 仍为 alpha 的 1200；删除最先到期的 `alpha` → 表/头移除且 `expiresAt` 抬升到 1500；无 Expires 的会话 cookie 轮换 → 保留值、移除该 name 的 expiry 项；轮换后凭证可端到端复用。
  - stable sourceIdentity：与 cookie 字节无关（轮换前后相同）、随 localAccountID 变化、64 hex、不含 cookie 材料；篡改 expiry 表（多余 name/缺 name/小数/负数/非 JSON）与非 kiro provider envelope 一律拒绝。
  - AccountQuotaClient/QuotaMonitor（生产文件）保存后兼容：addAccount→refresh 成功；state/快照指纹 == provider identity；store 中为轮换后 cookie（expiresAt=3600）且 identity 不变；`AccountQuotaState` Codable 往返一致；重启（同 store）states 相等、再 refresh 成功、指纹不变；Keychain 中凭证被换成他人 kiro cookie → `invalidCredential`、旧快照不被替换；客户端回带外来指纹的快照 → `unreadableResponse` 且不采纳。
- 另执行：`swiftc -typecheck` 快照原文 6 文件组合 → 发现 #1 的编译器错误（见上）。
- 静态核对（未执行）：`TokenPulse/UI/ProviderIcon.swift:92` `.kiro → "ProviderKiro"`，`Resources/ProviderIcons.xcassets/ProviderKiro.imageset/kiro.svg` 存在，`DemoMode.swift:40/437`、`WebSessionContainer.swift`（快照原文）`.kiro → KiroProviderClient.loginProfile`、`ProviderIntegration.swift:485` `.kiro → webSession`——实现+图标齐备（按验收标准不视为缺陷）。

## 未覆盖

- 未联网：未验证 app.kiro.dev 真实响应（所有 fixture 形状来自快照测试与 Smithy RPCv2-CBOR 约定）；发现 #4 的线上 ARN 无法证实。
- 未运行 xcodebuild/simctl/XCTest（按约束禁止）；因此不以“测试通过”作结论，仅以自建可执行复现与编译器输出为准。iOS 专属路径（WKWebView 登录视图、`#if os(iOS)` 的 `testAccountClientMonitor…` 用例）未执行，Monitor 逻辑在 macOS 命令行以同一生产源码验证。
- XKiroProvider、Widget 渲染运行时行为、通知/提醒链路不在本次范围。

## 结论

KiroProvider/KiroCBOR 的核心协议、边界与安全语义在真实执行的复现中全部符合声明（0 失败）；但存在 1 个已执行的编译级缺陷（WidgetSnapshotStore 漏 `.kiro`，使快照整体不可构建）、1 个已执行的同刻到期 credits 导致整账号刷新失败、1 个已执行的无到期试用窗口，以及 1 项静态的硬编码 profile ARN 风险。
