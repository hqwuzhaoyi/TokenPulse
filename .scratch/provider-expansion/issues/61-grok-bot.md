# 61: Grok Bot 独立周额度

**Status:** implemented — current integration/icon criteria met; aggregate tests delegated to root

**Type:** integration

**What to build:** 使用 Cursor 账号授权后，在独立 Grok Bot 卡片查看其每周额度。

**Blocked by:** 60 — Cursor 移动端授权与额度

## 当前验收标准（用户于2026-10-02调整）

- [x] 完成本票接入实现，并确认provider图标存在。真实账号/设备验证不再作为关票条件。

下方保留原实现要求与历史验证清单；未勾选不代表当前额外关票门槛。

## 原 Acceptance criteria（历史）

- [ ] 复用 Cursor 移动端授权，独立保存本服务账号的查询、缓存与提醒身份。
- [ ] Grok Bot 权益不与 SuperGrok 或 Cursor 月度模型池合并；无实际重置时间时不推断周一重置。
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

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/grok-bot.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。


## Implementation evidence

- `.grokBot` register/query/independent auth+JWT cookie+UUID/provider fingerprint/UI/Watch/widget/demo/PBX and secure lifecycle complete. Necessary Cursor auth helpers/views parameterized only for Cursor/GrokBot with existing Cursor default; no reusing a Cursor envelope as GrokBot credential.
- Fixed397c8fc4 service/Cursor auth source plus current official xAI FAQ read via agent-reach gh/Jina. REST get-sand with Origin and no redirects, not SuperGrok endpoint; weekly does not imply actual reset date. No periodStart+7d/Monday inference or marketing-price balance.
- Explicit absent/pooled-personal quota is successful static quotaStatusText/empty snapshot, removing old quota; unknown/missing flags do not become false subscription claims or fake0. Strict Bool/finite percent/contradiction/expiry and cross-provider/account validation.
- Seven tests plus preserved Cursor tests, source parse/PBX lint/diff checks. Root handles aggregate semantic tests/build; worker did not Xcode/simulator. Lobe xai.svg MIT fixed2e76c... is distinct from SuperGrok and image-set exists.
- Dedicated docs/grok-bot-provider-integration.md; no central README/CONTEXT/manifest.

Real login/API/cookie lifetime/iCloud/physicalWatch/widgets not measured; remain evidence gaps rather than current close gates. No real token accessed or exposed.
