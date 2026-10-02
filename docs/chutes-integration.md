# Chutes 订阅额度

`.chutes` 使用直接 API Key envelope，入口、凭证安全保存、多个账号 UUID 隔离、本机恢复/删除、iCloud、演示与 Watch 关注账号沿用现有流程。iPhone 与 Watch 各自发起 `GET https://api.chutes.ai/users/me/subscription_usage`，Bearer Key 只在认证头，不读取本机其它工具的凭证。不查询 per-chute 钱包/调用额，也不额外进行逐 chute 查询。每次 GET 禁止缓存，传输仅允许同源重定向。

## 一手契约与旧参考差异

2026-10-02 使用 agent-reach 的 GitHub 后端核对并固定官方 `chutesai/chutes-api` 提交 `3b5609f42f84e29dea374382ef1fa95b0fda329c`。其 [router.py 的 _get_subscription_usage](https://github.com/chutesai/chutes-api/blob/3b5609f42f84e29dea374382ef1fa95b0fda329c/api/user/router.py#L1221) 明确返回：

- `subscription=false`：无可用订阅，不生成零额度。
- `subscription=true`：`four_hour {usage, cap, remaining, reset_at}`；普通套餐另有 `monthly {usage, cap, remaining, reset_at}`。
- 自定义套餐的 monthly 为 `{uncapped:true}`，只限制四小时突发窗口。

[订阅配置](https://github.com/chutesai/chutes-api/blob/3b5609f42f84e29dea374382ef1fa95b0fda329c/api/config/__init__.py#L713) 明确 monthly_price 为 USD，四小时/月度 cap 由这个价格乘以固定系数；这是订阅可消耗的 **USD 预算额度**，不是请求数、token、积分或 API 钱包可用资金。预算原数通过原始 JSON 的 Decimal 解码及 `DecimalQuotaCounts` 存储，百分比仅用于 gauge。钱包和低余额提醒不适用。

[窗口函数](https://github.com/chutesai/chutes-api/blob/3b5609f42f84e29dea374382ef1fa95b0fda329c/api/invocation/util.py#L73) 和 [服务端窗口测试](https://github.com/chutesai/chutes-api/blob/3b5609f42f84e29dea374382ef1fa95b0fda329c/tests/unit/test_subscription_windows.py) 明确四小时为固定 bucket，而非过去四小时滚动计数；TokenPulse 显示“4 小时固定额度”。四小时长度来自接口字段 four_hour 的明确契约，不从重置时间猜长度；账期显示 monthly 周期身份但不合成 30 天重置。`reset_at` 使用接口提供的 ISO 8601；数字形式没有经一手契约确认，留空而不猜秒/毫秒。服务端给出的过去重置时间保留为待更新，不前移到未来。

[认证依赖](https://github.com/chutesai/chutes-api/blob/3b5609f42f84e29dea374382ef1fa95b0fda329c/api/user/service.py#L80) 支持 Bearer cpk_ API Key。本次没有真实 Key 或服务账号成功查询，这些源码证明契约实现，不能证明生产部署版本与所有账号响应相同。

固定旧参考 Pulse `397c8fc4f1bd52180a452d2f3f0c099def97cf69` 的 [文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/chutes.md)、[解析](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/ChutesUsageService.swift) 和 fixture 描述 subscription 对象、monthly.used/limit/credits 及 rolling_window.requests/limit/window_minutes/requests。它本身来自 CodexBar 合成 fixture。为保留已知线索，TokenPulse 只兼容这一组明确字段及 data/result 包装，不采用广泛别名归一、深层递归额度查找、四小时默认值或小于 1 乘 100 的比例猜测。旧 percent_used=0.5 就是 0.5%；旧窗口未提供明确 window_seconds/minutes/hours 则省略。旧请求数/credits 只用对应 unit，不当作当前 USD 预算。

## 缺失、无限与提醒

无订阅是 subscriptionRequired；订阅存在但没有可识别窗口是 noQuotaWindows；已用超过有效 cap 才标耗尽。缺失 cap 保持 total/比例未知，不补零；明确零 cap 不画满绿额度。严格 boolean/Decimal 类型拒绝 数值 0/1 伪装订阅或无限状态；非有限、负使用量、未知 shape 会失败保留旧快照。明确 uncapped 的窗口显示无限，百分比/计数/重置均为空，不触发额度或重置提醒。

有效预算窗口接入现有额度阈值、去重及预计重置提醒；没有假钱包余额或低余额提醒。App、widget 与 Watch 使用共享 exactCounts 原数和单位；采集时间、失败及过期状态来自同一快照。演示使用 USD 预算原数及固定四小时/账期窗口，在演示 suite 和内存凭证中隔离。固定 Lobe Icons 的 Chutes SVG，版权、MIT、路径、提交和模板矢量处理在 notices。

## 验证记录

已通过生产 module、9 项新增 `ChutesProviderTests`、7 项 Moonshot 和 9 项 Alibaba 测试的实际 Swift 6 iOS SDK typecheck，以及完整 App UI typecheck、PBX plist、diff 检查。脚本 `/tmp/tokenpulse-wave2-regional-static/check.py` 使用 Simulator26.5 SDK、arm64-apple-ios17.0-simulator 并执行新 XCTest 文件的 `-typecheck`，不是仅 parse。测试包含固定请求、Decimal USD 预算、uncapped、无订阅/缺限额/耗尽区分、未知字段和布尔/数字边界、旧 fixture 单位/百分比/时长、明确包装/不猜重置单位、HTTP/取消/跨 provider、widget/存档/提醒以及多账号恢复、失败保留、删除和另一个 monitor 自行刷新。

待 root 串行运行 `TokenPulseTests/ChutesProviderTests` 与完整 unsigned TokenPulse target build，覆盖 App/Widgets/Watch。没有启动 xcodebuild/模拟器或访问真实凭证。真实订阅 Key、服务器部署形状、普通/自定义套餐、真实 Key 失效、iCloud/Keychain 到达、关闭 iCloud 的设备生命周期、手机离线后的物理 Watch 查询、实际通知和 UI/widget 均仍未验收。源码、合成数据和独立 monitor 测试不能代替这些证据。

## Legacy Decimal regression repair (2026-10-03)

Pi02 found that the subscription-object compatibility branch still subtracted Double counters. With limit=1e17 and positive remaining=1e-23 it produced 100%, exhausted=true and an immediate 100% quota alert. Decimal added after a JSONSerialization/Double intermediate could not recover the original amounts.

The legacy branch now decodes only its known fields from original Data with typed Decimal values, including data/result wrappers. Used/remaining derivation reuses the primary branch's exactDifference inverse check. When Foundation cannot represent the difference exactly, reported total/remaining remain in partial exactCounts and derived usage, percentage and exhausted state stay unknown. Exhaustion compares Decimal used against total, rather than the Double percentage; the display-only near-100 guard is applied only after known exact used is less than total. No shared UI or reminder logic changed.

Four new regression tests cover naked/quoted 1e17/1e-23 and 1000/1e-13, preservation of known partial used/requests/remaining/limit values and coding through both wrappers, percent-only 0.5% with/without a limit, invalid/unknown rolling periods and inactive/expired subscription failures. Native Swift6 production-code replay compiled the actual parser plus NotificationPlanner and verified the original failures before the fix (two failures), then zero 100% alerts after it. The larger case keeps exact positive remaining and unknown usage/exhaustion; the smaller case keeps used=999.9999999999999, exhausted=false and percentage below100. Existing wrapper/partial/percent/duration/subscription replay checks also pass.

Artifacts: /tmp/tokenpulse-chutes-legacy-regression/before.log, after.log, run.py and main.swift. No xcodebuild or simulator was started; root performs integrated XCTest execution. Tests and replay use synthetic values only.
