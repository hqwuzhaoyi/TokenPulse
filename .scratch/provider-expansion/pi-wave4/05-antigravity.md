# 05-Antigravity 冻结快照回归报告（AntigravityProvider / AntigravityProviderTests 端到端集成）

日期：2026-10-05（快照冻结）。方法：只读快照源码；用 Swift 6（swiftlang-6.3.3.1.3）纯 Foundation 编译**真实生产源码**（`Domain/Models.swift`、`Providers/ProviderHTTP.swift`、`GoogleNativeOAuth.swift`、`AntigravityProvider.swift`、`ProviderRedirectPolicy.swift`、`Notifications/NotificationPlanner.swift`、`ReminderModels.swift`，以及从 `ProviderIntegration.swift` 逐字提取的类型定义段）在 `/tmp/tokenpulse-wave4-pi/05-antigravity/work` 复现，fixture transport 语义复制自 `AntigravityProviderTests.swift`。未联网、未跑 xcodebuild/XCTest（不伪称测试已跑）。

## 发现（2 项，均为已执行复现；无数据/数值级缺陷）

1. **[已执行] 用户填写的 Cloud 项目 ID 校验过晚且报错误导**
   - 位置：`TokenPulse/Providers/AntigravityProvider.swift:26`（`authorize` 内 `let project = try Self.project(configuredProject, required: false)`）；输入入口 `TokenPulse/UI/GoogleNativeOAuthLoginView.swift`（`project` TextField 未做前置校验）。
   - 最小输入：合法 clientID `12345-fixture.apps.googleusercontent.com`，项目填 `my project!`（空格/`!` 不在 project() 白名单）。
   - 预期：在 `begin()`/打开 ASWebAuthenticationSession 之前拒绝，提示项目 ID 格式问题。
   - 实际（已执行，CleanT fixture）：token 交换与 userinfo 均成功（2 次网络请求，即真实用户会先走完整个 Google 同意页）后，`Self.project` 抛 `RefreshFailure.unreadableResponse`，登录 UI 显示「无法读取额度响应」。
   - 用户影响：错误与用户实际输入（项目 ID 格式）完全无关，走完授权后失败且难以定位；无凭证误存（凭证确实未保存，安全面无损）。严重度：低-中（UX/校验顺序）。

2. **[已执行] 空 group displayName 产生空 scope 与带前导空格的窗口名**
   - 位置：`TokenPulse/Providers/AntigravityProvider.swift:166`（`scope: group` 未过滤空串）；`TokenPulse/Domain/Models.swift:351`（`displayName = "\($0) \(name)"`）。
   - 最小输入：`{"groups":[{"displayName":"","buckets":[{"bucketId":"b","remainingFraction":0.5}]}]}`。
   - 预期：空 displayName 视同缺失 → `name="b"`、`scope=nil`。
   - 实际（已执行）：`scope=""`，`QuotaWindow.displayName == " b"`（前导空格）。
   - 用户影响：卡片/详情标题出现前导空格；AG 无策略消费 scope（QuotaPolicy 仅作用 codex），纯外观。严重度：低。

## 实际检查与结果（均已执行，工作目录 /tmp/tokenpulse-wave4-pi/05-antigravity/work）

