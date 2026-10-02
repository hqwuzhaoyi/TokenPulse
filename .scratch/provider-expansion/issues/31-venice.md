# 31: Venice USD 与 DIEM 余额

**Status:** done

**Type:** integration

**What to build:** 输入 Key 后查看账号实际消费的 USD、DIEM，或当前官方契约中的 Bundled/Earned credits 与 legacy VCU 余额。

**Blocked by:** None (can start immediately)

## 当前验收标准（用户于2026-10-02调整）

- [x] 图标存在：`ProviderVenice`，映射及资源已核对，见[图标验收记录](../icon-acceptance.md)。本票已关闭。

以下原检查表保留为历史实现/验证记录，不再作为本票关票条件；未勾选项不改写为已实测。

## 原 Acceptance criteria（历史）

- [ ] 优先采用服务指定的消费单位；DIEM 作为非货币单位，不做换汇或美元低余额提醒。
- [ ] USD 接入货币低余额规则，切换计量单位后提醒状态和小组件保持一致。
- [ ] 从添加入口到安全凭证保存、账号管理、同步和删除完整可用；同一提供商多个账号隔离，iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别向服务端查询；Watch 获得配置和凭证后不依赖手机、Mac 或新增代查服务在线。
- [ ] 卡片、详情、iPhone 小组件、Watch 和演示数据覆盖新增计量方式；金额、积分、token、时长和预算单位不混淆。
- [ ] 适用的额度告警、重置或低余额提醒接入既有规则；不适用的设置不开放；失败保留旧数据与采集时间，缺失值不补零。
- [ ] 覆盖请求契约、字段边界、账号与站点隔离、成功与失败及适用提醒行为的测试；运行相关测试和 unsigned TokenPulse target 完整构建。
- [ ] 新增图标优先官方资源或既有 Lobe Icons，固定来源版本、记录版权许可，并验证矢量与模板渲染覆盖 App、Widgets 和 Watch。
- [ ] 保存真实登录、查询及 Watch 独立刷新验收结论；无账号凭证或设备时保留未验收项，不将合成响应测试当作真实接入证明。
- [ ] 更新支持范围、登录方式、字段含义和验证边界；研究来源固定版本，发现契约不可用时记录具体阻塞。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/venice.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。

## Implementation record (2026-10-02)

已实现APIKey/固定Bearer GET、服务指定USD/DIEM优先与严格缺失语义、Decimal金额、非货币DIEM/无虚构百分比周期、单位切换卡片/widget/提醒controls一致、演示/安全账号生命周期和licensed icon。5个VeniceProviderTests覆盖单位/边界/错误/请求/提醒与账号恢复删除。当前官方swagger固定0af2485确认bundledCredits/earnedCredits字段，已扩正常兼容BUNDLED_CREDITS/EARNED_CREDITS；VCU按官方Legacy Diem命名读取diem并保留VCU单位。均为非货币服务余额，不相加、不换汇；未知单位或对应余额缺失仍拒收而不误标美元。完整App及tests Swift6静态typecheck、PBX/diff通过；XCTest执行、unsigned资源构建与真实账号/设备验收保持开放。详见 `docs/venice-integration.md`。

Scope update: 以当前官方 BillingBalanceResponse 的明确字段扩展 Bundled/Earned credits 与 Legacy Diem/VCU，不能仅受旧 Pulse 文档限制。新增单位仍使用非货币余额路径，无美元低余额提醒；根来源固定到官方 swagger `0af24850577f540988ffd8cdd967119e7699c90e`。
