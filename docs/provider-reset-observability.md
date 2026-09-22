# 各提供商额度重置可观测性评估

评估日期：2026-09-22。本文评估现有响应能否证明额度周期发生了切换，并记录 App 最终选择的统一启发式。结论来自仓库源码、测试、现有接入文档及可获得的一手资料；除文中注明外，尚未完成真实账号跨周期采样。

## 结论

当前生产接入的提供商都没有向 `QuotaWindow.cycleID` 写入真实周期 ID。因此 App 对真实提供商使用本地推断，而不是声称提供商返回了明确重置事件。

因此需要区分三件事：

1. **周期身份**：用于同一额度周期内的阈值去重。
2. **观测边界**：服务端给出的周期结束时间，可用于展示和预排“预计已重置”。
3. **周期转换证据**：能否证明一个新周期已经开始，以及结论来自 provider 还是 App 推断。

仅有 `reset_at`、`resetsAt`、`nextResetTime` 或倒计时，不能同时保证零漏报和零误报：提前重置与服务端延期或滑动边界在现有输入中可能完全相同。

## 已选应用策略

为避免在缺少周期 ID 时长期压制新周期告警，TokenPulse 采用 Pulse 的统一窗口翻转规则：同一窗口的 `resetsAt` 向后推进超过 60 秒，或已用比例下降至少 40 个百分点，即创建新的推断周期身份并重新武装阈值。

该规则只使用成功刷新，provider `cycleID` 路径保持优先，钱包窗口排除。下文证据等级仍用于描述“提供商到底证明了什么”，不限制 App 基于已接受取舍执行启发式重新武装。推断翻转只在旧周期曾经发过额度告警时发送中性文案“额度已重置”，不再声称服务端确认。实现和验证见 `docs/reset-boundary-detection-gap.md`。

## 证据等级

| 等级 | 定义 | 可用于预排 | 可重新武装额度告警 | 可证明 provider 周期切换 |
| --- | --- | --- | --- | --- |
| A：提供商周期身份 | 提供商返回稳定周期 ID，或明确的周期实例标识 | 需另有未来结束时间 | 是 | 是 |
| B：已验证周期起点 | 提供商返回当前周期 `start`，且实测证明它只在周期切换时变化 | 需另有未来结束时间 | 是 | 需按契约决定 |
| C：已验证复合推断 | 多个独立信号与已知重置操作建立了可重复关联 | 需另有未来结束时间 | 可按产品取舍启用 | 否 |
| D：观测边界 | 服务端返回绝对结束时间，但稳定性未知 | 是 | 只能在明确接受推断风险后启用 | 否 |
| E：预计边界 | 相对倒计时按观测时间换算出的时间，没有稳定周期实例语义 | 是 | 否 | 否 |
| F：无周期语义 | 没有边界，或者数据本身是钱包余额 | 否 | 否 | 否 |

现有 `QuotaWindow` 只有 `cycleID` 和 `resetsAt`，无法表达 B、C、D、E 的差异（`Models.swift:99-140`）。在真实证据补齐前，不应把这些等级压成一个布尔值。

## 总表

