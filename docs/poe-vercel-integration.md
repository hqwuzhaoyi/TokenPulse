# Poe 与 Vercel AI Gateway 钱包接入

Poe、Vercel AI Gateway 接入与已有 DeepSeek 接入共用账号、Keychain、iCloud、刷新、失败保留、Watch 关注账号与 widget 快照流程。每个服务账号使用独立 UUID 保存凭证和数据；关闭 iCloud 后继续使用本地存储。iPhone 与 Watch 都使用 `ProviderQuotaClient` 直接请求端点，Watch 已取得配置和凭证后可以独立刷新。系统决定后台执行时机，不能保证定时刷新。

## 配置

- Poe：在 [Poe API Keys](https://poe.com/api/keys) 获取 Poe API Key；添加账号时选择 Poe，粘贴 Key。凭证通过 API Key envelope 存储，查询使用 Bearer header。不要粘贴浏览器 cookie。
- Vercel AI Gateway：在 Vercel AI Gateway 控制台创建 [AI Gateway API Key](https://vercel.com/docs/ai-gateway/authentication-and-byok#api-key)；添加账号时选择 Vercel AI Gateway，粘贴 Key。余额属于该 Key 对应的 team。这里不使用 Vercel 个人访问令牌或部署 OIDC token。

凭证写入现有凭证存储，不放入查询字符串、widget 或演示数据。删除账号沿用凭证删除和同步流程。

## 契约与语义

| 提供商 | 请求 | 读取字段 | 展示与提醒 |
| --- | --- | --- | --- |
| Poe | `GET https://api.poe.com/usage/current_balance` | `current_point_balance`，数值或数字字符串 | 明确的非货币 `points`，保留零；缺失或不可读即刷新失败，保留旧值。没有货币、百分比或重置提醒设置。 |
| Vercel AI Gateway | `GET https://ai-gateway.vercel.sh/v1/credits` | `balance`，精确十进制字符串 | USD，保留零和负余额。赠送/充值明细显示“未提供”。沿用可配置 USD 低余额提醒与去重、恢复后重新提醒。 |

二者使用 `Authorization: Bearer …` 与 `Accept: application/json`；不请求模型列表、历史消耗或分页明细。没有服务端额度总额、百分比、周期或重置时间，因此不生成这些指标。Vercel 的 `total_used` 是累计花费，不作为额度上限。无明确可用性字段时不根据余额臆造“无法调用 API”状态。

`WalletBalance.granted`、`toppedUp` 允许缺失；`isMonetary` 明确区分货币与 points，旧 DeepSeek 存档未带该字段时默认 `true`。DeepSeek 既有赠送、充值解析和人民币/美元提醒规则保留。App、Watch 详情和 widgets 共用余额格式；余额窗口不显示百分比环。采集时间与刷新失败状态沿用同一快照，失败不更新旧余额的采集时间。

演示模式增加 Poe points 与 Vercel USD 账号，仅使用演示 suite 和内存凭证。演示与真实账号、widget 数据继续隔离。

## 来源与验证边界

2026-10-02 使用 agent-reach 的 Exa 与网页后端核对 [Poe 当前余额 API](https://creator.poe.com/api-reference/getCurrentBalance)、[Poe Usage API](https://creator.poe.com/docs/resources/usage-api) 和 [Vercel AI Gateway REST API](https://vercel.com/docs/ai-gateway/sdks-and-apis/rest-api#check-credit-balance)。Poe 官方字段是 integer；数字字符串的兼容形式沿用 [Pulse 固定版本接入线索](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/poe.md)。Vercel 官方明确余额与累计花费单位为 USD。

Poe 图标使用固定版本 Lobe Icons；Vercel 使用官方 `vercel/vercel` 示例资产，版权、完整许可与改动记录在 `ProviderIconNotices.txt`。模板渲染和矢量保留在 image set 中声明。

`WalletProviderTests` 覆盖请求契约、错误映射、数值/缺失边界、旧钱包存档兼容、points 提醒隔离、USD 低余额去重/恢复，以及两个提供商多账号本地重开、凭证隔离、失败保留和删除。已有 `WalletTests` 与 `WalletPresentationTests` 覆盖 DeepSeek 与共用展示行为。

静态 Swift parse、Swift 6 domain/providers typecheck 与 PBX plist 检查已通过。完整 unsigned 构建及 XCTest 等待统一构建槽；真实 Key 查询、真实凭证失效、iCloud 跨设备同步和 iPhone/Watch 离线独立刷新尚未验收。本次没有读取真实密钥或启动模拟器。模拟响应和静态路由不能代替账号、设备验证。
