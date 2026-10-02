# 69: OpenAI API 钱包可用接口验证

**Status:** awaiting-validation

**Type:** feasibility

**What to build:** 核验当前可用凭证能否获取真实预付余额，并明确余额与组织花费的边界。

**Blocked by:** 用户授权的测试 key/账号与真实钱包余额路由；iPhone/Watch 真值对照与撤销测试。

## Acceptance criteria

- [x] 旧 credit_grants 路由兼容范围有限；Admin costs 仅表示消费，不能推算出未知的余额、充值或套餐上限。
- [x] 交付有来源链接和版本的认证、查询、凭证生命周期与平台约束调查，以及可重复执行的最小只读验证步骤。
- [ ] 若找到可行路径，先完成最小纵向验证：手机授权或配置、真实读取、凭证提供给 Watch 后在手机离线时再次直连读取；记录具体设备与数据证据。
- [x] 若未找到可行路径，交付明确的否定结论及缺口；缺少账号或设备的情形单独标记为未验证，不把它等同于不可行或通过。
- [x] 不自动引入 Mac 常驻进程、CLIProxyAPI 代查或设备外推送服务；改变独立刷新 ADR 需要另行决策。
- [ ] 验证通过后给出实施票的完整验收范围与真实阻塞项，实施票依赖本验证；验证票本身不宣布正式 provider 已接入。
- [x] 测试夹具和日志脱敏；不保存真实凭证，不对外发布账户资料。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/openai-api.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。

## Research result — 2026-10-02

官方 Admin Costs 查询可查消费，不能完成钱包余额目的；legacy credit_grants 当前账号兼容未验证。

研究报告：[认证、查询、生命周期、平台限制与最小验证](../research/69-openai-api.md)。只进行公开文档/固定源码研究，未读取用户凭证、未建立外部登录、未完成真实账号或 Watch 验收。

状态 `awaiting-validation` 表示研究交付已产出，整票未完成。第3项真实纵向验收和第6项通过后实施票仍未满足；已勾选的否定/缺口项仅代表报告清楚区分既有架构限制与实际未验证项。
