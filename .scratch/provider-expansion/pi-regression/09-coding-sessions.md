# 子任务报告：Augment Code / Zed / GrokBot / Cursor auth 复用（只检查已有实现）

日期：2026-10-02（续跑）｜快照：`09-coding-sessions/snapshot`｜工作产物：`09-coding-sessions/work/harness/`

## 一、发现

**没有发现可复现问题（0 项）。** 本任务重点核对的六个方面在现有实现中均通过提取真实生产代码的可执行复现验证，未触发任何与预期不符的行为。

非缺陷观察（不计入发现，供参考）：
- `CursorAccountAuthenticator.poll`（`TokenPulse/Providers/CursorAccountAuthenticator.swift:52-58`）成功响应里服务器返回 `refreshToken`，代码按注释刻意不存储（无已知刷新交换）；access JWT 过期后需重登。属已注释的既定取舍，非错误。
- `ZedProviderClient.window`（`TokenPulse/Providers/ZedProvider.swift:88-91`）在 used>total 时 `usedPercentage` 可 >100（如 120%），与 Cursor/GrokBot 的 `min(raw,100)` 钳制不同；同时 remaining=0、isExhausted=true，展示为“超支”属合理语义，未见用户损害，不计为缺陷。
- `CursorAccountSession.claims` 对 sub 不含 `|` 的 JWT 取整个 sub 作为 account（如 `noaccount`）——仅影响指纹标识符，不构成授权面，验证为通过（见检查 14）。

## 二、实际执行的检查

**方法**：`work/harness/build.sh` 用 awk/sed 从冻结快照**逐字提取**生产代码（未手抄）：`ProviderHTTP.swift` 全文、`WalletProvider.swift` 的 `ProviderDecimal`、`WebSessionContainer.swift` 的 Cookie 策略与 `WebProviderSession`（iOS WebKit/SwiftUI 段排除）、`CursorAccountAuthenticator.swift`、`GrokBotProvider.swift`、`CursorProvider.swift`、`ZedProvider.swift`、`AugmentCodeProvider.swift` 全文；配最小 stub（类型签名/默认值按 `Domain/Models.swift`、`ProviderIntegration.swift` 原样拷贝；`ProviderLoginSession` stub 改 `var` 以便构造篡改会话，已注明）。`swiftc -swift-version 5 -O -parse-as-library`（macOS，纯 Foundation+CryptoKit，离线 canned transport，无网络/无模拟器）编译运行。

**命令**：`bash work/harness/build.sh`（产物 `work/harness/harness`，日志 `run5.log`）

**结果：44/44 PASS —— `ALL CHECKS PASSED (0 failures)`。** 分组如下：

1. **nonce/PKCE**（`CursorAccountAuthenticator.begin`，CursorAccountAuthenticator.swift:22-37）：challenge == SHA256(verifier) base64url（S256，43 字符 verifier，256bit 熵）；nonce 为小写 UUID 且等于 state；无 redirect/callback URL（纯 poll 流，无回调 CSRF 面）。
2. **poll 前置校验**（同文件 40-47）：42 字符 verifier、非 cursor/grokBot provider、过期 session 分别抛 `invalidCredentialData`/`loginExpired`（先于任何网络请求）。
3. **token/account 隔离**（`CursorAccountSession`）：cursor 凭证不能当 grokBot 用、其他本地 accountID 被拒、篡改指纹被拒、<60s 到期 token 拒绝；cookie 恰为单个 `WorkosCursorSessionToken=acc_123%3A%3A<jwt>`，无其他 cookie 泄入。
4. **GrokBot available 语义**（GrokBotProvider.swift:33-44）：`usesPooledEnterpriseAllowance`/`includedLimitZero`/`hasNonZeroIncludedLimit=false` → **空 windows + 专属 quotaStatusText**；两标志冲突或全缺 → `unreadableResponse`（不猜测）；usagePercent 150 → 钳制 100 + isExhausted。
5. **quotaStatusText 传播**：GrokBot quota() 把 `sourceCredentialFingerprint` 写入快照（GrokBotProvider.swift:18）；代码路径核对 `QuotaMonitor.swift:178`（新快照整体替换，空 windows 清旧状态、lastFailure 置 nil）→ `WidgetSnapshotStore.swift:261`（复制进 widget 快照）→ `QuotaWidgetContent.swift:936`、`ContentView.swift:346`、`AccountSettingsView.swift:195`、`WatchAccountPagesView.swift:167` 均渲染；widget 在无窗口指标时以“套餐状态”指标展示（WidgetSnapshotStore.swift:41-44）。
6. **Cursor 百分比语义**：0.0267 保持 0.0267%（不按小数比例放大）；120 钳 100+exhausted；plan disabled 时仅 onDemand USD 窗（cents→USD 正确）；全不可用 → `noQuotaWindows`。
7. **Zed**：`"unlimited"` 字符串 → isUnlimited；1234/10000 cents → 12.34/87.66/100 exactCounts；无预算上限 → 状态注记；plan `free_plan` → "Free Plan"。
8. **Augment available 语义**（AugmentCodeProvider.swift:47-60）：`usageUnitsAvailable` 永不成为分母/金额（totalCount、usedPercentage 均 nil，仅 used/remaining counts + “总额度口径未确认”状态文）；仅 Available 的载荷 → `noQuotaWindows`。
9. **Cookie 提取策略**（WebSessionContainer.swift:11-56, 78-121）：仅选 allowlist 域/名字（zed.session / _session）；同名不同值冲突 → 拒；过期 cookie 跳过；`/api` cookie 匹配 `/api/credits` 端点；`values(in:)` 拒绝注入外来 cookie（如 `; evil=1`）；缺失必需名 → 拒。
10. **WebProviderSession 隔离**：指纹绑定 provider+localAccountID+origin；augment 凭证按 zed 校验、按其他账号校验均被拒。

**补充建议 XCTest（供 root 复核合入，本人未运行 XCTest）**：`work/harness/main.swift` 中 44 项检查可直接移植为 `GrokBotCursorAuthReuseRegressionTests.swift`（重点用例：PKCE challenge 重算、cursor↔grokBot 凭证互斥、GrokBot 三种无个人权益态的空 windows+statusText、Augment Available-only → noQuotaWindows、Zed cents/USD 精确计数、cookie 冲突/过期/外来注入拒绝）。

## 三、未覆盖范围

- **真实网络流**：`api2.cursor.sh/auth/poll`、`cursor.com`/`app.augmentcode.com`/`cloud.zed.dev` 实际 HTTP 行为（本环境禁止联网；离线 transport 仅验证本地逻辑与请求构造，含 Cookie 头恰为单 allowlisted 值）。
- **WKWebView 登录视图**（`CursorSessionLoginView`、`WebProviderSessionLoginModel`，iOS-only UI）：`#if os(iOS)` 段未编译执行；其 permits/ephemeral store/readStorage 逻辑仅静态审阅（origin allowlist + 独立 nonPersistent store + 二次 permits 复查，未发现可执行复现的问题）。
- **完整 XCTest / xcodebuild / 模拟器**：按规则由 root 统一串行执行，本报告不声称已运行。
- **真实账号端到端**（Cursor 账号实际授权、Grok Bot 企业池账号、Augment/Zed 网页登录真机）：不在本回归门槛内（票验收已改为实现完成+图标存在）。
- 其他 provider（超出本子任务范围，未研究）。
