# 63 Gemini：可配置原生 OAuth 与模型额度实施

调查/实施日期：2026-10-03。结论：自备 Google iOS OAuth client + 原生 PKCE + 官方源码 quota 契约足以实现独立设备接入。Google Cloud client 注册是用户接入前配置；缺当前真实账号不会阻塞实施。`v1internal` 服务对具体自备 client/项目的 entitlement 可拒绝，未承诺每一用户都能成功。

## 固定主源

- [Pulse Gemini 文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/gemini.md)与[客户端](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/GeminiUsageService.swift)：只读 CLI token，不当作手机授权。
- 官方 Gemini CLI `fb972b2f87fe7d5b06d37eac711490162d98de2c`：[oauth2.ts](https://github.com/google-gemini/gemini-cli/blob/fb972b2f87fe7d5b06d37eac711490162d98de2c/packages/core/src/code_assist/oauth2.ts)、[server.ts](https://github.com/google-gemini/gemini-cli/blob/fb972b2f87fe7d5b06d37eac711490162d98de2c/packages/core/src/code_assist/server.ts)、[types.ts](https://github.com/google-gemini/gemini-cli/blob/fb972b2f87fe7d5b06d37eac711490162d98de2c/packages/core/src/code_assist/types.ts)、[setup.ts](https://github.com/google-gemini/gemini-cli/blob/fb972b2f87fe7d5b06d37eac711490162d98de2c/packages/core/src/code_assist/setup.ts)。真实请求/结构来自官方源码，不以无第三方公开许可承诺当成不能实现的证据。
- [Google 原生应用 OAuth](https://developers.google.com/identity/protocols/oauth2/native-app)、[OAuth policies](https://developers.google.com/identity/protocols/oauth2/policies)：iOS public client、PKCE、custom scheme、无需 secret 刷新；不得用 WKWebView。App Check/DPoP 可选配置不在本次基本实现范围。
- 官方 AppAuth-iOS `fed71b8f5bbf93e17a0add68c738abb759d5e687` [OIDExternalUserAgentIOS.m](https://github.com/openid/AppAuth-iOS/blob/fed71b8f5bbf93e17a0add68c738abb759d5e687/Sources/AppAuth/iOS/OIDExternalUserAgentIOS.m)：ASWebAuthenticationSession 用 request.redirectScheme 动态接管回调，无 URLTypes 预检。GoogleSignIn-iOS SDK [GIDSignIn.m](https://github.com/google/GoogleSignIn-iOS/blob/6d09701051bf7cb243cbd8225d9744c6810c5279/GoogleSignIn/Sources/GIDSignIn.m) 则额外检查 plist schemes；本实现不使用该 SDK，不把它的预检限制套到直接 ASWebAuthenticationSession 上。
- [RFC6749 §5.1](https://www.rfc-editor.org/rfc/rfc6749#section-5.1)：scope 与请求一致可省略；显式 scope 必须满足请求集合。§6：refresh 响应可替换 refresh token，否则保留此前令牌。

## 用户接入前配置

1. 在 Google Cloud 配置 OAuth consent，注册 **iOS** OAuth client，bundle ID `com.tokenpulse.app`。输入自己得到的 `…apps.googleusercontent.com` client ID，不输入或提取别人的 client secret。
2. 授权 scopes：`https://www.googleapis.com/auth/cloud-platform`、`https://www.googleapis.com/auth/userinfo.email`、`https://www.googleapis.com/auth/userinfo.profile`。这些权限较广，需在 Google 同意页面确认；测试状态 client 的 test users/发布/组织策略由用户项目管理。
3. 先在官方 Code Assist/Gemini 服务完成已有账户和项目设置。TokenPulse 项目可留空以发现服务管理项目，或输入实际获权项目 ID。应用不会调用 onboardUser、创建项目或猜项目。
4. 此基本路线不支持强制 App Check/DPoP 的客户端配置；若开启这些要求，授权或服务请求可能拒绝。无法保证 Google 内部 quota 服务接受每个自备 client，拒绝准确显示，不伪造 CLI metadata 绕过。

## 认证与生命周期

授权 URL `https://accounts.google.com/o/oauth2/v2/auth`。redirect 对 `123-abc.apps.googleusercontent.com` 导出 `com.googleusercontent.apps.123-abc:/oauth2redirect`。ASWebAuthenticationSession 临时会话保留为可取消对象，callback 严格校验 scheme/host/path/state/时效/唯一参数，随后 exchange S256 verifier。

POST `https://oauth2.googleapis.com/token` 不包含 secret；code exchange 保存 access/refresh/expiry/granted scopes；GET `https://www.googleapis.com/oauth2/v2/userinfo` 获得 authenticated `id`，邮箱不用于 identity。401、429、服务错误区分。token 和响应 origin 校验，HTTP重定向拒绝；所有字段不写日志。

凭证通过既有 Keychain/iCloud 生命周期保存和同步。scope identity 对 `provider + local UUID + Google subject + clientID + resolved project` SHA256，getter 重算而不信 claimed hash，refresh access/refresh token 不改变身份。改变 client/project/subject/localUUID 时缓存不能串用。Watch 无网页授权需求，直接使用已配置凭证，临近 expiry 调 public native token endpoint，更新令牌先落库再查询；刷新响应不含新 refresh 时保留旧值，含新值保存替代，未引入专有刷新链。

## 只读 quota 契约

POST `https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist`，可含配置的 `cloudaicompanionProject`。metadata 固定如实 `ideType=IDE_UNSPECIFIED/platform=PLATFORM_UNSPECIFIED/pluginType=PLUGIN_UNSPECIFIED/ideName=TokenPulse`。响应当前已激活 tier 与服务返回 project 才构成可查询环境；无 currentTier 或无真实 project 报配置错误，不把 allowedTiers 当已开通套餐。

POST `:retrieveUserQuota` body `{project: 实际项目}`，参数按官方 required string。每次重新 load 后不能悄悄把 stored project 换成另一项目，必须重新配置。paidTier/currentTier 名称仅用作服务返回套餐名。

`buckets[]` 的 `remainingFraction` 严格有限 0…1；同 `modelId` 多个可比较 fraction 选最少剩余并保留同 bucket `resetTime`。未按自己猜测合并 Pro/Flash；period `.other` 不承诺 24h。`remainingAmount` 以 Decimal exact remaining 保留，没有分母不算比例；同模型 amount-only 不同 bucket 无从可靠比较时拒绝响应。时间必须可解码 ISO 且毫秒可进 Int64，不推断 reset。缺字段/坏类型/负数/非有限/空 quota 都失败，不生成0或无上限。

明确 `UNSUPPORTED_CLIENT` 错误 reason 显示 client 不支持；其他403显示 client/项目权限/资格相关访问失败。过期、权限拒绝、网络和限流由共用 runtime 准确持有失败状态。App/Watch/widget 共用 snapshots，不遮有效窗口；quota/reset 提醒只使用真实比例和真实 reset，余额不伪造。

## 验证与实际观察缺口

6个共享 OAuth tests：public PKCE、callback/state/path/host/重复/expiry、scope省略、subset/header注入、refresh保留/替换、userinfo限流/服务错误。12个 Gemini tests：limiting bucket/reset、畸形类型和finite边界、exact partial、不可比池、RPC项目/metadata、managed/configured发现、项目漂移、身份/token变化、多账号/expiry、服务拒绝、Watch兼容刷新、注册/widget/demo/icon。

生产 Foundation 小模块 Swift6 语义 typecheck 和原生 Google UI 的 iOS SDK typecheck 通过；未运行 Xcode/模拟器，完整 XCTest/unsigned App+Watch/widgets build 由 root 集成统一执行。

真实自有 iOS client 注册、Google同意/内部quota entitlement、真实quota数值、手机/Watch跨到期刷新与撤销均未观察。合成 fixture 不证明这些实际结果；按用户当前 **实现+图标** 验收不以无账号作为阻塞。Google拒绝自备client时显示错误，继续使用 CLI client 或伪装 CLI 都不在方案内。

Gemini图标：Lobe Icons `a94750e3f5f8fc33757b839d85030e742284e43a`，`packages/static-svg/icons/gemini.svg`，MIT，模板黑色/24×24/vector preservation，已登记 ProviderIconNotices。
