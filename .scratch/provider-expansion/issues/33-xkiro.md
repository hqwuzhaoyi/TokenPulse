# 33: xKiro 配额与钱包

**Status:** done

**Type:** integration

**What to build:** 输入 Key 后查看 5 小时、每周、每日免费 token 和钱包余额。

**Blocked by:** None (can start immediately)

## 当前验收标准（用户于2026-10-02调整）

- [x] 图标存在：`puzzlepiece.extension.fill`，映射及资源已核对，见[图标验收记录](../icon-acceptance.md)。本票已关闭。

以下原检查表保留为历史实现/验证记录，不再作为本票关票条件；未勾选项不改写为已实测。

## 原 Acceptance criteria（历史）

- [ ] 各类窗口保留服务给出的单位、周期与限额，套餐额度与钱包分开显示。
- [ ] API 可用状态、额度耗尽与钱包低余额分别按证据处理。
- [ ] 从添加入口到安全凭证保存、账号管理、同步和删除完整可用；同一提供商多个账号隔离，iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别向服务端查询；Watch 获得配置和凭证后不依赖手机、Mac 或新增代查服务在线。
- [ ] 卡片、详情、iPhone 小组件、Watch 和演示数据覆盖新增计量方式；金额、积分、token、时长和预算单位不混淆。
- [ ] 适用的额度告警、重置或低余额提醒接入既有规则；不适用的设置不开放；失败保留旧数据与采集时间，缺失值不补零。
- [ ] 覆盖请求契约、字段边界、账号与站点隔离、成功与失败及适用提醒行为的测试；运行相关测试和 unsigned TokenPulse target 完整构建。
- [ ] 新增图标优先官方资源或既有 Lobe Icons，固定来源版本、记录版权许可，并验证矢量与模板渲染覆盖 App、Widgets 和 Watch。
- [ ] 保存真实登录、查询及 Watch 独立刷新验收结论；无账号凭证或设备时保留未验收项，不将合成响应测试当作真实接入证明。
- [ ] 更新支持范围、登录方式、字段含义和验证边界；研究来源固定版本，发现契约不可用时记录具体阻塞。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/xkiro.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。

## Implementation evidence (2026-10-02)

Provider.xKiro direct Bearer usage route, fixed-point Decimal budget/wallet parsing, separate paid windows/free daily tokens/USD wallet, UTC documented free reset, explicit-null unlimited handling, scoped key identity, shared add/store/update/sync/delete, mixed UI and independent quota/wallet reminders, demo/widget and generic system icon implemented. Public docs and fixed Pulse contract checked; held funds not deducted; missing availability remains unknown. See docs/xkiro-provider-integration.md.

6 new tests and full App Swift6 module/semantic test typechecks, PBX lint and diff check passed. No xcodebuild/simulator/real Key used. Test execution and unsigned full target build remain root integration work; real account/device/notifications/sync and brand-vector license remain unverified. Acceptance boxes remain open.
