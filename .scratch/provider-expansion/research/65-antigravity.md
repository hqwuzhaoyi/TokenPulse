# 65 Antigravity：独立额度查询研究

调查日期：2026-10-02。结论：**固定 Pulse 本机语言服务器路线不满足 ADR；当前官方 CLI 已确认后端额度刷新，但没有建立 TokenPulse 可用的远程认证与 quota 契约**。不能继续沿用“额度仅存在本机”的全局否定判断。

## 来源与版本

- [Pulse 文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/antigravity.md)及[实现](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/AntigravityUsageService.swift)，固定 commit `397c8fc4f1bd52180a452d2f3f0c099def97cf69`。
- [官方 CLI /usage](https://www.antigravity.google/docs/cli/commands/usage/)，调查日公开读取：命令刷新后端模型配置与额度，并显示交互界面。
- [官方 CLI 安装与认证](https://antigravity.google/docs/cli/install/)和[企业认证](https://antigravity.google/docs/enterprise)：本地 keyring、远程 SSH 手动授权码、Gemini API key 或企业 ADC；这些描述 CLI 能力，没有第三方手机注册协议。
- [Google 原生 OAuth](https://developers.google.com/identity/protocols/oauth2/native-app)：iOS 原生认证能力存在，不能推导 Antigravity quota scopes/client entitlement 已开放。

## 固定 Pulse 的实际契约

Pulse 定位正在运行的 Antigravity/Antigravity IDE `language_server`、每次启动随机监听端口、命令行的 per-launch CSRF token。请求是本机 HTTPS loopback + `x-codeium-csrf-token`，RPC 名 `exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary`，第二个 `GetUserStatus` 仅取 plan 名称。不是 OAuth access token，也不是可迁移的远程 endpoint；不允许把 loopback hostname 换成猜测的云域名。

quota shape 为 `groups[].buckets[]`，bucket 有 `bucketId/window/remainingFraction/resetTime`，window 为 5h/weekly；剩余 fraction 反转成 used，稳定 ID 使用 bucketId，重置用真实时间。群组分 Gemini 与 Claude/GPT，但群组 allowance 不是钱包余额。上游实验性 Google OAuth 路线仅能证明模型 availability 的占位 100%，不能替代真实剩余额度。

## 新官方线索及其限度

当前官方 `/usage` 明确访问 backend，这足以推翻“服务器绝无额度数据”的推断，却未给出 quota URL、请求 schema、OAuth client 注册、scope、刷新协议或 response 与 Pulse bucket 的一一关系。CLI 支持远程授权码仍在终端完成 token 交换，不能直接假定 iOS 回调可用。API key 模式直接使用 Gemini API、没有 Antigravity 账号 session，不能拿它查询订阅的共享模型组额度。企业 ADC 又是另一 entitlement/项目体系，不能代替个人 Google AI 订阅。

没有安装/运行 Antigravity、读取 keyring、读取本机 token 或建立外部登录。本次认证续期只能记录官方 CLI 自动持有 session，不能给出未公开的生命周期数值。

遵守 [设备直连 ADR](../../../docs/adr/0001-device-side-refresh.md)：手机和 Watch 必须各自直接读取。运行 Mac 语言服务器、转发 RPC、同步 quota 文件或外部推送均不成立。

- 已证实：固定 Pulse 依赖本机语言服务器；官方新 CLI 会查后端。
- 不可行：该语言服务器/CSRF 架构原样用于 iPhone/Watch 独立刷新。
- 未验证：供应商支持的 TokenPulse 独立授权与真实 quota API、手机平台许可、token 续期与 Watch token 转移。

## 可重复的最小验证（本次未执行账号步骤）

1. 重取固定 Pulse 文档/实现，查 quota method、loopback、CSRF 的来源；读取最新官方 install 与 /usage 文档，并记录日期，因为官方产品已发展。
2. 取得供应商认可的远程 quota 请求和独立客户端注册契约，先核验 endpoint 对应个人/企业哪种订阅，不能用模型列表或 placeholder 当额度。
3. 自有 iPhone 授权只调用读额度接口，保存脱敏 bucket ID、group、remaining fraction、reset 与采样时间，与官方 /usage 实际值对照。
4. Watch 使用 TokenPulse 的有效可续期凭证，手机离线且所有桌面 Antigravity 进程停止后读取；跨 token 过期再续期读取，记录具体设备和 OS。
5. 测试撤销、无 entitlement、模型组缺失、账号切换；无成功实际值时维持 unavailable/未验证。

缺远程 quota/client 契约和真实双端设备实验，**票未完成**。正式实施票必须等待该实验，且覆盖个人/企业身份、模型组语义、刷新与撤销、稳定 bucket、双端直连、UI/组件/提醒，不将实验性 availability 路线发布为 provider。
