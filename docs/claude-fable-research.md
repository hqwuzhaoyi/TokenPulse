# Claude Fable 额度研究

研究日期：2026-09-09

研究范围：Claude Fable 的额度数据形状、套餐语义，以及 TokenPulse 的展示接入建议。本文只记录证据和设计建议，不修改应用代码。

## 结论

1. Fable 额度是**模型级、每周周期的作用域上限**，不是第二份独立的账号周额度。它和账号级 `weekly_all` 同时存在，并从同一个套餐周额度中消耗。
2. 新版响应中的可靠识别方式是遍历 `limits[]`，选择 `kind == "weekly_scoped"` 的条目，并使用服务端返回的 `scope.model.display_name` 作为名称。当前可见名称是 `Fable`，不应把实现绑定到固定模型版本名或虚构 `seven_day_fable` 字段。
3. 该条目的周期是每周：`group == "weekly"`；用量来自 `percent`，重置时间来自 `resets_at`。`percent` 按 0–100 百分数解释，`resets_at` 是可空的 ISO 8601 时间字符串。
4. Fable 模型可用于所有付费计划，但“套餐内 Fable 周上限”并不属于所有付费计划。当前官方规则是：Max、Team 高级席位、旧版席位制 Enterprise 高级席位包含 Fable；Pro、Team 标准席位和旧版 Enterprise 标准席位从一开始走 usage credits；用量制 Enterprise 和 API 按 API 计费。
5. 因此 TokenPulse 应当**按服务端实际返回的 scoped window 展示**，不存在时隐藏，不能仅凭套餐名推导或构造 Fable 额度。

## 响应字段

Claude Code 2.1.260 自带的第一方客户端校验器接受以下 usage 结构（省略与本研究无关的字段）：

```json
{
  "limits": [
    {
      "kind": "weekly_scoped",
      "group": "weekly",
      "percent": 37,
      "resets_at": "2026-09-14T00:00:00Z",
      "scope": {
        "model": {
          "display_name": "Fable"
        }
      }
    }
  ]
}
```

字段语义：

| 字段 | 结论 | 处理建议 |
| --- | --- | --- |
| `kind` | Fable 行属于 `weekly_scoped` | 用作额度种类，不用模型名猜周期 |
| `group` | 当前为 `weekly` | 用于校验/诊断；实际周期仍映射为 7 天 |
| `scope.model.display_name` | 服务端展示名，当前为 `Fable` | 原样保存为 scope；UI 可显示“Fable 周额度” |
| `scope.model.id` | 第一方客户端 2.1.260 的校验器不要求该字段 | 不依赖，不把空值当异常 |
| `percent` | 数字型已用百分数，按 0–100 解释 | 存入 `usedPercentage`；不要再次乘以 100 |
| `resets_at` | 可空 ISO 8601 字符串 | 有值则解析；缺失时仍可展示百分数，但不安排重置提醒 |
| `severity`、`is_active`、`locked_reason` | 私有响应可能附带；第一方校验器允许透传未知字段 | 不以 `is_active` 决定是否展示；耗尽状态可谨慎使用明确字段或 `percent >= 100` |

`percent` 的 0–100 语义并没有公开 API 契约；证据来自 Pulse 的解析（除以 100 存为 fraction）、Claude Code 的 usage UI/缓存形状以及实际客户端处理方式。它不是 0–1 的 fraction。示例中的数值仅用于说明结构，不是本机账号数据。

## 套餐语义

Anthropic 官方说明（页面在研究当周更新）：

- Fable 5 和 Fable 5.1 对所有付费计划可用。
- Max、Team 高级席位、旧版席位制 Enterprise 高级席位：Fable 是套餐标准部分，最多可使用常规周额度的 50%。Fable 使用也会消耗常规周额度，并且消耗速度更快。
- Pro、Team 标准席位：Fable 不包含在套餐额度中，从一开始使用 usage credits。
- 旧版席位制 Enterprise 标准席位：只有组织启用 usage credits 后才能使用。
- 用量制 Enterprise 和 Claude API：按标准 API 费率计费。
- 之前针对 Fable 5 的促销已于 2026-07-19 23:59:59 PT 结束，Fable 5.1 从未属于该促销。

这意味着 Fable scoped row 表达的是对共享周池的**子上限**：例如 Fable 显示剩余空间，并不代表账号在 `weekly_all` 已耗尽后仍有另一份可独立使用的额度。

来源：[Anthropic：Claude Fable models on your plan](https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan)。

## 第一方客户端证据

本机安装的官方 Claude Code：

- 版本：`2.1.260`
- 文件：`/Users/admin/.local/share/claude/versions/2.1.260`
- SHA-256：`3c269f66801028823e24a63ced9fdd3988cb86cf85fccd9f03f87e463b9d3e3c`

从该官方客户端产物可复核到：

- usage 请求为 `GET /api/oauth/usage`；
- 响应校验器允许顶层 `limits` 数组；每项包含必需的 `kind`、`group`、`percent`，可空的 `resets_at`，以及可空的 `scope.model.display_name` / `scope.surface.display_name`；
- 客户端筛选 `kind == "weekly_scoped"`，再按动态配置的模型展示名匹配，最终标题为 `Current week (<display_name>)`；
- 模型列表来自动态配置 `tengu_usage_overage_included_models`，说明客户端没有把额度实现硬编码为某个 Fable 版本；
- 第一方客户端将 `seven_day_overage_included` 映射为 `Fable limit`，但这是响应 header 的统一限流 claim 名称；usage 页面数据仍来自通用的 `limits[].weekly_scoped`，不能据此发明 JSON 字段 `seven_day_fable`。

