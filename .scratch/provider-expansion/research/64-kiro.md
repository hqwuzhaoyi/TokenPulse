# 64 Kiro：远程额度与认证研究

调查日期：2026-10-02。结论：**固定 Pulse ACP 路线在当前 ADR 下不可接入；脱离 CLI 的移动端 quota API 仍未建立契约**。官方支持手机浏览器完成 CLI 授权，与手机原生持有凭证并查询额度是不同能力。

## 来源与版本

- [Pulse Kiro 文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/kiro.md)、[ACP transport](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/KiroACPClient.swift)、[usage parser](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/KiroUsageService.swift)，均为固定 commit `397c8fc4f1bd52180a452d2f3f0c099def97cf69`。上游记录 CLI 2.22.1 / ACP agent server 0.66.4 与同账号 `/usage` 对照成功，属于 Mac CLI 证据。
- [Kiro 官方认证](https://kiro.dev/docs/getting-started/authentication/)与[CLI 命令](https://kiro.dev/docs/reference/cli-commands/)，调查日公开文档：Builder ID、Identity Center、Google、GitHub 的 CLI device flow。
- [Kiro 官方 headless](https://kiro.dev/docs/cli/headless/)和[FAQ](https://kiro.dev/faq/)：当前 API key 用于原生 headless 工作流；额度面板显示 monthly credits，后台更新可延迟。
- 调查了 AWS 官方前身 [amazon-q-developer-cli](https://github.com/aws/amazon-q-developer-cli/tree/15cc8f3cd18c4272925ce1c7053268eedff1ea0a) 源码树，包含 `amzn-codewhisperer-client` 的 `get_usage_limits`。它不是当前 Kiro CLI 的可用性、客户端注册或额度账号映射证明，本报告不把它作为 Kiro 可执行路由。

## 已确认的契约

Pulse 启动短生命周期本地子进程 `kiro-cli acp --agent-engine v3`，通过 stdin/stdout 完成 ACP 初始化，再调用 `_kiro/account/getUsage`。它是本地 JSON-RPC extension，不是 HTTPS 云端 URL，也没有携带 API key 的云端 HTTP 契约。认证和续期都由 Kiro CLI 负责，Pulse 不读取 SQLite、Keychain 或 access token。

返回外层 `success/message/data`；data 有 `planName`、`billingCycleReset` 和 `usageBreakdowns[]`。池字段为 `resourceType/displayName/used/limit/percentage/hasLimit`。只有有界正 limit 才画窗口，优先实际 used，否则 percentage/100×limit；stable ID 基于 provider resource type，而非数组序号。billing reset 是日期，不能据此声称固定 30 天长度。该 schema 只说明 ACP 输出，不能据它推断云端 request body。

## 手机认证、续期和平台限制

官方 device flow 说明 CLI 展示 URL/code，用户可在手机浏览器确认，CLI 自己轮询并持有 session。文档没有给 TokenPulse 可注册的 OAuth client、注册 scopes、device/token HTTP 契约、个人订阅额度远程 endpoint 或 Watch refresh 规则。当前 headless API key 对指定付费套餐可用，不代表 key 被准许读取 subscription dashboard；没有使用真实 key 测试额度权限。

FAQ 中第三方 harness 推理使用有明确原生接口边界。TokenPulse 只读额度的产品许可需独立确认；不能从 headless 推理能力或前身 AWS SDK 得出第三方 quota 许可。

遵守 [设备直连 ADR](../../../docs/adr/0001-device-side-refresh.md)。手机/Watch 不能运行此 Mac CLI ACP，Mac 常驻代查、CLIProxyAPI、推送快照不满足 ADR。

- 已证实：Pulse 本地 ACP 获取 bounded credit pools；官方 CLI 有 device 授权和自身 token 生命周期。
- 不可行：原样移植 Pulse ACP/local CLI 架构到手机/Watch 的直连 provider。
- 未验证：官方认可第三方原生 quota 客户端是否存在，API key 是否能查询订阅池、如何续期/绑定订阅账号。没有证据证明 Kiro 绝无远程 API。

## 可重复的最小验证（本次未执行账号步骤）

1. 通过固定源码核对 `_kiro/account/getUsage` 是 ACP method，而非网络 endpoint；同目录 public-evidence 脚本可重取。
2. 先从供应商或可审核的当前官方客户端取得移动端 client 注册、token 与 quota HTTP 契约。缺任一项停止，不猜 AWS hostname/path，不拿 ACP method 拼 URL。
3. 使用为 TokenPulse 建立的独立测试授权或明确支持的只读 key，iPhone 只读取 credits；记录套餐、各 resource ID、used/limit、账期日期和采样时间，与官方 `/usage` 对照。
4. Watch 接收自己的可用凭证，手机离线、CLI 停止后直接读取；跨过 token 过期验证续期。记录设备/OS、状态码与脱敏额度字段。
5. 验证撤销、无额度套餐、不同登录方式和地区不会错误关联账号或将缓存显示成 live。

无官方移动端 quota 契约、独立授权账号及 Watch 实机，票据保留**未验收**。只有上述纵向实验通过才拆正式实施票；届时要包含登录方式、订阅身份、resource 稳定性、日期语义、凭证失效、UI/组件/提醒及双端独立验收。
