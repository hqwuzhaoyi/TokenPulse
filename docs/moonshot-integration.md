# Moonshot 开放平台 API 钱包

本票实现 `.moonshot`，入口名称为“Moonshot API 钱包”，与 Kimi Code 套餐分开。添加和更新凭证都必须明确选择国内或国际；更换地区会要求重新输入该地区 Key。`ProviderRegion` 位于共享 Domain，配置与 Keychain 分开到达时，来源身份不符会在网络调用前拒绝旧凭证。

| 地区 | 唯一查询地址 | 币种 |
| --- | --- | --- |
| 国内 | `GET https://api.moonshot.cn/v1/users/me/balance` | CNY |
| 国际 | `GET https://api.moonshot.ai/v1/users/me/balance` | USD |

请求使用用户输入的 Bearer Key、禁止缓存，并沿用仅同源重定向策略。无论认证拒绝、限流或服务失败，都不去另一个地区试 Key。地区保存在 envelope 的 `metadata.region`；地区、provider 和 Key 的 SHA256 来源身份通过既有 `credentialIdentity` 路径保护缓存、同步与提醒去重。更换地区/Key 清除旧余额及旧提醒来源；更换地区同时取消旧币种选择，避免国内 CNY 选择隐藏新 USD 余额。账号 UUID 仍隔离多个账号。

响应必须明确包含 integer `code=0`、boolean `status=true` 和 `data.available_balance`。可用余额、`voucher_balance`（赠送）、`cash_balance`（充值）使用 Decimal，接受数值或严格十进制字符串，保留负数与零；可选明细缺失保持 nil，不补零，不换汇，不根据余额推断 API 可调用状态。钱包没有百分比、套餐周期或重置时间，App、Watch 与 widget 使用共享金额格式，仅开放低余额提醒。提醒仍支持阈值去重及恢复后重新提醒。

演示提供国内 CNY 与国际 USD 两个钱包，沿用演示 suite、演示 widget 快照和内存凭证隔离。图标使用 MoonshotAI 标记，与 Kimi Code 标记不同；Lobe Icons 固定提交、路径、版权、MIT 许可和模板/矢量改动在 `ProviderIconNotices.txt`。

2026-10-02 已验证：完整生产 module 与 7 项 `MoonshotProviderTests` 均通过实际 Swift 6 iOS Simulator SDK 类型检查；完整 App UI 的 Swift 6 typecheck、PBX plist 与 `git diff --check` 通过。类型检查命令记录在 `/tmp/tokenpulse-wave2-regional-static/check.py`，使用 `xcrun swiftc -swift-version 6 -sdk iPhoneSimulator26.5.sdk -target arm64-apple-ios17.0-simulator`；测试确实进行了 `-typecheck`，不是仅 parse。测试覆盖两地区请求/币种、无跨区回退、必选地区、严格状态与缺失字段、精确金额/负数、widget/存档、来源身份、换区清缓存和币种、本机恢复/账号删除/凭证隔离、iCloud 配置/旧 Key 分离到达防护以及独立 client 与提醒来源重置。

待 root 串行执行：`TokenPulseTests/MoonshotProviderTests` 及完整 unsigned TokenPulse target 构建（App、Widgets、Watch）。本 worker 未启动 xcodebuild 或模拟器。真实国内/国际 Key 查询、失效/撤销 Key、iCloud Keychain 到达、关闭 iCloud 的设备生命周期、手机离线后的物理 Watch 独立刷新与真实通知/widget 显示仍待验收。没有访问真实密钥；合成测试和类型检查不代替真实账号或设备证据。

契约来源为固定 Pulse `397c8fc4f1bd52180a452d2f3f0c099def97cf69` 的 [Moonshot 文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/moonshot.md)、[实现](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/MoonshotUsageService.swift) 和无秘密 fixture `Tests/PulseTests/Fixtures/moonshot-balance.json`。上游形状本身来自 CodexBar 的第二手契约，没有真实账号证据；TokenPulse 不采用它的跨区探测行为。生产契约兼容性仍需真实验收。
