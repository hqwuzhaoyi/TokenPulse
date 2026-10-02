# Hyper 的 HC 余额

添加 Hyper 服务账号并粘贴 API Key，只读取 `GET https://hyper.charm.land/v1/credits`，Bearer header 携带凭证。官方接口返回该 Key 认证团队的 Hypercredits 余额；没有团队切换选择器。App/Watch 共用设备直连路径，按账号 UUID 保存与同步凭证/缓存，支持本机恢复、删除及 iCloud 关闭；不读取浏览器或 CLI 登录态。

`balance` 必须为非负 JSON 数字，Decimal 解码保留数值；零有效，负值、缺失、null、布尔及数字字符串均不可读，不补零。单位为服务积分 HC，`WalletBalance.isMonetary=false`。不采用兑换率、不生成套餐百分比/总额、月度重置或时间。即使网站描述每月免费积分，当前余额接口没有给出账号当期上限和重置，因此不据此推导。

卡片、详情、Watch 与 widgets 显示实际 HC 和同一采集时间，失败保留旧余额；没有货币低余额、额度或重置提醒设置，也不会误触发这些提醒。演示 HC 和真实账号继续隔离。

2026-10-02 agent-reach 核对 [Hyper 官方 credits 文档](https://hyper.charm.land/docs/api/credits.html)，并参考 [Pulse 固定版本](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/hyper.md)。Hyper 官方 pi-hyper-provider 仓库和 Lobe Icons 未发现可复用 Hyper 品牌 SVG；使用平台原生 `bolt.circle` 作为通用图标，未复制品牌图形，更没有误用 Hyperbolic 的标志。此选择记录于 ProviderIconNotices.txt。

4个 HyperProviderTests 覆盖 HC/零/精确小数、负/缺失/类型边界、非货币提醒排除/widget、Bearer GET 错误与多账号失败保留/重开/删除。完整 App iOS Swift6 module 与相关 XCTest 静态 typecheck、PBX/diff 检查通过；实际 XCTest、unsigned 全目标构建、真实 Key/团队余额/失效、iCloud 和 Watch 独立刷新仍未验收。本次未访问真实凭证。
