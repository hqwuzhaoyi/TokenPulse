# 64 Kiro：官方 portal 独立 HTTPS 路线

调查更新：2026-10-03。**已从官方公开网页 release 建立个人账号认证、额度查询和续期的原生 HTTPS 契约，并实现 `.kiro` provider。** 固定 Pulse 的本地 ACP 路线仍不可用于设备直连，但它不再是 Kiro 唯一可证实的查询入口。

用户当前验收口径是实现与图标存在。未进行真实登录、账号对照或 Watch 实机观察；这些是未观察事实，不是本票关闭的硬门槛。完整 iOS XCTest 和 unsigned 全目标构建交给主线程执行，本文不把小模块测试当成这些构建的通过证明。

## 新增官方证据与锁定版本

- [Kiro Web Portal](https://app.kiro.dev) 的匿名首页公开 `cdn-base-url` release `7641e207feab0c25`，并加载同版本 main/vendor。首页每次有 nonce，不能把动态首页哈希当作可重取的静态版本锁。
- [官方 main.js](https://assets.app.kiro.dev/releases/7641e207feab0c25/main.js)：614703 bytes，SHA-256 `38176f7972d2e0a24f8f856eabc044f335bf5afc8548f8040ec0e175feea11ff`。`is` hook 调用 `useGetUserUsageAndLimits`；`r9/c9` 添加 Bearer/CSRF；`A9` 在认证失败后调用 RefreshToken 并重试；`Md` 明确个人登录方式的 production profile；`tT` 为 SDK 设置 BFF endpoint 和 credentials include。
- [官方 vendor.js](https://assets.app.kiro.dev/releases/7641e207feab0c25/vendor.js)：3900540 bytes，SHA-256 `610e1a0770e6b325eef96bd09b071f07cbf38c3e6d018c0fbb0a9bf1799e0e78`。`YKn`/`KIRO_STAGE_TO_BFF_ENDPOINT_MAPPING` 定义 production 为 `https://app.kiro.dev`；`gFe/m_` 定义 POST、CBOR 与 operation 路由；`ut=S3(...,"KiroWebPortalService",...)` 定义 service 名；`gpt/i1t/Spt` 是 GetToken/RefreshToken/GetUserUsageAndLimits 的正式 schema。
- [Kiro 官方认证文档](https://kiro.dev/docs/getting-started/authentication/)说明个人 Google、GitHub、Builder ID 与企业登录方式；本次实施只支持默认 production portal 的前三种个人会话。ExternalOIDC、Identity Center 和其它区域不自动兜底到个人账号。
- [官方 ACP migration](https://kiro.dev/docs/cli/v3/acp-migration/)现已明确 `_kiro/account/getUsage` 供 `/usage` 使用。它仍是 ACP，不是 HTTPS URL；相较旧调查，这是公开程度变化，不是移动端协议本身。

main/vendor 和固定 Lobe 图标已加入 `public-source-lock.json`。2026-10-03 实际重新 GET 两份 release asset，锁校验 2/2 通过。仓库不保存大 bundle。

## 可实施的线上 wire 契约

所有原生请求只发往 `https://app.kiro.dev`。SDK 的默认协议是 `smithy.protocols#rpcv2Cbor`，不是 AWS JSON target dispatch，也不是把 ACP method 拼成云端路径。

| 操作 | POST 路径 | CBOR body | 返回字段 |
| --- | --- | --- | --- |
| GetToken | `/service/KiroWebPortalService/operation/GetToken` | 空 map | `accessToken` |
| RefreshToken | `/service/KiroWebPortalService/operation/RefreshToken` | `csrfToken` | `accessToken, csrfToken, expiresIn, profileArn`（schema 可选字段不补默认值） |
| GetUserUsageAndLimits | `/service/KiroWebPortalService/operation/GetUserUsageAndLimits` | `isEmailRequired: true, origin: "KIRO_IDE", profileArn` | `usageBreakdownList, nextDateReset, subscriptionInfo`，另有旧 `usageBreakdown/limits` 与 overage 字段 |

请求头为 Cookie、`Content-Type/Accept: application/cbor`、`smithy-protocol: rpc-v2-cbor`、`X-CSRF-Token`、`x-kiro-userid`；额度请求另带 GetToken 返回的 Bearer。官方 client 的 profile middleware 把个人 profileArn 加入 CBOR body。

2026-10-03 对公开 GetToken 路由做了一次**不携带 Cookie、CSRF 或任何凭证**的只读空 map POST。实际 HTTP 400、`application/cbor`、`smithy-protocol: rpc-v2-cbor`，响应类型 BadRequestException、消息为 CSRF token required。这验证路由与序列化协议被真实服务识别，**不证明登录后额度请求成功**。匿名错误使用 break 终止 CBOR map，因此 codec 支持有界 map/array indefinite containers，拒绝 indefinite strings、byte chunks、重复 keys、超长/深层/过量节点、非有限浮点与未知 tags。

匿名路由可复现：构造 `Data([0xa0])`（空 map），仅设置上述三项协议头，向固定 GetToken URL POST；不要设置 Authorization/Cookie/CSRF，不要调用推理、购买、登录或账户变更方法。

## 会话、身份与续期

账号专属非持久 WKWebView 让用户登录官方 portal；只导出 `app.kiro.dev/kiro.dev`、根路径可用的 Cookie，排除统计前缀与其它站点。此公开 bundle 没给客户端读取的 auth cookie 名，所以没有猜单一 cookie 名：导出 scope 后用原生 GET 首页核验 head 中的 stage、个人 idp、user-id、CSRF，继而由额度查询验证会话；不能只凭某个 Cookie 的存在宣布已登录。

原生 GET 首页不运行 JS。元数据只来自去掉 scripts/styles/comments 后的 head，重复或不完整字段拒绝。user-id 是个人身份；profileArn 是官方公开服务 profile，不能拿它当个人 ID。source identity 为 origin/local account UUID/已核验 user-id/profileArn/idp 的哈希。每次查询重新验证身份相同。Cookie 内容仍由 generic envelope 指纹保护，但轮换不会改变缓存的个人 scope；AccountQuotaClient 保存轮换凭证后，QuotaMonitor 仍能接纳同一账号的快照。

每次刷新先获得新的短期 Bearer，Bearer/CSRF 不持久化或伪装成永久 API key。401 只触发一次该阶段的官方 RefreshToken 重试，缺字段、scope 改变或再次失败要求重新登录。原生响应的根路径 secure Set-Cookie 在当前账号 jar 内按 name 替换/删除；逐 Cookie 的已知到期表写入 envelope metadata，并重算最早到期。新 expiry 替换旧 expiry，不使用 `min(old,new)` 把续期锁在旧期限。没有服务器到期信息的浏览器 session Cookie 保持 unknown，依靠服务的认证结果失效；不编造永久有效期。撤销和完整生命周期尚未通过真实账号观察。

## 额度语义

解析主路径是明确的 `usageBreakdownList`，不回退猜测 ACP response。主要 decoded shape 如下（是字段契约示意，不是实际用户响应）：

```json
{
  "subscriptionInfo": { "subscriptionTitle": "string" },
  "nextDateReset": "CBOR tag 1 epoch timestamp",
  "usageBreakdownList": [{
    "resourceType": "CREDIT or SANDBOX_RUNTIME",
    "displayNamePlural": "string", "unit": "string",
    "currentUsage": "number?", "currentUsageWithPrecision": "number?",
    "usageLimit": "number?", "usageLimitWithPrecision": "number?",
    "freeTrialInfo": { "freeTrialStatus": "string", "freeTrialExpiry": "timestamp?", "currentUsage": "number?", "usageLimit": "number?" },
    "bonuses": [{ "status": "string", "bonusCode": "string", "expiresAt": "timestamp?", "currentUsage": "number?", "usageLimit": "number?" }],
    "overageCredits": [{ "expiresAt": "timestamp?", "currentUsage": "number?", "usageLimit": "number?" }]
  }]
}
```

官方页面优先 WithPrecision 字段，fallback 到普通字段；TokenPulse 相同，但不仿照网页把缺字段补 0。数值不能是 Bool、字符串、负数或非有限值。订阅池显示月度额度及返回的 reset；试用、active bonus 和可明确标识的 purchased credits 是到期额度，不宣称周期 reset。resourceType/bonusCode 是已知维度；credit expiry 仅标识同资源的到期 cohort，不能当单笔 pack 唯一身份。官方 OverageCredit 只有 currentUsage/usageLimit/expiresAt，没有 pack ID。单笔沿原路径显示实际 quota；同资源同刻到期的多笔显示“多笔同刻到期，单池标识未提供”cohort，保留真实 expiry，比例/计数/exactCounts/exhausted 全部 unknown，不求和、不填0、不声称无限，不用下标或可变用量伪造单池ID。其它月池、试用、bonus和不同expiry单笔继续显示。缺expiry仍按原契约拒绝。

credits 是非货币配额；即使响应有 currency/overageCharges，也不凭这些把有限 quota 或预付 credits 转成可提现钱包。未知限额不补 0、不算百分比，已用计数可单独显示。无有限池的明确空 list 显示静态无额度状态。

## 历史路径与限制

[固定 Pulse ACP transport](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/KiroACPClient.swift)和[usage parser](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/KiroUsageService.swift)仍用于说明原研究为什么受阻，固定 SHA 是 `397c8fc4f1bd52180a452d2f3f0c099def97cf69`。前身 AWS Q 源码和第三方 Hermes Kiro plugin 只作线索；新实现不复制其客户端注册、不运行 CLI，不读本机数据库或 Keychain，不把 localhost endpoint 猜成云端。

实现遵守 [设备直连 ADR](../../../docs/adr/0001-device-side-refresh.md)：iPhone/Watch 使用同步的本账号 session，自己执行 HTTPS，不需要电脑常驻或代理。企业、其它区域、真实会话撤销、浏览器登录兼容性和 Watch 离线行为没有实际账号观察，不扩大本次个人默认 portal 支持范围。

## 本次验证与后续观察

- 小范围 Swift 6 生产 module 语义检查通过；来源是实际 Models、Kiro provider/codec、HTTP/redirect 与按原文件抽出的通用 session/envelope 部分，未使用伪同名类型替换接口。
- macOS 命令行实际 XCTest：23 tests，0 failures，日志 `/tmp/tokenpulse-kiro-small/test.log`。覆盖独立 CBOR hex fixtures、边界拒绝、scope、未知字段、expiry/renewal、Cookie 更新与重启。
- 第24项 iOS AccountQuotaClient → QuotaMonitor 回归已提交，包含凭证落盘、同 scope 新快照接纳、重启后跨旧 expiry 查询、widget/demo/icon/registration；该用例及 unsigned 全目标由主线程运行，尚不在本报告宣称通过。
- Kiro 图标使用固定 Lobe MIT 源，资产与 mapping 存在，官方 `kirodotdev/kiro` 固定 `bfe7ff30d9b21e583566c844d75e3dd2b572e2c7` 只有 PNG、未建立可复用 SVG 许可，故遵循现有 Lobe 来源。

可选择的真实观察：在独立账号浏览器登录个人账号，与官方额度页对照；等待 Bearer/Cookie 到期或撤销；Watch 手机离线查询。未执行这些观察不阻塞用户当前的实现+图标验收，也不被写成成功。

## Pi06 回归处理（2026-10-03）

锁定公开 main/vendor 的 SHA256 与原锁完全一致，没有读取真实凭证或运行外部账户。

- F1：冻结快照漏widget case属旧缺陷，root已用ca87270修复，24项真实iOS XCTest与77provider unsigned build由root确认通过。本补丁不重复修改。
- F2：接受同expiry不等于唯一pack的缺陷。官方schema为 `Cut=[3,B,fYe,0,[x_,hM,tq],[1,1,4],2]`，符号解为currentUsage/usageLimit/expiresAt；main HM保留extraCreditPacks列表，未发现同expiry可相加证据。采用有界到期cohort，不整snapshot失败，不合并计数或猜单池身份。cohort无用量/ratio，实际NotificationPlanner不生成额度提醒或周期重置计划。
- F3：不采纳缺可选expiry就丢弃ACTIVE有效quota的建议。nonResettingAllowance只表示无周期重置；共用UI nextEventValue显示无周期重置，不是永不过期。仅Kiro未知expiry trial的window.name补到期时间未提供，App/Watch/widget使用同displayName，保留实际计数与比例。
- F4：不采纳改用任意page profile-arn。官方main Md对Google/Github取SOCIAL_PROFILE_ARN，对BuilderId/Internal取BUILDER_ID_PROFILE_ARN，只有其它idp才fallback meta。vendor production常量正是现实现的两枚ARN。当前支持Google/Github/BuilderId，企业/其它stage/Internal仍不在支持范围。新增不同meta ARN及三个支持idp的实际回归，保持官方映射。

实际验证：真实生产小module（Models、Kiro/CBOR、HTTP/redirect、从当前源码抽取的session/envelope定义、QuotaFormatting及NotificationPlanner/ReminderModels）Swift6编译；实际macOS命令行XCTest **28 tests，0 failures**，日志 `/tmp/tokenpulse-kiro-pi06/test.log`。新增5项覆盖同expiry保留月池/unknown字段/不报警、顺序/用量/pack数变化的cohort稳定性、不同expiry单笔不变、畸形/expired边界、trial未知expiry文案及官方profile映射。iOS专属Monitor回归不在这28项中；新补丁完整iOS XCTest和unsigned build留root统一执行。

Pi原报告日期2025-10-03笔误不沿用，本次实际日期为2026-10-03。真实个人账号/Watch观察仍未执行。
