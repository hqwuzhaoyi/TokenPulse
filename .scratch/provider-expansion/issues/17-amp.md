# 17: Amp 套餐额度与余额

**Status:** done

**Type:** integration

**What to build:** 输入 access token 后查看 Free、Agent、Orb 额度和个人美元余额。

**Blocked by:** None (can start immediately)

## 当前验收标准（用户于2026-10-02调整）

- [x] 图标存在：`ProviderAmp`，映射及资源已核对，见[图标验收记录](../icon-acceptance.md)。本票已关闭。

以下原检查表保留为历史实现/验证记录，不再作为本票关票条件；未勾选项不改写为已实测。

## 原 Acceptance criteria（历史）

- [x] 只解析已核实的响应文本形态；ANSI 和 Markdown 清理不改变数值，陌生文本明确报错。
- [x] 逐小时补充与每日重置区分；Orb 使用小时单位，周期结束日期保留其日期精度。
- [ ] 从添加入口到安全凭证保存、账号管理、同步和删除完整可用；同一提供商多个账号隔离，iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别向服务端查询；Watch 获得配置和凭证后不依赖手机、Mac 或新增代查服务在线。
- [ ] 卡片、详情、iPhone 小组件、Watch 和演示数据覆盖新增计量方式；金额、积分、token、时长和预算单位不混淆。
- [ ] 适用的额度告警、重置或低余额提醒接入既有规则；不适用的设置不开放；失败保留旧数据与采集时间，缺失值不补零。
- [ ] 覆盖请求契约、字段边界、账号与站点隔离、成功与失败及适用提醒行为的测试；运行相关测试和 unsigned TokenPulse target 完整构建。
- [ ] 新增图标优先官方资源或既有 Lobe Icons，固定来源版本、记录版权许可，并验证矢量与模板渲染覆盖 App、Widgets 和 Watch。
- [ ] 保存真实登录、查询及 Watch 独立刷新验收结论；无账号凭证或设备时保留未验收项，不将合成响应测试当作真实接入证明。
- [x] 更新支持范围、登录方式、字段含义和验证边界；研究来源固定版本，发现契约不可用时记录具体阻塞。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/amp.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。

## Implementation — 2026-10-02

已实现 `.amp` Access Token 配置、只读 balance RPC、严格已知 displayText 解析、Decimal 个人 USD 钱包、Free/Agent/Orb 稳定窗口、mixed 路由、demo 与固定 MIT 图标。小时 Free 使用 continuousReplenishment，不预排/确认 reset；billing end 用 day 精度保持源日期，不当 UTC 午夜精确重置。

[实施范围/字段与验证](../../../docs/amp-provider-integration.md)。7 个合成 XCTest 方法、全部 App Swift6 iOS module emit 及完整测试 semantic typecheck 通过，PBX/diff/资产 metadata 检查通过。未运行 xcodebuild/模拟器/XCTest，完整构建和测试由 root 集中验证；无真实 token/账号和物理 iPhone/Watch 直连、iCloud 与提醒验收，整票未完成。

跟进：加入 scoped credential 身份绑定，美元Free/Agent与Orb小时保存Decimal exactCounts。[本组最终静态验证](../../../docs/provider-wave2-research-validation.md)包含全部相关App/Widget/Watch源与完整测试语义，不冒充XCTest执行/真实设备通过。
