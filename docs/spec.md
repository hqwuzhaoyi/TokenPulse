# TokenPulse：iPhone 与 Apple Watch 多账号套餐额度监控

状态：产品范围与测试边界已确认；Issue 发布位置待指定。尚未发布 Issue，尚未完成真实账号验证。

## Problem Statement

用户同时使用 Claude、Codex、Z.ai、MiniMax 国内版和 SuperGrok 的订阅套餐或 Coding Plan，并可能在同一个提供商下拥有多个订阅账号。用户需要在 iPhone 和 Apple Watch 上方便地查看每个账号的已用比例、剩余额度和重置时间，及时发现额度不足，并在额度预计重置时收到提醒。

参考项目 Pulse 面向 macOS，部分登录和数据获取依赖 Mac 上的 CLI、编辑器或本地文件，不能直接满足手机和手表独立刷新的需求。不同额度窗口不能合并为一个含义不明的“账号总额度”，旧数据也不能被误认为最新额度。用户还希望通过 iCloud 恢复账号、设置和登录凭证，减少换机和跨设备使用时的重复配置。

## Solution

构建个人自用的 iPhone 与 Apple Watch 应用。iPhone 负责配置多个订阅账号，以列表分别展示每个账号的多个额度窗口；Watch 用类似表盘的界面分页展示关注账号，每页一个账号，页内分别显示多个额度窗口。手机和手表均直接向提供商查询，Watch 在 iPhone 不在线时仍能刷新。

iPhone 提供主屏幕和锁屏小组件，Watch 提供表盘复杂功能和智能叠放小组件。组件可指定账号，小尺寸选择一个额度窗口，大尺寸分别显示多个窗口。

通过 iCloud 同步个人数据、设置和安全存储的登录凭证；不开启 iCloud 时，iPhone 仍可本地使用。应用提供按账号配置的额度告警和重置提醒，清楚区分最新数据、旧数据、缺失指标以及预计重置。接受系统后台调度导致的告警延迟和跨设备偶尔重复通知，不引入设备外查询或推送服务。

## User Stories

