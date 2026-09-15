# Qoder 国际版与 DeepSeek 钱包接入

Approved: yes

用户批准原话：“可以”。批准对象为 5 张工单的粒度与阻塞关系，以及 Qoder 设备凭证过期后在 iPhone 重新授权、再同步到 Watch 的处理方式。记录日期：2026-09-15。

仅发布本地工单，未创建远端 Issue。设计依据：[设计访谈](../../../docs/qoder-deepseek-design-interview.md)、[A 原型](../../../TokenPulse/UI/qoder-deepseek.prototype.html?variant=A)。原型只确定布局与交互，所有数据均为示例，不作为接口事实。

## Apply gate

- 当前工作区已有本次接入的部分代码和测试，也有此前的演示模式等未提交改动。先检查实际差异再继续，保留既有工作；不得将文件存在视为已完成。
- 按阻塞关系执行，每张工单验收通过后才更新状态并勾选索引。当前 5 张均未验收完成。
- A 原型：沿用账号卡片；Qoder 个人额度与组织资源包分别展示；DeepSeek 用金额与币种表达钱包余额。
- 提醒入口统一位于设置中的服务账号配置。账号卡片不增加提醒设置入口。
- 刷新失败仅在对应卡片提示：收起显示警告图标；展开显示原因、保留旧数据说明、原采集时间和单账号刷新入口。不增加全局失败横幅。
- 币种与金额直接来自 DeepSeek API，不换算、不伪造使用百分比或重置时间；所选币种缺失时不替换成其他币种。
- Qoder 自动续期不可用，凭证过期后重新授权。不得调用参考代码中已知拒绝设备 token 的旧刷新接口，也不得承诺静默续期。
- 真实账号、凭证同步和独立 Watch 查询属于验收要求；缺少设备或凭证时保持未完成，记录阻碍，不以模拟响应代替。尚未批准延期的检查不得标为 `[~]`。
- 全端继承现有账号排序与关注配置、通知总开关、系统调度刷新及跨设备提醒策略。共享文件安排单一写入者，不能因为工单无业务依赖就并行编辑同一文件。
- 不直接操作或合并 master；不提交与本变更无关的用户改动。

## Tickets

- [ ] [01 — DeepSeek 钱包查询与账号卡片](tickets/01-deepseek-wallet-card.md) — 阻塞：无。
- [ ] [02 — DeepSeek 低余额提醒](tickets/02-deepseek-balance-alerts.md) — 阻塞：01。
- [ ] [03 — DeepSeek Watch 与小组件](tickets/03-deepseek-watch-widgets.md) — 阻塞：01。
- [ ] [04 — Qoder 国际版授权与双额度卡片](tickets/04-qoder-auth-quota-card.md) — 阻塞：无。
- [ ] [05 — Qoder Watch 与小组件](tickets/05-qoder-watch-widgets.md) — 阻塞：04。

初始可执行工单：01、04。01 完成后解锁 02、03；04 完成后解锁 05。02 与 03 无业务阻塞关系。

## 验证方式

- XCTest：`xcodebuild test -scheme TokenPulse -destination 'platform=iOS Simulator,name=iPhone 16e,OS=26.3.1'`。先检查当前可用模拟器；平台版本变化时记录实际使用的 destination。Keychain 测试使用默认本地签名。
- 完整生产 targets：`xcodebuild build -target TokenPulse -configuration Debug CODE_SIGNING_ALLOWED=NO`，不全局指定单个平台 SDK。
- 每张票记录命令、结果包或日志、实际通过/失败项；UI 与真机验收记录设备、操作、预期和实际结果。
- 工单发布时未运行构建或测试；后续共享集成验证结果记录如下，真实账号与实体设备条目仍保持未完成。

## 共享集成验证结果（2026-09-15）

由共享文件集成者执行；5 张工单均保持未完成，真实凭证/设备缺口见末行。

- XCTest：`xcodebuild test -scheme TokenPulse -destination 'platform=iOS Simulator,name=iPhone 16e,OS=26.3.1'` → **TEST SUCCEEDED**，Executed **133 tests, 0 failures**（实际使用 iOS 26.3 / 23D8133 模拟器）。
- 生产 target：`xcodebuild build -target {TokenPulse|TokenPulseWatch|TokenPulseWidgets|TokenPulseWatchWidgets} -configuration Debug CODE_SIGNING_ALLOWED=NO` → 四个 target 全部 **BUILD SUCCEEDED**；清空 `build/` 后重建，仓库不残留构建产物。
- 修复的前序问题：`ProviderIcon` 在 watchOS Widget target 编译失败；`ContentView` 缺少 `return`；`WalletPresentationTests.swift` 被工程引用但文件缺失；`WidgetAccountSnapshot.selectingQoderItem` 用 `scope` 过滤，与 QoderProvider 实际输出（两桶 `scope == nil`）不符，导致个人/组织额度无法分开；接管并修复了 `QoderProviderTests` 的 4 处 `await`-in-autoclosure 编译错误。
- 模拟器 smoke（iPhone 16e / iOS 26.3，演示模式）：首页账号卡片与 A 原型一致；DeepSeek 账号详情显示 CNY 110/10/100 与 USD 8/1/7 的总可用/赠送/充值余额，无百分比与重置时间；设置内含“低余额提醒”开关、币种与阈值。
- Qoder 集成：`ProviderQuotaClient` / 登录控制器 / Watch / Widget / 图标均已接入；`QoderProviderTests` 全部通过（含 PKCE 授权、轮询恢复、到期不静默续期、双额度不合并）。真实 Qoder 浏览器授权未执行。
- 真实凭证/设备缺口（未勾选、未声明完成）：DeepSeek 真实 API Key 查询；Qoder 真实浏览器授权与凭证有效期；iCloud 凭证到达后手机离线 + 实体 Watch 独立刷新；真机通知权限下实际投递；实体设备字号/深浅外观/辅助功能验收。
