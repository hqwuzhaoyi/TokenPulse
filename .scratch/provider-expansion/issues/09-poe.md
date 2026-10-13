# 09: Poe points 余额接入

**Status:** done

**Type:** integration

**What to build:** 用户输入 Poe Key，在双端及小组件查看剩余 points。

**Blocked by:** None (can start immediately)

## 当前验收标准（用户于2026-10-02调整）

- [x] 图标存在：`ProviderPoe`，映射及资源已核对，见[图标验收记录](../icon-acceptance.md)。本票已关闭。

以下原检查表保留为历史实现/验证记录，不再作为本票关票条件；未勾选项不改写为已实测。

## 原 Acceptance criteria（历史）

- [ ] points 使用明确的非货币单位，不套用人民币或美元格式，不虚构套餐总额、使用率与重置时间。
- [ ] 支持数值与数字字符串、零余额及缺失字段；缺少余额时明确报错或显示未提供。
- [ ] 本票不新增 points 阈值产品规则；现有货币低余额提醒与百分比额度提醒不错误作用于 points，界面不提供不可用的设置。
- [ ] 完成添加、凭证安全保存、多账号隔离、重新打开后恢复、账号删除与同步；iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别直连提供商查询；Watch 已取得配置和凭证后，不依赖手机或 Mac 在线。
- [ ] 账号卡片、详情、iPhone 小组件和 Watch 展示保持数值、单位、采集时间与过期状态一致；支持演示数据并保持演示与真实账号隔离。
- [ ] 适用的额度告警、重置提醒或低余额提醒沿用现有规则；失败保留旧数据，缺失指标不补零，预计重置不等同于确认恢复。
- [x] 增加有意义的请求契约、解析边界、账号隔离和提醒行为验证；运行相关测试和完整 unsigned TokenPulse target 构建，覆盖 App、Widgets 与 Watch 资源。
- [ ] 新增图标优先官方资产或既有 Lobe Icons 来源，固定来源版本、记录版权许可，并验证模板渲染与矢量资产。
- [ ] 记录实际账号查询、凭证失效和双端独立刷新证据；没有凭证或设备时准确保留未验收项，模拟响应通过不能代替真实验收。
- [ ] 更新提供商支持范围、登录说明、领域用语与验证边界。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/poe.md)。参考代码与模拟响应只作为契约线索，不能视为真实账号验证。

## Implementation progress (2026-10-02)

- Provider API Key envelope、固定 GET/Bearer 请求、App/Watch 共用直连 client、演示账号、widget 与详情展示已实现。
- Poe 使用非货币 points，隐藏提醒设置并在 planner 中排除货币/百分比/重置告警；Vercel 使用精确 USD，余额明细可缺失并显示“未提供”。
- WalletBalance 新字段缺失时按旧 DeepSeek 存档默认货币；未提供明细不补零。新增 WalletProviderTests 覆盖边界、错误、请求、多账号离线重开/失败保留/删除及提醒规则。
- 图标来源版本、资产路径、版权和许可已记录；模板渲染与矢量保留已声明。
- Swift 6 domain/providers typecheck、Swift parse、PBX plist 静态检查通过。unsigned 全目标构建与 XCTest 待统一构建槽验证，真实账号/凭证失效/设备独立刷新/iCloud 同步仍未验收，因此上述验收清单保留待勾选。
- 登录说明、单位语义、来源与验证边界见 `docs/poe-vercel-integration.md`。

## 集成验证（2026-10-02，root）

本轮完整 238 项 XCTest 全部通过，unsigned TokenPulse target 构建成功，覆盖 App、两端 Widgets 和 Watch；iPhone 模拟器演示卡片完成查看。分组提交时记录的“待中央构建/测试”已由本次结果补齐，详见[统一验证记录](../validation-record.md)。真实提供商登录/查询、物理 Watch 独立刷新和跨设备 iCloud 到达尚未验收，因此未标完成。
