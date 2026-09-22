# 服务端提前替换重置边界时的告警判定缺口

首次记录：2026-09-21。处理日期：2026-09-22。当前分支 `feature/ios-minimax-quota`。

## 结论

TokenPulse 已采用与 Pulse 相同的额度窗口翻转启发式。对于没有 provider `cycleID` 的同一额度窗口，最新成功刷新满足任一条件就视为进入新的告警周期：

```text
新 resetsAt - 旧 resetsAt > 60 秒
或
旧 usedPercentage - 新 usedPercentage >= 40 个百分点
```

provider `cycleID` 仍然优先；API 钱包余额不进入额度周期判定。翻转后使用新的推断周期身份重新武装阈值，不删除旧告警记录，保持 iCloud 账本集合合并的单调性。

该规则是产品选择的启发式，不声称服务端返回了可验证的周期事件。它优先解决真实新周期持续漏报的问题，并接受服务端大幅修正边界或用量时可能误判一次翻转。

参考实现固定在 Pulse 提交 `8eac7d9379ebbc243cea682246fc7eb0f88292cf`：

- [`UsageWindow.hasTurnedOver`](https://github.com/qunqin24/Pulse/blob/8eac7d9379ebbc243cea682246fc7eb0f88292cf/Sources/Pulse/Usage/ProviderUsage.swift#L8-L36)
- [`UsageAlerts.alerts`](https://github.com/qunqin24/Pulse/blob/8eac7d9379ebbc243cea682246fc7eb0f88292cf/Sources/Pulse/Usage/UsageAlerts.swift#L264-L338)
- [`AlertMemoryTests`](https://github.com/qunqin24/Pulse/blob/8eac7d9379ebbc243cea682246fc7eb0f88292cf/Tests/PulseTests/AlertMemoryTests.swift#L322-L402)

## 原缺口

Codex、MiniMax 等窗口没有 provider 周期 ID。旧实现只有在采集时间已经越过旧边界，并且服务端返回更晚边界时，才创建新告警周期。

当服务端在旧边界到达前就把额度清零并推出新边界时，旧实现会立即把 ledger 的 `resetAt` 覆盖成新值，却保留旧周期身份。结果是旧周期已经发过的阈值继续占位，新真实周期可能一直收不到额度告警。

复现场景：

| 步骤 | 时间 | 用量 | 服务端边界 | 旧实现 |
| --- | --- | --- | --- | --- |
| R1 | 09:00 | 85% | 10:30 | 发送 80% 告警 |
| R2 | 09:05，提前重置后 | 3% | 15:00 | 不识别翻转，边界覆盖为 15:00 |
| R3 | 09:55 | 88% | 15:00 | 80% 档位仍被旧周期占用 |
| R4 | 10:31 | 88% | 15:00 | 仍未越过账本中的 15:00 |

## 当前行为

### 边界推进

- 推进超过 60 秒：立即创建推断周期，不等待旧边界到达。
- 推进恰好 60 秒或更少：视为时间取整或小幅抖动，不翻转。
- 最新服务端边界仍用于页面展示和预计重置提醒重排。

### 用量下降

- 下降至少 40 个百分点：创建推断周期，即使 provider 没有返回 `resetsAt`。
- 下降不足 40 个百分点：视为滚动窗口滑动或数据抖动，不重新武装。
- 翻转时用量仍高于阈值：本次刷新可以立即发送新周期的额度告警。
- 翻转时用量低于阈值：先重新武装，之后再次达到阈值时发送告警。

### 账本

推断翻转使用 `ReminderCycleIdentity.inferred(collectedAt)`。旧 `QuotaAlertRecord` 保留，新的阈值记录写入新周期身份。

不采用“删除该窗口旧告警记录”的方案，因为 `ReminderLedger.merging` 对告警记录使用集合并集；删除状态会被另一设备的旧账本重新带回。

## 未改变的行为

- 有 provider `cycleID` 的窗口仍以周期 ID 变化为准。
- 钱包窗口继续只走低余额提醒。
- 预计重置通知仍使用最新服务端 `resetsAt` 排期和替换。
- 请求失败、缓存读取和过期快照不会调用成功刷新规划器制造新周期。
- 重置提醒开关和额度告警开关继续分别控制两类通知；推断翻转只有在旧周期曾发过额度告警时才发送“额度已重置”，空闲窗口只重新武装。

## 已知取舍

| 情况 | 结果 |
| --- | --- |
| 服务端只是把边界向后修正超过 60 秒 | 可能误判一次翻转 |
| 服务端把用量向下修正至少 40 个百分点 | 可能误判一次翻转 |
| 滚动窗口只下降少量 | 不翻转，避免阈值反复通知 |
| 刷新跨过归零时刻，直接看到较小的新用量 | 只要下降达到 40 个百分点仍可识别 |
| 新旧两次采样下降不足 40，边界也未明显推进 | 仍可能漏掉重置 |

这与 Pulse 的取舍一致：用一个统一、可测试的规则降低漏报，不为每个 provider 建立未经验证的周期策略。

## 验证

永久回归位于 `TokenPulseTests/NotificationTests.swift`，覆盖：

- 边界推进 61 秒立即重新武装；
- 边界推进恰好 60 秒不翻转；
- 无 `resetsAt` 时下降 40 个百分点重新武装；
- 下降 39 个百分点不重新武装；
- 已合并远端翻转账本时，不用更旧的本地快照再次创建周期；
- 远端只更新同周期观测时，本地继续以远端最新用量作为下降基线；
- 提前翻转会取消旧未来排期，并发送本次“额度已重置”通知；
- 未触发过额度告警的空闲滚动窗口不会发送重置通知；
- provider `cycleID` 路径保持优先。

独立 Swift 探针直接编译实际 `Models.swift`、`ReminderModels.swift` 和 `NotificationPlanner.swift`：旧实现稳定失败于 61 秒场景，当前实现通过边界推进与 40 点下降场景。

完整 iPhone/watchOS 设备构建通过。聚焦 XCTest 已完成编译和链接，但本机 Simulator 由 `FBSOpenApplicationServiceErrorDomain` 拒绝启动 `com.tokenpulse.app`，因此测试 runner 未执行；结果包记录在 Xcode DerivedData 的本次 Test 日志中。

## 仍建议的真实账号核实

Codex 手动重置仍值得做一次只读采样，用来了解误判概率，而不是作为本规则上线前置条件：

1. 记录重置前的 `used_percent`、`reset_at` 和 `available_count`；
2. 用户在官方客户端完成手动重置；
3. 立即以及 1、5、15 分钟后读取同一 usage 接口；
4. 观察用量降幅、边界推进量和新边界是否稳定。

TokenPulse 不调用重置消费接口，采样不得记录 Cookie、Bearer token、API Key 或可识别账号信息。
