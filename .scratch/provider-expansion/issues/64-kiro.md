# 64: Kiro 远程额度查询可行性

**Status:** awaiting-validation

**Type:** feasibility

**What to build:** 验证能否在不运行 Kiro CLI ACP 的情况下由手机和 Watch 查询订阅额度。

**Blocked by:** 官方支持的移动端远程 quota/client 契约；独立测试授权及 iPhone/Watch 实机。

## Acceptance criteria

- [x] 上游依赖 CLI 原生 usage 方法；寻找有来源证据的远程认证与额度路径，不能把 ACP 本地接口当云端 API。
- [x] 交付有来源链接和版本的认证、查询、凭证生命周期与平台约束调查，以及可重复执行的最小只读验证步骤。
- [ ] 若找到可行路径，先完成最小纵向验证：手机授权或配置、真实读取、凭证提供给 Watch 后在手机离线时再次直连读取；记录具体设备与数据证据。
- [x] 若未找到可行路径，交付明确的否定结论及缺口；缺少账号或设备的情形单独标记为未验证，不把它等同于不可行或通过。
- [x] 不自动引入 Mac 常驻进程、CLIProxyAPI 代查或设备外推送服务；改变独立刷新 ADR 需要另行决策。
- [ ] 验证通过后给出实施票的完整验收范围与真实阻塞项，实施票依赖本验证；验证票本身不宣布正式 provider 已接入。
- [x] 测试夹具和日志脱敏；不保存真实凭证，不对外发布账户资料。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/kiro.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。

## Research result — 2026-10-02

固定 Pulse ACP 架构不可用于当前 ADR；当前官方 CLI 的 device flow 不等于原生 quota 接口。

研究报告：[认证、查询、生命周期、平台限制与最小验证](../research/64-kiro.md)。只进行公开文档/固定源码研究，未读取用户凭证、未建立外部登录、未完成真实账号或 Watch 验收。

状态 `awaiting-validation` 表示研究交付已产出，整票未完成。第3项真实纵向验收和第6项通过后实施票仍未满足；已勾选的否定/缺口项仅代表报告清楚区分既有架构限制与实际未验证项。
