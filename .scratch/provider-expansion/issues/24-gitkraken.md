# 24: GitKraken AI 个人与组织额度

**Status:** done

**Type:** integration

**What to build:** 输入 GitKraken 账户会话 token 后查看个人额度和对应组织共享额度。

**Blocked by:** None (can start immediately)

## 当前验收标准（用户于2026-10-02调整）

- [x] 图标存在：`ProviderGitKraken`，映射及资源已核对，见[图标验收记录](../icon-acceptance.md)。本票已关闭。

以下原检查表保留为历史实现/验证记录，不再作为本票关票条件；未勾选项不改写为已实测。

## 原 Acceptance criteria（历史）

- [x] 该凭证属于会话 token，不标成永久 API Key；到期后提供重新配置入口。
- [x] 两种额度分开显示，标明所查询组织；无限和零配额不生成虚假百分比。
- [ ] 从添加入口到安全凭证保存、账号管理、同步和删除完整可用；同一提供商多个账号隔离，iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别向服务端查询；Watch 获得配置和凭证后不依赖手机、Mac 或新增代查服务在线。
- [ ] 卡片、详情、iPhone 小组件、Watch 和演示数据覆盖新增计量方式；金额、积分、token、时长和预算单位不混淆。
- [ ] 适用的额度告警、重置或低余额提醒接入既有规则；不适用的设置不开放；失败保留旧数据与采集时间，缺失值不补零。
- [ ] 覆盖请求契约、字段边界、账号与站点隔离、成功与失败及适用提醒行为的测试；运行相关测试和 unsigned TokenPulse target 完整构建。
- [ ] 新增图标优先官方资源或既有 Lobe Icons，固定来源版本、记录版权许可，并验证矢量与模板渲染覆盖 App、Widgets 和 Watch。
- [ ] 保存真实登录、查询及 Watch 独立刷新验收结论；无账号凭证或设备时保留未验收项，不将合成响应测试当作真实接入证明。
- [x] 更新支持范围、登录方式、字段含义和验证边界；研究来源固定版本，发现契约不可用时记录具体阻塞。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/gitkraken.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。

## Implementation — 2026-10-02

已实现session Token入口/JWT expiry提示、可选组织ID配置与header、个人与共享池credits窗口、无限/零配额边界、账号身份绑定/同步/缓存隔离、Widget/演示和官方MIT客户端符号。6个合成XCTest方法与全部App Swift6语义检查通过，完整CommandCode/Amp/GitKraken tests semantic typecheck通过（不等于测试执行）。

[实施范围/验证记录](../../../docs/gitkraken-provider-integration.md)。未xcodebuild/模拟器/XCTest、无真实会话和手机/Watch验证；当前API/组织权限、真实值、撤销重配、iCloud、物理双端直连、完整目标构建与提醒/视觉仍未验收，整票未完成。
