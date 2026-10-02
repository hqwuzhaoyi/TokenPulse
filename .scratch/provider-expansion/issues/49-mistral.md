# 49: Mistral API 与 Vibe 额度

**Status:** ready-for-agent

**Type:** integration

**What to build:** 登录 Mistral 后查看 API、Vibe 额度及钱包余额。

**Blocked by:** 40 — StepFun 套餐与网页登录

## Acceptance criteria

- [ ] 核验 Ory 会话 Cookie、CSRF 和允许的官方子域；登录重定向与过期状态明确处理。
- [ ] 钱包与 API、Vibe 两个窗口分开；页面流解析与辅助路由失败不抹除有效数据，金额仅在币种明确时展示。
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

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/mistral.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。
