# 69 OpenAI API：真实预付余额与组织费用边界

初次调查日期：2026-10-02；复核与实施：2026-10-03。结论：**官方 Admin Costs 有独立 HTTPS 查询契约，但它不是预付余额；legacy credit_grants 对当前账号/Key 的兼容性未验证**。本票不能因读取 costs 成功而宣布钱包接入可行。

## 来源与版本

- [固定 Pulse 文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/openai-api.md)及[客户端](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/OpenAIPlatformUsageService.swift)，commit `397c8fc4f1bd52180a452d2f3f0c099def97cf69`。上游明确余额 shape 来自二手插件/合成 fixture，没有真实账户 capture。
- 使用 **OpenAI Docs**，已搜索并实际打开[官方 Costs reference](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs)、[Admin API guide](https://developers.openai.com/api/docs/guides/admin-apis)及[Usage reference](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage)，于调查日读取。只以这些官方文档支持公开 API 结论，没有把社区帖子或 search snippet 当接口证据。

## 两种接口各自的契约

Pulse 的 legacy route 为 GET `https://api.openai.com/v1/dashboard/billing/credit_grants`，Bearer 使用用户明确配置的 key。预期 `total_granted/total_used/total_available` 和 `grants.data[]` 的 grant/used/expiry；可用余额只取实际 `total_available`，无字段/非法数值不能当 0。赠款不是单一额度窗口，不用 total_used/total_granted 画套餐百分比，不把 grant expiry 当未来充值或每月自动重置。

该 route 不在本次查看的当前官方公开 API reference 中。Pulse 注释称旧 user key 可用、project/admin key 不兼容，但这个兼容矩阵没有实际账号证据；本次仅确认上游设计，**不宣称今天所有旧 key 成功或所有新 key 必定拒绝**。没有官方钱包余额 API 承诺，也没有凭证下的请求结果。

公开 Costs route 为 GET `https://api.openai.com/v1/organization/costs`，`start_time` 必需，支持时间范围、分页/分组；Bearer 使用有 Admin endpoint 权限的 key。示例响应为 page `data[]` 的时间 bucket、`results[]` 的 `organization.costs.result`，金额 `amount.value` 与明确 `amount.currency`，可含项目/line_item 等字段。它提供历史消费，没有钱包 remainder、已充值总额、余额到期和套餐 allowance。读取日费、month-to-date 或全部历史费都不能算出未知余额；即使另有 spend limit，它也不是 prepaid wallet。

Pulse 在 legacy route 拒绝后探测 `organization/costs?start_time=<前一天>&limit=1`，成功说明该 key 在相应 Admin route 可用，却正确返回 no limits reported，没有读取费用作余额。这是能力判别，不是“余额查询 fallback”。Costs 失败也不能据此证明普通推理 key 无效，必须区别 credential 类型、权限与 endpoint 支持。

## 认证生命周期与设备限制

用户自己的静态 API/Admin key 可由手机明确配置；静态 Key 的 HTTPS 读取可在设备端实现，但公开官方支持与 legacy 私有接口兼容必须分别说明。它们没有此查询所需的 OAuth refresh-token 交换，撤销/轮换需用户更新 key；不能借用 Codex/ChatGPT OAuth 来读 OpenAI API 钱包。常规模型 project key、Admin key、dashboard web session 是不同 credential，不偷取浏览器 session，也不把官方推理 ephemeral token 当组织账单凭证。

[设备直连 ADR](../../../docs/adr/0001-device-side-refresh.md) 的独立 HTTPS 条件在静态 key 协议上可满足，Watch entitlement/网络与余额权限仍须实测。使用组织 Admin key 须明确是用户自己允许的账单访问能力；不执行创建/删除 key、充值、预算修改或推理。

- 已证实：Admin Costs 是当前公开接口，结果为消费；Pulse 没把费用算余额。
- 不可采用：Costs/Usage 推导钱包余额，未知上限生成环，ChatGPT/Codex token 混用、外部服务代查。
- 未验证：授权测试账号的 legacy credit_grants 可用性与正确金额、最小 key 权限、当前官方支持的 wallet route、双端实际读取与撤销。

## 可重复的最小验证（本次未执行账号步骤）

1. 重取固定 Pulse source，查看 legacy 与 costsProbe 分支；打开官方 Costs/Admin 文档确认金额语义。公开 source 可用同目录脚本重取。
2. 用户明确提供测试账号及为 TokenPulse 配置的 key 后，只 GET legacy route。记录 credential 类别、状态码/错误类别、是否有 total_available 与时间，不保存 key、grant 身份或组织资料。与当时官方账单钱包余额对照；无真实 total_available 就不能宣称完成真实余额验证（不影响当前实现加图标的关票标准）。
3. 若用户另行配置 Admin key，只 GET 最小 costs 范围验证权限，并把结果标成 spend；不能因为成功填补钱包缺失。普通 key 的 Admin 拒绝也保留为权限类别结果。
4. 在真实余额 route 可用后，Watch 手机离线时直接 GET，再测 key 撤销与更新；记录设备/OS、时间、脱敏金额及币种，确认两端旧缓存不冒充 live。
5. 分别记录 legacy/项目/Admin 类型的实际范围；若只有 costs 可用，结论是“该账号可做费用功能、未完成真实钱包验证”；不能用费用填补该账号的余额，费用功能要另有产品/实施决策。

## 2026-10-03 实施决定与当前验收

用户已将关票标准调整为完整实现加图标存在。未文档化与缺少凭证均不能证明路由废弃；本次官方检索/实际打开文档没有找到 credit_grants 废弃声明，也没有找到公开余额读取承诺。基于固定 Pulse 的明确 legacy contract，现实现窄兼容 `.openAIAPI`，显示名称与登录提示注明旧余额接口，兼容性因账号与 Key 而异。二手 shape 足以实现确定性的可审查客户端，但不能作为现时服务兼容矩阵或真实账户证明。

只 GET legacy route，合法 `total_available` JSON number 直接解码 Decimal，保留零与负数（实际欠额）；单位 USD 来自固定上游 contract。Lifetime grant/used 不作可用赠款明细，不推算百分比/重置/充值周期。403 为查询权限不足，401 为凭证错误，404 为路由/服务失败；不发 Costs probe，不把失败清为零，不删除用户 Key。响应 URL 同源校验与 transport 重定向策略避免跨域读数/凭证泄漏。静态 Key 采用现有系统安全存储、账号隔离、同步、Watch 直连与删除流程。

App、详情、Watch、Widget、纯钱包提醒、演示、注册与图标完成，七项合成 XCTest 已编写。小型实际 Foundation parser 运行与 Swift parse/PBX lint 通过；Xcode/XCTest 交 root 串行执行。本次仍未读取真实 Key、登录真实账号或完成设备真值实测，未将合成响应当实时接口证据。上述真实验证是可选后续证据，而非旧版票描述中的硬关票门槛。接入说明见 [docs/openai-api-integration.md](../../../docs/openai-api-integration.md)。
