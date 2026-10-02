# Provider integration status (Tickets 03–06)

This file records implemented contracts and the verification boundary. All response examples in tests are synthetic and contain no real credential or account data. No provider below has been validated with a real subscription or physical device yet.

## Kimi Code 国内版

Implemented:

- RFC 8628 device authorization against `https://auth.kimi.com/api/oauth/device_authorization` and token polling/refresh against `https://auth.kimi.com/api/oauth/token`, using the public Kimi Code client ID.
- OAuth access and refresh tokens remain inside the existing credential envelope and Keychain flow. Expiring access tokens are refreshed before querying, with refresh-token rotation preserved.
- `GET https://api.kimi.com/coding/v1/usages` maps the reported 5-hour, 7-day, and shared monthly limits to quota windows. `limit_month_code` is a breakdown of the shared monthly usage, so it is not exposed as a second monthly limit or notification source.
- Optional Extra Usage funding is shown as a currency balance. Its fixed-point amount follows the official client's millionths-of-a-cent conversion and does not invent granted/top-up wallet fields.
- The first release targets the mainland China endpoints. Global `.ai` endpoint selection is outside this provider entry.

Primary evidence: [Kimi Code device OAuth implementation](https://github.com/MoonshotAI/kimi-code/blob/main/packages/oauth/src/oauth.ts), [managed usage endpoint and response parser](https://github.com/MoonshotAI/kimi-code/blob/main/packages/oauth/src/managed-usage.ts), and [official Server API quota description](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/server-api.html). A live unauthenticated device-authorization request returned HTTP 200 with the documented fields, a `www.kimi.com` verification URL, a 30-minute lifetime, and a 5-second polling interval.

Not yet verified: browser completion with a real Kimi account, a production subscription response, access-token refresh and rotation against the live service, iCloud credential arrival, independent Watch refresh, or real notifications/widgets. The usage contract is public in Kimi's open-source client, but the HTTP endpoints can still evolve; fixture tests and the authorization handshake do not prove end-to-end account access.

## Qoder 国际版与 DeepSeek（本次接入）

Qoder 的参考版本为 [CLIProxyAPIPlus 7b9a231](https://github.com/kaitranntt/CLIProxyAPIPlus/commit/7b9a231e189d6a2e150cc6135de3209fa51f531d)。该提交暴露的是管理接口快照，TokenPulse 使用同版本源码中的直连流程：浏览器 PKCE 设备授权、轮询取得凭证、`GET https://openapi.qoder.sh/api/v2/quota/usage` 查询。个人额度与组织资源包分别表示，`expiresAt` 不当成重置时间。

认证限制：虽然 [认证辅助类](https://github.com/kaitranntt/CLIProxyAPIPlus/blob/7b9a231e189d6a2e150cc6135de3209fa51f531d/internal/auth/qoder/qoder_auth.go) 存在 refresh 方法，[实际执行器](https://github.com/kaitranntt/CLIProxyAPIPlus/blob/7b9a231e189d6a2e150cc6135de3209fa51f531d/internal/runtime/executor/qoder_executor.go#L691-L709) 明确说明设备 `dt-` token 调用该接口会返回 403，并禁用了自动续期。访谈初期关于支持续期的判断已据此更正。

DeepSeek 使用 [官方余额接口](https://api-docs.deepseek.com/api/get-user-balance)：`GET https://api.deepseek.com/user/balance`，API Key 作为 Bearer 凭证。金额使用 Decimal，保留币种、总可用余额、赠送余额、充值余额和账户级 `is_available`；不根据金额猜测可用状态，不生成使用百分比或重置时间。

待实测：Qoder iPhone 浏览器授权、真实额度响应和凭证有效期；DeepSeek 真实 API Key 查询；两者的 iCloud 凭证到达、手机离线时 Watch 独立刷新、真实通知和小组件。源码与模拟响应测试不等于真实账号验收。

## Shared integration API

- `ProviderQuotaClient(provider:)` implements `QuotaQuerying` and also exposes `quotaResult(for:credential:)` so a coordinator can persist a rotated credential when one is returned.
- `ProviderAuthenticationController` exposes direct Key creation, `beginLogin`, `continueLogin`, and `refreshCredentialIfNeeded`.
- Credentials are encoded as `ProviderCredentialEnvelope` JSON. OAuth refresh tokens, web session cookies and account identifiers remain inside that string so the existing credential store can protect them. They are never logged.
- The application coordinator refreshes and persists a rotated credential before querying. This avoids losing a newly rotated refresh token if the subsequent quota request fails.
- Every quota `GET` explicitly uses `reloadIgnoringLocalCacheData`; a cached reply must not receive a new collection time and trigger fresh-data behavior.

## Claude

Implemented:

- `ClaudeSessionLoginView(onCredential:)` starts only after the user taps “登录 Claude”.
- It uses an app-owned, non-persistent `WKWebView`; it does not read Safari, Claude Desktop or another application's cookies.
- After the login completes, only `sessionKey` and/or `sessionKeyV3` for the exact `claude.ai` domain are read from that WebView's `WKHTTPCookieStore`; they are combined into a restricted Cookie header and no other cookie is retained.
- `GET https://claude.ai/api/bootstrap` obtains the account's organization memberships. The user explicitly selects an organization.
- `GET https://claude.ai/api/organizations/{organizationID}/usage` returns the selected organization's quota windows. Both `limits[]` and the older top-level `five_hour`/`seven_day` response shapes are parsed without inventing missing metrics.

Evidence: these are web-client endpoints documented by the pinned Pulse reference, not public Anthropic APIs: [Claude provider notes](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Docs/providers/claude-code.md), [Claude web-session implementation](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/ClaudeDesktopSession.swift), and [shared usage parser](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/ClaudeCodeUsageService.swift).

Not yet verified: CAPTCHA/passkey behavior inside iOS WKWebView, session-cookie lifetime or rotation, multiple-organization membership on a real account, and whether Claude changes these private web routes. There is no separate refresh endpoint for this session credential; renewal currently requires the web session to remain valid or the user to sign in again.

## Codex

Remaining manual reset uses come from the same `GET /backend-api/wham/usage` response at `rate_limit_reset_credits.available_count`. TokenPulse displays this authoritative count (including zero); absent or invalid fields remain unknown. It does not derive the count from the potentially capped `credits` array or `total_earned_count`, and never calls a reset/consume operation. Evidence: [official backend client](https://github.com/openai/codex/blob/main/codex-rs/backend-client/src/client/rate_limit_resets.rs) and [reset-credit summary type](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/v2/account.rs).

Implemented:

- OpenAI's Codex device authorization flow:
  1. `POST https://auth.openai.com/api/accounts/deviceauth/usercode`.
  2. User opens `https://auth.openai.com/codex/device`.
  3. Poll `POST .../deviceauth/token`; HTTP 403/404 mean pending.
  4. Exchange the returned authorization code and provider-issued verifier at `https://auth.openai.com/oauth/token`.
- Refresh-token grant with rotation preservation.
- `GET https://chatgpt.com/backend-api/wham/usage`, including `ChatGPT-Account-Id` when present in the access-token claims.
- Plus and Pro recognition from `plan_type`. Plus account-wide windows show the returned five-hour and weekly quotas; Pro shows its account-wide weekly quota.
- Account-wide and additional per-model `primary_window`/`secondary_window` limits.
- GPT-5.3-Codex-Spark remains a compact detail-only field and does not participate in account-level alerts or reset reminders.
- Provider durations are normalized to shared five-hour, weekly, monthly, or other periods. One policy selects windows for summaries, details, widgets, and notifications; reset reminders require reported usage above zero.

Primary sources: [OpenAI Codex device-code implementation](https://github.com/openai/codex/blob/main/codex-rs/login/src/device_code_auth.rs) and [Codex login server/scopes](https://github.com/openai/codex/blob/main/codex-rs/login/src/server.rs). The usage route itself is not a public OpenAI API; response mapping follows the pinned [Pulse Codex implementation](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/CodexUsageService.swift).

Not yet verified: real device authorization, token exchange, refresh-token rotation across iPhone and Watch, account header behavior, and current private usage response compatibility.

## OpenCode Go

Implemented:

- Direct OpenCode Go API Key entry; mobile devices do not attempt to read a Mac OpenCode installation.
- `GET https://opencode.ai/zen/go/v1/usage` with bearer authentication and no request body.
- `usage.rolling`, `usage.weekly` and `usage.monthly` map to five-hour, weekly and monthly windows. Missing percentages omit only that window; no valid windows is an explicit failure.
- `percent` remains the reported used percentage and is clamped to 0–100. `status=rate-limited` is preserved as exhausted state for display and threshold alerts.
- HTTP 401 means an invalid key; HTTP 403 separately reports that the key has no OpenCode Go subscription; HTTP 429 remains rate limited.
- All reported windows participate in summaries, details, widgets and notifications. Reset reminders still require actual reported usage.

The route and response are implemented by OpenCode itself but are not listed in its public endpoint table, so they remain a change-sensitive integration contract. The response contains neither a plan field nor a Zen balance; TokenPulse identifies the provider as OpenCode Go and does not invent either value. Research and primary-source links are recorded in [OpenCode Go Provider 接入研究](opencode-provider-research.md).

Not yet verified: a real OpenCode Go API Key on iPhone, Watch credential arrival, independent Watch refresh, production response compatibility, or key revocation behavior.

## Z.ai

Implemented:

- Direct international Coding Plan Key entry; no OAuth or invented refresh flow.
- `GET https://api.z.ai/api/monitor/usage/quota/limit` with bearer authentication.
- The HTTP status and the response's `success`/`code` envelope are both checked.
- `TOKENS_LIMIT`, `CREDIT_LIMIT` and `TIME_LIMIT` windows are mapped from the provider's unit/count, usage, remaining, percentage and reset fields. Missing values remain missing.

The quota route is not publicly documented. Mapping follows the pinned [Pulse Z.ai implementation](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/ZaiUsageService.swift), which in turn tracks CodexBar's Z.ai provider. The public [Z.ai documentation](https://docs.z.ai/) establishes the international service but does not currently specify this quota response.

Not yet verified: a real international Coding Plan Key, rejection behavior, multiple accounts, response field casing, and continued availability of the private quota route.

## SuperGrok

When the CLI billing proxy omits `creditUsagePercent`, TokenPulse now tries the read-only `https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig` gRPC-web endpoint with the same OAuth Bearer token. It accepts an explicitly published percentage and validates framing/status; missing or malformed usage stays unknown. The bounded decoder reads the credits message fields only and does not infer usage from unrelated on-demand balances or an absent percentage. This additional contract follows the [CodexBar billing implementation](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Grok/GrokWebBillingFetcher.swift). A real device/account result remains to be verified.

Implemented:

- xAI RFC 8628 device authorization using the CLI public client and the discovery endpoints:
  - `https://auth.x.ai/oauth2/device/code`
  - `https://auth.x.ai/oauth2/token`
  - scopes `openid email offline_access grok-cli:access`
- `authorization_pending` and `slow_down` polling behavior.
- Refresh-token grant with refresh-token rotation preservation.
- `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits` with the CLI-required `x-xai-token-auth: xai-grok-cli` header.
- The billing `config` is represented as one account-level SuperGrok quota window. `creditUsagePercent` is used only when explicitly present; missing percentage or period timestamps remain missing and never become zero.
- The public [xAI Grok Build billing shape](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-shell/src/extensions/billing.rs) exposes usage percentage, period, on-demand values and prepaid balance, but no verified remaining manual-reset count. TokenPulse therefore keeps that account-level value unknown and never derives it from balances or history.

Authentication endpoints are published by [xAI OpenID discovery](https://auth.x.ai/.well-known/openid-configuration). The billing route is not public documentation; its interpretation follows the pinned [Pulse Grok provider notes](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Docs/providers/grok.md) and [implementation](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/GrokUsageService.swift). That reference identifies the response as the account-wide shared weekly pool used across Grok products and obtains the plan label from the same CLI proxy. It is not the Cursor Grok Bot endpoint and is not an ordinary pay-as-you-go API balance.

Not yet verified: a real SuperGrok subscription, whether the billing response still corresponds to that plan for the current account, real device login and refresh, multi-account separation, and cross-device refresh-token rotation. Until that validation occurs, the source evidence is a contract candidate rather than proof of a working SuperGrok integration.

## ElevenLabs

API Key 需 user_read 权限；直接查询官方 user/subscription 接口，采用 xi-api-key 头且拒绝重定向。仅使用服务返回的字符用量、总量与重置时间，不将 voice slots 当额度，不推断固定月度周期。缺少查询权限与凭证无效分别提示。手机与 Watch 使用各自 HTTP 客户端查询。当前使用合成响应测试，真实账号与物理设备尚未验收。

## StepFun

StepFun 的 Token Plan 积分池和 Coding Plan 五小时／每周额度通过按账号隔离的网页登录配置；国内与国际站凭证分别绑定。iPhone 与 Watch 使用同一受限 Cookie 和匹配设备标识独立查询，积分到期不是重置，不查询 API 预付钱包。契约、登录／同步方式及未真实验收范围见 [StepFun 接入记录](stepfun-provider-integration.md)。


## New API 自定义网关

每个服务账号绑定 HTTPS 服务器根地址及普通网关 Key。地址保存在 `ProviderCredentialEnvelope.metadata["serverAddress"]`，与 Key 作为整体由本机 Keychain 保存，并通过已开启的 iCloud Keychain 路径同步；账号配置的非秘密地址及凭证摘要用于显示和验证同步缓存。Watch 获得这份凭证后使用同一设备端客户端自行请求。关闭 iCloud 时仍使用本机凭证及账号配置。

地址移除尾斜杠和尾 `/v1`，保留合法的部署路径前缀；拒绝用户信息、查询、片段、路径穿越、编码分隔符及 HTTP。私网 HTTP 尚未实现，也未在 iOS/watchOS 验证 ATS 及本地网络权限。默认网关传输使用无 Cookie 的临时会话，同源重定向仅限原 scheme/host/port，跨源请求在转发前拒绝。

请求为 `GET /v1/dashboard/billing/subscription`、`GET /v1/dashboard/billing/usage` 和 `GET /api/status`。前两项使用 Bearer Key，公共 status 不携带凭证，并在每次采集重新读取单位设置。余额为 `hard_limit_usd - total_usage / 100`，使用 Decimal 保存货币金额。历史“剩余加已用”不是套餐上限，不生成百分比或周期重置。只有 status 明确 USD/CNY 或旧版 `display_in_currency: true` 时可显示货币；TOKENS 显示 Token 数量，CUSTOM/未知单位不补币种或零余额。三项 limit 同为 100000000 时识别无限 Key，并移除金额。缺少赠送和充值明细保留 nil。

服务器和 Key 的摘要绑定配置、状态、同步快照及提醒记录；更新凭证立即清除旧余额，过期的进行中请求和旧身份的同步状态不会覆盖当前账号。同一身份查询失败保留旧成功数据与采集时间，并标记失败。新配置先于 Keychain 到达时拒绝使用旧凭证；两者都到达后设备可独立刷新。USD/CNY 使用现有低余额去重和恢复规则；Token、未知单位及无限 Key 不触发钱包低余额告警。

契约依据：[Pulse 397c8fc4 接入研究](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/newapi.md)；直接核验 [New API 1a4166d8 controller/billing.go](https://github.com/QuantumNous/new-api/blob/1a4166d8e8ba9802d2ca56fe8ecf0ed5404e80d5/controller/billing.go)。源码与合成响应仅能验证契约，不能证明真实部署或双端查询成功。

验证边界：没有读取真实用户 Key、访问真实 New API 账号或进行 iPhone/Watch 真机、iCloud Keychain 与私网 HTTP 验收。完整 target 构建及自动测试结果记录在票据 12。
