# 全部 Tickets 实现与验收记录

用户于 2026-09-08 指示“先把其他的一起都实现了”，允许先开发全部功能，随后做真实账号与实机验收。任务索引中的复选框继续表示完整验收，不能以构建成功替代。

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

### 小组件账号汇总优化

- 根据用户要求移除窗口选择：Codex/SuperGrok 显示每周额度与重置时间，GLM 同一组件显示每周及 5 小时额度。用户随后明确 MiniMax 桌面小组件应显示 5 小时额度，已按桌面尺寸调整；各周期不相加。
- App/Watch 移除剩余额度和总额度展示；重置日期统一按当前地区及本地时区格式化。
- SuperGrok 补充读取账单 RPC 明确发布的百分比，未提供与真实 0% 保持区分。正向、缺失、畸形响应及日期/渠道筛选行为已覆盖。
- 66/66 全量测试通过（`/tmp/tokenpulse-widget-summary.Cqe40d/tests.log`），完整签名构建通过（`/tmp/tokenpulse-widget-summary-build.log`）。手机离线，尚未安装本轮更新。
- 用户确认“重置次数”为剩余可手动重置额度的次数。Codex 已按官方 `rate_limit_reset_credits.available_count` 字段接入，随账号快照持久化、同步并传到小组件；SuperGrok 尚无核实的对应字段，保留“未提供”。
- 接入次数后 69/69 全量测试通过（`/tmp/tokenpulse-reset-count-tests.log`），包括 0、缺失、非法值和明细列表长度不能替代可用次数的行为；没有执行重置操作。手机离线，待真机刷新确认实际返回值。

### Watch 通知按钮反馈修复

- Watch 入口“开启通知”原先丢弃系统返回值并吞掉错误，导致已授权、拒绝、失败均无可见反馈。
- 现已增加处理进度、重复点击禁用和授权结果弹窗；已开启时重新应用提醒安排，被拒绝时提示到 iPhone Watch App 检查通知设置。
- 修复前反馈测试失败，日志 `/tmp/tokenpulse-permission-red.log`；修复后 60/60 测试通过，日志 `/tmp/tokenpulse-watch-notification-tests.log`。
- 完整签名构建通过，日志 `/tmp/tokenpulse-watch-notification-build.log`。当前 Watch 连接握手超时、iPhone 离线，尚未将本次修复安装到真机。

### iOS 同步控制

- 已增加持久化的本机 iCloud 同步开关、手动同步及请求/接收时间。关闭后暂停应用主动读写云端配置及凭证；已有云端数据保留。
- 只有请求操作成功完成才记录请求时间，收到外部数据更新时单独记录接收时间；不会把本地缓存读取当成新到达的数据。
- 同步返回失败、数据无法解析、配额及账号变化通知会显示错误；手动按钮在关闭或执行中禁用。
- 58/58 自动测试通过（`/tmp/tokenpulse-sync-settings-tests.log`），完整签名构建通过（`/tmp/tokenpulse-sync-settings-final-build.log`）。当前 iPhone 离线，新版尚未覆盖安装并实机验证该设置页。

用户真机反馈：GLM（Z.ai）与 MiniMax 账号均成功查询。此项为用户报告的真实查询结果，不代表多账号隔离、断网、恢复及 Watch 等其余验收全部通过。

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
