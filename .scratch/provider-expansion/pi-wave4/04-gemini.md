# 04-Gemini 冻结快照回归报告

范围：`snapshot/TokenPulse/Providers/GeminiProvider.swift`、`TokenPulseTests/GeminiProviderTests.swift`、Provider 注册/登录路由、scope 身份指纹、Google 共享 OAuth（`GoogleNativeOAuth.swift`）在 Gemini 集成中的调用边界。共享 OAuth 基础由 03 组负责，此处只验证 Gemini 侧调用。未联网、未跑 xcodebuild/XCTest、未修改 snapshot。

## 发现

**0 个可复现问题。** 本轮未发现可复现的具体缺陷。

## 实际执行的检查（非 XCTest，纯 Swift 6 + Foundation，真实源码逐字提取后编译运行）

复现脚本位于 `/tmp/tokenpulse-wave4-pi/04-gemini/work/`，三个脚本均输出 `ALL PASSED`：

### 1. `work/snapshot_repro.swift` — 配额解析（逐字提取 `snapshot(_:accountID:collectedAt:)`、`Bucket`/`Quota`、`ProviderDecimal.amount`、`ProviderHTTP.isoDate`）
- 多 bucket 同 model 取最限制（fraction 最小）且保留该 bucket 自己的 `resetTime`；输出窗口按 model 排序；`period` 恒为 `.other`，无编造的 Pro/Flash 池或分母（`exactCounts` 为 nil）。
- `remainingAmount` 仅产出 `exactCounts.remaining`，不造 `total`、不给 percentage；大整数 `"9007199254740993"` 精确解析为 Decimal。
- 拒绝输入（全部 `.unreadableResponse`）：`{}`、`buckets:null`、空 bucket、`remainingFraction:true`、`-0.1`、`1.1`、`resetTime:"tomorrow"`、`remainingAmount:"-1"`、`"NaN"`、`1e400`（JSON 层即拒）；`buckets:[]` → `.noQuotaWindows`。
- 同 model 双 bucket 若不可比较（amount-only × 任意 / fraction 后接 amount-only）→ 拒绝，不合并成假共享池；fraction 相等时保留首个 bucket 的 reset。
- `remainingFraction:0` → `usedPercentage 100`、`isExhausted true`。

### 2. `work/client_repro.swift` — 发现/漂移/身份/拒绝分类（逐字提取 `discoverProject`、`quota` 前置守卫与漂移检查、`rpc`、`validProject`、`fingerprint`、`validateResponseOrigin`、`headerSafe`、`redirectURL`、`ProviderHTTP.send/queryFailure/refreshFailure`）
- 真实顺序：`quota()` 先 `loadCodeAssist`（body 含 `metadata.ideName=="TokenPulse"` 等四项，不强制塞 project），再 `retrieveUserQuota`（body 仅 `{"project": …}`）；均 POST、`httpShouldHandleCookies=false`（请求构造静态核对）。
- project 漂移：服务器返回 `different-project` → `.googleProjectRequired`，且漂移后**不再**发 quota 请求（transport 仅收到 1 个请求）。
- 前置守卫：accountID 不匹配 / access token 过期 → `.invalidCredential`，transport 零请求。
- 身份指纹：access/refresh token 轮换后不变；subject、clientID、project、localAccountID 任一改变即变；`grantedScopes` 缺失任一必需 scope → 拒绝。userinfo subject（`envelope.accountID`）在指纹输入中，client/project 来自 metadata，来源稳定。
- 服务拒绝分类：403/400 + `UNSUPPORTED_CLIENT` → `.googleClientUnsupported`；403 其他 → `.googleProjectRequired`；429 → `.rateLimited`；401 → `.invalidCredential`；500 → `.server`。
- `validProject`：`my-project.123:zone` 通过；含空格/`!` 或长度 257 拒绝。
- 发现策略：有 `currentTier` 时用服务端 `cloudaicompanionProject`；无服务端 project 时回落到用户配置值；无 `currentTier`（仅 `allowedTiers`）→ `.googleProjectRequired`，不猜测。

### 3. `work/refresh_repro.swift` — 刷新边界（逐字提取 `refreshIfNeeded` 与 `GoogleNativeOAuth.refresh/token` 的请求/响应路径）
- 剩余 >90s：不发任何网络请求，凭据原样返回（changed=false）；剩余 91s 边界同样不刷新；剩余 60s：刷新。
- 刷新请求仅指向 `https://oauth2.googleapis.com/token`，body 为 `grant_type=refresh_token&client_id=<用户自己的 clientID>`，**无 client_secret**；轮换后的 refresh_token 被保存。

### 4. 静态核对（未执行，仅读源码）
- 注册与路由：`Domain/Models.swift:28` `case … gemini`（CaseIterable → allCases 含 gemini）；`ProviderIntegration.swift:157` loginConfiguration → `.authorizationCode`；`:525/:575` beginLogin/continueLogin 对 gemini 抛 unsupportedLogin，强制走 `ProviderSignInView.swift:15` → `GoogleNativeOAuthLoginView` → `GeminiProviderClient.authorize`（transport 为 `rejectingRedirects()`）；`ProviderIntegration.swift:385/:597` quota 与 refreshCredentialIfNeeded 均路由到 GeminiProviderClient；`ProviderIntegration.swift:145` gemini 使用拒绝重定向的 URLSession transport。
- 图标与示例：`ProviderIcon.swift:66` → `"ProviderGemini"`；`Resources/ProviderIcons.xcassets/ProviderGemini.imageset/gemini.svg` 为 642 字节真实 SVG（template 向量）；`DemoMode.swift:54/145` 含 gemini 账号与 `gemini.gemini-2.5-pro/flash` 窗口；`WidgetSnapshotStore.swift:95` gemini 映射 visible 窗口。
- 刷新后缓存：`AccountQuotaClient.swift:13-17` 先 refresh、changed 时保存新凭据再查询，quota 返回 `updatedCredential: nil` 不覆盖身份。
- 测试文件 `GeminiProviderTests.swift` 与生产路径逐条对应（路径/顺序/body 断言、漂移、身份、刷新、拒绝分类、注册），未见与实现相悖的断言。

## 未覆盖
- 未运行真实 XCTest/xcodebuild（快照禁止），上述结论来自逐字提取源码后的独立 Swift 6 Foundation 运行 + 静态核对，非"测试已通过"的声称。
- 未联网验证 `cloudcode-pa.googleapis.com`/Google OAuth 真实端点行为（fixture 模拟响应）。
- `GoogleNativeOAuth.begin/callbackCode/exchange` 的完整 OAuth 交互、`GoogleNativeOAuthLoginModel` UI 流程属 03 组共享 OAuth 范围，此处只核对了 Gemini 调用边界（exchange 后 subject 写入、refresh 无 secret、端点/origin 校验）。
- Watch 端实际刷新（`testWatchCompatibleOfflineRefreshRetainsIdentityAndRotatedCredential` 场景）仅静态与脚本级验证，未在真实 Watch/模拟器上运行。
