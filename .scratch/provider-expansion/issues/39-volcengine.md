# 39: 火山方舟 Coding 与 Agent Plan

**Status:** implemented-awaiting-integrated-validation

**Type:** integration

**What to build:** 输入 AK/SK 后由手机及 Watch 直接签名查询 Coding 和 Agent Plan。

**Blocked by:** None (can start immediately)

## Acceptance criteria

- [ ] 采用移动端可执行的签名 API 路径，签名计算有独立验证；不调用 arkcli。
- [ ] 两个套餐独立解析，单个未订阅不抹去另一个的有效额度；无真实账号证据不能宣称可用。
- [ ] 从添加入口到安全凭证保存、账号管理、同步和删除完整可用；同一提供商多个账号隔离，iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别向服务端查询；Watch 获得配置和凭证后不依赖手机、Mac 或新增代查服务在线。
- [ ] 卡片、详情、iPhone 小组件、Watch 和演示数据覆盖新增计量方式；金额、积分、token、时长和预算单位不混淆。
- [ ] 适用的额度告警、重置或低余额提醒接入既有规则；不适用的设置不开放；失败保留旧数据与采集时间，缺失值不补零。
- [ ] 覆盖请求契约、字段边界、账号与站点隔离、成功与失败及适用提醒行为的测试；运行相关测试和 unsigned TokenPulse target 完整构建。
- [ ] 新增图标优先官方资源或既有 Lobe Icons，固定来源版本、记录版权许可，并验证矢量与模板渲染覆盖 App、Widgets 和 Watch。
- [ ] 保存真实登录、查询及 Watch 独立刷新验收结论；无账号凭证或设备时保留未验收项，不将合成响应测试当作真实接入证明。
- [ ] 更新支持范围、登录方式、字段含义和验证边界；研究来源固定版本，发现契约不可用时记录具体阻塞。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/volcengine.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。


## Implementation evidence (2026-10-02)

- `.volcengine` now uses AK/SK composite secure entry, account-bound Keychain envelope and a computed source fingerprint. App and Watch sign two fixed Top OpenAPI GET actions locally; no arkcli, model completion or host/region override exists. All default redirects are refused.
- Coding/Agent scopes and IDs remain separate. One failed/unsubscribed action preserves the other's valid result; both-failure priorities distinguish credentials, rate limit, server/network, malformed response and no subscription. Unknown/missing metrics are not zero, Quota=0 windows are absent, seconds/ms resets are read without inventing a cycle.
- Card/detail/widget/Watch consume normal quota snapshots; demo includes both scopes. Existing percentage and explicit-reset reminders apply; AFP is not a monetary wallet. Local restore/delete and credential changes reuse the synchronized scoped-credential pipeline.
- Official Python SDK signing source pinned at `d88be4d8028e35563b27ff1bafe3c1f7ed1ab656` was inspected via agent-reach GitHub. Independent Python reference vectors for Coding/Agent/Unicode queries match executed production Swift signer output byte-for-byte in an offline macOS driver (three vectors passed). Synthetic AK/SK only; no network or credential discovery.
- Production foundation-compatible source (all Domain/Providers plus Monitor/Demo/Reminder) emitted a temporary Swift 6 testable module; new `VolcengineProviderTests` semantic typecheck passed with the real XCTest Swift overlay. PBX plist lint and `git diff --check` passed. No xcodebuild or simulator started; XCTest runtime and unsigned full App/Widgets/Watch build still pending root integration.
- Lobe Icons fixed commit `a94750e3f5f8fc33757b839d85030e742284e43a`, asset `packages/static-svg/icons/volcengine.svg`, MIT copyright/notice recorded; black 24x24 template vector image set mapped. Actual resource compilation pending.
- No real AK/SK, Volcengine account or device validation occurred. No claim that the weakly sourced usage contract or offline signature has been accepted by a live deployment. Real login/API permissions, failure, sync arrival and Watch independent refresh remain open.

Detailed login, units, exact verification commands/scope and sources: [Volcengine integration](../../../docs/volcengine-provider-integration.md).
