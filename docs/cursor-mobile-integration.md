# Cursor 移动授权与模型池

`.cursor` 从 iPhone 的账号专用临时 WKWebView 完成 Cursor 账号授权，然后 iPhone 与 Watch 分别直连额度接口。此非官方接入不读 Mac 编辑器数据库、Safari Cookie、其它应用凭证或用户现有会话。`CursorAccountAuthenticator` 与 `CursorAccountSession` 是独立于额度解析的协议模块，可供后续 Cursor 账号服务复用；Grok Bot 61 没有实现，仍须本票真实移动登录与双端查询通过验收后再进入。

## 有依据的授权路径

采用固定 Pulse `397c8fc4f1bd52180a452d2f3f0c099def97cf69` 的 [CursorWebLogin.swift](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Auth/CursorWebLogin.swift) 协议。这不是第三方 OAuth：没有虚构 client ID、OAuth authorize/token URL、redirect URI 或续期端点。

1. 本次登录生成密码学随机 32 字节并 base64url 为 verifier，challenge 是 verifier 字符串的 SHA256/base64url。另生成 UUID nonce。
2. 仅加载 `https://cursor.com/loginDeepControl`，参数 challenge、uuid、mode=login、redirectTarget=sand、supportsSelectedTeamLogin=true 都来自固定源码。sand 是该原生 Cursor/Grok 客户端目标，UI 明确披露借用这条非官方路线；浏览器 URL 不携带 verifier。
3. 账号专用 `WebSessionContainer(provider:.cursor, accountID, host:cursor.com)` 使用全新的 nonPersistent 网站数据存储；不会读取或复用另一个账号的浏览器 Cookie。应用不导出任何网页登录 Cookie。
4. 本机每两秒 `GET https://api2.cursor.sh/auth/poll?uuid=…&verifier=…`。404 为尚未完成，403 为拒绝，网络/服务失败只在同 nonce 的五分钟期限内重试，429 加长等待；取消或重新开始会取消任务、废弃 nonce 并清理原 WK 会话。旧响应在新 run/dismissal 后不能查询或保存凭证。
5. 200 返回 accessToken/refreshToken。访问 JWT 的 sub 和 exp 构成账号身份与真实到期；没有假设 60 天固定寿命。只存查询必需的 accessToken，未验证的 refreshToken 被丢弃，没有编造自动续期。
6. 默认先用新访问令牌完成 Cursor usage-summary 的额度验证，再允许添加/更新账号。有效授权但不返回可识别窗口的账号目前会停在明确验证错误，需要重试或后续适配，不会保存假零额度；这也意味着没有额度窗口的 Free/新账号兼容性未得到确认。

[CursorAppLogin.swift 的 session(from:)](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Auth/CursorAppLogin.swift) 给出 Cookie 构造依据：JWT sub 最后一段账号 ID + `%3A%3A` + token，唯一 Cookie 名 `WorkosCursorSessionToken`。TokenPulse 只移植这段纯转换，不包含源文件的数据库读取代码。账号 ID 做完整安全百分号编码，JWT 字符集、长度、非布尔有限 exp、来源指纹、允许 host、实际 localAccountID 和到期均验证后才构造 Header。JWT 内容不是应用自行验签后的身份断言；来源是 HTTPS 原生登录服务，额度服务仍负责最终认证。

Credential envelope 用 `.session`、明确 localAccountID 和 SHA256 来源身份绑定账号缓存/iCloud/提醒。JWT exp 至少留 60 秒请求余量；到期或 HTTP401/403 提示重新登录。重新登录的新来源清旧账号数据及提醒去重，另一个服务账号不受影响。关闭登录窗口/完成登录会清除临时 WK 数据；删除账号沿用 Keychain 删除、配置 tombstone 和提醒清理。无需手机在线的 Watch 只读取同步过来的同 UUID envelope 并自行构造 Cookie/查询。

## 请求与额度