可复核命令：

```bash
claude --version
shasum -a 256 /Users/admin/.local/share/claude/versions/2.1.260
grep -abo 'weekly_scoped' /Users/admin/.local/share/claude/versions/2.1.260
```

本机 `~/.claude.json` 的脱敏结构核对也确认 `cachedUsageUtilization.utilization.limits[]` 使用相同字段；核对时只读取了键名、类型和 scope 展示名，没有记录账号标识、百分数或重置时间。

### 证据边界

`/api/oauth/usage`、`claude.ai/api/organizations/{id}/usage` 以及 `limits[]` 都不是 Anthropic 面向第三方发布的稳定公共 API。官方帮助中心确认产品和套餐语义，但**没有公开这些响应字段的正式契约**。Claude Code 二进制属于第一方客户端实现证据，仍可能随版本改变；接入必须容忍字段缺失和未知 kind。

## Pulse 固定提交与最新版

核查对象：

- 固定提交 [`8d7fd60454ce383dd0a136a30790c1e277f8069b`](https://github.com/qunqin24/Pulse/tree/8d7fd60454ce383dd0a136a30790c1e277f8069b)（2026-09-07）
- 研究时最新 `main`：[`56218e735367eab487401a03fc89e284ccf0ad9e`](https://github.com/qunqin24/Pulse/tree/56218e735367eab487401a03fc89e284ccf0ad9e)（2026-09-09）

两者的 Claude usage parser 在本研究相关部分一致：

- 优先解析 `limits[]`；
- `session` 映射为 5 小时；
- `weekly_all` 和 `weekly_scoped` 映射为每周；
- scoped 名称取 `scope.model.display_name`；
- `percent / 100` 转为内部已用 fraction；
- `resets_at` 按 ISO 8601 解析；
- ID 由 `kind + scope` 组成，因此账号周额度和 Fable 周额度不会互相覆盖。

固定提交中没有出现 `Fable` 专用分支，也没有 Fable 专用字段；它通过通用的 `weekly_scoped` 支持 Fable。这是应保留的设计方向。

来源：[固定提交 parser](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/ClaudeCodeUsageService.swift)、[固定提交 Web session 路由](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/ClaudeDesktopSession.swift)、[最新版 parser](https://github.com/qunqin24/Pulse/blob/56218e735367eab487401a03fc89e284ccf0ad9e/Sources/Pulse/Providers/ClaudeCodeUsageService.swift)。

## TokenPulse 当前状态

当前 `ClaudeProviderClient.windows(_:)` 已具备基础解析能力：它接受 `weekly_scoped`、读取 `scope.model.display_name`、把周期映射为 7 天，并把 `percent` 原样存入 `usedPercentage`。因此，服务端返回 `display_name: "Fable"` 时，数据层理论上已经会产生独立的 Fable 周额度窗口。

现有自动测试只用 `Sonnet` 验证 scoped window，没有覆盖 Fable 的真实名称和展示策略；这可能让“通用解析已支持”和“产品界面明确支持 Fable”之间存在验收空档。

## 实现建议

### 数据模型

- 保持通用 `weekly_scoped`，不要新增 Fable 专用 provider 字段或枚举。
- 窗口稳定标识继续由 provider + kind + scope 构成；显示名使用服务端 `display_name`。
- 对空白 `display_name` 的 scoped row 可使用通用“模型周额度”，但不要猜成 Fable。
- 同一响应若未来返回多个 `weekly_scoped`，全部保留，并以稳定的服务端顺序或明确排序展示，不要只取第一项。

### 展示

- 账号级主窗口：`5 小时额度`、`每周额度`。
- Fable scoped window：建议显示为 `Fable 周额度`，并在详情中说明“包含在共享周额度内”，避免用户误认为多了一份额度。
- 若小组件容量允许展示三个环，可展示 5 小时、账号每周、Fable 每周；容量不足时优先保留账号级窗口，Fable 放详情或支持用户选择。
- 服务端不返回 Fable row 时不占位、不显示 0%、不根据 Max/Pro 猜测。

### 通知

- 若产品决定 scoped window 参与通知，应沿用通用窗口通知策略，而不是新增 Fable 特判。
- 通知标题必须带 scope，例如“Fable 周额度已使用 80%”，不能只写“每周额度”。
- `resets_at == null` 时可做阈值告警，但不能安排重置通知。
- Fable 与 `weekly_all` 可能同时跨阈值；建议按窗口分别提醒并在文案中区分，避免错误去重。
- 不要因 `is_active == false` 隐藏或跳过通知。第一方客户端的 usage 展示筛选不依赖该字段，它更可能表示当前绑定/严重性，而不是窗口是否存在。

### 最小验收用例

1. `session + weekly_all + weekly_scoped(Fable)` 同时返回时生成三个不同窗口。
2. Fable 行显示服务端名称、周周期、百分数和独立重置时间。
3. 未返回 scoped row 时只显示账号级窗口，不制造 Fable 0%。
4. `resets_at: null` 时仍显示百分数，但不产生重置通知。
5. 两个不同 `weekly_scoped` 同时返回时均保留，ID 不冲突。
6. scoped 通知包含 `Fable`，与账号每周通知可以独立去重。
