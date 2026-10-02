# 19: Chutes 订阅额度

**Status:** implemented-awaiting-validation

**Type:** integration

**What to build:** 输入 Key 后分别查看滚动窗口和月度订阅额度。

**Blocked by:** None (can start immediately)

## Acceptance criteria

- [ ] 确认真实响应字段和使用率尺度；未知字段不通过递归搜索或比例猜测产生额度。
- [ ] 窗口长度仅采用接口给出的值；无订阅、未提供限额和耗尽分别显示。
- [ ] 从添加入口到安全凭证保存、账号管理、同步和删除完整可用；同一提供商多个账号隔离，iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别向服务端查询；Watch 获得配置和凭证后不依赖手机、Mac 或新增代查服务在线。
- [ ] 卡片、详情、iPhone 小组件、Watch 和演示数据覆盖新增计量方式；金额、积分、token、时长和预算单位不混淆。
- [ ] 适用的额度告警、重置或低余额提醒接入既有规则；不适用的设置不开放；失败保留旧数据与采集时间，缺失值不补零。
- [ ] 覆盖请求契约、字段边界、账号与站点隔离、成功与失败及适用提醒行为的测试；运行相关测试和 unsigned TokenPulse target 完整构建。
- [ ] 新增图标优先官方资源或既有 Lobe Icons，固定来源版本、记录版权许可，并验证矢量与模板渲染覆盖 App、Widgets 和 Watch。
- [ ] 保存真实登录、查询及 Watch 独立刷新验收结论；无账号凭证或设备时保留未验收项，不将合成响应测试当作真实接入证明。
- [ ] 更新支持范围、登录方式、字段含义和验证边界；研究来源固定版本，发现契约不可用时记录具体阻塞。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/chutes.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。

## Implementation and validation (2026-10-02)

Implemented Key entry, direct device-side requests, quota/widget/Watch/demo/reminder paths and pinned vector icon. Primary backend commit `chutesai/chutes-api 3b5609f42f84e29dea374382ef1fa95b0fda329c` establishes subscription Bool, fixed four-hour and billing budgets in USD, and custom uncapped monthly quota; this supersedes the older rolling-window description. Raw budget amounts use Decimal/exactCounts. See [provider evidence and boundaries](../../../docs/chutes-integration.md).

Verified production module, all nine new XCTest methods, complete App UI with real Swift 6 iOS type checking, PBX plist and diff checks. Root still owns serial XCTest and full unsigned App/Widgets/Watch builds. Real Key/plan response, revoked credentials, Keychain/iCloud delivery, iCloud-off device lifecycle, physical Watch independent refresh and real UI/notifications are pending; no real credential was accessed and acceptance checkboxes stay open.
