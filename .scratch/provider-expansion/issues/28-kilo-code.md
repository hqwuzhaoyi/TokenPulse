# 28: Kilo Code 钱包与 Kilo Pass

**Status:** done

**Type:** integration

**What to build:** 输入 Key 后查看美元余额与 Kilo Pass 当期额度。

**Blocked by:** None (can start immediately)

## 当前验收标准（用户于2026-10-02调整）

- [x] 图标存在：`ProviderKiloCode`，映射及资源已核对，见[图标验收记录](../icon-acceptance.md)。本票已关闭。

以下原检查表保留为历史实现/验证记录，不再作为本票关票条件；未勾选项不改写为已实测。

## 原 Acceptance criteria（历史）

- [ ] 微美元金额精确换算；套餐基础和奖励额度仅按明确契约合并。
- [ ] 余额块各自的到期不当成套餐重置；tRPC 子请求失败与未订阅状态正确处理。
- [ ] 从添加入口到安全凭证保存、账号管理、同步和删除完整可用；同一提供商多个账号隔离，iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别向服务端查询；Watch 获得配置和凭证后不依赖手机、Mac 或新增代查服务在线。
- [ ] 卡片、详情、iPhone 小组件、Watch 和演示数据覆盖新增计量方式；金额、积分、token、时长和预算单位不混淆。
- [ ] 适用的额度告警、重置或低余额提醒接入既有规则；不适用的设置不开放；失败保留旧数据与采集时间，缺失值不补零。
- [ ] 覆盖请求契约、字段边界、账号与站点隔离、成功与失败及适用提醒行为的测试；运行相关测试和 unsigned TokenPulse target 完整构建。
- [ ] 新增图标优先官方资源或既有 Lobe Icons，固定来源版本、记录版权许可，并验证矢量与模板渲染覆盖 App、Widgets 和 Watch。
- [ ] 保存真实登录、查询及 Watch 独立刷新验收结论；无账号凭证或设备时保留未验收项，不将合成响应测试当作真实接入证明。
- [ ] 更新支持范围、登录方式、字段含义和验证边界；研究来源固定版本，发现契约不可用时记录具体阻塞。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/kilo-code.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。

## Implementation record (2026-10-02)

Kilo tRPC batch、API Key/个人账户路径、精确微美元钱包、明确基础+奖励 Pass、实际 billing reset、混合卡片/Watch/widget/独立提醒/演示与官方licensed icon已实现。7个KiloCodeProviderTests覆盖契约、包装/错误、缺失/零/负与精确金额、恢复/账号隔离及删除。完整App iOS Swift6 module/测试静态typecheck、PBX/diff检查通过；真实账号、失效、Watch/iCloud、unsigned目标构建与XCTest执行仍开放。详见 `docs/kilo-code-integration.md`。
