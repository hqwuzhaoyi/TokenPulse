# 回归报告：共享网页登录与凭证隔离（WebSessionContainer / ProviderSignInView / NewAPIProvider / QuotaMonitor）

快照：`/private/tmp/tokenpulse-pi-regression-20261002-222956/01-web-session/snapshot`
复现材料：`/tmp/tokenpulse-pi-regression-20261002-222956/01-web-session/work/`（harness 源码与输出均在此，不修改快照源码）

## 发现

### 发现 #1【中】Claude 网页会话凭证未绑定本地账号、无来源指纹：错误账号不被拒绝，QuotaMonitor 的全部身份防护对 Claude 失效

- **位置**
  - `TokenPulse/Providers/ClaudeProvider.swift:13-21`：`ClaudeProviderClient.quota` 的 guard 只检查 kind/cookieFormat/organizationID，从不把凭证与传入的 `accountID` 比对。
  - `TokenPulse/Providers/ClaudeProvider.swift:138-151`：`ClaudeSessionLoginModel.select` 构造凭证时 metadata 仅有 `cookieFormat`、`organizationID`，模型持有的 `accountID` 只用于创建 `WebSessionContainer.scope`（ClaudeProvider.swift:122），从未写入凭证。
  - 连带失效点：`TokenPulse/Providers/NewAPIProvider.swift:112-130`（`sourceCredentialIdentity` 对 Claude 走最后的 `metadata["sourceCredentialFingerprint"]` 兜底 → 恒为 nil）→ `TokenPulse/Application/QuotaMonitor.swift:166-175`（refresh 的 latest-credential 与快照指纹复核被跳过）、`QuotaMonitor.swift:296-320`（replaceCredential 不再绑定身份、不清旧快照）、`QuotaMonitor.swift`（mergeSynchronized 的身份守卫）、`TokenPulse/Platform/CloudAccountSyncStore.swift:213-226`（mergeStates 的旧绑定快照清除仅对有身份的账号生效）。
- **触发（最小输入）**：一次 Claude 网页登录产出的凭证 envelope（`{"provider":"claude","kind":"session","accessToken":"sessionKeyV3=...","metadata":{"cookieFormat":"restrictedHeader","organizationID":"org-x"}}`），拿它对任意 `accountID` 调 `ProviderQuotaClient(provider: .claude).quotaResult(for:credential:)`。
- **影响**：
  1. 错误账号不拒绝——同一凭证在任意本地账号下查询都成功（对照组：`WebProviderSession.validate`（WebSessionContainer.swift:163-172）、`CursorAccountAuthenticator.swift:98-105`、`StepFunProvider.swift:85-94` 都强制 `localAccountID == accountID` 并重算指纹，StepFun 还交叉校验 webID）。
  2. 凭证换绑（在账号设置里重新登录到另一组织/另一 Claude 账号）后，`replaceCredential` 因 `sourceIdentity == nil` 不清旧快照；若新会话刷新失败（网络/服务异常），界面继续把旧组织的额度当作该账号的"上次成功"数据展示。
  3. 跨设备同步时 `mergeSynchronized`/`CloudAccountSyncStore.mergeStates` 的"旧绑定观测不得并回"防护全部跳过：另一设备用旧 Claude 会话刷出的（更晚 collectedAt 的）旧组织快照可以并入当前已换绑的账号行。这正是 newAPI（`testReplacementFailureCannotShowOldServerBalance`、`testNewConfigurationBeforeKeychainNeverQueriesOldCredential`）和身份类 provider 已显式防护、Claude 缺失的同款问题。
- **证据（实际执行）**：`work/harness2`（从快照逐字提取的生产代码：`ClaudeProviderClient`、`ProviderHTTP`、`WebSessionCookiePolicy`、`sourceCredentialIdentity` 扩展 + 与 `ClaudeSessionLoginModel.select` 逐字一致的凭证构造）：
  ```
  PASS  P1 cookie filter keeps only claude.ai sessionKey*      （共享过滤本身正确）
  PASS  P2 login credential carries no localAccountID binding
  PASS  P3 wrong local accountID is NOT rejected by the Claude client
  PASS  P4 snapshot carries no source credential fingerprint
  PASS  P5 quota windows parsed from fixture
  PASS  P6 QuotaMonitor sourceCredentialIdentity is nil for Claude (no scoping in monitor)
  ```
  命令：`cd work && swiftc -o harness2 stubs2.swift extracted_policy_only.swift extracted_claude.swift claude_select.swift build2/main.swift && ./harness2`（完整输出 `work/harness2.out`）。
- **补充测试**：`work/ClaudeWebSessionIsolationRegressionTests.swift`（未执行，待 root 复核合入；其中 `testClaudeWebSessionCredentialIsAccountBound` 当前预期失败，即本发现的固化用例）。

### 发现 #2【中｜静态分析，未运行】"清除会话并重新登录"后屏幕仍显示已关闭的旧 WKWebView，重新登录永远验证失败

- **位置**
  - `TokenPulse/Providers/WebSessionContainer.swift:219` + `:330-333`：`ProviderSessionBrowser(webView:)` 的 `updateUIView` 为空实现且无 `.id(...)`。
  - `TokenPulse/Providers/WebSessionContainer.swift:256-260`：`start()` 在同一 MainActor 调用内先 `close()`（container=nil）再赋新 container；SwiftUI 将两次 @Published 写合并为一次渲染，`if let` 分支结构身份不变 → `makeUIView` 不会再次调用，`updateUIView` 又不换视图。
  - 同型问题：`TokenPulse/UI/CursorSessionLoginView.swift:13,54-60` + `:105-110`；`TokenPulse/UI/StepFunSessionLoginView.swift:22`（`.id(site)` 只在**跨站点**切换时重建视图，同站点重启仍触发）+ `:82-95`。