1. As a subscriber, I want to monitor Claude subscription quota, so that I can see whether my account has capacity remaining.
2. As a subscriber, I want to monitor Codex subscription quota, so that I can plan my coding usage.
3. As a subscriber, I want to monitor Z.ai Coding Plan quota, so that I can track my plan limits.
4. As a subscriber, I want to monitor MiniMax China Coding Plan quota, so that I can track the correct regional subscription.
5. As a SuperGrok subscriber, I want to monitor my subscription quota, so that I can understand my available capacity.
6. As a subscriber, I want to configure multiple accounts for the same provider, so that I can monitor all my subscriptions separately.
7. As a subscriber, I want each account's credentials and quota to remain separate, so that I do not confuse one account with another.
8. As an iPhone user, I want to configure my accounts on my phone, so that I can manage the application without a Mac.
9. As an iPhone user, I want to see my accounts in a list, so that I can compare their current quota at a glance.
10. As a subscriber, I want to see each account's quota windows separately, so that short-period and weekly limits retain their meaning.
11. As a subscriber, I want to see used percentage, remaining quota and reset time when available, so that I can decide when to use each account.
12. As a subscriber, I want unavailable metrics to say they were not provided, so that I do not mistake estimated values for real data.
13. As an iPhone user, I want my phone to fetch quota directly, so that a Mac does not need to be online.
14. As a Watch user, I want my watch to fetch quota directly after account setup, so that I can refresh when my phone is unavailable.
15. As a device user, I want opening the application to refresh quota, so that I can obtain current information when I check it.
16. As a device user, I want to refresh manually, so that I can request an update when needed.
17. As a device user, I want background refresh when the system permits it, so that data can update without every check requiring an app launch.
18. As a device user, I want to see when quota was collected, so that I can judge how current it is.
19. As an offline user, I want to retain the last successful data with a refresh failure indication, so that a connection failure does not erase useful information.
20. As a subscriber, I want an old window to show that an update is needed after its expected reset time, so that I do not assume quota has recovered.
21. As an iPhone user, I want to select and order followed accounts, so that the watch shows the accounts I care about in my preferred order.
22. As a Watch user, I want one dial-style page per followed account, so that I can focus on one account while seeing its separate quota windows.
23. As a Watch user, I want to swipe between account pages, so that I can inspect other followed accounts quickly.
24. As an iPhone user, I want Home Screen widgets, so that I can check quota without opening the application.
25. As an iPhone user, I want Lock Screen widgets, so that key quota information is available from the lock screen.
26. As a Watch user, I want watch face complications, so that I can check a selected account from my watch face.
27. As a Watch user, I want Smart Stack widgets, so that I have another quick entry point to quota information.
28. As a widget user, I want to select an account and a window for a small widget, so that limited space shows the information I choose.
29. As a widget user, I want larger widgets to display multiple windows separately, so that I can inspect more quota information without merging limits.
30. As an iCloud user, I want account data, settings and supported credentials to synchronize securely, so that my own devices can use consistent configuration.
31. As a user replacing my phone, I want synchronized credentials to restore where the provider permits it, so that I can refresh without repeating every login.
32. As a user without iCloud enabled, I want local account setup and quota queries on my phone, so that cloud synchronization is optional for local use.
33. As a Watch user, I want already provisioned credentials to remain usable for independent queries, so that temporarily unavailable synchronization does not require my phone to perform queries.
34. As a Watch user, I want a clear indication when new configuration has not synchronized, so that I understand why an account is not yet ready.
35. As a subscriber, I want quota alerts enabled by default at 80%, 95% and 100% used, so that I can notice approaching limits.
36. As a subscriber, I want to adjust thresholds per account and separately enable or disable quota and reset reminders, so that notifications match my needs.
37. As a subscriber, I want each threshold to alert once per quota window cycle on a device, so that repeated refreshes do not repeatedly notify me.
38. As a subscriber, I want an initial query that is already over a threshold to alert, so that an account added late still receives a useful warning.
39. As a subscriber, I want a refresh that crosses multiple thresholds to notify only the highest reached threshold, so that I do not receive a burst of lower-level alerts.
40. As a subscriber, I want simultaneous alerts from multiple windows of one account combined into one notification, so that all affected windows are reported without unnecessary notification volume.
41. As a subscriber, I want an expected-reset reminder when a provided reset time arrives, so that I know when to check for recovered quota.
42. As a subscriber, I want reset reminders without a known reset time only after a query confirms a reset, so that the application does not invent a reset schedule.
43. As a subscriber, I want confirmed data after an expected-reset reminder to update the display without another reset notification, so that the same event is not announced twice on one device.
44. As a subscriber, I want reminder settings to apply independently of the watch's followed-account list, so that accounts not shown on the watch can still alert me.
45. As a phone and watch user, I want either device to issue alerts independently and share reminder records when possible, so that independent use still works while avoidable duplicates are reduced.
46. As the project owner, I want provider login, refresh and renewal verified before full interface development, so that an unavailable integration is discovered early.
47. As the project owner, I want unsupported independent-refresh integrations reported before scope changes, so that I decide whether to defer a provider.

## Implementation Decisions

