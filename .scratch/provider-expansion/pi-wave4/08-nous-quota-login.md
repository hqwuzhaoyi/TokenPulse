# 08 — NousPortalProvider / Nous 登录两端集成 批量回归报告

范围：`TokenPulse/Providers/NousPortalProvider.swift`、`TokenPulse/Application/NousDeviceLoginModel.swift`、`TokenPulseWatch/WatchNousAuthorizationView.swift`、`TokenPulse/UI/ProviderSignInView.swift`（DeviceLoginModel）、以及 `QuotaMonitor.replaceCredential/refresh`、`AccountQuotaClient`、`DeviceOAuthCredentialVault` 的 Nous 相关路径。底层 vault/CAS 归 07 组，此处只覆盖 provider 解析与两端登录集成。

## 复现方式（已执行）

在 `/tmp/tokenpulse-wave4-pi/08-nous-quota-login/work` 用 **冻结快照的真实源码** 编译了 Swift 6 纯 Foundation 复现程序（未声称跑过 XCTest / xcodebuild / 模拟器）：

- 真实源文件原样拷贝：`NousPortalProvider.swift`、`ProviderHTTP.swift`、`ProviderRedirectPolicy.swift`、`WalletExpansionHTTP.swift`（含 `WalletDecimalValue`）、`Domain/Models.swift`、`DeviceOAuthCredentialVault.swift`、`PlatformConstants.swift`；
- 从真实文件按行截取：`ProviderIntegration.swift` L1–L132（envelope/login session/transport）+ L640–655（providerEncoder/Decoder）、`WalletProvider.swift` L3–18（`ProviderDecimal`）、`KeychainCredentialStore.swift` L59–61（`KeychainError`）；
- 测试侧仅新增：脚本化 `ProviderTransport` 桩、内存版 `DeviceOAuthRecordStoring`、`CredentialStoring` 协议签名 shim。

命令：`swiftc -swift-version 6 <上述文件> runner.swift -o repro && ./repro`（本机 macOS，结果见下）。复现脚本与全部输出在 work 目录。

## 已执行验证通过的行为（非缺陷）

- device flow：`begin` 校验 verification_uri 必须为 `https://*.nousresearch.com`（host/port/user 校验），session 携带 `localAccountID/ownerDeviceID`；`poll` 校验 provider/ownerDevice/deviceCode 安全字符、`expiresAt` 过期即 `loginExpired`。
- poll 错误语义：`authorization_pending`/`slow_down`（+5s 封顶 60s）→ pending；`expired_token`→loginExpired；`access_denied`→invalidCredential；**429 或 `x-vercel-mitigated` → pending（≥10s 退避）**（已执行）。
- account credits 语义（已执行）：订阅窗 `used=size-remaining`、remaining>size（rollover）时 used 钳为 0；`remaining=0` → isExhausted 且 used=100%；仅 `purchased_credits_remaining`（字符串小数也接受，如 "12.5"）→ `nous.purchased` 非重置窗；`total_usable_credits` → `nous.total` 钱包窗，`WalletBalance(currency:"credits", isMonetary:false)`，**不编造 USD**；organisation.id 与 paid_service_access.organisation_id 不一致 → 拒绝；空数据 → `noQuotaWindows`。
- subject/org 一致性：`quota()` 用 `/api/oauth/account` 的 `privy_did`+org 与本地 envelope 逐一比对，不一致 → `invalidCredential`（含 3xx 重定向视为 invalidCredential）。
- 同 scope 多链稳定 fingerprint（已执行）：fingerprint = SHA256([provider, portal, localAccountID, subject, organizationID])，不含 token/chainID/ownerDeviceID —— 同一本地账号在 iPhone 与 Watch 分别授权得到相同 fingerprint；refresh 换新链（新 chainID/refresh_token）后 fingerprint 不变；换本地账号则变。
- Watch 独立授权（已执行）：Watch 侧 envelope `ownerDeviceID=device-Watch` 在 Watch 的 vault 上 `validateLocal` 通过；同一 envelope 放到 iPhone 的 vault（ownerDeviceID 不匹配）→ `invalidCredential`（设备本地隔离生效）。
- 取消/迟到/配置中途变化（已执行）：`NousSessionCoordinator` 单飞；token 刷新前先 CAS 写 `rotationState=pending`；刷新期间另一写入者抢先 CAS → `CancellationError` 且对方凭证保留；`invalid_grant` → terminal 并丢弃 refresh token，不再重发；`uncertain/pending` 状态绝不重发一次性 refresh（已验证零 token 请求）；查询成功后 generation 变化 → 放弃写入。`NousDeviceLoginModel` 每个挂起点后 `runID`/`Task.isCancelled` 双重守卫，取消后 completion 不再触发（静态走查）。
- iPhone 首次登录（ContentView:723）与重新登录（AccountSettingsView:366）都传入真实 `accountID`，`beginLogin` 把它写入 `localAccountID`，`ProviderScopedCredentialStore.save` 再用 `validateLocal` 强制 accountID/ownerDeviceID 匹配（静态走查 + work 中直接调用 validateLocal 间接覆盖）。

## 发现（按严重度排序，共 3 项）

### 1.（已执行）`begin()` 把 Vercel WAF 拦截（403 + `x-vercel-mitigated`）误分类为凭证无效

