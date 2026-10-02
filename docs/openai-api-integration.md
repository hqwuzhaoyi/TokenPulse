# OpenAI API Legacy 余额接入

TokenPulse 的“OpenAI API（Legacy 余额）”只查询旧 `GET https://api.openai.com/v1/dashboard/billing/credit_grants`。用户在手机或 Watch 主动配置自己的 Key，凭证复用系统安全存储和既有按账号同步/删除机制；两端各自 HTTPS 查询，无 Mac 或外部代查进程。静态 Key 不自动刷新，撤销、过期或轮换后需更新。

旧接口兼容性因账号与 Key 而异，未列入本次核对的当前公开 API 文档，也未找到官方废弃声明。没有保证所有旧 user key 有效，或所有 project/Admin key 无效。接口不可用时显示查询失败与已有缓存时间，无法读取余额。不会使用 ChatGPT/Codex 的凭证，也不自动收集浏览器 session。

余额只取响应 `total_available` JSON number，以 Decimal 保存；零、负数与细小金额保留。USD 来自固定 legacy contract，响应未显式提供币种。缺失、null、Boolean、字符串或非法/非有限数字均失败，不补零。`total_granted`、`total_used` 与逐笔 grant expiry 不代表当前赠款明细或单一套餐额度，所以不作为赠款/充值 breakdown、不计算环或未来 reset。App/详情/Watch/Widget 都显示钱包余额，适用低余额提醒，无套餐百分比/重置提醒。

请求仅向固定 api.openai.com URL发送 Bearer，15秒超时、不用HTTP缓存；transport限制同源重定向，客户端再校验响应同源。401表示凭证错误；403保留为账单查询权限不足；404等为服务/路由失败，429为限流。不会因账单权限拒绝删除 Key，也没有向 Organization Costs 发验证或兜底请求。

当前公开 Organization Costs 返回历史消费 buckets，不是余额、充值总额或 allowance，不能从消费求出未知余额。即使 Admin key 可以读取 Costs，也不由此宣称余额接入成功。

## 来源与验证边界

2026-10-03 使用 openai-docs 实际打开官方 [Costs reference](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs)、[Admin guide](https://developers.openai.com/api/docs/guides/admin-apis) 与 [Error codes](https://developers.openai.com/api/docs/guides/error-codes)。这些官方资料支持消费与信用耗尽错误语义，不承诺 legacy balance route。

通过 agent-reach 的 GitHub/gh读取 [Pulse source](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/OpenAIPlatformUsageService.swift) 与 [fixture](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Tests/PulseTests/Fixtures/openai-api-credit-grants.json)，固定 commit `397c8fc4f1bd52180a452d2f3f0c099def97cf69`。它明确 shape 来源为 CodexBar 二手实现及合成 fixture，并非真实响应。TokenPulse 没采用上游 Costs probe，也没有继承其未经实测的通用旧 Key 成功承诺。

七个合成 XCTest 覆盖 Decimal/零/欠额、缺失/非法/Costs不冒充余额、GET/权限错误与不探测Costs、provider/kind隔离、异源响应、账号缓存/重启/删除、Widget/demo/提醒。Swift parse、PBX lint、实际 Foundation parser 边界运行通过，完整 Xcode 与 XCTest 由 root 串行整合；本票没有启动构建或模拟器。

图标复用已存在 ProviderCodex OpenAI SVG，路径、固定来源与 MIT 许可见 ProviderIconNotices.txt，vector/template 配置已存在。本轮用户验收为实现加图标存在；没有真实账号、当前 Key 类型兼容矩阵、手机/Watch独立读取或撤销实测证据。后续可由用户主动配置 Key，核对 `total_available` 与官方 billing页，再验证 Watch离线直连、撤销/更新；不保存真实 Key或组织身份在测试记录中。