| 提供商 | 当前窗口/字段 | 最强现有信号 | 当前等级 | 主要缺口 | 建议 |
| --- | --- | --- | --- | --- | --- |
| Claude | `session`、`weekly_all`、`weekly_scoped`；`percent`、`resets_at` | 服务端绝对结束时间 | D | 无周期 ID、起点、重置计数或公开字段契约 | 已使用统一翻转规则；继续采样验证边界稳定性 |
| Codex | primary/secondary 及附加额度；`used_percent`、`reset_at`、`available_count` | 用户确认操作成功后，次数与窗口字段变化可组成候选复合信号 | D；具备 C 候选信号 | App 单独看到次数减少时，无法区分兑换、到期或服务端修正，也不能映射具体窗口 | 优先完成一次手动重置前后采样；建立重复关联后才能升级为 C |
| OpenCode Go | rolling/weekly/monthly；`status`、`percent`、`resetsAt` | 服务端按窗口类型计算的结束时间 | D/E（逐窗口、逐状态） | 无周期 ID/起点；未使用的 rolling 窗口会形成滑动预计时间 | 不冻结为全局周期身份；验证线上是否采用源码中的 fallback 语义 |
| Z.ai | `limits[]`；`nextResetTime`、用量、剩余量 | 服务端绝对结束时间 | D | 私有接口，边界稳定性和数组顺序均未验证 | 已使用统一翻转规则；自然边界与提前重置分别采样 |
| MiniMax 国内版 | 短周期和周周期；`start_time/end_time`、`weekly_end_time`、各类剩余时长 | 短周期可取得候选周期起止时间 | D/E；具备 B 候选信号 | 周周期通常没有起点；相对倒计时会随采集时间重算 | 保留 provider 返回的周期起点；验证后才升级为 B |
| SuperGrok | `currentPeriod.start/end` 或 billing period；credits RPC reset timestamp | 主接口可取得候选周期起止时间 | D；具备 B 候选信号 | 当前模型丢弃周期起点；主接口与 RPC 是否为同一额度池尚未验证 | 先验证跨源一致性，再决定是否保留并使用 `currentPeriod.start` |
| Qoder 国际版 | 个人额度、组织资源包；total/used/remaining/percentage | 无 provider 周期信号 | F | `expiresAt` 是到期时间，不是重置时间 | 用量下降至少 40 个百分点时可推断新周期；不能视为 provider 确认 |
| DeepSeek | API 钱包余额和 `is_available` | 无周期语义 | F | 钱包充值、扣费和可用状态变化都不是额度周期重置 | 继续只走低余额提醒，排除周期 Planner |

## 分提供商评估

### Claude

`ClaudeProviderClient` 读取新版 `limits[]` 中的 `kind`、`percent`、`resets_at` 和可选模型范围，也兼容旧版 `five_hour` / `seven_day`（`ClaudeProvider.swift:43-93`）。所有窗口都没有 `cycleID`。

仓库证据和本轮查阅的公开资料都没有证明 `resets_at` 在周期内固定，也没有找到重置计数、周期起点或重置事件。Claude Web usage 路由还是未公开契约（`docs/provider-integration.md` 的 Claude 小节）。当前只能把它视为观测边界。

最小实测：固定同一组织及同一 `kind + scope`，覆盖正常消耗和自然边界，每 1–5 分钟保存脱敏响应，观察 `resets_at` 是否稳定、边界后如何推进，以及窗口是否临时消失。

### Codex

`GET /backend-api/wham/usage` 返回账号级和附加额度的 `used_percent`、`limit_window_seconds`、`reset_at`，但没有周期 ID（`CodexProvider.swift:58-87`）。同一响应的 `rate_limit_reset_credits.available_count` 是权威剩余手动重置次数；实现不会从 credits 列表或累计获得次数推导（`CodexProvider.swift:44-55`、`ProviderTests.swift:6-38`）。

单个信号都不足以确认具体窗口重置：

- 用量下降可能是数据修正或额度池变化；
- 边界提前变晚可能是手动重置，也可能是边界修正；
- `available_count` 减少只说明当前可用次数变少；额度可能被兑换，也可能到期或被服务端修正，并且不能指出 primary、secondary 或附加额度中的哪个窗口发生了切换。

只有在用户已经从官方客户端确认手动重置成功的上下文中，“次数减 1 + 某窗口用量下降 + 该窗口边界推进”才能形成强推断；TokenPulse 单独观察这些字段时证据仍然不足，也不应使用“已确认”文案。官方 Codex 协议还定义了 credit 的到期时间、状态和消费结果，但 TokenPulse 当前只读取汇总 `available_count`，未获得可直接归因到窗口的重置结果；证据见 `docs/provider-integration.md` 的 Codex 小节和 [官方账号协议](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/v2/account.rs)。

最小实测按 `docs/reset-boundary-detection-gap.md:140-157` 执行：用户在官方客户端执行一次手动重置，TokenPulse 或独立只读请求只采集前后响应，随后在旧边界前后继续采样。不得记录 Bearer token，也不得由 TokenPulse 调用消费接口。

### OpenCode Go

接口为 `GET /zen/go/v1/usage`。rolling、weekly、monthly 每个窗口只有 `status`、`percent`、`resetsAt`，没有周期 ID 或周期起点（`OpenCodeGoProvider.swift:7-72`）。

