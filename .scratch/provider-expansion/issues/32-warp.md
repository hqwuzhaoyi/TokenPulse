# 32: Warp 套餐与附加 credits

**Status:** implemented; static contract verified; central build/test and mobile/real-account validation pending

**Type:** integration

**What to build:** 输入 Warp Key 后查看套餐及附加 credits。

**Blocked by:** None (can start immediately)

## Acceptance criteria

- [ ] 核验移动端直连的只读 GraphQL 请求和必需客户端头；平台约束必须形成真实验证结论。
- [ ] 个人与工作区的附加额度来源保持清晰，不能把无统一周期的 grants 相加形成套餐百分比。
- [ ] 从添加入口到安全凭证保存、账号管理、同步和删除完整可用；同一提供商多个账号隔离，iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别向服务端查询；Watch 获得配置和凭证后不依赖手机、Mac 或新增代查服务在线。
- [ ] 卡片、详情、iPhone 小组件、Watch 和演示数据覆盖新增计量方式；金额、积分、token、时长和预算单位不混淆。
- [ ] 适用的额度告警、重置或低余额提醒接入既有规则；不适用的设置不开放；失败保留旧数据与采集时间，缺失值不补零。
- [ ] 覆盖请求契约、字段边界、账号与站点隔离、成功与失败及适用提醒行为的测试；运行相关测试和 unsigned TokenPulse target 完整构建。
- [ ] 新增图标优先官方资源或既有 Lobe Icons，固定来源版本、记录版权许可，并验证矢量与模板渲染覆盖 App、Widgets 和 Watch。
- [ ] 保存真实登录、查询及 Watch 独立刷新验收结论；无账号凭证或设备时保留未验收项，不将合成响应测试当作真实接入证明。
- [ ] 更新支持范围、登录方式、字段含义和验证边界；研究来源固定版本，发现契约不可用时记录具体阻塞。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/warp.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。


## Implementation evidence

- `.warp` public Key/controller/query/shared account lifecycle routing, read-only GraphQL body/client headers, independent phone/Watch path, per-source/per-grant credits, exact quantities, expiry, widgets and isolated demo implemented.
- Fixed Pulse397c8fc4 source checked through agent-reach GitHub/gh. Added workspace uid/createdAt from official Warp query definition at 3f37d69ff3e87818d24f803c16b2e045fa4bd95e; no live account queried.
- Personal and workspace grants are separate; no aggregate percentage across unrelated grants. IDs omit consumption and preserve workspace uid identity. Unlimited and denominator-unknown cases never invent percentages.
- Seven tests cover readonly contract/headers, quantities/source/expiry, stable IDs, flags/invalid shapes/overflow, independent reminders/demo/widgets/coding and isolated account restore/rekey/delete/failure retention. Full App/new test Swift6 typecheck passed; no xcodebuild/simulator run.
- Non-brand generic Apache2 vector/template icon follows fixed Pulse; official Warp app assets are AGPL and not imported. Only this ticket and dedicated docs changed, no central README/CONTEXT/manifest.

Mobile platform constraints are specifically NOT accepted: the reference macOS compatibility context has not been accepted by a real Warp account on iPhone/Watch. Complete unsigned builds, XCTest execution, real Key/fields/lifetime/revocation, iCloud, physical independent refresh, notifications/widgets remain open. The planned shared nonResettingAllowance / own Key scope follow-up must be integrated for complete reminder lifecycle semantics.

生产 Warp 解析代码 macOS 合成 smoke 通过套餐/个人/工作区分离、独立到期、消费变化稳定ID、无限、缺少分母、真实Bool及计数矛盾拒绝。不是移动端/真实Key验证或模拟器XCTest。
