# 69: OpenAI API 钱包可用接口验证

**Status:** ready-for-agent

**Type:** feasibility

**What to build:** 核验当前可用凭证能否获取真实预付余额，并明确余额与组织花费的边界。

**Blocked by:** None (can start immediately)

## Acceptance criteria

- [ ] 旧 credit_grants 路由兼容范围有限；Admin costs 仅表示消费，不能推算出未知的余额、充值或套餐上限。
- [ ] 交付有来源链接和版本的认证、查询、凭证生命周期与平台约束调查，以及可重复执行的最小只读验证步骤。
- [ ] 若找到可行路径，先完成最小纵向验证：手机授权或配置、真实读取、凭证提供给 Watch 后在手机离线时再次直连读取；记录具体设备与数据证据。
- [ ] 若未找到可行路径，交付明确的否定结论及缺口；缺少账号或设备的情形单独标记为未验证，不把它等同于不可行或通过。
- [ ] 不自动引入 Mac 常驻进程、CLIProxyAPI 代查或设备外推送服务；改变独立刷新 ADR 需要另行决策。
- [ ] 验证通过后给出实施票的完整验收范围与真实阻塞项，实施票依赖本验证；验证票本身不宣布正式 provider 已接入。
- [ ] 测试夹具和日志脱敏；不保存真实凭证，不对外发布账户资料。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/openai-api.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。
