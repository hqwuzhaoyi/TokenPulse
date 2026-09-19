# OpenCode Go Provider 接入研究

> 研究日期：2026-09-09
>
> 原 Pulse 固定参考提交：[`8d7fd60454ce383dd0a136a30790c1e277f8069b`](https://github.com/qunqin24/Pulse/tree/8d7fd60454ce383dd0a136a30790c1e277f8069b)（2026-09-07）
>
> OpenCode 官方源码参考提交：[`830d5eb5354874105cc31599635a80c1662609e8`](https://github.com/anomalyco/opencode/tree/830d5eb5354874105cc31599635a80c1662609e8)（2026-09-09）

## 结论

原 Pulse 支持的不是“所有 OpenCode 用量”，而是 **OpenCode Go 订阅额度**。它用 OpenCode Go API key 请求 `GET https://opencode.ai/zen/go/v1/usage`，展示服务端返回的 5 小时滚动、每周、每月三个已用百分比与重置时间。

这一路径适合迁移到 TokenPulse：额度读取本身是无状态 HTTPS + Bearer key，不需要启动 OpenCode CLI，也不依赖 Mac 本地数据库或本地会话统计。iPhone 与 watchOS 可以独立发起同一请求。真正的平台差异在凭证来源：原 Pulse 的“自动读取 `~/.local/share/opencode/auth.json`”只适用于 Mac；iPhone/watchOS 必须使用用户录入并安全保存/同步的 key。

建议把 provider 命名为 **OpenCode Go**，固定展示三个标准窗口，并按这三个窗口参与通知：

| 能力 | 设计建议 |
| --- | --- |
| Provider | `OpenCode Go`，不要简称为泛化的 `OpenCode` |
| 套餐 | 固定显示 `Go`；不要从 usage 响应推断价格或 Zen 余额 |
| 概览 / 详情 / 小组件 | 5 小时、每周、每月均显示 |
| 额度告警 | 三个窗口都参与 |
| 重置提醒 | 三个窗口都参与；沿用“有实际用量才预排”的统一规则 |
| 凭证 | iPhone 输入 API key；共享给 Watch 后才能独立刷新 |
| 不接入 | Zen 按量余额、本地 `opencode stats` 历史、Mac `auth.json` 自动发现 |

## 原 Pulse 的实现

### Provider source 与接线位置

核心服务是 [`OpenCodeGoUsageService.swift`](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/OpenCodeGoUsageService.swift#L18-L155)：

- `Provider` 中是独立的 `.openCodeGo` case，显示名为 `OpenCode Go`，图标资源为 `opencode`。[`UsageProvider.swift` L8-L35、L64-L73](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/UsageProvider.swift#L8-L35)
- `UsageStore` 在全量刷新时构造 `OpenCodeGoUsageService(enteredKey:)` 并与其他 provider 并发请求。[`UsageStore.swift` L302-L341](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/UsageStore.swift#L302-L341)
- 手动刷新也只请求 OpenCode Go 自己，不依赖其他 provider。[`UsageStore.swift` L521-L550](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/UsageStore.swift#L521-L550)
- 原仓库自己的 provider 说明页明确标记：不支持额外账号，当前不读本地 transcript。[`opencode-go.md` L1-L7](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Docs/providers/opencode-go.md#L1-L7)

### 认证凭证来源与优先级

原 Pulse 按以下顺序取 key：

1. 用户在 Pulse Settings 粘贴的 key；非空时优先。
2. OpenCode CLI 保存到 `~/.local/share/opencode/auth.json` 的 `root["opencode-go"]["key"]`。
3. 两者都没有时返回 `.apiKeyMissing`。

源码证据：[`OpenCodeGoUsageService.swift` L25-L31、L69-L83](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/OpenCodeGoUsageService.swift#L25-L31)。原 Pulse 文档也写明了相同优先级。[`opencode-go.md` L9-L16](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Docs/providers/opencode-go.md#L9-L16)

OpenCode 官方文档说明 Go key 的获取方式：登录 OpenCode、订阅 Go、复制 API key，然后在 TUI `/connect` 中选择 `OpenCode Go` 并粘贴。[官方 `go.mdx` L41-L52](https://github.com/anomalyco/opencode/blob/830d5eb5354874105cc31599635a80c1662609e8/packages/web/src/content/docs/go.mdx#L41-L52) 官方 provider 文档确认 `/connect` 添加的 provider key 存储在 `~/.local/share/opencode/auth.json`。[官方 `providers.mdx` L16-L20](https://github.com/anomalyco/opencode/blob/830d5eb5354874105cc31599635a80c1662609e8/packages/web/src/content/docs/providers.mdx#L16-L20)

官方 CLI 源码进一步证明 `auth.json` 位于 `Global.Path.data`，API 凭证结构是 `{ type: "api", key: string }`，写入权限为 `0600`。[官方 `auth/index.ts` L7-L24、L52-L72](https://github.com/anomalyco/opencode/blob/830d5eb5354874105cc31599635a80c1662609e8/packages/opencode/src/auth/index.ts#L7-L24) `Global.Path.data` 来自 XDG data 目录下的 `opencode`。[官方 `global.ts` L0-L20](https://github.com/anomalyco/opencode/blob/830d5eb5354874105cc31599635a80c1662609e8/packages/core/src/global.ts#L1-L20)

原 Pulse 自己保存的粘贴 key 位于 `keys.dat`，每个 provider 分别 AES-GCM 加密，密钥材料包含 Mac 的 `IOPlatformUUID`。[`APIKeyStore.swift` L5-L24、L27-L48](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/APIKeyStore.swift#L5-L48)，[`LocalSecrets.swift` L12-L55](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/LocalSecrets.swift#L12-L55)

### 远端 endpoint 与请求

请求契约：

```http
GET https://opencode.ai/zen/go/v1/usage
Authorization: Bearer <OpenCode Go API key>
```

原 Pulse 使用 `URLSession.shared`，超时 15 秒，没有 request body，也没有依赖 CLI 子进程。[`OpenCodeGoUsageService.swift` L23-L36](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/OpenCodeGoUsageService.swift#L23-L36)

这个 endpoint 现在有直接的 OpenCode 官方服务端源码佐证：路由读取严格的 `Bearer` header，以 key 联查 user/workspace/billing；缺 key 或无效 key 返回 401，没有 Go entitlement 返回 403。[官方 `usage.ts` L8-L67、L89-L105](https://github.com/anomalyco/opencode/blob/830d5eb5354874105cc31599635a80c1662609e8/packages/console/app/src/routes/zen/go/v1/usage.ts#L8-L67)

需要保留一个稳定性边界：固定参考提交中的 Pulse 明确把该路径称为“未公开文档化、可能变化”。[`opencode-go.md` L18-L26](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Docs/providers/opencode-go.md#L18-L26) 截至官方源码参考提交，OpenCode 的公开 Go 文档列出了模型调用 endpoint 与 models endpoint，却仍未把 `/usage` 列在公开 endpoints 表中。[官方 `go.mdx` L254-L298](https://github.com/anomalyco/opencode/blob/830d5eb5354874105cc31599635a80c1662609e8/packages/web/src/content/docs/go.mdx#L254-L298) 因此它是“有第一方实现证据的服务端路由”，但不应包装成有兼容性承诺的公开稳定 API。

### 响应字段与额度周期

原 Pulse 解码的最小响应如下：

```json
{
  "usage": {
    "rolling": { "status": "ok", "percent": 12, "resetsAt": "2026-09-09T12:00:00.000Z" },
    "weekly":  { "status": "ok", "percent": 34, "resetsAt": "2026-09-14T00:00:00.000Z" },
    "monthly": { "status": "ok", "percent": 56, "resetsAt": "2026-10-09T00:00:00.000Z" }
  }
}
```

`usage` 以及三个 window 都是 optional；每个 window 的 `status`、`percent`、`resetsAt` 也是 optional。只有存在 `percent` 的 window 才会生成额度窗口。百分比会从 0…100 换算为 0…1，并 clamp 到范围内；`resetsAt` 同时接受带或不带毫秒的 ISO 8601。[`OpenCodeGoUsageService.swift` L85-L102、L123-L154](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/OpenCodeGoUsageService.swift#L85-L102)

映射关系：

| API 字段 | Pulse window id | 标准周期 | `windowSeconds` |
| --- | --- | --- | ---: |
| `usage.rolling` | `rolling` | 5 小时 | 18,000 |
| `usage.weekly` | `weekly` | 每周 | 604,800 |
| `usage.monthly` | `monthly` | 每月 | 2,592,000（原 Pulse 仅以 30 天作名义值） |

源码：[`OpenCodeGoUsageService.swift` L104-L122](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/OpenCodeGoUsageService.swift#L104-L122)。官方产品文档也明确列出 Go 的 5 小时、每周、每月三层额度，并说明这些额度以美元价值定义。[官方 `go.mdx` L121-L131](https://github.com/anomalyco/opencode/blob/830d5eb5354874105cc31599635a80c1662609e8/packages/web/src/content/docs/go.mdx#L121-L131)

官方 usage 路由直接返回 `usage.{rolling,weekly,monthly}`，每项由 `formatUsage` 规范成 `status`、`percent`、`resetsAt`。[官方 `usage.ts` L107-L150](https://github.com/anomalyco/opencode/blob/830d5eb5354874105cc31599635a80c1662609e8/packages/console/app/src/routes/zen/go/v1/usage.ts#L107-L150)

`percent` 的语义是 **已用百分比**，不是剩余额度。官方计算函数用 `usage / limit * 100` 生成 `usagePercent`；用尽时固定为 100。[官方 `subscription.ts` L49-L80、L83-L112、L114-L143](https://github.com/anomalyco/opencode/blob/830d5eb5354874105cc31599635a80c1662609e8/packages/console/core/src/subscription.ts#L49-L80)

`status` 的官方枚举只有 `ok | rate-limited`。因此原 Pulse 的“任何非 `ok` 都标记为 exhausted”在当前契约下等价于把 `rate-limited` 标记为耗尽；它不是从百分比自行猜测。[官方 `usage.ts` L144-L149](https://github.com/anomalyco/opencode/blob/830d5eb5354874105cc31599635a80c1662609e8/packages/console/app/src/routes/zen/go/v1/usage.ts#L144-L149)，[`OpenCodeGoUsageService.swift` L129-L142](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/OpenCodeGoUsageService.swift#L129-L142)

周期边界需要比原 Pulse 更精确：官方 rolling 长度来自服务端配置，当前产品文档定义为 5 小时；每周窗口固定为 UTC 周一 00:00 至下一周一；每月窗口以订阅时的 UTC 日与时刻为锚点，月末会收敛到当月最后一天，因此实际可能是 28、29、30 或 31 天。[官方 `subscription.ts` L49-L143](https://github.com/anomalyco/opencode/blob/830d5eb5354874105cc31599635a80c1662609e8/packages/console/core/src/subscription.ts#L49-L143)，[官方 `date.ts` L1-L35](https://github.com/anomalyco/opencode/blob/830d5eb5354874105cc31599635a80c1662609e8/packages/console/core/src/util/date.ts#L1-L35) 所以 TokenPulse 应把 monthly 识别为“月额度”并相信 `resetsAt`；不要用固定 30 天计算月周期已经过比例。原 Pulse 的 30 天值只适合作为分类/排序值。

### 套餐与余额

- 官方产品名为 **OpenCode Go**，当前官方文档称 `$10/month`。[官方 `go.mdx` L9-L14](https://github.com/anomalyco/opencode/blob/830d5eb5354874105cc31599635a80c1662609e8/packages/web/src/content/docs/go.mdx#L9-L14)
- 服务端内部模块仍使用 `lite` 命名，但对外 `planName()` 返回 `lite` 只属于服务实现细节；UI 不应显示 `Lite`。[官方 `lite.ts` L5-L18](https://github.com/anomalyco/opencode/blob/830d5eb5354874105cc31599635a80c1662609e8/packages/console/core/src/lite.ts#L5-L18)
- `/usage` 成功响应没有 plan 字段。原 Pulse 因此令 `plan = nil`，不根据额度窗口猜套餐。[`OpenCodeGoUsageService.swift` L57-L66](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/OpenCodeGoUsageService.swift#L57-L66)
- Go 可以在额度耗尽后选择回退到 Zen balance，但 `/usage` 当前只返回 Go 三个额度窗口，没有 balance 字段。官方文档只说明余额回退能力。[官方 `go.mdx` L228-L241](https://github.com/anomalyco/opencode/blob/830d5eb5354874105cc31599635a80c1662609e8/packages/web/src/content/docs/go.mdx#L228-L241) TokenPulse 第一版不应把 Go percentage 与 Zen 钱包余额合并。

### 错误处理

原 Pulse 的映射完整而简单：

| 条件 | 原 Pulse 状态 |
| --- | --- |
| 没有可用 key | `.apiKeyMissing` |
| URLSession 抛错 / 超时 / 无响应 | `.unreachable` |
| HTTP 401、403 | `.apiKeyRefused` |
| HTTP 429 | `.rateLimited` |
| 其他非 200 | `.serverError` |
| HTTP 200 但 JSON 无法解码 | `.unreadableReply` |
| 可解码但没有任何带 `percent` 的 window | `.noLimitsReported` |
| 至少一个有效 window | `.live` |

源码：[`OpenCodeGoUsageService.swift` L25-L66](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/OpenCodeGoUsageService.swift#L25-L66)。

一个可改进点：官方服务端已区分 401（缺失/无效 key）与 403（有效 key 但没有 Go subscription）。原 Pulse 把两者都映射成“key refused”。TokenPulse 若已有通用错误模型，建议把 403 展示为“此 key 没有 OpenCode Go 订阅”，证据来自官方路由的 `EntitlementError`。[官方 `usage.ts` L89-L104](https://github.com/anomalyco/opencode/blob/830d5eb5354874105cc31599635a80c1662609e8/packages/console/app/src/routes/zen/go/v1/usage.ts#L89-L104)

原 Pulse 在 provider service 之外还有统一的 last-good cache：请求失败时保留上次成功窗口并标记 stale，而不是清空卡片。[`UsageStore.swift` L390-L408](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/UsageStore.swift#L390-L408)

## Mac 本地依赖与跨设备迁移

### 哪些是 Mac-only

1. 自动读取 `NSHomeDirectory()/.local/share/opencode/auth.json` 假定当前设备存在 OpenCode CLI 的 XDG data 文件。
2. Pulse 自己的 `keys.dat` 加密密钥绑定 `IOPlatformUUID`，并依赖 `IOKit`。这个文件即使复制到另一台设备也无法解密。
3. OpenCode 的本地 sessions / `opencode stats` 没有用于 quota 请求，原 Pulse 明确把 `keepsLocalTranscripts` 设为 false。[`UsageProvider.swift` L91-L110](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/UsageProvider.swift#L91-L110)

### 哪些可以直接迁移

- endpoint、GET 方法、Bearer header、15 秒超时思想；
- `usage` / `rolling` / `weekly` / `monthly` Codable 模型；
- 已用百分比 clamp、ISO 8601 重置时间解析；
- 5 小时 / 每周 / 每月标准周期映射；
- HTTP 与解码错误分类；
- 三窗口展示、阈值告警和重置提醒。

这些逻辑只需要 Foundation 网络与解码能力；源码中没有 CLI 进程、本地数据库、浏览器 cookie 或 Mac IPC 参与请求。

### iPhone / watchOS 独立刷新结论

**可以，但前提是设备持有 API key。**

- iPhone：用户粘贴 Go API key 后可以直接独立请求远端 usage endpoint。
- Apple Watch：若希望 Watch 在 iPhone 不可达时仍刷新，Watch app 自己必须能读取一份安全保存的 key；只同步额度快照不算“独立刷新”。
- 不应尝试把 Mac 的 `auth.json` 或 `keys.dat` 作为移动端凭证来源。合理方案是沿用 TokenPulse 已有的跨设备 credential 机制；如果目前只同步 quota snapshot，则需要单独设计 key 下发与撤销。
- Go key 是 workspace 级权限凭证；应只传给明确启用独立刷新的设备，不写入普通 UserDefaults、Widget 配置或日志。

以上“可独立刷新”是从官方远端 Bearer API 与原 Pulse 的纯 HTTP 实现推导出的迁移结论，不代表 OpenCode 官方专门承诺 iOS/watchOS 客户端兼容性。

## 与当前统一额度策略的对齐

OpenCode Go 是“token plan 大多有短周期 + 周期上限”抽象的一个完整三窗口实例：

| 标准周期 | 原字段 | 概览 | 详情 | 小组件 | 额度告警 | 重置提醒 |
| --- | --- | --- | --- | --- | --- | --- |
| 5 小时 | `usage.rolling` | 是 | 是 | 是 | 是 | 有实际用量时 |
| 每周 | `usage.weekly` | 是 | 是 | 是 | 是 | 有实际用量时 |
| 每月 | `usage.monthly` | 是 | 是 | 是 | 是 | 有实际用量时 |

这里没有模型级辅助额度，也没有 Plus / Pro 分支。任一窗口字段缺失或没有 `percent` 时，仅忽略该窗口；三个都无效时整体报告“未返回额度”，不要补 0%。

## 接入前需要保留的边界

1. Provider 必须叫 `OpenCode Go`，避免把订阅额度误认为所有 OpenCode provider 的公共额度。
2. usage route 虽已有官方服务端源码，但未列入公开 endpoints 文档；解析器要小而宽容，错误要可见。
3. 不从 `status` 发明更多状态；当前官方只有 `ok` 与 `rate-limited`。
4. 不从三窗口推断 Zen 余额；API 没有返回余额。
5. 不读取或上传本地 OpenCode sessions；服务端 usage 已覆盖这个 key 对应账号的额度状态。
6. 移动端首版以手动录入 key 为主；Mac CLI 文件自动发现只能作为 Mac 平台增强能力。
7. 原 Pulse 固定提交没有 OpenCode Go 响应解析 fixture；迁移时应为完整三窗口、缺窗口、缺 `percent`、`rate-limited`、两种 ISO 8601 时间、401/403/429 和坏 JSON 补契约测试。