- **既有状态**：当前项目只有已确认设计、领域词汇和架构决定，没有应用代码、既有接口、数据库结构或测试框架。以下描述行为与职责，不假定已经存在可复用的应用模块。
- **平台职责**：iPhone 管理账号配置；iPhone 与 Watch 均独立查询。Watch 的首次配置可由 iPhone 完成，独立刷新不扩展为必须脱离 iPhone 独立安装和登录。
- **服务范围**：Claude、Codex、Z.ai 国际服务、MiniMax 国内版及 SuperGrok。允许参考 Pulse 的非官方接入方式，但不将候选 HTTP 或 OAuth 路线视为实机验证完成。
- **接入前置验证**：逐家完成真实登录、额度查询、凭证续期和多账号隔离验证；Watch 需要在 iPhone 不在线时验证直接查询与续期。受阻时由用户决定是否暂缓该服务，不静默删减服务或改成 Mac 代查。
- **领域区分**：提供商、订阅账号、关注账号、套餐额度、额度窗口、额度告警和重置提醒沿用领域词汇。一个提供商可有多个订阅账号，一个账号可有多个独立额度窗口，不合并短周期与每周额度。
- **数据表达**：保存每个账号下各窗口的实际可用指标、重置信息和采集时间，能够区分缺失指标、上次成功数据、刷新失败及待更新状态。同步到达时间不得代替采集时间。具体持久化结构及提供商原始响应映射在验证阶段确定，不在本规格中锁定字段名。
- **共享应用职责（拟议模块划分）**：账号额度监控负责协调刷新、窗口状态和提醒行为；提供商接入负责认证、查询及续期；平台存储、同步、通知与各显示入口负责对应系统能力。按实际实现保持职责分离，不为每个内部步骤引入公共抽象。
- **列表与分页**：iPhone 列表显示账号和分别列出的窗口；Watch 按关注账号顺序分页，每页一个账号，页内分别显示多个窗口，左右滑动切换。
- **小组件**：iPhone 主屏幕、锁屏以及 Watch 表盘复杂功能、智能叠放均在范围内。每个组件指定账号，小尺寸指定一个窗口，大尺寸分别展示多个窗口。主应用与组件应一致表达数据的新旧状态，不承诺组件持续实时刷新。
- **刷新规则**：前台打开时刷新、支持手动刷新，后台按系统机会执行。成功获得新数据后检查额度告警；后台不保证固定间隔，不引入设备外采集及推送服务。
- **失败与过期**：查询失败保留最后成功数据并显示状态；旧窗口跨过预计重置时间后显示“待更新”，不得直接清零用量或宣称额度恢复。提供商没有给出的指标显示“未提供”，不得伪造成真实数据。
- **同步与凭证**：通过 iCloud 同步账号数据、配置、关注顺序、提醒设置和可安全迁移的凭证；已提醒记录用于减少跨设备重复。具体同步机制未锁定。原项目绑定 Mac 的加密凭证文件不能原样承担跨设备恢复；验证同步后的凭证访问及刷新令牌轮换，避免两端续期互相失效。
- **无 iCloud 使用**：iPhone 可本地配置与查询；开启同步后恢复跨设备能力。Watch 已取得可用凭证时继续独立查询，新增配置尚未到达时明确提示。同步不可用不等于提供商查询必须不可用。
- **额度阈值**：每个账号默认已用 80%、95%、100%，可调整。各窗口独立判断，每个窗口周期内每档只提醒一次；新的周期应重新允许提醒。
- **跨档告警**：首次查询已超限也触发；一次从 70% 到 98% 时只发 95% 档提醒，并将 80% 档标记为已提醒。同账号多个窗口在同次刷新中触发时合并为一条通知，并列明窗口。
- **重置提醒**：有确定的预计重置时间时预排“预计已重置”提醒，查询确认后更新数据而不重复通知。提供商更新重置时间时重新安排。没有明确时间时仅在查询确认重置后提醒，不根据任意用量下降推断重置。
- **提醒控制**：每个账号分别开关额度告警及重置提醒，默认均开启；关注列表只控制 Watch 展示。两端允许独立通知并同步提醒记录，不承诺断开同步时全局去重。
- **未锁定技术细节**：最低 iOS/watchOS 版本、签名、持久化和同步框架、各服务认证契约，以及跨端凭证续期策略需要结合实机和接入验证确定。不得把这些待验证项表述为已实现或已作出的具体技术选择。

## Testing Decisions

测试边界已获用户确认。优先在一个较高的应用层边界验证“账号额度监控”的完整可观察行为，不围绕内部辅助函数或调用顺序拆成大量测试边界。

