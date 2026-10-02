# 16: Command Code 美元余额与限额

**Status:** implemented-awaiting-real-validation

**Type:** integration

**What to build:** 输入 Key 后查看美元余额和服务明确给出的用量限额。

**Blocked by:** None (can start immediately)

## Acceptance criteria

- [x] 余额与滚动或组织限额分别展示；不使用上游按套餐价格推算的月度总额。
- [ ] 确认 Key 可以独立查询；按服务返回的金额与单位解析，不将积分数推算为美元。
- [ ] 从添加入口到安全凭证保存、账号管理、同步和删除完整可用；同一提供商多个账号隔离，iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别向服务端查询；Watch 获得配置和凭证后不依赖手机、Mac 或新增代查服务在线。
- [ ] 卡片、详情、iPhone 小组件、Watch 和演示数据覆盖新增计量方式；金额、积分、token、时长和预算单位不混淆。
- [ ] 适用的额度告警、重置或低余额提醒接入既有规则；不适用的设置不开放；失败保留旧数据与采集时间，缺失值不补零。
- [ ] 覆盖请求契约、字段边界、账号与站点隔离、成功与失败及适用提醒行为的测试；运行相关测试和 unsigned TokenPulse target 完整构建。
- [ ] 新增图标优先官方资源或既有 Lobe Icons，固定来源版本、记录版权许可，并验证矢量与模板渲染覆盖 App、Widgets 和 Watch。
- [ ] 保存真实登录、查询及 Watch 独立刷新验收结论；无账号凭证或设备时保留未验收项，不将合成响应测试当作真实接入证明。
- [x] 更新支持范围、登录方式、字段含义和验证边界；研究来源固定版本，发现契约不可用时记录具体阻塞。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/command-code.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。

## Implementation — 2026-10-02

已实现 `.commandCode` 添加入口、Key envelope、安全保存/账号隔离与既有同步/删除路径、双端直接客户端、混合额度+钱包能力、Widget/演示、固定 MIT 图标与7个合成契约测试。只读取 whoami 与 credits，不调用 subscriptions/summary、不含价格表或推算月度总额。钱包只在三个金额池全部明确返回时以 Decimal 相加，未知池不补零。

[实施范围与验证记录](../../../docs/command-code-provider-integration.md)。完整 App 的 Swift6 iOS module emit 和完整新增 XCTest 文件 semantic typecheck通过，PBX/plist与diff检查通过；未运行xcodebuild/模拟器，真实Key、iCloud到Watch、手机离线的物理Watch读取、真实提醒及完整无签名目标构建仍未验收，由root集中验证。未把合成测试或源码接口作为真实账号证明。

跟进：加入 scoped credential SHA-256 身份绑定与 Decimal exactCounts，新增精确小数限额归档/Widget回归，当前8个测试方法。[本组最终静态验证](../../../docs/provider-wave2-research-validation.md)覆盖完整App/Widgets支持源/44个Watch target源及所有相关测试语义；XCTest执行和实际验收仍待root。