- 编译：`swiftc -swift-version 6` 通过（Swift 6 并发检查无错误），生产文件为逐字节拷贝。
- 解析矩阵 39/39 通过：7-scope 集合核对（cloud-platform/userinfo.email/userinfo.profile/cclog/experimentsandconfigs/aicode/openid）；fraction 反转（0.04→96%）、0/1 边界、1e-17→<100 且非耗尽；Int64 amount 字符串/数值两种形态（含 `9223372036854775807`）、0、负数/溢出/`"1.5"`/`true` 均正确拒绝；oneof 冲突拒绝；fraction 越界/`"NaN"`/`true`/`1e999` 拒绝；disabled 窗口：名称加「（未启用）」、percentage/resetsAt/isExhausted 全 nil 且不发通知（N3 deliverOps=0）；空 bucketId、重复 bucketId、`groups:null`+`buckets:null`、`{}` 拒绝；空 groups → 「未返回模型组额度」；groups 存在时根 buckets 不叠加（E1：`windows=["antigravity.bucket.g"]`）；未知 window→`.other`、缺失→nil；resetTime 坏值/数值型拒绝，分秒/带时区偏移可解析；QuotaSnapshot Codable 往返一致。
- 授权流（A1）：4 请求 = `/token`→`/oauth2/v2/userinfo`→`/v1internal:loadCodeAssist`→`/v1internal:retrieveUserQuotaSummary`；managed 项目优先（`project=managed-project`、quota body `{"project":"managed-project"}`、`Authorization: Bearer fixture-access`）；localAccountID/planName/subject/指纹均写入；随后 quota 复查 windows=1、updatedCredential=nil。
- 项目/资格（A2-A4）：无 managed 时用配置项目（quota body `{"project":"my-project"}`）；完全无项目→`insufficientPermissions`（3 请求，无 quota 调用）；allowedTiers-only/空 tier id/空响应→`subscriptionRequired`；`projectValidationError.code=7`→`insufficientPermissions`；无任何 `onboard` 请求路径。
- 刷新与身份（A5/A6/E5）：过期凭证轮换后 access/refresh 更新、project 与 `sourceCredentialFingerprint` 保持、快照指纹一致（2 请求）；token 响应缺 `scope` 字段时沿用旧 grantedScopes；project 改动/grantedScopes 缩水/localAccountID 不符/指纹篡改/subject 改动 5 种场景均 `invalidCredential` 且 **0 网络请求**；仅 access/refresh 轮换不改变指纹（A10 stable=true）。
- 错误映射（A7）：401→invalidCredential、403→insufficientPermissions、429→rateLimited、500→server。
- 登录门槛（A8/A9/E4）：quota 响应不可解码→登录失败不保存凭证；非法 clientID 前置拒绝；userinfo 空 subject→unreadableResponse。project() 长度>256/非 ASCII/`/` 拒绝、空串→nil。
- 通知集成（N1/N2）：96% 窗口→`quotaAlert`；0% 耗尽→`quotaAlert`；disabled 不告警。
- 静态核对（非执行）：`ProviderIcon.swift:36` → "ProviderAntigravity"；imageset 存在（24x24 黑色模板 SVG、preserves-vector + template intent）；`ProviderIconNotices.txt:55` 记录 Lobe commit/路径/MIT；`DemoMode.swift:55,376` 含 antigravity 演示窗口；`Provider.antigravity` 不在 `hasWalletBalance`/`hasMonetaryWallet` 列表；`ProviderQuotaClient` 对 `.antigravity` 用 `URLSessionProviderTransport.rejectingRedirects()`；`ProviderSignInView.swift:20-28` 以 7 scopes 接入 `GoogleNativeOAuthLoginView`+`authorize`。

说明：work 目录早期一次 fixture 改写引入了自身 bug（Optional 插值破坏 scope 字符串，编译器曾警告），导致一次 A1/E2 误报；已用干净的内联 CleanT fixture 重证 E2（即发现 1），其余结论均来自未受污染的首轮运行与 CleanT 运行。

## 未覆盖

- 未运行 xcodebuild/XCTest/模拟器（按约束禁止）；上述 Swift 6 复现不等同于 XCTest 通过，冻结测试文件的断言与生产行为经独立执行一致，但 `testTwoAccountsFailureCacheRestartAndDeletion`（QuotaMonitor/UserDefaults/Keychain 路径）与 `testWidgetDemo...` 的 `WidgetAccountSnapshot` 未在本次执行（属 03 共享基础范围）。
- 无真实 Google 账号授权、真实 scope 授予（含 Google 是否对自有 iOS client 回显 `openid`）、真实 `retrieveUserQuotaSummary` 响应形状；`resetTime` 按 protobuf-JSON 字符串形式解析（对象形式整体拒绝）符合规范但未实测；`window` 值大小写（如 `WEEKLY`）未实测。
- Watch/Widget 二进制展示、`loadCodeAssist` metadata（ideType 等）与官方 CLI 的逐字段一致性仅凭文档 1.2.15 描述，未联网核对。

## 结论

在 AG 专属范围内（自有 OAuth 7-scope、load 激活项目、quota oneof/disabled/Int64/resetTime/零/缺失/partial、project/client/subject/localUUID 身份与刷新），未发现数值正确性、身份绑定、刷新轮换或安全层面的可复现缺陷；仅 2 项低严重度、已执行复现的 UX/外观问题（发现 1、2）。实现与图标（含 notices）存在。
