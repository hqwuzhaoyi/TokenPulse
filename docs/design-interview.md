# TokenPulse 设计访谈

状态：用户已最终确认共同理解，本轮设计访谈完成，本文作为后续实现依据；尚未开始应用实现或真实账号验证。

## 已确认方向

- 参考项目：https://github.com/qunqin24/Pulse 。
- 提供 iPhone 和 Apple Watch 版本，支持 iCloud 同步。
- 首版面向个人自用，先跑通手机、手表和同步。
- iPhone 负责配置，Watch 负责快速查看关键数据和表盘快捷查看，并支持独立刷新。
- 同步目标是换手机后恢复配置、自己的设备看到一致的数据，并安全同步登录凭证。
- iPhone 必须独立刷新数据，不依赖 Mac 在线采集。
- 首版接入 Claude、Codex、Z.ai、MiniMax 国内版和 Grok；Antigravity 暂不接入。
- 首版展示订阅套餐／Coding Plan 的已用比例、剩余额度和重置时间，不以 API 按量付费余额或本机 Token 消耗为目标。
- 每个提供商支持配置多个订阅账号。
- 支持安全同步登录凭证，目标是新手机恢复后可直接刷新；各提供商的凭证迁移限制仍需验证。
- Watch 首页展示已同步的全部账号，沿用账号列表顺序，不提供单独的关注选择和排序。
- 表盘组件固定展示用户指定的一个账号，进入应用后查看其额度窗口和重置时间。
- 接受沿用参考项目的非官方接入方式；先验证手机登录、刷新和续期，再开展完整界面开发。
- Grok 接入对应 SuperGrok 订阅，不是 Cursor 的 Grok Bot 权益。
- Watch 自己联网时必须能独立获取最新额度，不依赖 iPhone 在线代查。
- 首版需要额度告警和额度重置提醒。
- 额度告警默认阈值为已用 80%、95%、100%，允许按账号调整；同一额度窗口内每档只提醒一次。
- 有明确重置时间时，按该时间发送“预计已重置”提醒，刷新确认后更新数据，不重复通知；没有明确时间时，仅在查询确认重置后提醒。
- 应用提供通知总开关；每个账号可分别开关额度告警和重置提醒，默认均开启。
- 打开应用时刷新，支持手动刷新；后台按系统调度机会刷新，每次成功取得新数据后检查告警。不要求固定分钟间隔的后台查询，当前范围不包含设备外查询和推送服务。
- 查询失败或离线时保留最后成功数据，并显示采集时间和刷新失败状态；超过预计重置时间的旧窗口标记为“待更新”，不推断额度已经恢复。
- iCloud 未开启时，iPhone 可本地配置和查询；开启后同步账号、凭证和设置。Watch 已取得凭证后可独立查询，新配置尚未同步时明确提示。
- 同一账号的多个额度窗口分别显示，不合并成单一额度。
- iPhone 主界面采用列表展示；Watch 应用采用类似表盘的布局，每页一个账号，页内分别展示多个额度窗口，左右滑动切换账号。
- iPhone 支持主屏幕和锁屏小组件；Watch 支持表盘复杂功能和智能叠放小组件。每个组件可指定账号，小尺寸指定一个额度窗口，大尺寸分别展示多个窗口。
- 各额度窗口独立判断阈值和重置；同次刷新触发多个窗口告警时，合并为一条账号通知并列明触发窗口。
- 允许手机与 Watch 重复通知，两端都能独立发出提醒；同步已提醒记录以减少可避免的重复，不承诺跨端完全去重。
- 首次查询已超限也提醒；一次跨过多个阈值时仅发送最高已达到档位的告警，并将较低档位标为已提醒。
- 提供商缺失的比例、剩余额度或重置时间显示“未提供”，不推算成真实数据。
- 先验证五家服务的登录、查询和续期；某家无法实现独立刷新时报告障碍，由用户决定是否暂缓该服务，再继续完整开发。

## 实现前验证清单

