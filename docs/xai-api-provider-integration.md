# xAI API 团队预付余额

xAI API 是开发者平台团队的预付余额，和 SuperGrok 的消费者订阅是不同提供商，不共享凭证、窗口或身份。选择“xAI API”，填 `TeamID:ManagementKey`；使用第一个英文冒号分开，Key 内的冒号保留。需要 console.x.ai → Settings → Management Keys 创建的管理 Key 和账单读取权限。普通推理 Key 不能访问 Management API；不通过猜测 Key 前缀判定权限，服务端拒绝按无效凭证处理。

凭证整体保存在本机 Keychain，并沿现有可关闭的 iCloud Keychain 路径同步。Team ID 与 Key 同属于该账号的安全 envelope；团队 ID 仅允许一个 1–128 字符的 ASCII 字母/数字/下划线/横线标识（首字符为字母或数字），UUID 格式兼容。拒绝斜杠、点段、百分号编码、查询、片段和控制字符，不能改变域名或路径。Key 不写入配置、额度缓存或日志；配置保留计算出的团队+Key 摘要。修改团队或 Key 会使旧余额/提醒身份失效，旧同步快照不能覆盖新绑定，其他团队账号不受影响。本机保存、恢复与删除沿统一账号生命周期执行。

iPhone 和 Watch 获得这份凭证后，各自发起唯一的只读 GET：

```
https://management-api.x.ai/v1/billing/teams/{teamID}/prepaid/balance
Authorization: Bearer <ManagementKey>
```

默认传输使用临时会话且拒绝全部重定向。没有访问 inference API、浏览器 Cookie、使用历史或充值写接口，也不需要手机、Mac 或新增代查服务。

## 金额含义

官方账单参考把 `total` 定义为 USD Cents，并展示充值账本项 `amount.val: "-1000"`。固定参考实现将负账本 `total.val` 取反并除以 100，故 `"-1234"` 显示 `12.34 USD`；正账本值可对应负可用余额。使用严格十进制字符串和 Decimal，拒绝缺失、数字/布尔类型、NaN、科学记数法、垃圾尾缀、超精度及下溢，不将不可读回复补成 0。

这是已入账的团队预付账本。CodexBar 的真实账号观测说明在账期结算前，尚未入账的消费会使它高于控制台实时余额；本项目没有自行验证这一账号行为，界面和说明明确这一局限。历史充值变化不是当前赠送/充值余额明细，也不是套餐上限。本实现不推导百分比、周期重置或“可否调用 API”状态；缺失钱包明细保持 nil。

账号卡片、详情、Watch 和小组件使用相同 USD 钱包与采集时间。USD 低余额提醒使用现有金额阈值、持续低余额去重和恢复后再提醒规则；默认 2 USD，可修改。钱包不开放百分比或重置提醒设置。查询失败保留同一团队/Key 身份的旧成功余额与时间并标记失败；更新凭证后查询失败不会恢复前一团队的数据。演示有独立 xAI 团队 USD 钱包，沿本机演示隔离存储使用。

## 来源和验证边界

- [xAI 官方 Management API guide](https://docs.x.ai/developers/management-api-guide)：管理 Key 和推理 Key 分开，固定 `management-api.x.ai` 域与认证方式。
- [xAI 官方 Billing REST reference](https://docs.x.ai/developers/rest-api-reference/management/billing#list-prepaid-credit-balance-and-balance-changes)：GET 路由、string Team ID、`total` 的美元分单位及负充值示例。
- [Pulse 397c8fc4 接入研究](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/xai-api.md) 与 [CodexBar 2cfa6325 自己的账号观测说明](https://github.com/steipete/CodexBar/blob/2cfa63250079b96b00a0da10358001e676cee19d/docs/xai.md)：倒置账本与已入账/实时差异。没有将它们的真实验收当 TokenPulse 真实验收。

`XAIAPIProviderTests` 覆盖负/正/零/微小 Decimal 分金额、畸形缺失值、团队路径注入、认证角色、固定请求、HTTP 失败、Team/Key 改变后恢复与旧同步拒绝、多团队隔离、钱包提醒恢复/去重、Widget 和演示。生产 Domain/Providers/Monitor/Demo/Reminder/WidgetKit 代码及新增 XCTest 源以 Swift 6 语义 typecheck 通过；PBX plist lint 和 diff 检查通过。

没有读取真实用户 Key、访问真实团队或启动模拟器/xcodebuild。XCTest 执行与 unsigned 完整 App/Widgets/Watch 构建由 root 统一运行，当前仍待补证。真实管理 Key 权限/失效、真实账本读取、iCloud 凭证到达和 Watch 在手机离线时独立刷新均未验收。

图标沿项目既有 Lobe Icons 源，commit `a94750e3f5f8fc33757b839d85030e742284e43a`，`packages/static-svg/icons/xai.svg`，MIT，来源与版权记录于 `ProviderIconNotices.txt`；黑色、显式 24×24、模板与矢量保留已配置，跨目标资源编译待统一构建。