唯一 quota `GET https://cursor.com/api/usage-summary`。Cookie 显式设置，关闭自动 Cookie 处理、禁用缓存；生产 factory 对 Cursor 所有重定向拒绝。原生 auth 模块的生产 UI 同样使用拒绝所有重定向的 transport，不把 verifier、Cookie 或令牌带到另一 origin。

字段来自固定 [CursorUsageService.swift](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/CursorUsageService.swift)：individualUsage.plan 或 teamUsage.pooled 分别报告 `autoPercentUsed`（Cursor Models）、`apiPercentUsed`（Other Models）。它们是 0–100 百分比，0.0267 就是 0.0267%，不乘 100；缺失池不补零。两个池保持独立，不按套餐价格拼出池总额。

individualUsage.onDemand 或 teamUsage.onDemand 的 enabled、used、limit、remaining 表示额外支出额度。货币原数是 **cents**，转换为 Decimal USD 预算并通过 exactCounts 保留；不是钱包余额，因此没有低余额提醒。明确 enabled=false 或非正限额不生成窗口。若两个模型池都未提供，plan 的实际金额只作为独立“套餐金额额度”备用窗口，不与模型池并列成矛盾分母。缺失用量仍保持未知，明确总额可显示而不生成 0% 或耗尽状态。billingCycleEnd 只读服务返回的 ISO 重置时间；账期身份归 monthly，不合成 30 天重置。

Boolean/数值/Decimal 的类型错误、无法解析响应与没有窗口均保留上次成功数据和采集时间；没有无依据的无限、低余额或手动重置数量。返回的模型池及额外预算进入卡片、详情、全部 Widget 指标与 Watch 页面，适用额度告警和预计重置提醒沿用既有规则。Scoped 模型池在 Watch/账号设置显示完整详情与重置；演示包含两个模型池和额外 USD 预算，继续使用隔离 suite/内存凭证。

## 验证状态与风险

2026-10-02 完成 12 项 `CursorProviderTests` 的实际 Swift 6 iOS SDK typecheck，包含 nonce/PKCE/固定参数、pending/拒绝/到期/网络/取消、JWT/Cookie/账号来源校验、两个池和 cents 精度、team/备用额度/禁用额外支出、未知指标/严格旗标、请求/重定向策略、widget/通知、WK 隔离、关闭/重启期间旧授权响应保护以及多账号恢复/重新授权/删除和独立 Watch monitor 查询。此前 25 项新 provider 测试仍一并 typecheck 通过。

完整生产 module、完整 App UI、iPhone Widgets、Watch App 和 Watch Widgets 均通过实际 Swift 6 类型检查；PBX plist/diff 通过。命令脚本 `/tmp/tokenpulse-wave2-regional-static/check.py` 采用 iPhoneSimulator26.5 SDK（arm64-apple-ios17.0-simulator）和 WatchSimulator26.5 SDK（arm64-apple-watchos10.0-simulator），新测试执行 `-typecheck`，不是仅 parse。

本 worker 未运行 xcodebuild、模拟器或真实账号登录。XCTest 执行与完整 unsigned App/Widgets/Watch target build 留待 root 串行验证；静态 UIKit/Widget 类型检查不代替资源编译、网页或设备测试。真实 WK 移动登录、SSO/CAPTCHA/账号选择、nonce 交付、Cookie usage-summary 兼容、各套餐/团队生产形状、凭证撤销、Keychain/iCloud 到达、iCloud-off 设备生命周期、手机离线时物理 Watch 独立刷新以及真实 UI/提醒仍全部未验收。

主要风险：两条登录/查询 URL 都不是公开 API，固定原生授权路线原本针对 Cursor/Grok 客户端，手机 WKWebView 可能受身份服务的嵌入登录限制；当前只有源码和合成响应证据，没有真实成功握手。没有已验证的续期协议，必须重新登录。无额度窗口账户可能无法完成本版本的登录后验证。Grok Bot 的放行门槛保持关闭，不能把这里的模拟测试当成 61 的真实授权验收。