- **主要测试边界**：给定账号配置、提供商返回的窗口数据、时间、已有采集及提醒记录和同步状态，执行用户可触发的刷新或设置操作，验证输出的账号/窗口展示状态、持久化后可恢复的状态，以及应发出、取消或重新安排的通知。只替代真实网络、时间和系统服务等外部依赖，不绑定内部类名、私有方法或具体存储布局。
- **覆盖职责**：通过上述边界覆盖账号隔离、额度窗口表达、失败状态、告警和重置规则、设置恢复及同步状态。提供商接入使用脱敏响应做外部契约验证；UI、组件和平台权限的正确性以少量设备验证补充，不为每个页面重复全部业务规则测试。
- **多账号与多窗口**：同一提供商的两个账号返回不同额度时不混用；同一账号的短周期和每周窗口分别显示与判断；任一缺失指标保留为“未提供”。
- **刷新与旧数据**：成功刷新更新采集时间；失败保留旧值并显示失败；同步到达不能伪装成新采集；跨过预计重置时间只进入待更新状态，不制造已恢复的数据或新的额度告警。
- **阈值场景**：首次查询超限会提醒；70% 到 98% 只发 95% 档；同周期重复刷新不重发同档；到达 100% 可发新档；新窗口周期重新具备告警资格；同账号多窗口触发合并为一条。
- **重置场景**：有明确时间时预排预计提醒，时间改变时更新安排，随后查询确认不重复通知；未知时间时不能预排猜测提醒，必须有查询确认的重置依据。
- **控制场景**：两种提醒开关互不混用；调整阈值按账号隔离；取消关注不关闭提醒；关闭某类提醒后不再投递该类已安排的提醒。
- **同步场景**：不开启 iCloud 仍可本地使用；开启后恢复账号、配置和可迁移凭证；提醒记录已同步时避免可避免的重复；两端离线各自提醒允许重复，不把这种行为当作失败。
- **真实接入验证**：五个服务分别验证 iPhone 登录、查询及令牌续期；同一提供商验证多账号隔离；Watch 在手机不可用时查询和续期；验证同步凭证与两端令牌轮换不会互相使登录失效。不能用模拟响应替代这些验收。
- **平台与显示验证**：实机检查 iPhone 列表、Watch 每页一账号及窗口可读性、关注排序，以及四类小组件入口的账号/窗口选择、显示内容和旧数据状态。后台不按承诺外的固定分钟间隔验收。
- **既有测试先例**：当前项目无测试、应用代码或测试框架；不能宣称沿用了不存在的测试设施。选择能覆盖上述行为的最小测试设施，不移植与本项目行为无关的参考项目测试。
- **测试数据**：使用脱敏响应及可控时间验证规则；真实凭证不进入规格、版本库、响应夹具或测试输出。

## Out of Scope

- Antigravity 和上述五家之外的提供商。
- Cursor Grok Bot 权益、普通 API 按量付费余额、本机会话 Token 统计及费用估算。
- Mac 采集依赖、自建后台查询和推送服务、固定分钟间隔的后台告警保证。
- 跨设备断网或同步延迟时的绝对通知去重。
- 推算提供商未返回的真实指标，或仅凭预计重置时间宣称额度已恢复。
- Watch 必须脱离 iPhone 完成首次安装、配置与登录。
- 公开发行、商业化、多用户共享账号数据及独立的产品账号体系。

## Further Notes

- 本规格综合已最终确认的设计访谈、领域词汇与设备侧查询架构决定，没有重新开启产品范围访谈。
- 接入研究仅核查了源码与文档，未使用真实账号验证。Claude 移动端 OAuth、各服务的非官方接口兼容性、两端共享凭证续期是实现前验证重点。提供商返回的数据能力可能不同，不能预先保证五家都返回全部指标。
- 参考版本为 Pulse `8d7fd60454ce383dd0a136a30790c1e277f8069b`：[提供商说明](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Docs/providers/README.md)、[认证实现](https://github.com/qunqin24/Pulse/blob/8d7fd60454ce383dd0a136a30790c1e277f8069b/Sources/Pulse/OAuthLogin.swift)。
- 平台依据：[iOS 后台调度](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate)、[Watch 后台任务](https://developer.apple.com/documentation/watchkit/using-background-tasks)、[本地通知](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)、[Keychain 同步](https://developer.apple.com/documentation/security/ksecattrsynchronizable)。这些能力不等于真实设备及第三方凭证行为已验证。
- 发布时使用标题“TokenPulse：iPhone 与 Apple Watch 多账号套餐额度监控”，应用 `ready-for-agent` 标签。标签不代表真实接入验证已完成；执行顺序必须先完成接入可行性验证。
- 发布前尚需指定本项目的 Issue tracker。当前目录不是 Git 仓库，没有 remote 或现有 Issue 配置，因此此文件目前是本地规格草稿，不是已发布 Issue。
