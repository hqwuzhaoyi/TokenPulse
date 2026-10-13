# Decimal 与提醒回归报告（NotificationPlanner / ReminderModels / QuotaFormatting / Wallet* / Chutes / HostedWebProviders）

快照：`/private/tmp/tokenpulse-pi-regression-20261002-222956/02-decimal-reminders/snapshot`
执行方式：从快照源码原样提取 `Domain/Models.swift`、`Notifications/NotificationPlanner.swift`、`Notifications/ReminderModels.swift`、`Providers/ChutesProvider.swift`、`Providers/WalletProvider.swift`、`Providers/WalletExpansionHTTP.swift`（经 `CodebuffProvider.swift` 引入）、`Providers/HostedWebProviders.swift`、`Providers/ProviderHTTP.swift`、`UI/QuotaFormatting.swift` 等真实生产代码，用 `swiftc`（Swift 6.3.3，macOS，Foundation）编译为原生可执行复现程序（未改动任何快照源码，编译副本与补丁仅在 work 目录）。未运行 xcodebuild/模拟器/完整 XCTest。

## 一、发现

### 1.（高）乱序/过期 snapshot 在 provider-cycle 路径缺少陈旧保护：误发“额度已重置”、误触发已恢复的阈值告警，并可吞掉下一次真实重置通知
- 位置：`TokenPulse/Notifications/NotificationPlanner.swift:18-20`（陈旧守卫只对 `resetSemantics != nil` 的窗口生效）；`NotificationPlanner.swift:218-227`（cycleID 分支的 `didReset` 判定不比较 `collectedAt` 与 `existing.observedAt`）；`NotificationPlanner.swift:51-58`（`ledger.setCycleState` 无条件回写，旧数据可覆盖新状态）；`NotificationPlanner.swift:63-70`（阈值告警去重同样不看时间戳）。
- 最小触发输入（三个连续 refresh，窗口带 `cycleID`）：
  1. `cycleID="A"`，`usedPercentage=50`，`collectedAt=t0` → 记录状态 A；
  2. `cycleID="B"`，`collectedAt=t0+60` → 正确发一次 `confirmedReset`；
  3. **乱序回放** `cycleID="A"`，`collectedAt=t0+30`（早于 ledger 中 `observedAt=t0+60`）。
- 预期：像 `resetSemantics` 路径（18-20 行）和 `observeWalletAlert`（`observedAt <= previous.observedAt → return false`）一样忽略过期观测。实际（`work/repro3` 输出）：
  - 步骤 3 再次投递 `confirmedReset[main]`（重复误报“额度已重置”）；
  - 阈值变体（80% → 恢复 20% → 乱序回放 95%，`collectedAt` 早于已恢复读数）投递 `quotaAlert[main达到95%]`（阈值误触，用户已恢复到 20% 却收到 95% 告警）；
  - 后续真实新周期 `cycleID="C"` 的 `confirmedReset` 被吞掉（乱序回放把 ledger cycle 状态回写为旧 A，`.expectedAt(resetA)` 与已确认记录撞车）：步骤 4 输出无 `confirmedReset`。
- 用户影响：多设备 ledger 合并（`AppRuntime.receive → NotificationRuntime.merge`）或任何过期快照进入 `planSuccessfulRefresh` 时，出现假“已重置”通知、假阈值告警，或漏掉真实的重置通知。
- 证据：`work/repro3`（未打补丁，见下方命令与输出）；`work/repro_patched`（把 18-20 行守卫放宽到所有窗口后，步骤 3/7 静默、步骤 4 恢复 `confirmedReset[main]`、正常升级告警仍触发），补丁在 `work/NotificationPlanner.patched.swift`（diff 仅 3 行，未应用到快照）。

### 2.（中）Chutes 兼容（subscription 对象）分支用 Double 做 `total - remaining`，把微小 remaining 静默舍入为 0：假 100%/“已用尽”与即时 100% 阈值告警
- 位置：`TokenPulse/Providers/ChutesProvider.swift:151-154`（`else if let total, let remaining { percentage = max(total - remaining, 0) / total * 100 }`）及同函数 `isExhausted: validPercentage.map { $0 >= 100 }`。
- 最小触发输入（legacy 形状，测试 `ChutesProviderTests.swift:127` 固定使用该形状）：
  `{"subscription":{"active":true},"rolling_window":{"limit":100000000000000000,"remaining":0.00000000000000000000001,"window_seconds":3600}}`
  更现实的尺度同样触发（Double 相对精度 ~2.2e-16）：`limit=10000000000000000, remaining=0.5`、`limit=100000, remaining=1e-14`、`limit=1000, remaining=1e-13`。
- 预期：remaining > 0 时不报 100%/exhausted（主路径已正确做到：见下）。实际（`work/repro4`）：
  - `[compat 1e17/1e-22] pct=100.0 exhausted=true`，并立即投递 `quotaAlert 滚动额度（1 小时）达到100%`；
  - `remainingCount` 显示为 `1.0000000000000001e-23`（Double 噪声）。
- 对照：同文件主路径（Decimal + `exactDifference` 回验，`ChutesProvider.swift:127-145/154-165`）对相同数值返回 `pct=nil, exhausted=nil, exactCounts` 精确保留——兼容分支是唯一失守点。Raycast/ZoomMate（`HostedWebProviders.swift`）同样返回 nil 而非假值（`work/repro7` 验证）。
- 用户影响：legacy 响应形状下，剩余量小于 `limit×~2.2e-16` 的账号被标记“已用尽”并收到假 100% 告警。
- 建议补丁（与 `HostedQuotaMath.percentage` 既有约定一致，`CodebuffProvider.swift:35`）：`remaining > 0` 时 `percentage = min(computed, Double(100).nextDown)`。

