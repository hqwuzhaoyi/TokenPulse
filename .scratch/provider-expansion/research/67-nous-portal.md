# 67 Nous Portal：独立 OAuth 会话与双端续期研究

调查日期：2026-10-02。结论：**官方客户端有远程 device-code 授权、刷新与账号额度读取；独立 TokenPulse 客户端许可和双端会话隔离未验证**。同一个一次性 refresh token 经 iCloud 同步后由两端续期会触发 replay 风险，不能作为实现方案。

## 来源与版本

- [Pulse 文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/nous-portal.md)与[provider](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/NousPortalUsageService.swift)，固定 commit `397c8fc4f1bd52180a452d2f3f0c099def97cf69`，只借用 Hermes access token。
- Nous 官方 Hermes Agent commit `b7200efef01dce2097c3c5556843ff3cd2764789`：[constants](https://github.com/NousResearch/hermes-agent/blob/b7200efef01dce2097c3c5556843ff3cd2764789/hermes_cli/auth_constants.py)、[device flow](https://github.com/NousResearch/hermes-agent/blob/b7200efef01dce2097c3c5556843ff3cd2764789/hermes_cli/auth_device_flow.py)、[refresh](https://github.com/NousResearch/hermes-agent/blob/b7200efef01dce2097c3c5556843ff3cd2764789/hermes_cli/auth_nous.py)、[account query](https://github.com/NousResearch/hermes-agent/blob/b7200efef01dce2097c3c5556843ff3cd2764789/hermes_cli/nous_account.py)。这是官方实际客户端协议。
- [官方 Portal 集成文档](https://hermes-agent.nousresearch.com/docs/integrations/nous-portal)，调查日公开读取。文档的 loopback 登录描述与源码 device flow 均存在，应记录所选方式，不能只按旧文档判断必需本机 callback。

## 认证与查询契约

Portal base 默认 `https://portal.nousresearch.com`。官方 client ID 为 `hermes-cli`，default scope 为 `inference:invoke`，另有 `billing:manage`；本次没有证明 TokenPulse 可以复用该 client ID、可注册新 client，或只读 account 最小 scope 是什么。独立会话指新登录产生的 token chain，不是复制 Hermes token 文件。

Device flow：form POST `/api/oauth/device/code`，字段 `client_id`、可选 `scope`；返回 `device_code/user_code/verification_uri/verification_uri_complete/expires_in/interval`。用户在浏览器确认后，form POST `/api/oauth/token`，`grant_type=urn:ietf:params:oauth:grant-type:device_code`、`client_id`、`device_code`，取得 access/refresh 等状态。这个流程生成会话，**本次没有执行**。

只读账号请求为 GET `/api/oauth/account`，header `Authorization: Bearer <access_token>` 与 Accept JSON。Pulse 解析 `subscription.plan/monthly_credits/credits_remaining/rollover_credits/current_period_end`、顶层 `purchased_credits_remaining`、`paid_service_access.subscription_credits_remaining/purchased_credits_remaining/total_usable_credits`。只在正 monthly allowance 且 reported remainder 存在时计算周期 used；total usable 或购买余额与订阅池分开，不凭 allowance 伪造 balance。Pulse 把 credits 当 USD，响应本身没有 currency；单位及实际账期必须在当前账号实测确认。不能用 API key inference 成功当 account 权限证明。

## 生命周期与双端问题

Pulse 在过期前 60 秒停止使用 access token且不刷新；其一小时寿命来自上游描述，正式实现应使用服务器 `expires_in`/expiry，不硬编码。官方 refresh 是 POST `/api/oauth/token`，form `grant_type=refresh_token`、`client_id`，**refresh token 在 `x-nous-refresh-token` header，不是旧示例中随意假设的 body 字段**。成功后须原子持久化新 token chain。`invalid_grant/invalid_token/refresh_token_reused` 是需重新登录；上游明确 reuse 会撤销整条 session。边缘安全挑战 403/429 可能是临时拒绝，不能无条件清除凭证。

Hermes 在同机使用文件锁共享 store；iCloud 最终同步不能提供跨离线设备互斥。两个设备复制同一 refresh token，即使各自本地加锁仍不安全。候选是让 iPhone 和 Watch 各有独立授权 token chain，可在 iPhone 浏览器分别完成 device approvals，并按设备隔离 refresh secret。必须先取得供应商支持并验证多个 session 是否共存；它是候选设计，未实测，不能自动改写现有凭证同步架构。

遵守 [设备直连 ADR](../../../docs/adr/0001-device-side-refresh.md)：两端只向 Portal 直连；不能让手机作为 Watch 唯一续期者，也不能借用 Hermes refresh token 或 Mac 锁/代理服务。

- 已证实：官方云端授权、查询、刷新协议有源码；旧 token replay 明确危险。
- 不可采用：借用 Hermes session、两端共享同一个 rotating refresh token、只同步短期 access token 后声称长期独立刷新。
- 未验证：TokenPulse 注册身份/只读 scope、两条授权会话同账号共存、iPhone 与 Watch 长期续期及真实 credits 单位。

## 最小纵向验证（本次未执行）

1. 固定源码重取可用同目录 public-evidence 脚本；不读取 `~/.hermes`。
2. 获得独立客户端许可后，分别为 iPhone 与 Watch 创建 TokenPulse 自己的授权 chain。保留设备/session 标识，不记录 secret、邮箱或账号资料。
3. iPhone GET account，与 Portal 面板对照订阅与购买池；Watch 在手机离线、Hermes 不运行时 GET account。
4. 跨过 access expiry，由两端分别刷新再读取；有意并发的测试只用各自独立 chain，验证没有交叉撤销，禁止试重放实际 Hermes token。
5. 撤销一个 TokenPulse session，确认另一设备的预期行为和失效显示；记录设备、OS、时间、状态码和脱敏额度字段。测试不调用 inference/billing 修改。

缺独立 client 许可、两个测试授权 session 和 Watch 实机，**票未完成**。验证通过后的实施范围须包含按设备凭证隔离、原子旋转/重试、撤销与临时挑战区分、额度单位/账期、双端直接读取、缓存与组件/提醒及真实验收。