- **触发**：在 typeSafe / qwenCloud / raycastAI / t3Chat / zoomMate 的 `WebProviderSessionLoginView`、`CursorSessionLoginView` 或 `StepFunSessionLoginView` 中点击"清除会话并重新登录"（StepFun 为同站点）。
- **影响**：用户看到的是旧容器的 WKWebView（其 ephemeral store 已被 `close()` 异步清空、已 `stopLoading`，但页面与交互仍在）。用户在该旧视图上重新登录，Cookie 写入**旧** store；而"完成登录并验证"读取 `model.container`（新容器）的 `httpCookieStore.getAllCookies` → 永远读不到会话 → 反复提示"无法验证登录，请完成登录后重试"。必须关闭并重新打开登录 sheet 才能恢复。"清除会话"这一按钮承诺的隔离重置对用户不可见也不生效。对照组：`ClaudeSessionLoginView` 的 `close()`（onDisappear 时 `webView=nil`）与下次 `start()` 分属两个渲染周期，视图会被移除后重建，不受影响；StepFun 的 `.id(site)` 说明代码库已知该 representable 需要随容器重建。
- **证据**：SwiftUI 契约——`makeUIView` 仅在视图首次插入时调用一次，属性变化只走 `updateUIView`（此处为空）；上述行号可复核。本机环境不允许运行 UIKit/SwiftUI/模拟器，**此发现未做运行验证，属静态回归建议**。
- **修复方向（供参考）**：浏览器 representable 挂 `.id(model.container)`（或 `.id(site)` 扩展为容器标识），或在 `updateUIView` 中把 webView 换为 superview 子视图切换（不推荐）；StepFun 需让同站点重启也改变 id。

## 实际执行的检查

1. **harness（全部通过，33 项断言）**：从快照逐字提取 `WebSessionCookiePolicy`、`CookieWebSessionPolicy`、`WebProviderSession`（credential/fingerprint/validate）、`GatewayServerAddress`、`sourceCredentialIdentity` 扩展，纯 Foundation+CryptoKit 在本机编译运行（`swiftc`）。覆盖并确认：
   - Cookie 过滤：外域/子域后缀/兄弟路径/`/api` vs `/apiary` 边界/过期/重名冲突值/空值全部按预期拒绝或排除；`_ga` 前缀拒绝；dot-domain 与 host-only 都匹配。
   - 凭证头再解析 `values(in:)`：未知名（前缀策略）、重名拒绝；round-trip 一致。
   - 实际 token 指纹：错误 `accountID`/错误 origin 被拒；篡改 accessToken 或 workspace 元数据 → 指纹变化且 validate 失败；encode/decode 后指纹不变。
   - newAPI：地址大小写/端口/尾 `/v1` 归一后身份一致；userinfo/query/fragment/`%2F`/`..`/公网 HTTP 全部拒绝；身份按实际 Key+规范化地址重算，metadata 里的 `sourceCredentialFingerprint` 无法冒充（E4）。
   - 命令：`cd work && swiftc -o harness stubs.swift extracted_production.swift main.swift && ./harness`（输出 `work/harness.out`）。
2. **harness2（发现 #1 证据）**：见上。
3. **语法层**：`swiftc -parse` 对提取的生产代码通过。
4. **静态走查（未发现可复现问题）**：`WebProviderSessionLoginModel`/`CursorSessionLoginModel`/`StepFunSessionLoginModel`/`DeviceLoginModel` 的取消与迟到结果防护——每个 `await` 之后都有 `runID == run && !container.closed && !Task.isCancelled`（或 `activeRunID`/`completed`）检查点，`onCredential` 前后无裸写回；`QuotaMonitor.refresh/replaceCredential` 的 `credentialRevisions`/identity 复核顺序正确，迟到请求不会写回旧快照（现有测试 `testInFlightOldRequestCannotRestoreBalanceAfterKeyReplacement` 亦覆盖）。
5. **验证过且判定非缺陷的边界**：`WebProviderSession.fingerprint` 不覆盖 `expiresAt`（harness C5）——本地改期不改变身份绑定与快照归属，实际会话有效性仍由服务端裁决，无错误归属影响；`URLRequest.setValue` 对含 CRLF 的 newAPI Bearer 头直接丢弃该头（无头注入，自伤性输入只会得到 401）。

## 未覆盖范围

- 完整 XCTest 由 root 统一串行执行，本任务未运行任何 `xcodebuild`/模拟器/WebKit 运行时；发现 #2 因此仅为静态回归建议。
- 无真实账号与网络：各站点真实 Cookie 形态无法验证（例如 zoom 会话 Cookie 若为 `zoommate.zoom.us` host-only 且无 `Domain` 属性，将被 `domains:["zoom.us"]` 排除导致登录失败——`HostedWebProviders.swift:26-31`，此为无法在本环境证实的猜测，不计入发现）。
- `CloudAccountSyncStore` 仅阅读与身份相关的 merge 段落；Demo 模式、Watch/小组件、newAPI 之外的 provider、以及快照中尚未完成的 provider 注册不做评判。
- `WebProviderSessionLoginView` 的多 workspace 候选路径（`choices.count > 1`）当前无任何 profile 返回多于一个候选，显式选择 UI 存在但未被执行验证。
