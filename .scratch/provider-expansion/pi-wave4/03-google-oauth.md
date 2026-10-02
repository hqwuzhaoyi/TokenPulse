# 03 Google 原生 OAuth 冻结快照回归报告

范围：`TokenPulse/Providers/GoogleNativeOAuth.swift`、`TokenPulse/UI/GoogleNativeOAuthLoginView.swift`、`TokenPulseTests/GoogleNativeOAuthTests.swift`（含其依赖 `ProviderHTTP.swift`、`ProviderRedirectPolicy.swift`、`ProviderIntegration.swift`、`Domain/Models.swift` 的相关片段）。
只读 snapshot；复现在 `/tmp/tokenpulse-wave4-pi/03-google-oauth/work`；未跑 XCTest/xcodebuild/模拟器，未联网，未读 home/环境变量/Keychain/凭证。Gemini/Antigravity provider 未合入，未把缺少其注册当缺陷。

## 实际执行的检查（Swift 6 纯 Foundation，真实源码 + 最小 shim）

复现方式：把真实 `GoogleNativeOAuth.swift`、`ProviderHTTP.swift` 原样拷入 work 目录，配最小 shim（Provider/Envelope/RefreshFailure 等与 snapshot 定义一致）与真实测试同款 `GoogleFixtureTransport`，`swiftc` 编译执行。

1. `work/repro`（`swiftc Shims.swift GoogleNativeOAuth.swift ProviderHTTP.swift main.swift -o repro`）：
   - PKCE/授权 URL：redirect_uri=`com.googleusercontent.apps.12345-test:/oauth2redirect`；URL 无 client_secret、无 code_verifier；`code_challenge_method=S256` 且 challenge 与 session.codeVerifier 的 SHA-256 base64url 一致；verifier 64 字符（UUID 十六进制，RFC7636 unreserved 内）；10 次 begin 全部唯一；state 与 session.state 一致；scope/access_type=offline/prompt=consent select_account 正确。
   - callback 矩阵：错 state、重复 state、含 error、含 fragment、无 code 值、无 state、大写 `STATE`、大写 scheme、错 host/错 path、过期 601s、跨 clientID session —— 全部 `invalidCallback` 拒绝；`&extra=1` 附加参数接受（无影响）。
   - exchange：token body 为 `client_id=…&code=…&code_verifier=…&grant_type=authorization_code&redirect_uri=…`（redirect_uri 正确 percent-encode，无 client_secret）；userinfo 带 `Bearer synthetic-access`；accountID=subject-1；grantedScopes 缺省继承请求 scope；expiresAt=now+3600。
   - scope：显式缩水 scope → `unsupportedLogin`；显式超集（含 openid）→ 接受。
   - refresh：保留/轮换 refresh_token、accountID 与 metadata（project）保留；错 clientID、apiKey kind、400/401 → invalidCredential，429 → rateLimited，500/503 → server；token_type 非 bearer、expires_in 0/1e300、注入 CRLF 的 access_token → 拒绝。
   - userinfo：503 → server，非 JSON → unreadableResponse。
   - redirectURL 校验：空串、`secret`、`123 bad.…`、`client.…/path`、`apps.googleusercontent.com`、`12345_TEST…` 均抛错；但 `-.apps.googleusercontent.com`、`x.apps.…`、`1-2--3.apps.…` 被接受（见发现 3）。
2. `work/model_sim`（无 UIKit 复刻 GoogleNativeOAuthLoginModel 的 runID/busy/browser/task 状态机）：重复完成（成功后第二次回调被 runID 判失效，仅一次 onCredential）、上一轮迟到结果（新 start 后旧回调被忽略，新回调成功）、complete 进行中 onDisappear 取消（无凭证、无泄漏 busy=false）、出错后重试成功、浏览器取消路径 —— 均符合预期，未发现缺陷。
3. `work/edges`：`URLError(.cancelled)` 经 ProviderHTTP → `CancellationError()`（视图分支为静默返回）；纯 302 响应对象（无 URLSession 重定向跟随）→ server；`URL.port` 默认端口为 nil、显式 443 为 443（`validateResponseOrigin` 同源下 nil==nil 通过）；refresh 无 refresh_token → invalidCredential；apiKey kind → invalidCredential；scope 字符串大小写不同按缺失处理。

## 发现（最多 5，按严重度）

