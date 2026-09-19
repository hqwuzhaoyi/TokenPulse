# TokenPulse 实现任务

Approved: yes

用户批准原话：“可以”。批准对象为 12 张任务的粒度、交付范围、阻塞关系及逐张本地发布方式；记录日期：2026-09-08。

任务仅发布到本地，未创建远端 Issue。应用实现已开始。采用 OpenSpec 目录组织不表示已配置或执行 OpenSpec 工作流。

2026-09-08 用户追加指令：“先把其他的一起都实现了”。据此允许先完成全部 tickets 的实现与自动验证，真实账号及实机验收随后进行；此调整不代表真实验收已经通过。

## 依据

- [已确认规格](../../../docs/spec.md)
- [领域词汇](../../../CONTEXT.md)
- [设备侧刷新架构决定](../../../docs/adr/0001-device-side-refresh.md)
- [获批拆分记录](../../../docs/ticket-breakdown.md)

## 执行与验收门槛

- 按代码依赖推进全部任务，允许并行开发；真实账号和实机验收不再阻塞后续代码实现。
- 每张任务的验收条件全部通过后，才能勾选对应索引；分别记录实现、自动验证和实机验收状态。
- 01—06 的五家登录、查询、适用续期、多账号隔离与 Watch 独立查询的真实验证仍须完成，但允许先实现 07—12。
- 使用已确认的应用层行为测试边界；真实登录、凭证轮换、iCloud 恢复和手机断联后的 Watch 查询须保留实机证据，不以模拟数据替代。没有真实验证不得标完成。
- 已建立原生 SwiftUI/XCTest 工程，最低 iOS 17、watchOS 10；实际验证使用 Xcode 26.2、Swift 6。逐项记录构建和检查命令。
- 沿用领域术语和架构决定，不新增 Mac 代查或设备外查询服务。某个服务接入不可行时报告具体障碍，由用户决定是否暂缓，再修订范围与依赖，不能直接跳过。
- 保持已完成路径可运行，不为没有需求的兼容层或抽象增加任务；不得直接操作 master 或合并，相关操作仍需用户人工确认。
- 原始凭证不得写入文档、版本库、测试夹具或输出。不得将未执行的手工验收擅自标为有意延期。

## Tickets

当前 12 张任务均为 `implemented-awaiting-device-validation`：实现已落地，50 项自动测试及完整设备代码构建通过。下列复选框继续保留真实账号与实机完整验收语义，详见 [统一验收记录](../../../docs/implementation-status.md)。

- [ ] [01 — iPhone 独立查询 MiniMax 国内版套餐额度](tickets/01-iphone-minimax-quota.md) — 阻塞：无。
- [ ] [02 — MiniMax 账号同步后在 Watch 独立刷新](tickets/02-watch-minimax-sync.md) — 阻塞：01。
- [ ] [03 — Claude 多账号登录与双端独立刷新](tickets/03-claude-independent-refresh.md) — 阻塞：02。
- [ ] [04 — Codex 多账号登录与双端独立刷新](tickets/04-codex-independent-refresh.md) — 阻塞：02。
- [ ] [05 — Z.ai Coding Plan 多账号双端查询](tickets/05-zai-independent-refresh.md) — 阻塞：02。
- [ ] [06 — SuperGrok 多账号登录与双端独立刷新](tickets/06-supergrok-independent-refresh.md) — 阻塞：02。
- [ ] [07 — iPhone 完整账号列表、提醒配置与同步恢复](tickets/07-iphone-account-list-sync.md) — 阻塞：03、04、05、06。
- [ ] [08 — Watch 表盘式账号分页与独立刷新体验](tickets/08-watch-account-pages.md) — 阻塞：07。
- [ ] [09 — 双端按窗口额度告警](tickets/09-quota-alerts.md) — 阻塞：07。
- [ ] [10 — 双端预计重置与确认重置提醒](tickets/10-quota-reset-reminders.md) — 阻塞：09。
- [ ] [11 — iPhone 主屏幕与锁屏小组件](tickets/11-iphone-widgets.md) — 阻塞：07。
- [ ] [12 — Watch 表盘复杂功能与智能叠放小组件](tickets/12-watch-widgets.md) — 阻塞：08。

依赖关系：01 → 02 → {03、04、05、06} → 07；07 → {08、09、11}；09 → 10；08 → 12。