- 逐家验证五个提供商的 iPhone 登录、订阅额度查询、续期及多账号隔离；不将源码存在等同于实机可用。
- 在 iPhone 不在线时验证 Watch 的直接查询和续期，尤其确认同步凭证是否引发两端刷新令牌轮换冲突。
- 验证 iCloud 数据及安全凭证同步、换机恢复，以及未开启 iCloud 时的本地使用。
- 根据实际设备和开发环境确定最低系统版本、签名和组件支持范围；不能静默缩减已确认的平台入口。
- 验证告警规则：首次超限、跨越多档、多窗口合并、窗口重置后重新告警、已知重置时间变更和离线旧数据不产生新额度告警。
- 任一服务无法实现独立刷新时，按已确认规则向用户报告并决定是否暂缓；不静默改成依赖 Mac。

## 端到端验收场景

1. 在 iPhone 配置同一提供商的两个账号，分别显示各自的多个额度窗口，账号数据互不混用。
2. 账号同步后，Watch 按账号列表分页展示；手机离线时 Watch 仍能自行获取最新额度。
3. 两端小组件按指定账号和窗口展示，并能够区分旧数据与最新采集结果。
4. 已用比例从 70% 跳到 98% 时只发最高已达到档位告警；同账号多个窗口同时触发时合并通知。
5. 已知重置时间到达时提醒“预计已重置”，未刷新前旧窗口显示“待更新”；缺失数据不伪造。
6. 开启 iCloud 后恢复账号、设置及可迁移凭证；未开启时 iPhone 本地查询仍可用。

## 参考项目事实

核验版本：`8d7fd60454ce383dd0a136a30790c1e277f8069b`。

- 现有应用面向 macOS；部分数据来源依赖本机 CLI 凭证、编辑器数据库、本地语言服务器和会话文件。
- 订阅额度与从本机会话计算的 Token 历史是不同数据。
- 原有凭证文件加密绑定 Mac，不能直接通过同步文件实现跨设备凭证使用。

来源：[提供商说明](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Docs/providers/README.md)、[凭证存储实现](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/LocalSecrets.swift)。

## 独立刷新接入核查

以下为源码与文档核查结果，尚未完成真实 iPhone 登录验证。

- Claude：查询走 HTTP，但现有 OAuth 使用本机 loopback 回调，移动端登录需要原型验证。
- Codex、Grok：参考项目有设备码登录和 HTTP 查询路径，移动端仍需实测；相关额度接口及客户端登录路线不能视为官方第三方集成。
- Z.ai：可输入 Coding Plan Key 查询，参考项目使用未公开的额度路由。
- MiniMax 国内版：官方 FAQ 已提供套餐剩余额度查询示例；订阅 Key 与按量付费 Key 不同。
- Grok 与使用 Cursor 权益的 Grok Bot 是不同接入；本项目已确认使用 SuperGrok。

来源：[OAuth 实现](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/OAuthLogin.swift)、[认证说明](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Docs/providers/authentication.md)、[MiniMax 官方 FAQ](https://platform.minimaxi.com/docs/token-plan/faq)、[Grok Bot 说明](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Docs/providers/grok-bot.md)。

## Apple 平台约束

- iOS 与 watchOS 的后台刷新由系统调度，不能保证固定间隔执行，因此仅依赖设备后台任务不能保证分钟级额度告警。
- 已知重置时间可以预排本地通知，应用不运行时由系统处理；后续查到时间改变时应重新安排。
- iCloud Keychain 支持同步凭证，但不能据此认定提供商的刷新令牌可以安全地由多个设备并发续期，仍需实机验证。
- Watch 独立刷新不等于必须支持脱离 iPhone 完成首次安装和登录；本项目目前由 iPhone 配置。

来源：[iOS 后台调度](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate)、[watchOS 后台任务](https://developer.apple.com/documentation/watchkit/using-background-tasks)、[本地通知](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)、[Keychain 同步](https://developer.apple.com/documentation/security/ksecattrsynchronizable)。
