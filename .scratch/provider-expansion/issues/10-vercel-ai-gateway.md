# 10: Vercel AI Gateway 钱包余额接入

**Status:** ready-for-agent

**Type:** integration

**What to build:** 用户输入 AI Gateway Key，在双端查看美元余额并配置低余额提醒。

**Blocked by:** None (can start immediately)

## Acceptance criteria

- [ ] 使用精确十进制解析余额，保留零与负余额；累计花费不作为额度上限。
- [ ] 完善仅返回总余额的钱包展示：赠送或充值明细缺失时显示未提供，不填零；验证现有 DeepSeek 明细和提醒不回归。
- [ ] 完成添加、凭证安全保存、多账号隔离、重新打开后恢复、账号删除与同步；iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别直连提供商查询；Watch 已取得配置和凭证后，不依赖手机或 Mac 在线。
- [ ] 账号卡片、详情、iPhone 小组件和 Watch 展示保持数值、单位、采集时间与过期状态一致；支持演示数据并保持演示与真实账号隔离。
- [ ] 适用的额度告警、重置提醒或低余额提醒沿用现有规则；失败保留旧数据，缺失指标不补零，预计重置不等同于确认恢复。
- [ ] 增加有意义的请求契约、解析边界、账号隔离和提醒行为验证；运行相关测试和完整 unsigned TokenPulse target 构建，覆盖 App、Widgets 与 Watch 资源。
- [ ] 新增图标优先官方资产或既有 Lobe Icons 来源，固定来源版本、记录版权许可，并验证模板渲染与矢量资产。
- [ ] 记录实际账号查询、凭证失效和双端独立刷新证据；没有凭证或设备时准确保留未验收项，模拟响应通过不能代替真实验收。
- [ ] 更新提供商支持范围、登录说明、领域用语与验证边界。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/vercel-ai-gateway.md)。参考代码与模拟响应只作为契约线索，不能视为真实账号验证。
