# 03 网页登录与设备授权实施证据

状态：源和翻译已交付，待负责人整合运行、可视检查后完成。未提交、推送或发布。没有独立启动 xcodebuild 或模拟器。

## 修改范围

- `UI/ProviderSignInView.swift`：设备码标题、授权页动作、等待/恢复/重试和错误。验证码与 authorizationURL 直接显示原值；完整动态短语使用 L10n.format。
- `UI/GoogleNativeOAuthLoginView.swift`：Google 自有 client/project 指导、动作与应用错误。client ID、项目输入、callback、scopes 和 PKCE 行为保持原样。
- `UI/StepFunSessionLoginView.swift` 与 `Providers/StepFunProvider.swift` 站点 displayName：国内/国际站指导、验证状态、缺失会话恢复；站点 rawValue、host、设备标识与 Cookie 规则不变。
- `UI/CursorSessionLoginView.swift`：Cursor/Grok Bot 范围说明、等待与恢复错误。nonce、轮询、expiry、账号隔离不变。
- `UI/JetBrainsImportView.swift`：独立设备导出导入说明、验证、未保存候选与重试恢复。CLI 导出值和授权导入行为不变。
- `Application/NousDeviceLoginModel.swift`：同一 Nous 用户/组织校验与重试提示； sourceCredentialIdentity 比较不变。
- `Providers/ClaudeProvider.swift` 的 iOS 登录展示：组织选择、临时浏览器提示与应用错误； organization.name/id 和会话构造保持原样。
- `Providers/WebSessionContainer.swift` 的应用展示：工作区/组织选择、验证/重登、应用错误和应用生成的候选名称。未知候选、品牌与来自服务的名称直接显示。
- `Providers/{AugmentCode,Zed,Kiro,Devin,Replicate,NotionAI}Provider.swift`：仅登录选择项的应用生成标题及 Notion 缺失套餐文案。组织 username/name/tier/id 不翻译，不参与本地化键；Replicate account.id 与凭证 metadata 保持原样。
- `Providers/{ProviderIntegration,GoogleNativeOAuth,GeminiProvider,AntigravityProvider}.swift`：仅明确由应用写出的 unsupportedLogin 错误字符串接入 L10n。ProviderIntegration 的 credentialLabel 保持原文，由票02在显示边界处理。
- 翻译片段 `fragments/03.json`：100 个 zh-Hans→en 条目；静态 SwiftUI 字面量沿用原生 catalog，模型返回文案与动态条件显式查询。共享 catalog 由负责人合并。

## 真实行为测试

扩展现有测试文件与 transport/cookie fixtures，没有新增测试 target 文件。

- `ProviderTests.testPersistentNetworkFailureStopsAndRetryPreservesAuthorizationCode`：zh-Hans/en 网络耗尽恢复指导，同一 TEST-CODE、同一设备会话继续，成功只完成一次，不重复 device begin 请求。
- `CopilotProviderTests.testLocalizedDeviceCodeExpiryAndDenialRecoverWithoutChangingRequestIdentity`：zh-Hans/en 明确取消无错误无凭证；expired_token/access_denied 显示不同恢复文案、清除旧 session，重新开始成功。TEST-CODE、授权 URL、请求 body、access Token 原样。
- `StepFunProviderTests.testLocalizedWebSignInRecoversFromMissingCookiesAndKeepsSelectedSiteIdentity`：zh-Hans/en 缺失 Cookie 的指导与不查询/不保存；重试成功后 international site、localAccountID、fixture-token、fixture-device 原样。
- `GoogleNativeOAuthTests.testUnexpectedTransportCancellationHasFeedbackButExplicitTaskCancellationIsSilent`：zh-Hans/en 意外传输取消的可恢复反馈，显式任务取消保持 nil，未知 Provider-specific 文案保持原样。
- Google/Gemini/Antigravity 项目输入既有断言改为检查完整本地化指导；无效项目仍在任何 HTTPS 请求前拒绝。
- 仍沿用现有 DeviceLoginModel foreground/background/session expiry 与成功单次完成、StepFun Cookie 读取/查询取消和切站、Cursor 关闭/取消/expiry、Nous 账号范围与设备独立授权行为场景。

