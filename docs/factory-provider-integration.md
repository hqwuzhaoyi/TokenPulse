# Factory 套餐接入与验证边界

用户在 `app.factory.ai` 的 Settings → API keys 取得 Factory Key，在 iPhone 添加账号或重新配置凭证。TokenPulse 不读取 `.factory`、环境变量、浏览器 Cookie 或桌面应用凭证；Key 沿用账号 UUID 隔离的安全存储、配置同步及删除流程。iCloud 关闭时本地账号可用；Watch 收到配置与凭证后直接请求 Factory，同一实现用于 iPhone 和 Watch。

契约固定于 [Pulse 397c8fc4 Factory 源码](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/FactoryUsageService.swift) 和 [说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/factory.md)。该版本的响应形状来自 CodexBar，无真实账号捕获；这些路由属于网页计费接口，不能视为稳定公开 API。

请求均为只读 GET，Bearer Key 只发往 `api.factory.ai`，包含 `Accept: application/json`、`x-factory-client: web-app`、`Origin: https://app.factory.ai`、`Referer: https://app.factory.ai/`。禁用自动 Cookie，继承跨 origin 重定向防护，并核对响应 host/scheme。

1. `/api/app/auth/me` 决定凭证是否有效，获取可选套餐名与 `userProfile.id`。
2. `/api/billing/limits`：只有真实 Bool `usesTokenRateLimitsBilling=true` 且存在 `limits` 才选新计费。路由请求失败（取消除外）、标志缺失/false 或缺少 limits 按固定上游转到旧接口。明确选中新计费但额度结构畸形时失败，不能用旧 Standard/Premium 冒充新池。
3. `/api/organization/subscription/usage?useCache=true&userId=...`：URLComponents 编码用户标识，读取旧计费；身份没有返回用户标识时仅传 useCache。

新计费的 Standard/Core 分别按 fiveHour、weekly、monthly 展示，标识为 `factory.rate.{pool}.{period}`。`usedPercent` 明确按百分比处理。Core 全零且没有时钟时省略，缺少数值不补零；窗口已结束且没有新的正 secondsRemaining 时省略。重置优先正 `secondsRemaining`，否则未来 `windowEnd`。支持 epoch 秒、超过 10¹² 的毫秒、数值字符串和 ISO 日期；所有时间和计算必须有限且毫秒可由 Int64 表示，不将账期月份捏造成固定 30 天。

旧计费的 Standard/Premium 使用 `factory.legacy.standard` / `.premium`，互不混入新 Core。`usedRatio` 明确按 0…1，允许上下 0.001 的浮动；零缓存比例与正已用量/有效限额矛盾时由 `userTokens / totalAllowance` 修正。否则可信比例优先，或两项有效计数回退；缺少限额时不把 ratio>1 猜成百分比。超过 10¹² 的限额按固定参考的无限哨兵显示“无限”，没有假分母、百分比或提醒。日期到期的旧周期不生成新的成功窗口。

`extraUsageBalanceCents` 独立显示“附加用量余额”，原始单位为 `cents（币种未提供）`。响应没有 currency，上游 USD 来自未验证的价格推断，因此本实现不构造 WalletBalance、不换算金额，也不开放该项低余额提醒。这笔附加用量与套餐池不相加。将来若取得明确币种证据，可接入已有混合钱包展示及独立钱包提醒接口。

提醒沿用套餐已用阈值及服务明确重置时间，未知余额和无限额度不触发额度/余额/重置提醒。错误保留上次成功数据与采集时间；所有组件通过统一窗口映射显示数值、单位和日期。演示包含新 Standard/Core 与旧 Standard/Premium 两个独立账号，沿用本机隔离演示存储。

图标取自 Factory 官方 [factory-zed-extension](https://github.com/Factory-AI/factory-zed-extension/tree/6a5d674f5e106d63ff25346c3d1e607db525e2f0) 的 `droid-zed.svg`，固定 `6a5d674f5e106d63ff25346c3d1e607db525e2f0`，Apache 2.0。黑色模板化及匹配 viewBox 调整、来源和完整许可位于 ProviderIconNotices.txt。

验证：新增 FactoryProviderTests 覆盖新旧路由、Headers、账号 ID 编码、真实 Bool、有限数和时间、旧缓存比例冲突、缺失/无限/过期、未知币种、提醒、组件、多账号恢复/替换/删除和失败保留。App 全源及新增测试已做 Swift 6 iOS Simulator 17.0 静态类型检查。unsigned 全目标构建和模拟器测试由 root 串行执行，本票不自行运行。

尚未真实验收：Factory Key 查询、当前新旧计费选择条件、Core 发放、无限哨兵、额度已用尽、实际账号重置、附加余额币种、真实凭证失效、iCloud 凭证到达、物理 Watch 独立刷新、提醒与组件外观。未访问、输出或捏造真实凭证；静态/合成结果不能代替这些验收。

额外验证：生产 Factory 解析代码的 macOS 合成响应 smoke 通过新旧池身份、零缓存比例修正、Core 省略、真实 Bool、有限数/时间溢出拒绝、过期窗口和未知币种余额检查。未执行模拟器 XCTest。
