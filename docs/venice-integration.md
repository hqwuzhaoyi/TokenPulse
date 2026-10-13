# Venice 的 USD 与服务积分余额

添加 Venice 并粘贴 API Key，使用 Bearer GET `https://api.venice.ai/api/v1/billing/balance` 查询认证用户。App 与 Watch 自行请求，不读取浏览器 session；按账号 UUID 隔离凭证、缓存、恢复、同步和删除，iCloud 关闭时本机可用。

验证 `canConsume` 的布尔类型和 balances 对象；余额支持 JSON 数字或严格十进制字符串，null/空白字符串保持缺失，其他无效值报错。服务明确指定 USD、DIEM、BUNDLED_CREDITS 或 EARNED_CREDITS 时，只显示对应 usd、diem、bundledCredits、earnedCredits 字段；该值缺失不自动换成另一单位。VCU 按官方 deprecated Legacy Diem 命名读取 diem，但保留返回的 VCU 单位，不做换汇。未指定消费单位时优先已返回 USD，再 DIEM、earnedCredits、bundledCredits；所有缺失不补零。USD 以 Decimal 保留零和负数；DIEM、VCU、Bundled/Earned credits 均按非货币服务单位展示，不触发美元低余额提醒，不合计各余额池。

余额不生成百分比、额度总额或 reset；`canConsume` 只验证类型，不转成 0/100%，`diemEpochAllocation` 不推导时间周期或使用率。卡片/Watch/widget 显示同一实际单位；从 USD 切到 DIEM 后，旧 USD 提醒选择不能隐藏新 DIEM 读数，货币提醒 controls 自动隐藏。此前 USD 告警历史不因另一单位或缺失观测伪造恢复。演示 DIEM 与真实状态隔离，失败保留旧值与采集时间。

2026-10-02 agent-reach 核对 [官方 Billing Balance](https://docs.venice.ai/api-reference/endpoint/billing/balance)、[VVV/DIEM](https://docs.venice.ai/overview/vvv-diem)，以及 [官方 swagger 固定版本](https://github.com/veniceai/api-docs/blob/0af24850577f540988ffd8cdd967119e7699c90e/swagger.yaml)。当前 BillingBalanceResponse 已明确 bundledCredits、earnedCredits 字段；api_keys/create 说明 VCU 是 deprecated Legacy Diem。网页搜索索引返回的旧 schema 缺少新字段，本实现以下载的当前官方 schema 和固定 swagger 为准，正常兼容新单位。旧 [Pulse 固定版本](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/venice.md) 仅作为初始 USD/DIEM 线索。未知单位或服务指定单位的余额缺失会明确失败保留旧数据，不套用旧上游美元 fallback。

官方 veniceai/api-docs 没有可复用的仓库许可，venice-mcp-server 未找到可用 SVG；使用固定 Lobe Icons venice.svg，MIT 来源与版权记在 ProviderIconNotices.txt。

5个 VeniceProviderTests 覆盖消费单位优先、精确 USD/零/负、缺失和类型边界、Bundled/Earned/VCU 当前单位支持与未知单位拒收、USD→DIEM widget/提醒一致、GET 契约/错误与多账号本地恢复/失败/删除。完整 App iOS Swift6 module 与相关 XCTest 静态 typecheck、PBX/diff 检查通过；实际 XCTest、unsigned App/Widgets/Watch 构建、真实 Key/失效/iCloud 和 Watch 独立刷新尚未验收。没有读取真实密钥，合成响应不等于真实接入证据。