### 1.（已执行）userinfo 瞬态失败丢弃已签发的令牌，强制用户完整重新授权；对应测试名宣称“不强制重新认证”但只验证了错误分类
- 位置：`TokenPulse/Providers/GoogleNativeOAuth.swift:48-54`（第 54 行 `throw failure` 使第 48 行已成功返回的 envelope 整体丢弃）；`TokenPulseTests/GoogleNativeOAuthTests.swift:74-81`。
- 最小输入：fixture transport 依序返回 `[(200, {"access_token":…,"refresh_token":…,"expires_in":3600,"token_type":"Bearer"}), (503, "{}")]`，调用 `exchange`。
- 预期：userinfo 是瞬态可重试调用（429/5xx），不应使已消费的一次性授权 code 与已签发的 refresh token 作废；至少可重试 userinfo 或先落盘再补 subject。实际：`exchange` 抛 `RefreshFailure.server`/`rateLimited`，envelope 丢失，`onCredential` 永不调用；视图显示“提供商服务异常”后用户必须重新点按钮，从 `begin()` 重新走浏览器同意（且该视图 `prompt=consent` + `prefersEphemeralWebBrowserSession=true`，需重新选账号/输凭证）。
- 证据：`work/repro` C5（503 → throws RefreshFailure server，无 envelope 可得）；测试 `testUserinfoTransientFailuresDoNotForceReauthentication` 第 76-79 行仅断言 `error as? RefreshFailure == expected`，没有断言避免重新认证，测试名与验证内容不符。
- 影响：Google 侧一次 429/5xx（ userinfo 是登录尾部调用，恰在 consent 完成之后）即导致整次登录失败并要求完整重新授权。

### 2.（静态推断 + 部分执行）传输层取消/重定向拒绝被映射为 CancellationError，登录视图静默吞掉：转圈消失、无提示、无凭证
- 位置：`TokenPulse/UI/GoogleNativeOAuthLoginView.swift:77`（`if error is CancellationError { return }`）+ `TokenPulse/Providers/ProviderHTTP.swift:11-16`（URLError.cancelled → CancellationError）+ `TokenPulse/Providers/ProviderRedirectPolicy.swift:14-17`（`rejectingRedirects()` 拒绝一切重定向，URLSession 以 cancelled 结束任务）。
- 最小输入（已执行部分）：transport 抛 `URLError(.cancelled)` → `GoogleNativeOAuth.refresh` 抛 `CancellationError()`（`work/edges` R1）；视图分支逻辑复刻（`work/model_sim` 场景 3）显示结果为 busy=false、message=nil、无 onCredential。
- 预期：用户主动取消（onDisappear/task.cancel）静默合理；但非用户发起的取消（如 token/userinfo 端点 3xx 被 redirect 策略拒绝、系统层取消）应显示错误。实际：两类取消不可区分，全部静默。
- 影响：视图仍在前台时若发生上述传输层取消，用户只看到“正在授权并验证额度”消失，无任何错误信息。注：此为共享基础设施行为，非 Google 独有；触发前提（Google 端点 3xx）离线无法验证，故标注静态推断。

### 3.（已执行）`redirectURL` 接受退化 clientID 前缀（`-`、`x`、`1-2--3`），生成 `com.googleusercontent.apps.-:/oauth2redirect` 这类 scheme
- 位置：`TokenPulse/Providers/GoogleNativeOAuth.swift:10-15`（只校验非空 + 字符集，未要求最小形态/长度）。
- 最小输入：`GoogleNativeOAuth.redirectURL(clientID: "-.apps.googleusercontent.com")` → 返回 `com.googleusercontent.apps.-:/oauth2redirect`（`work/edges` R4）。
- 预期：格式校验拒绝明显非真实的 client ID；实际被接受并进入浏览器流程，最终由 Google 拒绝。
- 影响：轻微——多一次注定失败的浏览器往返与较晚的错误提示；无安全影响（前缀字符集已限制）。

## 次要观察（不计入缺陷）
- scope 比较区分大小写（`work/edges` R5）：Google 原样回显请求 scope，实际无影响。
- refresh 响应省略 scope 且凭证无历史 grantedScopes 时回退为“假设全量授权”（`GoogleNativeOAuth.swift:73`，`work/repro` E5）：仅在 requestedScopes 与原始授权不一致时才可能掩盖降权，当前调用面恒为默认全量 scope。
- token 过期时间无时钟偏移余量（`expiresAt = now + expires_in`），属常见取舍。
- 登录视图错误后 `runID` 不清空（`GoogleNativeOAuthLoginView.swift:80` 后），但下次 start() 会先 cancel()，无泄漏路径。

## 未覆盖
- 未运行 XCTest/Xcode 构建（按约束禁止 xcodebuild），snapshot 中 6 个测试未真实执行；仅以同源码+同 fixture 的独立可执行复现，逐条核对其断言在逻辑上应通过（含 `\r\n` 注入与缩水 scope 两个用例的字符串语义核对）。
- `complete` 闭包的真实实现（应来自未合入的 Gemini/Antigravity provider）不在 snapshot 内，project 参数的落盘与刷新链路无法回归。
- 真实 Google 端点行为（granted scope 回显格式、token 端点是否 3xx、ASWebAuthenticationSession 对 `com.googleusercontent.apps.*` scheme 的真实回调）需联网/模拟器，未验证；UIKit 展示路径（presentationAnchor、ASWebAuthenticationSession.start() 返回 false）未执行，仅静态审阅 + 状态机复刻。
- 持久化/Keychain、凭证编码（ProviderCredentialEnvelope.encode/decode）未在本次范围。
