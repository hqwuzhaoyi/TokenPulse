# 04: Moonshot API 钱包余额接入

**Status:** implemented-awaiting-real-validation

**Type:** integration

**What to build:** 用户明确选择 Moonshot 国内或国际账号并输入 Key，两端查看对应币种的 API 钱包余额。

**Blocked by:** None (can start immediately)

## Acceptance criteria

- [ ] Moonshot 开放平台与 Kimi Code 在添加入口中明确区分；地区绑定凭证与请求地址，不自动跨地区试 Key。
- [ ] 保留可用、赠送、充值余额的原始含义和十进制精度；币种依据已核实的服务契约，负余额保留，不做换汇。
- [ ] 账号支持低余额设置和恢复后重新提醒；钱包不绘制套餐百分比或重置倒计时。
- [ ] 完成添加、凭证安全保存、多账号隔离、重新打开后恢复、账号删除与同步；iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别直连提供商查询；Watch 已取得配置和凭证后，不依赖手机或 Mac 在线。
- [ ] 账号卡片、详情、iPhone 小组件和 Watch 展示保持数值、单位、采集时间与过期状态一致；支持演示数据并保持演示与真实账号隔离。
- [ ] 适用的额度告警、重置提醒或低余额提醒沿用现有规则；失败保留旧数据，缺失指标不补零，预计重置不等同于确认恢复。
- [ ] 增加有意义的请求契约、解析边界、账号隔离和提醒行为验证；运行相关测试和完整 unsigned TokenPulse target 构建，覆盖 App、Widgets 与 Watch 资源。
- [ ] 新增图标优先官方资产或既有 Lobe Icons 来源，固定来源版本、记录版权许可，并验证模板渲染与矢量资产。
- [ ] 记录实际账号查询、凭证失效和双端独立刷新证据；没有凭证或设备时准确保留未验收项，模拟响应通过不能代替真实验收。
- [ ] 更新提供商支持范围、登录说明、领域用语与验证边界。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/moonshot.md)。参考代码与模拟响应只作为契约线索，不能视为真实账号验证。

## 实施与验证（2026-10-02）

已实现显式地区 UI、地区 Key/envelope/缓存身份、双端直连路由、Decimal 全余额及可选明细、低余额提醒、widget、双地区演示与固定许可图标。详见 [Moonshot 接入边界](../../../docs/moonshot-integration.md)。

已验证：生产 module、新增 7 项 XCTest 文件、完整 App UI 通过真实 Swift 6 iOS SDK typecheck；PBX plist 和 diff 检查通过。尚未执行 XCTest 或 unsigned target 构建，由 root 统一串行验证。实际国内/国际 Key、凭证失效、iCloud 与本机安全存储生命周期、物理 Watch 离线独立刷新和实际 UI/通知均未验收；未读取真实凭证，所有验收勾选保持开放。
