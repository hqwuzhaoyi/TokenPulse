# v0 Platform Key、账期 credits 和消息限流

配置 v0 Platform API Key，由现有账号 UUID 隔离的安全凭证存储、账号恢复/替换/删除与 iCloud 配置同步处理。手机和取得凭证的 Watch 各自发起直接查询，不需要另一设备在线。两条请求是只读 `GET https://api.v0.dev/v1/user/billing` 与 `GET https://api.v0.dev/v1/rate-limits`，使用 Bearer/JSON Accept，禁用自动 Cookie和缓存，继承跨 origin 重定向阻断；不读本机桌面配置或其他应用 Key。

契约依据固定 [Pulse V0UsageService](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/V0UsageService.swift) 和 [说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/v0.md)。该版本来自 CodexBar 及其引用 API 文档的二手形状，不能替代真实账号验证。

`billingType=token` 读取 `data.balance.total/remaining` 和 `data.billingCycle.end`；`legacy` 读取 `data.limit/remaining/reset`。其余类型失败并保留旧快照。两种账期统一为 `v0.billing`，单位仅为 v0 的 credits，不擅称美元或货币钱包；`onDemand.balance` 的单位没有可信证据，本次不展示。

消息限流独立为 `v0.rate_limit`，单位“条消息”。辅助请求失败或其响应不可读不会丢掉本次取得的有效账期额度；这次不复用旧限流数据并贴上新的采集时间，而在卡片、Watch、组件明确显示“消息限流：未提供”。账期缺失剩余额度时同样不制造百分比，若另一窗口有效则可单独显示并注明缺失。

额度计数接受服务的非负 JSON 数字或十进制字符串，以 Decimal 保存与相减；`exactCounts` 用于各端精确显示，环形百分比仅转有限 Double。未知/缺失 remainder 不填零，布尔、非有限、负数和剩余额度超过上限的矛盾拒绝。只有实际报告的 0 才代表耗尽。缺少两者有效窗口时是 noQuotaWindows，不将格式坏的账期回答当无套餐。

时间支持 Unix 秒、≥10¹² 的毫秒、数值字符串及 ISO；0 仅表示没有重置。时间必须有限且毫秒可由 Int64 表示。账期长度、消息限流长度均未确认，归为 other，不捏造 30 天或一天周期。只有报告的 reset 用于预计重置和过期状态，预计提醒不能证明恢复。钱包低余额与手动重置设置不适用；缺少 reset 时不展示重置开关。已有使用阈值去重规则分别处理两个窗口。

演示包含两个分开单位的窗口，本机存储与真实账号隔离。七个专项测试覆盖 token/legacy、请求头/顺序、辅助失败、缺失 remainder、无币种余额省略、Bool/计数矛盾/时间溢出、通知/编码/组件/demo、多账号恢复/替换/删除/失败保留及辅助请求取消。App 全源与新测试 Swift6 typecheck 已验证；root 串行执行 unsigned 完整构建和模拟器测试，本分支不启动模拟器。

图标采用官方 [vercel/v0-sdk](https://github.com/vercel/v0-sdk/tree/4e1613d8a861e7d53abac212eb5ee924bb792de5) 的 `examples/v0-clone/apps/web/app/icon.svg`，固定 `4e1613d8a861e7d53abac212eb5ee924bb792de5`，Copyright 2025 Vercel, Inc.，Apache 2.0。提取原始两个 glyph path、去背景/CSS，保留 180×180 viewBox，黑色模板与矢量；来源、改动和许可已记录。

未真实验收：真实 v0 Key、当前账期形状/单位、生产消息限流、mobile/watch Key 兼容、撤销和失效、iCloud 到达、物理 Watch 独立查询、通知与组件视觉表现。没有真实账号或硬件证据，不宣称接入验收完成。

生产 v0 解析代码 macOS 合成 smoke 通过：credits/messages 单位、秒/毫秒重置、缺失 remainder、坏辅助数据保留账期、Bool/计数矛盾/时间溢出。不是模拟器 XCTest 或真实账号证据。