OpenCode 路由最终使用当前时间加 `resetInSec` 生成 `resetsAt`：[官方 `usage.ts`](https://github.com/anomalyco/opencode/blob/dev/packages/console/app/src/routes/zen/go/v1/usage.ts)。其 fallback 计算会区分窗口：[官方 `subscription.ts`](https://github.com/anomalyco/opencode/blob/dev/packages/console/core/src/subscription.ts) 中，正在使用的 rolling 窗口以最后更新时间加窗口长度作为结束点；过期且未使用时返回完整窗口秒数，因此查询所得绝对时间会跟随当前时间滑动；weekly 使用当前周结束点；monthly 使用订阅锚点计算月边界。剩余秒数取整后再叠加当前时间，还可能产生约一秒的边界抖动。路由可能先采用 inference proxy 的结果，所以源码说明了可能语义，不能直接证明当前线上账号一定走同一路径。

最小实测：三个窗口分别进行连续采样，并覆盖 rolling 从使用中到过期、闲置的状态变化。比较 `resetsAt - collectedAt` 与连续请求的绝对 `resetsAt`，核实线上 rolling 是否按状态在稳定边界和滑动预计时间之间切换，同时验证 weekly/monthly 是否保持各自的日历边界。

### Z.ai

私有接口 `GET /api/monitor/usage/quota/limit` 的 `limits[]` 返回 `type`、`unit`、`number`、用量字段，以及 `nextResetTime` / `next_reset_time`（`ZaiProvider.swift:37-66`）。没有周期 ID；当前窗口 ID 还包含响应数组下标，这个下标本身也不是周期身份。

`nextResetTime` 是唯一边界信号。公开 Z.ai 文档没有给出该私有路由的字段契约，仓库测试也只有单次响应（`ProviderTests.swift:253-275`）。由于窗口 ID 包含数组下标，服务端只要重排 `limits[]`，同一个业务窗口就会获得不同 ID；这会破坏告警账本身份，属于已经可由源码确定的风险。

最小实测：对每种 `type/unit/number` 保存连续原始响应，覆盖自然边界；同时验证 `limits[]` 重排后窗口 ID 是否稳定。若产品支持提前重置，再单独记录操作前后变化。

### MiniMax 国内版

`GET /v1/token_plan/remains` 的模型条目可能提供：

- 短周期绝对 `start_time/end_time`；
- 周周期绝对 `weekly_end_time`；
- 相对 `remains_time/weekly_remains_time`。

短周期只有在 `start_time < end_time` 时才采用绝对 `end_time`；否则直接用 `collectedAt + remains_time` 构造预计边界。周周期独立优先使用 `weekly_end_time`，缺失时才使用 `weekly_remains_time`（`MiniMaxQuotaClient.swift:81-180`）。当前短周期解析已经读取 `start_time`，但只用它计算周期长度，没有把周期起点传给通知领域模型。

因此必须逐窗口分级：带有效起止时间的短周期拥有 B 级候选信号，验证前仍按 D 级处理；周周期只有 `weekly_end_time` 时为 D 级；短周期缺少有效起止组合时，按实际回退结果分为 E 级（有 `remains_time`）或 F 级（无可用边界）。不能把这些形态统一视作稳定边界。

最小实测：对同一个 `model_name` 覆盖自然短周期和周周期，记录起止时间、状态、剩余比例和使用计数；确认 `start_time` 是否只在周期切换时改变，以及绝对字段是否会退化为相对倒计时。

### SuperGrok

主 billing 响应包含 `config.currentPeriod.start/end`，并兼容 `billingPeriodStart/End`；当前实现用起止时间计算周期长度，只把 `end` 保存为 `resetsAt`（`SuperGrokProvider.swift:61-78`）。主接口缺少使用率时，额外 credits RPC 可以返回使用率和 reset timestamp，该时间优先覆盖主接口结束时间（`SuperGrokProvider.swift:22-29,83-124`）。

`currentPeriod.start` 是当前接入中少数由服务端直接给出的候选周期起点，比单独结束时间更适合作为周期转换证据，但私有 billing 契约和真实账号行为尚未验证，因此当前仍是 D 级。credits RPC 的使用率和 reset timestamp 会覆盖主接口窗口的部分字段；使用主接口 `start` 解释 RPC 数据前，必须先证明两者代表同一个额度池和周期。

最小实测：同一真实账号在边界前后同时采集主 billing 与 credits RPC，确认 `currentPeriod.start` 是否稳定、是否在自然周期切换时改变，以及两条结束时间是否一致。

### Qoder 国际版

Qoder 返回个人额度和组织资源包的总量、已用、剩余、百分比及耗尽状态（`QoderProvider.swift:34-57`）。两个窗口都明确没有 `resetsAt` 和 `cycleID`；`expiresAt` 只保留为个人额度的到期信息，测试明确要求不能把它当成重置时间（`QoderProviderTests.swift:136-160`）。

当前可观察的是额度余额变化，而不是 provider 周期切换。统一启发式会在同一窗口用量下降至少 40 个百分点时创建新的推断周期，但套餐到期和余额恢复仍不构成 provider 确认。

### DeepSeek

官方 [`GET /user/balance`](https://api-docs.deepseek.com/api/get-user-balance) 只有钱包可用状态和各币种余额。窗口没有使用百分比、重置时间或周期 ID（`DeepSeekProvider.swift:37-60`、`WalletTests.swift:8-24`）。

充值、赠送、扣费和 `is_available` 恢复都是钱包状态变化，不是额度周期重置。DeepSeek 应继续完全排除在周期判定之外。

## 对通知模型的设计影响

### 1. 当前实现保持统一启发式

当前 `CycleResolution` 区分周期是否翻转，以及本次推断是否值得发送重置通知。周期身份使用 `.provider`、`.resetBoundary`、`.inferred` 和 `.unidentified`；没有引入完整的证据等级模型。上面的 A–F 等级保留为调查与真实账号验证框架，只有后续确实需要 provider 专属行为时才进入领域模型。

推断翻转可以重新武装额度告警，但用户文案统一为“额度已重置”；只有旧周期确实发过额度告警才发送该通知，避免空闲滚动窗口反复提示。

### 2. 展示边界和周期锚点分开

`WindowCycleState.resetAt` 当前既参与下一次重置判定，又被每次刷新覆盖为最新展示边界（`NotificationPlanner.swift:36-41,201`）。展示/预排应始终采用最新服务端时间；周期判定应保存独立证据，不能让展示时间更新静默改写判定语义。

### 3. 不要伪造 `cycleID`

MiniMax `start_time` 和 SuperGrok `currentPeriod.start` 值得保留，但它们应作为“提供商周期起点”建模，而不是转换成字符串冒充 opaque `cycleID`。先通过真实跨周期采样证明稳定性，再让它们参与周期切换。

### 4. 提供商语义应由窗口携带

如果实测证明确有稳定边界、滑动预计时间等差异，应由 provider parser 在每个 `QuotaWindow` 上携带最小证据类型，Planner 不应按提供商名称分支。MiniMax 同一提供商的不同响应形态已经证明该语义需要细化到窗口，而不是只细化到提供商。

## 验证优先级

1. **Codex**：唯一已有明确手动重置次数及现实缺口的提供商。完成一次用户主动重置前后只读采样。
2. **MiniMax、SuperGrok**：验证现有周期起点字段能否成为 B 级证据。
3. **OpenCode Go**：验证官方按剩余秒数生成的绝对时间在连续请求中是否稳定。
4. **Claude、Z.ai**：完成自然边界前后采样，判断绝对结束时间是否稳定。
5. **Qoder**：观察真实响应是否新增周期字段，并验证统一 40 点下降规则不会把组织资源包调整误判为频繁翻转。
6. **DeepSeek**：钱包没有重置设计，不需要周期实验。

跨提供商采样还必须覆盖以下对照场景：

- 结束时间只有秒级小幅抖动；
- 周期起点不变，但结束时间被修正；
- Codex reset credit 到期但用户没有执行重置；
- SuperGrok 主 billing 与 credits RPC 返回不一致的周期或额度池信息。

所有实测只保存必要且脱敏的响应字段，不记录 Cookie、Bearer token、API Key 或可识别账号信息。
