# 65 Antigravity：独立额度查询研究

初次调查：2026-10-02；官方静态协议深化与实施：2026-10-03。当前结论：**固定 Pulse 本机语言服务器路线不满足 ADR；官方 CLI 1.2.15 内嵌远程协议现已核实，原生自有 OAuth client 窄接入已实现；自有 client 的 scope/entitlement 授予无通用承诺且未实测**。不再将真实账号/设备当硬关票门槛。

## 来源与版本

- [Pulse 文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/antigravity.md)及[实现](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/AntigravityUsageService.swift)，固定 commit `397c8fc4f1bd52180a452d2f3f0c099def97cf69`。
- [官方 CLI /usage](https://www.antigravity.google/docs/cli/commands/usage/)，调查日公开读取：命令刷新后端模型配置与额度，并显示交互界面。
- [官方 CLI 安装与认证](https://antigravity.google/docs/cli/install/)和[企业认证](https://antigravity.google/docs/enterprise)：本地 keyring、远程 SSH 手动授权码、Gemini API key 或企业 ADC；这些描述 CLI 能力，没有第三方手机注册协议。
- [Google 原生 OAuth](https://developers.google.com/identity/protocols/oauth2/native-app)：iOS 原生认证能力存在，不能推导 Antigravity quota scopes/client entitlement 已开放。

## 固定 Pulse 的实际契约

Pulse 定位正在运行的 Antigravity/Antigravity IDE `language_server`、每次启动随机监听端口、命令行的 per-launch CSRF token。请求是本机 HTTPS loopback + `x-codeium-csrf-token`，RPC 名 `exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary`，第二个 `GetUserStatus` 仅取 plan 名称。不是 OAuth access token，也不是可迁移的远程 endpoint；不允许把 loopback hostname 换成猜测的云域名。

quota shape 为 `groups[].buckets[]`，bucket 有 `bucketId/window/remainingFraction/resetTime`，window 为 5h/weekly；剩余 fraction 反转成 used，稳定 ID 使用 bucketId，重置用真实时间。群组分 Gemini 与 Claude/GPT，但群组 allowance 不是钱包余额。上游实验性 Google OAuth 路线仅能证明模型 availability 的占位 100%，不能替代真实剩余额度。

## 新官方线索及其限度

初次调查时官方 `/usage` 明确访问 backend，但网页没有给出 wire contract；本轮通过官方公开CLI归档静态解析补齐 quota 路由/schema与consumer登录scope。CLI 支持远程授权码仍在终端完成 token 交换，不能直接假定 iOS 回调可用。API key 模式直接使用 Gemini API、没有 Antigravity 账号 session，不能拿它查询订阅的共享模型组额度。企业 ADC 又是另一 entitlement/项目体系，不能代替个人 Google AI 订阅。

没有安装/运行 Antigravity、读取 keyring、读取本机 token 或建立外部登录。本次认证续期只能记录官方 CLI 自动持有 session，不能给出未公开的生命周期数值。

遵守 [设备直连 ADR](../../../docs/adr/0001-device-side-refresh.md)：手机和 Watch 必须各自直接读取。运行 Mac 语言服务器、转发 RPC、同步 quota 文件或外部推送均不成立。

- 已证实：固定 Pulse 依赖本机语言服务器；官方新 CLI 会查后端。
- 不可行：该语言服务器/CSRF 架构原样用于 iPhone/Watch 独立刷新。
- 已实现但服务权限未验证：用户自有iOS OAuth授权、续期、quota直连与凭证向Watch同步；无供应商对任意第三方client开放Antigravity权限的承诺。

## 可重复的最小验证（本次未执行账号步骤）

1. 重取固定 Pulse 文档/实现，查 quota method、loopback、CSRF 的来源；读取最新官方 install 与 /usage 文档，并记录日期，因为官方产品已发展。
2. 取得供应商认可的远程 quota 请求和独立客户端注册契约，先核验 endpoint 对应个人/企业哪种订阅，不能用模型列表或 placeholder 当额度。
3. 自有 iPhone 授权只调用读额度接口，保存脱敏 bucket ID、group、remaining fraction、reset 与采样时间，与官方 /usage 实际值对照。
4. Watch 使用 TokenPulse 的有效可续期凭证，手机离线且所有桌面 Antigravity 进程停止后读取；跨 token 过期再续期读取，记录具体设备和 OS。
5. 测试撤销、无 entitlement、模型组缺失、账号切换；无成功实际值时维持 unavailable/未验证。

## 官方CLI 1.2.15 静态深化证据

官方 [安装脚本](https://antigravity.google/install.sh)指向 [darwin_arm64 manifest](https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/darwin_arm64.json)。本轮记录版本1.2.15、[归档](https://storage.googleapis.com/antigravity-public/antigravity-cli/1.2.15-5434575321694208/darwin-arm/cli_mac_arm64.tar.gz) SHA512：`1b75da1501ee3e877fa708116f31bd88fabc7f25d8a4b29ef7948b9647d7ad8549b98f6c23418756a38fa210a1a25a526739005ea7b178e50847b67b967cfc7d`。实际对下载归档独立校验匹配，再只读解析Mach-O中的FileDescriptor与Go函数/常量，不执行归档内程序。

`google/internal/cloud/code/v1internal/quota_summary.proto` descriptor位于已解压antigravity文件offset 51935891，长度1234；`prediction_service.proto` offset52905578，长度4807；`onboarding.proto` offset53802614，长度9645。HTTP annotation明确`POST /v1internal:retrieveUserQuotaSummary`、body `*`；request.project为required string。CodeAssistClient.fetchRetrieveUserQuotaSummary静态函数以项目getter取得project并调度该RPC；`cloudcode-pa.googleapis.com`为官方客户端常量，不是从Pulse loopback猜测的host。

response.groups[].buckets[]使用bucketId/displayName/window/disabled/resetTime；remainingFraction为float、remainingAmount为int64且同oneof remaining，resetTime为protobuf.Timestamp。根buckets是deprecated compatibility字段，groups存在时不合并重复根buckets。数量字段没有货币或token单位；无法从int64剩余数量造分母。`5h`/`weekly`窗口字符串对应固定Pulse解析事实，新unknown窗口不推算周期。

consumer OAuth静态调度与GCP模式不同：公共CLI scope slice有cloud-platform、userinfo.email、userinfo.profile、cclog、experimentsandconfigs；consumer路径另外补aicode、openid。本实施保留已核实的7scope集合，因为尚无依据证明后三个内部scope可删除或3scope足够。**静态存在不证明这些scope对用户自有client开放，也不证明每个scope对quota均必要**。未复制官方Google-owned clientID/secret；TokenPulse使用用户自行注册的iOS公共OAuth client、reverse-client callback、PKCE、state、offline refresh与Googleuserinfo subject。

loadCodeAssist descriptor含currentTier/paidTier/allowedTiers/cloudaicompanionProject/projectValidationError。实现只消费已经激活的tier与实际managed或用户配置项目，不调用onboardUser、创建项目或购买。metadata为UNSPECIFIED并用TokenPulse名字，不声明官方CLI/IDE身份。自有client被Google拒绝时准确显示授权/权限失败，不提供伪装或外部proxy绕过。

官方 [CLI repo](https://github.com/google-antigravity/antigravity-cli/tree/ae27bff644d78ed0c759b4d8a6b79506f1bed96d)仅公开文档/examples；[Python SDK](https://github.com/google-antigravity/antigravity-sdk-python/tree/12f9a4c3becf487302dc799b0f59054f01f3ddb9)的[local_connection.py](https://github.com/google-antigravity/antigravity-sdk-python/blob/12f9a4c3becf487302dc799b0f59054f01f3ddb9/google/antigravity/connections/local/local_connection.py)启动local harness subprocess，其[models.py](https://github.com/google-antigravity/antigravity-sdk-python/blob/12f9a4c3becf487302dc799b0f59054f01f3ddb9/google/antigravity/models.py)提供AI Studio/Vertex配置；不能把这个SDK称为个人订阅quota SDK。官方当前[/credits](https://antigravity.google/docs/cli/commands/credits/)说明还存在AI Premium credits；本65仅模型组quota，不因credits面板推算钱包或换汇。

## 当前交付与验收

原生授权、token续期、作用域身份、真实quota schema、App/Watch/Widget/提醒/demo/注册与图标完成。七项合成XCTest已写，小型实际Foundation parser及Swift6 provider/OAuth和5项parser/auth测试语义检查通过，parse/PBX lint通过；完整构建测试交root串行。

用户当前验收为实现+图标存在，故票记done。仍没有真实Google账号、scope授予、quota真值或双端设备实测；这些未验证事实保留，不等于服务一定拒绝、不等于协议不存在，也不能宣称任意第三方client兼容。详见[接入说明](../../../docs/antigravity-integration.md)。
