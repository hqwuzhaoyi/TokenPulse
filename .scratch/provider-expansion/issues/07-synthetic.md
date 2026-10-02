# 07: Synthetic 多窗口额度接入

**Status:** implemented-awaiting-real-validation

**Type:** integration

**What to build:** 用户输入 Synthetic Key，在双端分别查看 5 小时、每周和搜索额度。

**Blocked by:** None (can start immediately)

## Acceptance criteria

- [ ] 解析不同窗口各自的计数或比例语义，搜索额度保留独立标识和单位。
- [ ] 滚动恢复的下一次补充时间不作为完整额度重置时间，不据此预排重置提醒或反复触发窗口翻转。
- [ ] 完成添加、凭证安全保存、多账号隔离、重新打开后恢复、账号删除与同步；iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别直连提供商查询；Watch 已取得配置和凭证后，不依赖手机或 Mac 在线。
- [ ] 账号卡片、详情、iPhone 小组件和 Watch 展示保持数值、单位、采集时间与过期状态一致；支持演示数据并保持演示与真实账号隔离。
- [ ] 适用的额度告警、重置提醒或低余额提醒沿用现有规则；失败保留旧数据，缺失指标不补零，预计重置不等同于确认恢复。
- [ ] 增加有意义的请求契约、解析边界、账号隔离和提醒行为验证；运行相关测试和完整 unsigned TokenPulse target 构建，覆盖 App、Widgets 与 Watch 资源。
- [ ] 新增图标优先官方资产或既有 Lobe Icons 来源，固定来源版本、记录版权许可，并验证模板渲染与矢量资产。
- [ ] 记录实际账号查询、凭证失效和双端独立刷新证据；没有凭证或设备时准确保留未验收项，模拟响应通过不能代替真实验收。
- [ ] 更新提供商支持范围、登录说明、领域用语与验证边界。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/synthetic.md)。参考代码与模拟响应只作为契约线索，不能视为真实账号验证。

## Implementation evidence (2026-10-02)

Provider.synthetic and direct fixed HTTPS Bearer quota client added, with separate rolling five-hour, weekly and Search hourly windows. Continuous replenishment uses the shared resetSemantics/nextReplenishmentAt contract; partial recovery never emits a reset, and quota reminders rearm only below the lowest configured threshold. Add/update/store/sync/delete use existing API-key paths plus a provider/key identity. Demo, widgets and a generic system extension icon are included. See docs/synthetic-provider-integration.md.

Swift 6 full App module emit and the complete new Synthetic XCTest file semantic typecheck, PBX lint and diff checks passed. No xcodebuild or simulator was started by this agent; test execution and unsigned App/Widgets/Watch build remain for root. No real Key was accessed. Real service/device/notifications/sync and brand-icon evidence remain unverified, so acceptance boxes remain open.
