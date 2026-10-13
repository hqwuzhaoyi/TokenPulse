# 14: Bifrost 虚拟 Key 预算接入

**Status:** done

**Type:** integration

**What to build:** 用户配置 Bifrost 网关与虚拟 Key，在双端查看 Key、上游提供商和模型的预算窗口。

**Blocked by:** 12 — New API 自定义地址与余额查询

## 当前验收标准（用户于2026-10-02调整）

- [x] 完成本票接入实现，并确认provider图标存在。真实账号/设备验证不再作为关票条件。

下方保留原实现要求与历史验证清单；未勾选不代表当前额外关票门槛。

## 原 Acceptance criteria（历史）

- [ ] 使用虚拟 Key 对应的只读查询路径和认证方式，明确展示预算适用范围，不合并不同层级预算。
- [ ] 仅在临时额度覆盖实际有效时计入预算；账号停用与未配置预算分别显示。
- [ ] 区分固定时长与可能按日历对齐的周期，只对可证明的重置时间启用重置提醒。
- [ ] 完成添加、凭证安全保存、多账号隔离、重新打开后恢复、账号删除与同步；iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别直连提供商查询；Watch 已取得配置和凭证后，不依赖手机或 Mac 在线。
- [ ] 账号卡片、详情、iPhone 小组件和 Watch 展示保持数值、单位、采集时间与过期状态一致；支持演示数据并保持演示与真实账号隔离。
- [ ] 适用的额度告警、重置提醒或低余额提醒沿用现有规则；失败保留旧数据，缺失指标不补零，预计重置不等同于确认恢复。
- [ ] 增加有意义的请求契约、解析边界、账号隔离和提醒行为验证；运行相关测试和完整 unsigned TokenPulse target 构建，覆盖 App、Widgets 与 Watch 资源。
- [ ] 新增图标优先官方资产或既有 Lobe Icons 来源，固定来源版本、记录版权许可，并验证模板渲染与矢量资产。
- [ ] 记录实际账号查询、凭证失效和双端独立刷新证据；没有凭证或设备时准确保留未验收项，模拟响应通过不能代替真实验收。
- [ ] 更新提供商支持范围、登录说明、领域用语与验证边界。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/bifrost.md)。参考代码与模拟响应只作为契约线索，不能视为真实账号验证。


## 2026-10-02 wave3 evidence

`.bifrost` 完整gateway账号/凭证/UI/Watch/widget/demo注册；x-bf-vk只读查询，Key/provider/model三层Decimal预算分窗，active override和旧/日历reset边界，停用与无预算的明确不同状态已实现。SF Symbol puzzlepiece.extension.fill存在并映射，来源许可已记录。新BifrostProviderTests、小模块Swift6语义检查、parse/PBX/diff通过；root统一实际XCTest/构建，本分支无真实Key/部署/设备请求。当前AC完成，旧清单与真实未验证边界保留。[源码与专属说明](../../../docs/bifrost-provider-integration.md)。
