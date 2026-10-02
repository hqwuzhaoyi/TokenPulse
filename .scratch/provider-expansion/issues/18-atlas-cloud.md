# 18: Atlas Cloud 钱包余额

**Status:** implemented-awaiting-real-validation

**Type:** integration

**What to build:** 输入具有余额读取权限的 Key 后查看账户余额并配置低余额提醒。

**Blocked by:** None (can start immediately)

## Acceptance criteria

- [ ] 核验 account scope 和币种；以十进制处理金额，保留零及负余额。
- [ ] 仅覆盖 API 钱包；没有套餐上限时不生成使用率或 Coding Plan 额度。
- [ ] 从添加入口到安全凭证保存、账号管理、同步和删除完整可用；同一提供商多个账号隔离，iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别向服务端查询；Watch 获得配置和凭证后不依赖手机、Mac 或新增代查服务在线。
- [ ] 卡片、详情、iPhone 小组件、Watch 和演示数据覆盖新增计量方式；金额、积分、token、时长和预算单位不混淆。
- [ ] 适用的额度告警、重置或低余额提醒接入既有规则；不适用的设置不开放；失败保留旧数据与采集时间，缺失值不补零。
- [ ] 覆盖请求契约、字段边界、账号与站点隔离、成功与失败及适用提醒行为的测试；运行相关测试和 unsigned TokenPulse target 完整构建。
- [ ] 新增图标优先官方资源或既有 Lobe Icons，固定来源版本、记录版权许可，并验证矢量与模板渲染覆盖 App、Widgets 和 Watch。
- [ ] 保存真实登录、查询及 Watch 独立刷新验收结论；无账号凭证或设备时保留未验收项，不将合成响应测试当作真实接入证明。
- [ ] 更新支持范围、登录方式、字段含义和验证边界；研究来源固定版本，发现契约不可用时记录具体阻塞。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/atlas-cloud.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。

## Implementation record (2026-10-02)

账户余额 scope、精确 Decimal/币种、API Key 添加及共用凭证/恢复/删除/同步、双端直连、纯钱包展示/低余额提醒/widget/演示和 licensed icon 已实现。AtlasCloudProviderTests 覆盖契约、边界、错误与多账号生命周期。完整 iOS Swift 6 module 与相关 XCTest 静态 typecheck、PBX/diff 检查通过；实际 XCTest、unsigned 全目标资源构建和真实账号权限/设备验收未执行，清单保持开放。详见 `docs/atlas-cloud-integration.md`。
