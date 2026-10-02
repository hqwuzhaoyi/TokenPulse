# 07-billing-sessions 回归报告：Abacus / Perplexity / Notion AI

## 结论

**未发现可复现问题（0 项缺陷）。** 对三个 provider 的现有实现按重点逐项核验，并基于快照源码逐字提取（verbatim）构建了 macOS 可执行复现程序，41/41 项断言全部通过。Qwen 已转 root，未检查。未访问任何用户数据/环境变量/真实账号；未运行 xcodebuild/XCTest（由 root 统一执行）。

## 发现

没有发现可复现问题。以下为核验过的关键行为（均为实际执行证据，非静态推测）：

| 重点 | 结论 |
|---|---|
| compute points vs 钱 | Abacus 窗口 `unit: "compute points"`、`exactCounts` 精确 Decimal（1000/750/250），`wallet == nil`；Perplexity `balance_cents` 320 → USD 3.2（Decimal 整除 100，无 Double 中间态），不发明百分比/重置时间；Notion AI credits 用 `exactCounts`，`wallet == nil`。 |
| token chunks 连续完整 | Perplexity 分片 cookie（`__Secure-next-auth.session-token.N`）在捕获与刷新两端都经 `sessionNames` 校验索引连续（0..<n、<32、数字严格格式）；12 分片（含 `.10`/`.11`，字典序会乱序）实测按索引序完整发送：`.0=c0; .1=c1; …; .11=c11`。缺片（.0,.1,.3）与索引 32 均在捕获时拒绝。 |
| workspace 显式绑定 | Notion `getSpaces` 列出全部工作区（free+business 都可选，不自动选第一个付费），每个选项独立 `workspaceID` metadata + 独立指纹；刷新时 `getCreditRateLimitStatus` 请求体仅携带所选 `spaceId`，并重校验该空间仍存在且 `userID` 与凭据 `accountID` 一致；篡改 metadata（指纹失效）、跨用户工作区、已移除工作区均 `invalidCredential` 且不发后续请求。 |
| 多账号 | `WebProviderSession.validate` 强制 `localAccountID == accountID`；实测三家用 A 账号凭据在 B 账号刷新均在任何网络请求之前抛 `invalidCredential`。 |
| 可选 tier 失败不抹额度 | Abacus `_getBillingInfo` 503/失败 → `billing = nil`，compute points 窗口与精确计数原样保留，仅 resetsAt/planName 置空（CancellationError 正确透传）。Notion `not_applicable` 为成功态（状态文案，空窗口），非 basic_ai_credits 的 creditType 报 `unreadableResponse` 而非清零。集成层 `retainingWalletAfterPartialFailure` 对这三家为 no-op（从不设置 `walletFailure`，且保留需指纹一致）。 |
| Cookie 来源/redirect | 登录捕获仅取显式 domain/path 白名单内的会话 cookie（analytics、evil.example、notion.so 旧域均被排除；过期 cookie 拒绝）；配额请求 `httpShouldHandleCookies=false`、`rejectingRedirects()`，302 → `invalidCredential`，不跟随到登录页；`permits()` 拒绝非白名单 origin 与 URL 内嵌凭证。 |

## 实际执行的检查

- 复现程序：`work/repro/`（`swiftc -O` 编译成功 exit 0；运行 exit 0，`pass=41 fail=0`）。
  - 组成：`AbacusProvider.swift`、`PerplexityProvider.swift`、`NotionAIProvider.swift`、`ProviderHTTP.swift`、`ProviderRedirectPolicy.swift`、`WebSessionCore.swift`（WebSessionContainer.swift 非 iOS 部分）、`Models.swift` 及 Support/ProviderDecimal/WalletDecimalValue/HostedQuotaMath 提取，全部为快照源码逐字拷贝或按标记整段截取；仅补 `FakeTransport` 假传输层。
  - 命令：`cd work/repro && swiftc -O *.swift -o repro && ./repro`（完整输出见 `work/repro/run-output.txt`）。
- 对照阅读现有 XCTest：`TokenPulseTests/AbacusProviderTests.swift`、`PerplexityProviderTests.swift`、`NotionAIProviderTests.swift`——现有断言与本复现一致且更细；本报告不声称这些 XCTest 已执行（root 统一串行运行）。
- 集成路径核对：`QuotaMonitor.swift:177` 的钱包保留逻辑对三家 provider 无副作用（见上表）。

## 未覆盖范围

1. 真实账号端到端（WKWebView 登录流、真实 cookie 形态、真实 API 响应）——环境禁止且非关票门槛。
2. 完整 XCTest/xcodebuild 执行——由 root 统一执行。
3. 快照中不存在实现的其他 provider——未研究。
4. 单 cookie >32KB 或分片总 header >32,768 字节的极端 token（会被保守拒绝为 `invalidCredential`）——属防御性行为，无真实触发样本，未列为缺陷。
5. Qwen——已转 root。

## 建议（可选，root 复核后合入）

`work/WebSessionChunkOrderingSupplementTests.swift`：补一条 ≥10 分片（`.10`/`.11` 字典序乱序场景）的捕获+刷新顺序锁定测试；复现程序已验证该路径，现有测试仅覆盖 2 分片。
