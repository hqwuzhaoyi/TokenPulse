# 01: 智谱国内版套餐额度接入

**Status:** implemented-awaiting-real-validation

**Type:** integration

**What to build:** 用户输入国内 Coding Plan Key 后，在 iPhone、Watch 与小组件查看国内账号的套餐额度。

**Blocked by:** None (can start immediately)

## Acceptance criteria

- [ ] 国内与国际服务明确区分；Key、缓存和查询地址按服务账号绑定，国内 Key 不发送到国际站。
- [ ] 显示服务实际返回的各额度窗口与重置时间；复用解析前验证国内响应的状态码、单位与缺失字段语义。
- [ ] 完成添加、凭证安全保存、多账号隔离、重新打开后恢复、账号删除与同步；iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别直连提供商查询；Watch 已取得配置和凭证后，不依赖手机或 Mac 在线。
- [ ] 账号卡片、详情、iPhone 小组件和 Watch 展示保持数值、单位、采集时间与过期状态一致；支持演示数据并保持演示与真实账号隔离。
- [ ] 适用的额度告警、重置提醒或低余额提醒沿用现有规则；失败保留旧数据，缺失指标不补零，预计重置不等同于确认恢复。
- [x] 增加有意义的请求契约、解析边界、账号隔离和提醒行为验证；运行相关测试和完整 unsigned TokenPulse target 构建，覆盖 App、Widgets 与 Watch 资源。
- [ ] 新增图标优先官方资产或既有 Lobe Icons 来源，固定来源版本、记录版权许可，并验证模板渲染与矢量资产。
- [ ] 记录实际账号查询、凭证失效和双端独立刷新证据；没有凭证或设备时准确保留未验收项，模拟响应通过不能代替真实验收。
- [ ] 更新提供商支持范围、登录说明、领域用语与验证边界。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/zai.md)。参考代码与模拟响应只作为契约线索，不能视为真实账号验证。

## Implementation and validation record (2026-10-02)

Implemented on `sol/regional`: provider-bound regional Key login, explicit regional host routing, shared account persistence/Keychain/synchronization paths, device-side refresh routing, demo account, licensed existing brand icon, and all reported widget metrics. See [regional contracts and validation boundary](../../../docs/regional-provider-integration.md).

Verified: Swift parser and provider/domain type checking; the 14 new `RegionalProviderTests` also type-check against a temporary macOS module. `git diff --check` passes. Tests use synthetic credentials and response fixtures.

Pending: root's integrated XCTest run and full unsigned `TokenPulse` build (App, Widgets, Watch assets); actual regional subscription query and expired/revoked Key; real Keychain/iCloud credential arrival; iCloud-off app lifecycle on device; offline-phone Watch independent refresh; real widget/Watch UI and notification delivery. No real credentials were accessed, no physical-device acceptance was claimed, and all acceptance checkboxes remain open until their evidence is recorded.

## 集成验证（2026-10-02，root）

本轮完整 238 项 XCTest 全部通过，unsigned TokenPulse target 构建成功，覆盖 App、两端 Widgets 和 Watch；iPhone 模拟器演示卡片完成查看。分组提交时记录的“待中央构建/测试”已由本次结果补齐，详见[统一验证记录](../validation-record.md)。真实提供商登录/查询、物理 Watch 独立刷新和跨设备 iCloud 到达尚未验收，因此未标完成。
