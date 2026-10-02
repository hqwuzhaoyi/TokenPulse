# Atlas Cloud 钱包

添加账号时选择 Atlas Cloud，输入具有账户余额读取权限的 API Key。账户 owner、Account Admin 或 Finance Key 的具体权限由 Atlas Cloud 管理。App 与 Watch 共用设备直连 client；Key 进入既有按账号 UUID 隔离的凭证存储、同步及删除流程。iCloud 关闭时使用本机状态与凭证。不会读取 CLI 文件或其他应用凭证。

查询 `GET https://api.atlascloud.ai/public/v1/balance`，只使用 Bearer header，不把 Key 放入 URL。必须是 `object=balance`、`scope=account`，`available.value` 为精确十进制字符串，`currency` 为三个 ASCII 字母并按返回值大写显示。金额保留零和负数；赠送、充值明细未提供时保持缺失。不读取模型花费或 Coding Plan，不从余额生成使用率、总量或重置时间。

卡片、详情、Watch 和 widgets 使用同一余额快照，失败保留旧余额与采集时间；演示余额为独立演示数据。货币低余额提醒使用既有按币种阈值、去重和恢复后重新提醒规则。只有钱包时不提供套餐告警或重置设置。

2026-10-02 使用 agent-reach 核对 [官方余额文档](https://www.atlascloud.ai/docs/zh/public-api/balance) 和 [Billing Public API](https://www.atlascloud.ai/docs/en/public-api) 的账户范围与余额权限；参考 [Pulse 固定契约](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/atlas-cloud.md)。检查官方 AtlasCloudAI/atlascloud_comfyui 仓库未找到可复用品牌 SVG，使用固定 Lobe Icons `atlascloud.svg`，来源与 MIT 许可记在 ProviderIconNotices.txt。

AtlasCloudProviderTests 覆盖 scope、币种、数字类型、零/负余额、精确小数、Bearer GET/状态码、多账号不同余额、离线恢复、失败保留、删除和 widget 采集时间。完整 iOS App Swift 6 module 及相关 XCTest 静态 typecheck、PBX plist 和 diff 检查已通过；XCTest 执行、unsigned App/Widgets/Watch 构建及真实 Key、权限失效、iCloud 跨设备与 Watch 独立刷新仍待集成/设备验收。本次没有读取真实密钥，模拟响应不能替代真实验收。