- 位置：`TokenPulse/Providers/NousPortalProvider.swift` L104 `func begin(...)`：`if let failure = ProviderHTTP.integrationFailure(status: response.statusCode) { throw failure }` —— 这是 begin 对响应体的唯一分类，status 403 → `ProviderIntegrationError.invalidCredential`，完全不检查 `x-vercel-mitigated` 头。
- 最小输入（work/runner.swift T3 已执行）：`POST /api/oauth/device/code` 返回 403，头 `x-vercel-mitigated: request`，空体。
- 预期：与其余三个入口一致 —— `poll()`（L141：429 或 mitigated → pending 退避）、`account()`（L82：mitigated → `rateLimited`）、`refresh()`（L159：mitigated → `safeRejection(.rateLimited)`）都把 WAF 当限流处理。实际：`begin()` 抛 `invalidCredential`。
- 用户影响：WAF/风控拦截启动设备码时，iPhone 端 `DeviceLoginModel` 落入 default 分支显示"登录未完成，请重试或检查账号授权设置。"，Watch 端 `NousDeviceLoginModel` 显示"授权尚未完成，请重试。"——都诱导用户在风控窗口内立即反复重试（正是 WAF 想抑制的行为），且提示语义错误（问题不在凭证）。同文件内四处入口分类不一致，属实现遗漏。

### 2.（已执行）`poll()` 最后一步取身份的瞬时网络失败会丢弃已签发的 token 对，且 iPhone 的网络重试机制对此不生效

- 位置：`NousPortalProvider.swift` L143–L150：token 端点成功后立即 `account(accessToken:)` 取 `privy_did`/org；该调用抛出的任何错误直接冒泡，已解码的 `Tokens`（access/refresh token）不返回、不缓存。配套：`ProviderSignInView.swift` L152–L161 的 3 次网络重试只 `catch let error as ProviderIntegrationError where error == .network`，而 poll 冒泡的是 `RefreshFailure.network`，重试分支永远不命中。
- 最小输入（work/runner.swift T5 已执行）：`POST /api/oauth/token` 200 返回完整 token JSON；随后 `GET /api/oauth/account` 抛 `URLError(.notConnectedToInternet)`。
- 预期：设备码流程已在服务端完成授权、token 已签发；瞬时失败应可重试（或先返回凭证、身份延后校验）。实际：`poll` 抛 `RefreshFailure.network`，token 对被丢弃，account 端点无任何重试（已验证调用数 ≤1）；两端登录视图终止流程，用户必须从 device/code 开始完整重新授权（还要在网页上重新点一次同意）。
- 用户影响：授权最后一秒的网络抖动 = 全部重来。相对照：同一模型里 pending 轮询和 copilot 流程都有退避/重试，唯独"已成功"的最后一步没有任何容错。

### 3.（静态推断，未执行）iPhone 用另一 Nous 账号重新授权后，Watch 端旧账号凭证继续静默产出过期数据，无重新授权提示

- 位置：`TokenPulse/Application/QuotaMonitor.swift` L166–L170：refresh 成功后 `guard sourceIdentity(latest, ...) == identity else { return }` —— 静默 return，不落 `lastFailure`、不更新快照、不提示。配套：`TokenPulseWatch/WatchAccountPagesView.swift` L271–L291 只有身份为 nil 时才禁用"连接此 Watch"，无"身份不匹配 → 提示重新授权"路径；Watch 的 vault 凭证是设备本地的，iPhone 换号不会同步清除。
- 最小输入（推断链）：iPhone `AccountSettingsView:366` 重新登录时 `replaceCredential(value, accountID:)` **不带** `expectedIdentity`（AccountSettingsView.swift:368），可接受不同 subject/org 的新凭证并更新 `configuration.credentialIdentity`（经 iCloud 同步到 Watch）；Watch 本地 vault 仍是旧账号 envelope，旧 token 未过期期间每次 refresh 都成功取回旧账号数据，随后被 L166–L170 静默丢弃。
- 预期：身份漂移应显式失效/提示（如标记 `invalidCredential` 或引导重新授权）。实际：Watch 界面无限期显示旧账号最后一次成功快照，无任何错误或提示，直到旧 access token 过期（`expires_in`，最长可见数小时）才转为失败态。
- 说明：此为静态走查结论（QuotaMonitor 为 @MainActor 且依赖未包含在冻结复现集内，未实际执行）；Watch 侧新登录本身的身份门（`NousDeviceLoginModel` L36 + `replaceCredential` L302–L304 + L323 的写后回滚）已静态/执行确认是严密的。

## 未覆盖

- 真实网络行为（portal.nousresearch.com 实际响应、refresh token 是否必须放 `x-nous-refresh-token` 头而非 form body、`refresh_token_reused` 错误码是否真实存在）——按任务要求未联网，无法验证协议假设。
- `KeychainDeviceOAuthRecords`/iCloud 同步通道、widget 端、07 组负责的 vault/CAS 底层实现本身。
- `NousDevicePollPacing`（private actor）的 slow_down 跨 session 累计行为仅静态走查（封顶 60s、finished 清理）。
- SwiftUI 视图生命周期（scenePhase 重入、sheet dismiss 时序）未运行，仅逻辑走查。
- Snapshot 中尚无 Nous 专属 XCTest（`TokenPulseTests/` 无 NousPortalProviderTests.swift）；按任务声明"新增 tests 还在开发，缺测试不是缺陷"，未据此报告问题。
