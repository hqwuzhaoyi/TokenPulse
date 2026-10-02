# DeepInfra 钱包与支出上限

添加账号选择 DeepInfra 并输入 API Key，使用设备直连 `GET https://api.deepinfra.com/payment/checklist?compute_owed=true`。Bearer header 承载凭证，API Key 不进入 URL；账号 UUID 隔离的安全保存、恢复、同步、删除与 iCloud-off 本机使用沿用既有流程，Watch 得到凭证后自行查询。

`stripe_balance`、`recent` 是服务返回的 JSON 数字，用 Decimal 解码与运算。负账本表示预付资金；可用 USD 为 `-(stripe_balance + max(recent,0))`，未结算支出只扣一次。欠费保留负余额，明确零有效。赠送与充值明细没有给出时保持 nil。

仅 `limit>0` 产生独立支出上限窗口，用 `max(recent,0)/limit` 计算比例；exactCounts 保存精确 USD 用量、剩余和上限。没有上限、零或负上限时只显示钱包。API 没有给出账期长度或重置时间，因此保持 other/nil。`suspended` 不转成 100% 额度或余额比例。卡片、Watch、详情和 widgets 同时展示钱包与实际预算；额度与低余额提醒独立，没有时间就不提供重置设置。失败保留旧数据、采集时间与单位。

2026-10-02 agent-reach 核对 [DeepInfra 官方 Checklist schema](https://docs.deepinfra.com/api-reference/billing/get-checklist) 的 Bearer、compute_owed、数值类型与倒置账本含义；待结算扣除采用 [Pulse 固定版本契约](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/deepinfra.md)，仍待真实账号校验。图标使用固定官方 deepinfra/docs 的 logo/light.svg，将 viewBox 裁至品牌符号并保留路径，明确尺寸与黑色模板填充；完整仓库 MIT 许可及版权见 ProviderIconNotices.txt。

6个 DeepInfraProviderTests 覆盖精确预付/欠费/零、负 recent、正/零/缺失限额、停用不造百分比、类型错误、混合 widget/独立提醒、固定请求和多账号恢复/失败/删除。完整 App iOS Swift6 module 与相关 XCTest 静态 typecheck、PBX 与 diff 检查通过；XCTest 执行、unsigned 全目标构建、真实 Key/失效/iCloud 和 Watch 独立刷新未验收，本次没有读取真实密钥。
