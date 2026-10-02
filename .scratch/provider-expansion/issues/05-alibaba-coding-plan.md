# 05: 阿里百炼 Coding Plan 额度接入

**Status:** ready-for-agent

**Type:** integration

**What to build:** 用户选择百炼国内或国际服务并提供可用凭证，在双端查看 Coding Plan 三个额度周期。

**Blocked by:** None (can start immediately)

## Acceptance criteria

- [ ] 实施前核验选定站点的 Key 查询是否可用；遇到要求控制台会话时明确提示，不把登录失败显示成零额度或无套餐。
- [ ] 显示有效套餐的 5 小时、每周与账期额度；多个套餐中不选择已过期套餐的数据。
- [ ] 凭证只发送至所选地区；缺失额度和已过期重置时间不通过猜测补齐；真实 Key 不可用时记录阻塞，不能宣称完成。
- [ ] 完成添加、凭证安全保存、多账号隔离、重新打开后恢复、账号删除与同步；iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别直连提供商查询；Watch 已取得配置和凭证后，不依赖手机或 Mac 在线。
- [ ] 账号卡片、详情、iPhone 小组件和 Watch 展示保持数值、单位、采集时间与过期状态一致；支持演示数据并保持演示与真实账号隔离。
- [ ] 适用的额度告警、重置提醒或低余额提醒沿用现有规则；失败保留旧数据，缺失指标不补零，预计重置不等同于确认恢复。
- [ ] 增加有意义的请求契约、解析边界、账号隔离和提醒行为验证；运行相关测试和完整 unsigned TokenPulse target 构建，覆盖 App、Widgets 与 Watch 资源。
- [ ] 新增图标优先官方资产或既有 Lobe Icons 来源，固定来源版本、记录版权许可，并验证模板渲染与矢量资产。
- [ ] 记录实际账号查询、凭证失效和双端独立刷新证据；没有凭证或设备时准确保留未验收项，模拟响应通过不能代替真实验收。
- [ ] 更新提供商支持范围、登录说明、领域用语与验证边界。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/alibaba-coding-plan.md)。参考代码与模拟响应只作为契约线索，不能视为真实账号验证。
