# 全部 Tickets 实现与验收记录

用户于 2026-09-08 指示“先把其他的一起都实现了”，允许先开发全部功能，随后做真实账号与实机验收。任务索引中的复选框继续表示完整验收，不能以构建成功替代。

## 提供商扩展最新快照（2026-10-02，c5e3382）

46个提供商代码入口已集成：原有9个、首批8个、第二批29个。扩展tracker共69票，其中37张代码票已按用户最新“图标存在”标准关闭，7张研究票待验证，25张接入票未实施（24张依赖已解除）。图标检查见[验收记录](../.scratch/provider-expansion/icon-acceptance.md)。root已实际执行465项完整XCTest、0 failures，并完成unsigned App/Watch/两端Widgets目标构建。新增卡片AX/重点截图及添加菜单已抽查，完整UI和真实账号/物理Watch/iCloud/生产接口与通知未因此通过；审查修复和最终重新验证已完成。当前范围见[提供商表](../README.md#提供商与登录方式)和[第二批记录](../.scratch/provider-expansion/wave2-progress.md)，最终证据由root维护[统一验证记录](../.scratch/provider-expansion/validation-record.md)。

下方原始功能Ticket编号与历史验证保持原意，和provider-expansion的01–69编号不是同一票据集。

## 实现映射

| Ticket | 实现入口 | 实机验收仍需覆盖 |
| --- | --- | --- |
| 01 | MiniMaxQuotaClient、QuotaMonitor、KeychainCredentialStore | 两个真实国内 Coding Plan 账号、失效 Key、重启与断网 |
| 02 | SynchronizableCredentialStore、ICloudSyncRuntime、AppRuntime | 签名权限、Watch 凭证到达、手机离线后 Watch 直查、恢复 |
| 03 | ClaudeProvider、ClaudeSessionLoginView | 手机登录/组织选择、Cookie 生命周期、双账号、Watch 直查 |
| 04 | CodexProvider、ProviderSignInView | 设备码授权、订阅额度、令牌续期及双端轮换 |
| 05 | ZaiProvider | 国际 Coding Plan 凭证、双账号、多窗口和失效状态 |
| 06 | SuperGrokProvider、ProviderSignInView | 真实 SuperGrok 套餐归属、授权、续期和双端查询 |
| 07 | AccountConfiguration、AccountSettingsView、AppRuntime | 配置恢复、全局通知开关、无 iCloud 本地使用 |
| 08 | WatchAccountPagesView | 目标 Watch 的分页、多窗口可读性、后台与独立刷新 |
| 09 | NotificationPlanner、NotificationRuntime | 系统通知权限、两端告警和跨设备记录同步 |
| 10 | NotificationPlanner、UserNotificationCenterAdapter | 应用未运行时预计重置提醒、取消及重排 |
| 11 | TokenPulseWidgets | 主屏幕/锁屏配置与真实系统刷新 |
| 12 | TokenPulseWatchWidgets | 表盘/智能叠放配置与真实系统刷新 |

## 本轮已执行验证（2026-09-08）

- 50/50 XCTest 通过，0 failures；覆盖 21 项初始 MiniMax/应用规则、3 项账号配置、9 项提供商契约、14 项通知规则及 3 项平台存储/合并行为。
- 测试使用 `/tmp/tokenpulse-ios-tests.BERwFU/TokenPulse.xcodeproj` 的临时 iOS 测试入口：源码绝对引用本工作区，移除的仅为测试入口中的 Watch 嵌入依赖。没有替换业务代码。Xcode scheme 因未安装 watchOS 26.2 模拟器组件不能在此机器直接运行完整嵌入 scheme。
- 测试结果：`/tmp/tokenpulse-ios-tests.BERwFU/DerivedData/Logs/Test/Test-TokenPulse-2026.09.08_09-18-13-+0800.xcresult`；日志：`/tmp/tokenpulse-ios-tests.BERwFU/final-tests.log`。
- 原始完整工程设备构建通过：`xcodebuild build -project TokenPulse.xcodeproj -target TokenPulse -configuration Debug CODE_SIGNING_ALLOWED=NO SYMROOT=/tmp/tokenpulse-final-products OBJROOT=/tmp/tokenpulse-final-obj`。日志 `/tmp/tokenpulse-production-final.log`。这是实际 iOS/watchOS target 编译及嵌入检查，没有移除生产工程依赖。
- 完整 iPhone 产物位于 `/tmp/tokenpulse-final-products/Debug-iphoneos/TokenPulse.app`，包含 `PlugIns/TokenPulseWidgets.appex` 和 `Watch/TokenPulseWatch.app/PlugIns/TokenPulseWatchWidgets.appex`。
- 最新 iPhone 模拟器 App 构建、安装、启动成功（`com.tokenpulse.app`），空状态/账号设置/添加入口截图已检查：`/tmp/tokenpulse-all-tickets.png`。
- plist/entitlements 语法检查通过；新增源码中未发现私钥或长 Token 模式。原有 ticket 文件尾部的空白不属于功能错误。
- watchOS 模拟器组件下载已取消，未宣称完成模拟器安装、Watch 模拟器运行或真机测试。

## 真机安装进度（2026-09-08）

- 已连接 iPhone 15 Pro，iOS 27.0 Beta，开发者模式已开启。
- 已配置开发团队 `58M23C5WLR`，自动生成 Apple Development 签名及 App/扩展 provisioning profiles。
- 原默认 App Group 注册不可用，已统一改为 `group.com.tokenpulse.58m23c5wlr.shared`。
- 完整签名构建通过，日志 `/tmp/tokenpulse-device-signing.log`；签名产物 `/tmp/tokenpulse-device-validation/products/Debug-iphoneos/TokenPulse.app`。
- `devicectl device install app` 已确认 `com.tokenpulse.app` 安装成功。
- 首次启动被手机锁屏拒绝（`FBSOpenApplicationErrorDomain / Locked`）；用户解锁后于 09:47 成功启动。
- `devicectl` 确认主应用进程（PID 2539）与 iPhone Widget 扩展进程（PID 2545）存在。已验证真机安装和启动，尚未验证真实账号查询、Widget 显示或 Watch 运行。

## 尚待验收

### 环状额度小组件与多账号布局

- 已采用 A — Pulse Rail：保留现有渠道 SVG 和模板渲染，额度窗口独立成环并显示自己的重置时间；账号级可手动重置次数每个账号只显示一次。
- 小、中、大组件都从主屏幕已配置账号列表中选择，分别最多选择 1、2、4 个具体账号，选择顺序就是展示顺序；重复选择会按首次出现去重，每个可见账号区域拥有独立深链。
- MiniMax 统一显示 5 小时单环；GLM 与 Codex Plus 分别显示 5 小时、周额度双环；Codex Pro 按套餐策略只显示账号级周额度；SuperGrok 显示共享额度环。
- SuperGrok 的公开账单结构只核实到使用率、周期、按需字段和预付余额，没有可信的剩余手动重置次数字段，因此 Widget 显示“未提供”，不使用原型示意值或推算值。
- Watch 表盘账号跨进程刷新修正后 87/87 全量测试通过；结果包 `/tmp/tokenpulse-watch-selection-race-final/Logs/Test/Test-TokenPulse-2026.09.09_22-24-31-+0800.xcresult`，日志 `/tmp/tokenpulse-watch-selection-race-tests.log`。
- iOS/watchOS 全部生产 targets 无签名设备构建通过；日志 `/tmp/tokenpulse-watch-selection-race-build.log`，iPhone 产物 `/tmp/tokenpulse-watch-selection-race-products/Debug-iphoneos/TokenPulse.app`，包含 iPhone Widget、Watch App 与 Watch Widget。
- iPhone 17 Pro / iOS 26.3.1 模拟器已在系统 Widget Gallery 检查小、中、大尺寸；大组件实际添加到主屏幕，两个账号时自动撑满，左右账号区域分别进入“工作账号”和“个人账号”。
- 后续在同一模拟器验证大组件编辑页：系统从主屏幕账号列表提供“工作账号 / Codex”“个人账号 / Claude”，可通过“添加新项目”组成账号集合；未配置的旧组件明确提示“请选择展示账号”。
- 用户反馈表盘四角无法展示后，确认缺少 `accessoryCorner` family。现已加入四角专用渠道图标与沿表盘边缘的额度 Gauge/重置标签；watchOS 26.2 模拟器和实体 Apple Watch Series 8 destination 均签名构建通过，新版 Watch App 已成功覆盖安装到实体手表。四角槽位最终显示仍待用户在表盘编辑界面确认。
- 用户进一步确认 Watch 不适合在 complication 配置中选择账号。Watch complication 现为无参数插件，统一读取 TokenPulse Watch App →“表盘设置”中的“表盘显示账号”；未设置或原账号删除时默认首个账号，修改后立即刷新全部 complication。iPhone 继续保留 1/2/4 个账号集合配置。Watch App 移除手动通知按钮，首次启动自动请求系统通知权限，允许后按默认开启的账号提醒规则运行。新版已覆盖安装并启动，实体 Watch 主 App 与 Widget extension 进程均确认运行。
- 用户反馈选择其他账号后表盘仍显示第一个。确认设置页原先依赖 Picker `.onChange` 异步写入，且 App Group 写入后立即全量刷新可能让 Widget extension 读到旧值。现改为显式账号按钮，等待写入、跨进程同步并定向刷新 `TokenPulseWatchQuota` 后才返回；独立 store 实例读回测试覆盖该路径。最新版已再次覆盖安装并启动，最终表盘切换待用户确认。
- 完整 HTML 原型已保存到非 master 分支 `prototype/ios-quota-ring-widgets`，提交 `dda276a25d9ccf2cc6b6ab045670061615a1f605`；当前实现分支不保留原型代码。
- 实体 iPhone 当前不可用；实体 Watch 可见但没有完成本轮 Widget 添加和显示验证，继续作为实机验收差距，不影响已完成的自动与模拟器验收。

### 小组件账号汇总优化

- 根据用户要求移除窗口选择：Codex/SuperGrok 显示每周额度与重置时间，GLM 同一组件显示每周及 5 小时额度。用户随后明确 MiniMax 桌面小组件应显示 5 小时额度，已按桌面尺寸调整；各周期不相加。
- App/Watch 移除剩余额度和总额度展示；重置日期统一按当前地区及本地时区格式化。
- SuperGrok 补充读取账单 RPC 明确发布的百分比，未提供与真实 0% 保持区分。正向、缺失、畸形响应及日期/渠道筛选行为已覆盖。
- 66/66 全量测试通过（`/tmp/tokenpulse-widget-summary.Cqe40d/tests.log`），完整签名构建通过（`/tmp/tokenpulse-widget-summary-build.log`）。手机离线，尚未安装本轮更新。
- 用户确认“重置次数”为剩余可手动重置额度的次数。Codex 已按官方 `rate_limit_reset_credits.available_count` 字段接入，随账号快照持久化、同步并传到小组件；SuperGrok 尚无核实的对应字段，保留“未提供”。
- 接入次数后 69/69 全量测试通过（`/tmp/tokenpulse-reset-count-tests.log`），包括 0、缺失、非法值和明细列表长度不能替代可用次数的行为；没有执行重置操作。手机离线，待真机刷新确认实际返回值。

### OpenCode Go 接入

- 参考原 Pulse 与 OpenCode 第一方源码，接入 `GET https://opencode.ai/zen/go/v1/usage`；iPhone 手动录入 API Key，凭证沿用现有 Keychain 与双端同步，不读取 Mac 的 `auth.json`。
- `rolling`、`weekly`、`monthly` 分别映射为 5 小时、每周、每月窗口，进入 App、Watch、小组件、额度告警及有实际用量时的重置提醒。
- `status=rate-limited` 显示为“已用尽”并触发最高阈值告警；401 表示 Key 无效，403 单独表示没有 OpenCode Go 套餐；坏 JSON 与无有效窗口分别报错。
- OpenCode 图标取自固定参考提交的 Pulse 资源并保留 MIT 来源说明。
- 85/85 全量测试通过，日志 `/tmp/tokenpulse-opencode-full-tests.log`。尚未使用真实 OpenCode Go Key 在 iPhone 与 Watch 验证。
- 2026-09-22 将原“必须跨过旧边界”规则替换为 Pulse 的统一窗口翻转启发式：`resetsAt` 推进超过 60 秒或用量下降至少 40 个百分点时重新武装阈值。推断周期使用独立身份；空闲窗口不会发送重置通知，已合并远端账本时也不会用更旧的本地快照再次翻转。

### OpenCode 月额度与 Claude Fable 展示

- OpenCode Go 的 5 小时、每周、每月指标全部进入主屏幕小/中/大组件和 Inline；三个环时自适应缩小间距与直径。角落、圆形和矩形附件保留主窗口，避免不可读布局。
- Claude `weekly_scoped` 使用服务端 `scope.model.display_name`，Fable 显示为“Fable 每周额度”；主屏幕组件最多显示 5 小时、账号每周、Fable 每周三个环。
- scoped 额度的概览、详情、辅助功能和通知统一保留模型名称；Fable 缺少 `resets_at` 时仍显示用量，但不安排重置提醒。
- 研究证据见 `docs/claude-fable-research.md`；真实 Claude 账号与各尺寸组件仍待实机验收。
- 87/87 全量测试通过，日志 `/tmp/tokenpulse-opencode-monthly-fable-tests.log`。

### Watch 通知默认开启

- Watch 不再提供单独的“开启通知”按钮或重复配置入口；首次启动自动请求系统通知权限，用户允许后默认启用额度告警和重置提醒。
- 系统拒绝状态仍由 watchOS 控制，应用不会重复弹窗或绕过权限；需要恢复时由用户在 iPhone Watch App 的通知设置中处理。
- 通知授权行为和表盘账号共享选择均有自动测试覆盖；最终全量结果为 87/87。
- 实体 Watch 签名构建、覆盖安装和启动通过，主 App 与 Widget extension 进程均确认运行。

### iOS 同步控制

- 已增加持久化的本机 iCloud 同步开关、手动同步及请求/接收时间。关闭后暂停应用主动读写云端配置及凭证；已有云端数据保留。
- 同步按钮固定显示“立即同步”，右侧只显示成功提交/收到更新中较新的一个时间；点击时原图标在 0.6 秒内旋转一圈，遵循“减少动态效果”。同步中拦截重复点击，不切换文字、颜色或添加占位宽度不同的加载图标。
- 本轮简化后构建通过，3 项同步行为回归通过（`/tmp/tokenpulse-simple-sync-tests.log`）；模拟器录屏确认图标旋转、文字与时间位置稳定（`/tmp/tokenpulse-simple-sync.mov`）。尚未安装真机。
- 只有请求操作成功完成才记录请求时间，收到外部数据更新时单独记录接收时间；不会把本地缓存读取当成新到达的数据。
- 同步返回失败、数据无法解析、配额及账号变化通知会显示错误；手动按钮在关闭或执行中禁用。
- 58/58 自动测试通过（`/tmp/tokenpulse-sync-settings-tests.log`），完整签名构建通过（`/tmp/tokenpulse-sync-settings-final-build.log`）。当前 iPhone 离线，新版尚未覆盖安装并实机验证该设置页。

用户真机反馈：GLM（Z.ai）与 MiniMax 账号均成功查询。此项为用户报告的真实查询结果，不代表多账号隔离、断网、恢复及 Watch 等其余验收全部通过。

### 账号删除与拖动排序修复（2026-09-10）

- 模拟器复现：展开的 `DisclosureGroup` 被 `List` 拆成标题和详情两个排序项，详情出现额外拖动手柄。将整个账号包进同一行后，正反排序均保持完整卡片，每个账号只有一个拖动手柄。
- 排序回归测试在修复前捕获到一次移动发布三次列表，其中两次缺少账号；现在先在副本上完成移动，再一次发布完整列表。
- 首页左滑显示删除按钮，点击后确认；关闭整行滑到底触发操作，编辑模式不显示减号删除入口。进入 Edit 时仅显示账号概览，禁用点击展开并保留拖动排序。账号设置底部也可删除。按账号 ID 删除，保留同提供商的其他账号。删除记录持久化并参与双向云端合并，旧数据不能恢复已删除账号；凭证清理失败可重试，未完成的刷新也不能写回已删账号的数据或凭证。
- 删除会更新小组件并取消该账号的待发送重置提醒；启动时继续清理中断删除留下的快照和凭证。模拟器验证了删除确认及取消后账号保留；本轮尚未安装真机，真实 iCloud 双端删除仍待验收。
- 98/98 全量测试通过，包含 iOS/watchOS 与两端 Widget 的模拟器构建；日志 `/tmp/tokenpulse-account-final-tests.log`，结果 `/tmp/tokenpulse-account-fix/Logs/Test/Test-TokenPulse-2026.09.10_22-55-22-+0800.xcresult`。
- 后续 Edit/左滑交互调整构建通过（`/tmp/tokenpulse-edit-swipe-build.log`）；模拟器确认编辑时自动收起且点击不展开、拖动排序有效，以及删除操作仍弹出账号确认、取消后账号保留。

### 账号详情展开动画修复（2026-09-10）

- 录屏复现了行高立即切换、标题和详情随后重新排布的跳动。保留单个账号一个列表行，通过原生 [DisclosureGroupStyle](https://developer.apple.com/documentation/swiftui/disclosuregroupstyle) 与可动画的 [Layout](https://developer.apple.com/documentation/swiftui/layout)，让详情可见高度逐帧变化，标题保持顶部对齐，下方账号随高度同步移动。
- 展开/收起使用 0.25 秒缓入缓出，遵循“减少动态效果”；隐藏详情不能点击，也不会被辅助功能读取。Edit 仍收起详情、禁用展开，并保留排序和删除入口。
- 相同账号反复展开/收起的录屏对比通过：修复前 `/tmp/tokenpulse-expand-before.mov`，修复后 `/tmp/tokenpulse-expand-layout.mov`；逐帧检查确认卡片位置经过中间高度，无标题跳位和内容重叠。未安装真机。
- 新增宿主视图布局回归，验证部分展开时行高正确且详情不会被压缩；与账号配置回归共 10/10 通过，日志 `/tmp/tokenpulse-expand-tests.log`。本轮 iOS/watchOS 与两端 Widget 构建通过。

### Codex 浏览器授权返回修复

- 用户报告外部浏览器授权后返回应用显示“网络连接失败，请重试”。通过实际认证控制器与可控网络测试重现：一次连接中断会终止原 UI 轮询，重新执行会重新申请授权码。
- 登录页面现在随前后台状态暂停/恢复任务，`DeviceLoginModel` 保存当前授权会话；网络中断有限重试，持续失败可继续原会话；取消不显示网络失败，已过期授权提示重新开始。
- 修复前两项恢复测试失败，日志 `/tmp/tokenpulse-codex-red.log`；修复后 54/54 全量测试通过，日志 `/tmp/tokenpulse-codex-fixed-tests.log`。
- 完整签名构建通过，日志 `/tmp/tokenpulse-codex-device-build.log`，09:57 已覆盖安装到原 iPhone。尚需用户再次完成真实 Codex 授权来确认手机上的原场景已解决。

- 自动化使用脱敏或构造的契约响应；从未将它们标为真实账号证据。
- iOS/watchOS 构建验证代码、SDK 和 target 配置；签名、iCloud Keychain、后台调度和设备授权结果须在实际设备上记录。
- 请求失败保留上次快照。跨过预计重置时间只改变过期状态，不推断额度恢复。
- 提供商未返回的指标保留为空；供应商非公开契约变化时必须以实际响应重新核实。
- 所有代码保留在功能分支，不提交、不合并 master。