## 已执行检查

- `swiftc -frontend -parse`：全部修改的授权视图/模型/Provider 与测试通过，含 #if DEBUG fixture。
- JSON 解析、授权源中中文应用字符串与片段比对：100 条；没有缺失，含 Client ID 占位符、完整 format 参数。
- 源 diff 检查：未修改请求 URL、scope、credential metadata、授权码、nonce、callback、轮询决定、数据库字段或 enum rawValue。未编辑 Models.swift/共享 L10n/xcstrings/工程。
- 全工作树 `git diff --check` 发现票05测试文件正在编辑中的空白问题；03 归属文件单独检查通过。
- 上述 checks 不代替 XCTest 和可视验收；暂不声称运行成功。

## 无秘密真实可视路径

负责人可在 Debug-only launch-argument fixture sheet 展示真实产品视图：

- Google：`ProviderSignInView(provider: .gemini, accountID: fixtureID) { _ in }`，检查自有 OAuth Client 与 Cloud project 指导、禁用空 Client ID 的授权动作、中文/英文及大辅助字号。不要填真实凭证或外跳授权。
- JetBrains：同上 provider `.jetBrainsAI`，检查导出说明、SecureField、导入禁用条件和两语言长文案。不要填真实 export。
- Device：`ProviderSignInView(provider: .copilot, accountID: fixtureID, loginModel: .authorizationFixture()) { _ in }`。直接展示 TEST-CODE、Copilot 客户端解释、等待。`DeviceLoginModel.authorizationFixture(failingInitially: true)` 先耗尽3次网络失败，显示恢复与“继续等待”；点击后保持 TEST-CODE/URL 并回到 waiting。
- 负责人在 fixture sheet 用 OpenURLAction `.handled` 截断授权 Link，记录动作可点击且码未改变，避免请求真实网页。
- DeviceLoginModel fixture transport 是 #if DEBUG 的 actor，begin 和 polling 纯内存 fixture，永远 pending；所有 HTTPS 返回由 stub 构造，不能发真实 HTTP。view 的新可注入 initializer 默认仍创建原 DeviceLoginModel。
- 需截图/点击/大字号与 accessibility 证据，等待负责人 `.scratch` XCTestUI harness 结果；第三方网页本体不翻译。

## 待整合验收

1. 负责人合并100条资源并构建全部目标。
2. 串行运行 ProviderTests/CopilotProviderTests/GoogleNativeOAuthTests/GeminiProviderTests/AntigravityProviderTests/StepFunProviderTests/CursorProviderTests/NousPortalTests，记录日志。
3. zh-Hans/en Google、JetBrains、设备码 waiting/recovering 实际截图与操作，大字号无截断，VoiceOver码与动作可读。
4. 成功后由负责人补日志与截图路径并将03设complete；现在保持in-progress。

复查补充：Replicate `Account.title` 同时用于 quota snapshot.scope，已保留其原始 canonical 返回；仅 loginProfile 构造 WebLoginCredentialChoice 时本地化界面标题，避免把当前语言写入缓存和影响查询输出。现有 Replicate scope 断言不需改动。

## 整合测试修正

负责人全量781项XCTest真实执行中，03新增Copilot恢复测试的HTTP body字节比较因JSON字典键顺序不稳定失败。已改为解码NSDictionary后严格比较全部keys/value，并断言全部请求HTTP method、完整URL及headers；新增session.deviceCode/provider与credential client_id/scope原值检查。产品请求实现不变。修正后swiftc语法解析、归属diff检查通过，待负责人重跑。签名环境导致的Keychain既有测试失败由负责人使用正确entitlements签名重跑，不删或跳过。
