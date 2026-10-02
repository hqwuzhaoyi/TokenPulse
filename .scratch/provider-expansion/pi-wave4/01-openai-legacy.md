# 冻结快照回归报告：OpenAIAPIProvider（Legacy 余额）

范围：`TokenPulse/Providers/OpenAIAPIProvider.swift`、`TokenPulseTests/OpenAIAPIProviderTests.swift` 及相关注册 / 钱包提醒 / 缓存 identity 链路。仅审本快照，未联网，未运行 xcodebuild/simctl，未修改 snapshot。XCTest **未真实执行**；已用 Swift 6 + 纯 Foundation 将生产解析源码逐字复制后在 /tmp 运行真实复现（见下）。

## 发现

**共 1 个具体可复现问题（低严重度）；其余检查项未发现可复现缺陷。**

### 1. 超过 38 位有效数字的余额被静默舍入而非拒绝（已执行复现）

- 位置：`TokenPulse/Providers/WalletExpansionHTTP.swift:65-75`（`WalletNumericDecimal`，被 `OpenAIAPIProvider.swift:12` 的 `Reply.total_available` 使用）
- 最小输入：`{"total_available":99999999999999999999999999999999999999999}`（41 位）
- 预期：按代码注释"strict decimal without a Double intermediate"的严格语义，超出 `Decimal` 38 位尾数容量的数值应拒绝（`unreadableResponse`）或至少不丢失数位。
- 实际（已执行，/tmp/tokenpulse-wave4-pi/01-openai-legacy/work/repro2.swift，逐字复制生产 `WalletNumericDecimal` + `Reply`）：
  - 41 位输入解码为 `99999999999999999999999999999999999999000`（末 3 位被清零），`isNaN=false`，作为钱包余额展示。
  - 19 位 `12.300000000000000001` 精确（测试覆盖的范围正常）；`1e999`/`1e200` 被 JSONDecoder 报"not representable"并落入 `unreadableResponse`（正确拒绝）。
- 用户影响：仅当 legacy 接口返回超过 38 位有效数字的余额时显示值与真实值不符；现实 USD 余额几乎不可能触发，属边界一致性缺口，非实际数据风险。静态推断其余依赖该 decoder 的 provider（Hyper/DeepInfra/TypeSafe）同样受影响，但它们不在本轮范围。

## 实际检查 / 命令结果（区分静态与已执行）

已执行（Swift 6.3.3 纯 Foundation 真实源码复现，work/repro.swift、work/repro2.swift）：
- `12.3`、`0`、`-0.01`、`12.300000000000000001`、38 位整数均精确解码且与 `Decimal(string:)` 相等；`null`/`true`/字符串/缺 key/`1e999`/`1e200` 全部抛错 → 会被映射为 `unreadableResponse`，无假余额。

静态审读（未执行 XCTest，不将测试断言当作已通过）：
- legacy 范围声明：`ProviderIntegration.swift:434-435`（loginConfiguration `.apiKey` + "OpenAI Key（需兼容旧余额接口）"）、`Models.swift:134`（"OpenAI API（Legacy 余额）"）、`AccountSettingsView.swift:309` 与 `ContentView.swift:647` 展示 `connectionNotice`；endpoint 固定为 `/v1/dashboard/billing/credit_grants`，不探测 Costs API。✔
- 错误分类：`OpenAIAPIProvider.swift:32` 403→`insufficientPermissions` 先于通用 403→invalidCredential；401/404/429/503 经 `ProviderHTTP.queryFailure` 正确映射。✔
- 跨 origin：`OpenAIAPIProvider.swift:28-30` 在状态码检查前校验 `ProviderRedirectPolicy.permits`（scheme+host+port），foreign 响应→`server`；Bearer 头不进 URL。✔
- 换 Key 不串缓存：`QuotaMonitor.swift:156-176` 对 apiKey 计算 SHA256(provider, key) identity 并 stamp 到 `snapshot.sourceCredentialFingerprint`；`bindScopedCredential`（386-424）在 identity 变化时清空不匹配快照。✔（`assertWalletExpansionLifecycle` 与测试对应，但未执行）
- 每端展示无假 quota：`Models.swift:56` `balancePresentation == .walletOnly`；`WidgetSnapshotStore.swift:97-104` openAIAPI widget 仅在有钱包币种时输出一条 metric，`ringFraction` 依赖 `usedPercentage`（恒 nil）故无进度环；`DemoMode.swift:372` demo 快照同为纯钱包。✔
- 注册与图标：pbxproj 包含 `OpenAIAPIProvider.swift`（app+watch 两 target）与测试文件；`ProviderCodex.imageset` 存在，`ProviderIconNotices.txt:5` 声明复用来源。✔
- 提醒：`NotificationPlanner.swift:150-175` 仅对 `isMonetary` 钱包按币种阈值（USD 默认 2）触发 `walletAlert`，额度阈值告警只遍历 `window.wallet == nil` 的窗口——legacy 账号只有钱包窗口，不会产生假额度告警。✔

## 未覆盖

- 未执行 XCTest/xcodebuild（按指令禁止），测试文件断言与生产代码一致性仅经静态比对。
- 未做真实网络请求、真实登录、模拟器/Watch 实体与 iCloud 同步实测（无联网、无模拟器）。
- `WalletNumericDecimal` 的 38 位舍入对其它 provider（Hyper/DeepInfra/TypeSafe）的影响未展开验证（超出本轮范围）。
- UI 渲染（AccountSettingsView/ContentView 的实际显示）未运行，仅静态确认 notice 文案与钱包窗口构造。
