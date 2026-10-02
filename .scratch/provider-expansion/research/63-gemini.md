# 63 Gemini：独立认证与模型额度研究

调查日期：2026-10-02。结论：**Google 原生 iOS OAuth 可行；TokenPulse 自有客户端能否获准读取 Code Assist 内部额度未验证**。不能以 Google 通用 OAuth 支持推出 Gemini CLI 订阅额度已经可接入。

## 来源与版本

- [Pulse Gemini 文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/gemini.md)及[客户端](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/GeminiUsageService.swift)：固定比较版本，仅借用 CLI access token；不是手机授权实现。
- Google 官方 Gemini CLI，核对 commit `fb972b2f87fe7d5b06d37eac711490162d98de2c`：[OAuth](https://github.com/google-gemini/gemini-cli/blob/fb972b2f87fe7d5b06d37eac711490162d98de2c/packages/core/src/code_assist/oauth2.ts)、[HTTP 服务](https://github.com/google-gemini/gemini-cli/blob/fb972b2f87fe7d5b06d37eac711490162d98de2c/packages/core/src/code_assist/server.ts)、[额度类型](https://github.com/google-gemini/gemini-cli/blob/fb972b2f87fe7d5b06d37eac711490162d98de2c/packages/core/src/code_assist/types.ts)。这些是客户端实际契约，`v1internal` 不等于第三方公共 API 承诺。
- [Google OAuth 原生应用文档](https://developers.google.com/identity/protocols/oauth2/native-app)，于调查日公开读取：自有 iOS client、PKCE、重定向与刷新规则。

## 契约与生命周期

Pulse 从 `~/.gemini/oauth_creds.json` 只读 `access_token`、毫秒 `expiry_date`，过期不发请求、不刷新、不提取 CLI client secret。`settings.json` 中 API Key / Vertex 认证不满足该路线。

额度请求是 Bearer + JSON POST：`https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist`，Pulse body 的 metadata 为 `ideType=GEMINI_CLI`、`pluginType=GEMINI`；随后 `:retrieveUserQuota` 的 body 为 `{project: 返回的项目ID}`。项目、当前/付费 tier、不可用 tier 的原因必须按响应处理，不猜项目名。官方 CLI 的 `RetrieveUserQuotaRequest.project` 是必需字符串，Pulse 容忍空 body 不能当成官方无项目保证。

响应 `buckets[]` 包含 `modelId`、`tokenType`、`remainingFraction`、`resetTime`，新官方类型另有 `remainingAmount`。只对有限的 0…1 fraction 求 `1-remainingFraction`；同模型多 bucket 取最少剩余的 bucket 及其 reset，不能把模型自己归为 Pro/Flash 套餐。reset 为时间字符串；响应没有窗口长度，不能凭 daily 排序键宣布精确 24 小时周期。

官方 CLI 请求 cloud-platform、userinfo.email、userinfo.profile scopes，使用自身已登记客户端。代码公开 client ID/installed-app secret 不授予 TokenPulse 使用该客户端身份的权利。合法手机路线须登记 TokenPulse iOS client，使用外部受支持浏览器或 Google Sign-In/AppAuth，不能把授权放在 WKWebView，也不能移植桌面 loopback 重定向。Google token endpoint 为 `https://oauth2.googleapis.com/token`，原生 iOS client 刷新不需要 client secret；刷新失败/撤销须重新授权。取得通用 token 后能否通过 Code Assist 内部接口的客户端/tier 检查仍未知。

## ADR 与判断

遵守 [设备直连 ADR](../../../docs/adr/0001-device-side-refresh.md)：iPhone、Watch 直接请求，iCloud 仅同步个人资料与凭证。借用一个小时左右的 CLI access token 不可持续；Mac 刷新/代理不是替代方案。自有 OAuth 的项目绑定、Workspace 管理员限制、Code Assist entitlement 和 Watch 可刷新 token 的客户端绑定均缺实际验证。

- 已证实：独立原生 OAuth 有官方协议；quota 云端请求与响应有官方源码。
- 不可采用：只同步 CLI access token；提取 CLI secret 并冒用其客户端；本机 CLI 代查。
- 未验证：TokenPulse 自有客户端访问 `v1internal` 是否被允许，具体账号/项目是否返回真实 quotas，iPhone/Watch 续期能否长期独立工作。

## 可重复的最小验证（本次未执行账号步骤）

1. 重取上述固定 commits，核对 OAuth scopes、`project` 与 buckets 类型；无需用户凭证。公开证据可用同目录 `verify-public-evidence.py` 重取。
2. 在已获得合法客户端许可后，用测试 iOS app 的自有 client 完成一次授权。只记录 client 类型、账号 entitlement 类别、项目是否绑定成功，不保存 token 或邮箱。
3. 只调用两个读取 RPC，记录 HTTP 状态、模型 bucket 标识、fraction、reset 与采集时间；遇到 `UNSUPPORTED_CLIENT` / eligibility 拒绝，记为此客户端不被接受，禁止伪造 metadata 绕过。
4. 为 Watch 提供属于 TokenPulse 的可续期凭证，手机断网且 Mac/CLI 不运行时直接读；跨 access-token 过期后再刷新和读取。记录 iPhone/Watch 型号、OS、时间、脱敏返回字段与官方额度面板对照。
5. 撤销授权，验证两端正确转为需登录且不展示旧数据为 live。只读测试不调用推理、不 onboard 新项目。

没有实际账号授权、Google 项目/客户端配置或 Watch 实机，本票**未完成**。通过后实施票还必须覆盖自有授权与重新登录、账号/项目隔离、token 生命周期、模型稳定 ID、缓存与通知、双端直连和真实额度对照。
