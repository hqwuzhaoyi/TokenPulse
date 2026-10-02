# 44: Devin 网页账户额度

**Status:** done

**Type:** integration

**What to build:** 从 iPhone 登录 Devin 后在双端直接查询每日和每周额度。

**Blocked by:** 40 — StepFun 套餐与网页登录

## 当前验收标准（用户于2026-10-02调整）

- [x] 完成本票接入实现，并确认provider图标存在。真实账号/设备验证不再作为关票条件。

下方保留原实现要求与历史验证清单；未勾选不代表当前额外关票门槛。

## 原 Acceptance criteria（历史）

- [ ] 在已有按账号隔离的网页登录路径上增加最小必要的同源网页存储凭证提取；核验 token、账户与组织的一致性。
- [ ] 只采用对应账号的远程查询结果，失败保留本账号旧快照，不回退 Mac 编辑器保存的计划。
- [ ] 网页登录使用按服务账号隔离的会话容器，只提取已核实的必要凭证；明确有效域名、过期处理、重新登录及删除清理，并验证双端使用会话的兼容性。
- [ ] 从添加入口到安全凭证保存、账号管理、同步和删除完整可用；同一提供商多个账号隔离，iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别向服务端查询；Watch 获得配置和凭证后不依赖手机、Mac 或新增代查服务在线。
- [ ] 卡片、详情、iPhone 小组件、Watch 和演示数据覆盖新增计量方式；金额、积分、token、时长和预算单位不混淆。
- [ ] 适用的额度告警、重置或低余额提醒接入既有规则；不适用的设置不开放；失败保留旧数据与采集时间，缺失值不补零。
- [ ] 覆盖请求契约、字段边界、账号与站点隔离、成功与失败及适用提醒行为的测试；运行相关测试和 unsigned TokenPulse target 完整构建。
- [ ] 新增图标优先官方资源或既有 Lobe Icons，固定来源版本、记录版权许可，并验证矢量与模板渲染覆盖 App、Widgets 和 Watch。
- [ ] 保存真实登录、查询及 Watch 独立刷新验收结论；无账号凭证或设备时保留未验收项，不将合成响应测试当作真实接入证明。
- [ ] 更新支持范围、登录方式、字段含义和验证边界；研究来源固定版本，发现契约不可用时记录具体阻塞。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/devin.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。

## Implementation evidence (2026-10-02)

Scoped temporary WK login profile + exact app.devin.ai storage extraction, user/token pairing and explicit org choice/probe implemented. Account-bound session fingerprint, remote org quota route and same-org404 alternative, used-percent parsing/hide/no-allocation/USD overage, shared add/save/relogin/sync/delete, Watch direct query, mixed UI/demo/widget and pinned MIT ProviderDevin vector asset registered. See docs/devin-provider-integration.md; 7 contract/scope/lifecycle tests authored. Parser, PBX/diff and asset XML/JSON/presence checks passed. Root owns Xcode/test execution. Real account/device evidence remains unperformed, explicitly no longer a closure blocker under revised criterion.
