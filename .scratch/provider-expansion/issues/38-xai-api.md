# 38: xAI API 团队预付余额

**Status:** implemented-awaiting-integrated-validation

**Type:** integration

**What to build:** 配置 Team ID 与 Management Key 后查看该团队美元余额。

**Blocked by:** None (can start immediately)

## Acceptance criteria

- [ ] 团队身份与凭证绑定并安全同步；团队参数严格验证，不能改变请求域名或路径结构。
- [ ] 与 SuperGrok、Grok Bot 独立识别；使用十进制和已核实的金额单位，不把推理 Key 当管理 Key。
- [ ] 从添加入口到安全凭证保存、账号管理、同步和删除完整可用；同一提供商多个账号隔离，iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别向服务端查询；Watch 获得配置和凭证后不依赖手机、Mac 或新增代查服务在线。
- [ ] 卡片、详情、iPhone 小组件、Watch 和演示数据覆盖新增计量方式；金额、积分、token、时长和预算单位不混淆。
- [ ] 适用的额度告警、重置或低余额提醒接入既有规则；不适用的设置不开放；失败保留旧数据与采集时间，缺失值不补零。
- [ ] 覆盖请求契约、字段边界、账号与站点隔离、成功与失败及适用提醒行为的测试；运行相关测试和 unsigned TokenPulse target 完整构建。
- [ ] 新增图标优先官方资源或既有 Lobe Icons，固定来源版本、记录版权许可，并验证矢量与模板渲染覆盖 App、Widgets 和 Watch。
- [ ] 保存真实登录、查询及 Watch 独立刷新验收结论；无账号凭证或设备时保留未验收项，不将合成响应测试当作真实接入证明。
- [ ] 更新支持范围、登录方式、字段含义和验证边界；研究来源固定版本，发现契约不可用时记录具体阻塞。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/xai-api.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。


## Implementation evidence (2026-10-02)

- Added distinct `.xaiAPI` enum and `TeamID:ManagementKey` secure composite entry with explicit billing/management role instructions. Team ID is one strict ASCII path segment; Key/control character/size guards run before any request. Envelope team+key synchronize together through existing Keychain; identity is recomputed from actual team/key rather than trusting cached metadata.
- Direct read-only device GET to fixed `management-api.x.ai` prepaid balance endpoint; ephemeral default transport rejects all redirects. Management envelopes are distinct from SuperGrok/inference envelopes, with no CLI/browser/inference or billing writes.
- Official xAI Billing REST page identifies `total` as USD cents, and purchases are negative ledger values; Decimal `-total.val / 100` supports negative balances. Missing malformed values fail; no fabricated quota percentages, reset, balance components or API availability. Posted-vs-live caveat is on add/update UI and dedicated docs.
- Account, Watch, widget, demo and USD low-balance behavior reuse the wallet pipeline. Tests include exact money/boundaries, fixed headers/route, team path and role refusal, failures, multi-team persistence/replace/delete/stale sync, reminder recovery and widget/demo.
- Swift 6 temporary testable module includes real Domain/all Providers/Monitor/Demo/Reminder/WidgetSnapshotStore/PlatformConstants/formatting. New XAI and existing new Volcengine XCTest sources semantic typecheck passed with the real XCTest Swift overlay. PBX lint/UI syntax/diff validation passed; no xcodebuild/simulator/XCTest runtime executed by this agent. Root integrated tests and unsigned complete target build remain pending.
- Icon uses pinned Lobe Icons `a94750e3f5f8fc33757b839d85030e742284e43a`, `packages/static-svg/icons/xai.svg`, MIT notice, black explicit-size template vector. Actual resource compilation pending.
- No real Management Key/team, invalid-key live response, iCloud arrival or independent Watch refresh has been validated. Actual account and device criteria remain unchecked. Sources and all validation limits: [xAI API integration](../../../docs/xai-api-provider-integration.md).