### 3.（低）`QuotaFormatting.balance/money` 把小于 1e-8 的余额显示为 "0 <币种>"，与提醒正文的全精度输出不一致
- 位置：`TokenPulse/UI/QuotaFormatting.swift`（`balance`/`money` 使用 `.precision(.fractionLength(0...8))`；`count(Decimal)` 用 `0...38`）。
- 触发：`WalletBalance(currency:"USD", total: 1e-22)`。实际（`work/repro6`）：UI/Watch/widget 显示 `0 USD`（`ContentView.swift:443/556`、`WidgetSnapshotStore.swift:124`、`WatchAccountPagesView.swift:183` 均走 `balance`），而同一余额的低余额提醒正文是 `USD 可用余额 0.00000000000000000000001，已达到低余额阈值`（`NotificationPlanner.swift` `walletMessages` 直接插值 Decimal，全精度）。
- 用户影响：仅显示层；非零余额显示为 0，与告警文案自相矛盾。是否放宽精度属产品决策，故列为低。

其余重点未发现可复现问题（见下）。

## 二、实际执行的检查

- 编译并运行真实生产代码复现程序（命令与输出均保留在 work 目录）：
  - `swiftc -o repro3 … main.swift`（乱序/重复 snapshot + 阈值误触场景，`work/repro3`）
  - `swiftc -o repro4 …`（Chutes legacy/primary 1e17 与 1e-22 解析 + planner，`work/repro4`）
  - `swiftc -o repro5 …`（continuous/nonResettingAllowance、partial counts、钱包失败保留、混合开关、重复快照，`work/repro5`）
  - `swiftc -o repro6 …`（QuotaFormatting 极值显示，`work/repro6`）
  - `swiftc -o repro7 …`（Raycast/ZoomMate/T3Chat 1e17/1e-22 与百分比解析，`work/repro7`）
  - `swift decimalcheck.swift`（JSONDecoder Decimal 数值字面量解析精度：0.1/1e-22/1234567890123456.78 均精确）
  - `swift chutes_scale.swift`（Double 舍入触发尺度表）
  - `swiftc -o repro_patched … NotificationPlanner.patched.swift`（验证建议补丁修复发现 1 且不破坏正常告警/升级/重排）
- 通过真实 `planSuccessfulRefresh` 验证为符合设计的行为：
  - 精确计数阈值判定（80%/95% 于 1e17、1e-22 用尽、`used>=total` 早退、NSDecimalDivide/Multiply `.down` 不放大数值）；重复同值快照去重；`stale replay` 在 `resetSemantics` 路径被正确跳过。
  - `continuousReplenishment`：95% 告警 → 补充至 10% 重新武装 → 再到 90% 重发（报最高新阈值 80%）→ 重复 90% 静默；`nonResettingAllowance`：不排重置计划、不确认重置、阈值只告警一次（80% → 100% 升级正确）。
  - 钱包：`walletFailure != nil` 保留旧余额时不告警也不重新武装；恢复 50 USD 清除活动态；再跌回 1 USD 重新告警；`walletAlertsEnabled=false` 时 0 USD 不告警；`setQuotaAlertsEnabled` 在 `.mixed`（codebuff）先冻结旧生效值（true 保持），`.walletOnly`（poe）沿用 legacy nil 回退；1e17 阈值与 1e-22 余额的 Decimal 比较精确。
  - Chutes 主路径 1e17/1e-22：`exactDifference` 回验拒绝静默舍入（`used=nil, pct=nil`，不产生假告警）；Raycast/ZoomMate 同样安全（`work/repro7`）。
  - `desiredResetSchedules`：signature 去重、非 reset 窗口排除、过期 resetAt 不排；重排只 cancel 差集。
- 未执行（环境限制，如实声明）：xcodebuild / 模拟器 / 完整 XCTest 套件（由 root 统一串行执行）；未访问任何真实账号、凭证或网络。

## 三、未覆盖范围

- 快照内源码不存在的 provider 不在本次范围；未研究范围外 provider。
- `T3ChatProviderClient.customer()` 的多帧 tRPC 流解析只验证了单行 batch 形状；多帧引用链未做穷举。
- ZoomMate `cycle_end_date` 假定为毫秒（`millisecondsOnly: true`）无法离线证实真实单位；未发现反证，不列为缺陷。
- 真实账号、物理 Watch、通知实际投递与后台刷新调度未验证（按调整后的验收标准不构成关票门槛）。
- 发现 3 的显示精度取舍（是否放宽到更多小数或改用科学计数）需维护者决策，报告仅给出一致性测试建议。

## 四、补充建议

- 建议合入的 XCTest：`work/DecimalReminderRegressionTests.swift`（6 个用例：乱序重放不复燃 confirmedReset、不复燃已恢复阈值、不吞真实重置、Chutes legacy 两个尺度假用尽、亚微余额零显示策略断言）。注意：前 4 个在当前快照上预期失败，即对应发现 1/2；后 2 个中 Chutes 用例预期失败（发现 2），显示用例当前也失败（发现 3，可按决策删除）。
- 建议补丁（未应用）：`work/NotificationPlanner.patched.swift`（发现 1，3 行 diff：把 18-20 行陈旧守卫放宽到所有非钱包窗口）；发现 2 可按 `HostedQuotaMath.percentage`（`CodebuffProvider.swift:35`）的 `Double(100).nextDown` 封顶约定修复 `ChutesProvider.swift:153`。
