# IBM Bob 实例与团队 Bobcoins

选择“IBM Bob”，输入一个安全复合凭证：

- `apikey:<通用 API Key>`：使用 `Authorization: Apikey`。需要在 Bob 门户创建 General 类型 Key；推理专用 Key 不适合读取管理用量。
- `token:<登录 JWT>`：使用 `Authorization: Bearer`。本机只检查 JWT 的结构及已声明的 exp，不在本地认证其签名；IBM 服务验证有效性和权限。token 到期后需更新，不尝试自动浏览器登录或 IAM 换取。

第一个英文冒号分开类型和秘密，API Key 内的冒号保留。拒绝未知前缀、空值、控制字符和非可见 ASCII。Key/token 和类型作为同一个 Keychain envelope 安全保存与同步，登录 token 的已声明到期时间随 envelope 保存。配置、缓存和提醒记录只保留从实际类型和秘密计算的摘要，不包含 Key/token；更换任何一个会使旧数据身份失效。关闭 iCloud 仍使用本机配置和 Keychain；删除沿现有同步 tombstone/凭证清理路径执行。没有读取 Mac、浏览器或真实用户凭证。

## 独立设备请求与域名限制

iPhone 和 Watch 自行读取各自已获得的凭证，直接 GET `https://api.us-east.bob.ibm.com/admin/v1/profile`，再查询每个有 user_id 的实例所属团队：

```
GET https://<允许的区域主机>/admin/v1/teams/{teamID}/users/{userID}
x-instance-id: <instanceID>
x-team-id: <teamID>
```

区域白名单仅包含 `api.us-east.bob.ibm.com` 和 `api.eu-de.bob.ibm.com`。裸 `us-east.bob.ibm.com` / `eu-de.bob.ibm.com` 可加 api 前缀，大小写与尾 DNS 点规范化；缺失区域使用 home。未知的其他 `.bob.ibm.com` 子域也拒绝。URL、端口、路径、userinfo、查询、片段、编码混淆均不能成为区域主机。所有实例的区域及 ID 先验证，再发送任何区域请求；后面的恶意区域不会导致先发出部分区域查询。实例/团队/user ID 只接受一个受限 ASCII 路径段并检查重复窗口身份，不允许 header 或路径注入。默认临时会话拒绝全部重定向。

2026-10-02 仅对这两个入口进行了无 Authorization 的公开 HEAD `/admin/v1/profile`，TLS 验证通过并返回 HTTP 401，证明当前服务入口存在。没有获取账号资料；这不是 Key、登录、预算响应或真实查询验收。后续服务新增区域需要独立核验后扩白名单，不自动信任响应中的域名。

## 每个预算池分别展示

每个窗口由实例 ID、团队 ID、user ID 稳定标识，范围显示实例名与团队名。各实例/团队的使用量、预算和重置时间独立，不计算跨团队总额或最早总重置时间；plan_name 仅作为计划说明去重展示。没有 user_id 的实例无法执行个人用量路由，会跳过；没有可查询的团队返回 subscriptionRequired。

Bobcoins 是 IBM 的计费用量单位，并不是钱包余额、美元或原始 token。本实现不套用官网当前套餐表的固定额度、不按标价把它兑换为钱。`usage` 和 `budget_limit` 使用验证后的 Decimal，保存在独立可选的 `DecimalQuotaCounts`；预算大于 0 时以 Decimal 计算剩余和比例，仅把比例转为有限 Double 供既有进度条/告警使用。实际用量可能超过预算，不据此断言 API 已阻断或用户不可超额付费。

团队明细回复未包含 budget_limit 时，可用 profile 独立报告的团队预算；明确返回 null 时保持预算未知，不回填有限 profile 值。缺少预算时显示“已用 X Bobcoins”和“预算未提供”，剩余、总额和比例保留缺失；预算明确为 0 时保留 0 而不除零或生成百分比。缺失/畸形 usage、负值、布尔值、NaN、不可表示的 Decimal、重复身份或无法读取的响应均视为失败。没有预算的成功回复与网络/凭证失败是不同状态；任何请求失败保留上一份同一凭证身份的成功快照与采集时间，新凭证失败不恢复旧数据。

月度由官方 Bobcoins 说明确定，但不把账期假定为固定 30 天。重置仅读取实例返回的 Unix 秒或 ISO 8601 refresh_at；缺失/0 不猜日期，非法格式拒绝。App、详情、Watch、小组件共享同一精确数量、范围、采集时间和过期规则。缺少分母时不开放百分比阈值；没有明确重置时间时不开放本提供商的重置开关。有正的已用量和明确重置时间时，沿既有规则预排“预计已重置”，不将它当作服务端确认恢复。Bobcoins 不触发货币低余额提醒。演示覆盖有预算和只报告用量的两个独立池。

## 核验依据与边界

- [IBM 官方 API keys](https://bob.ibm.com/docs/shell/account/api-keys)：Key 属于用户及订阅实例，General 和 Inference 类型的权限差异。
- [IBM 官方 Bobcoins](https://bob.ibm.com/docs/shell/account/bobcoins)：月度账期分配、额外消费、Bobcoins 与 token 不同。本项目不把当前价格表当 API 额度契约。
- [Pulse 397c8fc4 固定研究](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/ibm-bob.md) 和 [CodexBar 2cfa6325 IBMBobUsageFetcher](https://github.com/steipete/CodexBar/blob/2cfa63250079b96b00a0da10358001e676cee19d/Sources/CodexBarCore/Providers/IBMBob/IBMBobUsageFetcher.swift)：当前管理路由、Apikey/Bearer、profile/team 回复形状为源码核验及合成示例，尚无 TokenPulse 的真实账号捕获。TokenPulse 保持独立预算池，没有复制上游求和或无限预算补 0% 的显示行为。

`IBMBobProviderTests` 覆盖 API Key/JWT 类型与过期、路径/header/区域白名单、未知后续区域的提前拒绝、各实例独立 Decimal/重置、缺失/null/零预算、失败与无套餐区分、HTTP 错误、本机缓存保留/换 Key 清除/恢复/删除、独立额度提醒、只有已用量时的预计重置、Widget 和演示。共享 exactCounts 的可选化是独立 commit `01f4485`，兼容旧三项 initializer/存档，并有独立缺失与 0 区分的测试。

生产 Domain/Providers/Monitor/Demo/Reminder/WidgetKit 代码和上述新增 XCTest 源以 Swift 6 语义 typecheck 通过；App/Watch/Widget SwiftUI 文件完成语法验证，PBX 和 diff 检查通过。没有 xcodebuild、模拟器或 XCTest target 执行；完整 unsigned App/Widgets/Watch 构建与 XCTest 由 root 统一进行。没有真实账号凭证，真实登录、认证失效、profile/team schema、iCloud 到达和 Watch 在手机离线时刷新仍待验收，两个无凭证 401 不替代这些证据。

IBM 图标沿已有 Lobe Icons 源 commit `a94750e3f5f8fc33757b839d85030e742284e43a` 的 `packages/static-svg/icons/ibm.svg`，MIT，已记来源、版权、许可并按黑色/显式尺寸/矢量保留/模板渲染包装。官方 IBM/ibm-bob 仓库固定 `76fe1c08ecb27eba5b942e3f8b346218851f7465` 未提供适合此目标的矢量标记。资源在三个产品目标的编译仍待 root 完整构建。
