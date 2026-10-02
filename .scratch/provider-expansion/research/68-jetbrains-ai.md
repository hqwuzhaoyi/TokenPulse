# 68 JetBrains AI：账户级远程额度研究

调查日期：2026-10-02；静态发布包补核：2026-10-03。结论：**个人远程 quota 的 HTTPS 请求、JWT 头、JSON schema、AI credits 转换与 refill 时间已从固定官方 Central CLI 发布包建立；原生初始导入签发和完整认证 fallback 链仍未闭合，状态 protocol-gap**。本地 XML 不满足独立刷新；个人/license、企业 shared pool 与公开许可证 API 不能混为一种额度。真实账号/实体设备观察不作为当前验收门槛。

## 来源与版本

- [Pulse 文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/jetbrains-ai.md)与[实现](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/JetBrainsAIUsageService.swift)，固定 commit `397c8fc4f1bd52180a452d2f3f0c099def97cf69`。
- [官方 AI 订阅与 usage](https://www.jetbrains.com/help/ai-assistant/licensing-and-subscriptions.html)、[Central Console credits](https://www.jetbrains.com/help/jetbrains-console/manage-ai-credits.html)，调查日读取：个人账户/IDE 可看用量，企业 shared pool 有个人子上限。
- [官方 Central CLI 内部流程](https://www.jetbrains.com/help/central-cli/cli-in-depth.html)，调查日读取：OAuth PKCE 登录、workspace usage-limit token、license/platform 路线及续期。
- [官方 Account API 文档](https://www.jetbrains.com/help/jetbrains-console/jetbrains-account-api.html)页面 Last modified `10 September 2026`；[公开 OpenAPI](https://account.jetbrains.com/openapi/specs/public.swagger.jba-api.json)本次读取 SHA-256 `e822f15658bf56535037ed10256a7141c8d4c7e540e5c38049171b76611bdd78`，13 个 paths，无 quota/credit schema。公开 API 的存在不证明 AI 额度 API 可用。

## 固定 Pulse 契约与否定范围

Pulse 没有网络请求或账号授权，寻找已知 IDE 目录的 `options/AIAssistantQuotaManager2.xml`，选最后修改文件。`quotaInfo` JSON 有 `type/current/maximum/until/tariffQuota`；`nextRefill` 有 `next/tariff.amount/tariff.duration`。used 取 current/maximum，reset 取 nextRefill.next 而不是 subscription until；只有明确 duration 才声称窗口长度。IDE 停止后快照不更新，重新读文件也不等于新的 live 观测。

手机/Watch 无法访问 IDE 的真实数据文件；复制/同步快照只传递历史观测，不满足 [设备直连 ADR](../../../docs/adr/0001-device-side-refresh.md)。**此路线不可接入**，不能把文件同步实现验收勾为独立刷新。

## 远程线索、认证与续期

官方个人 JetBrains Account 能展示 usage，Central Console 能展示企业池，因此不能宣称额度只在本机存在。企业个人 limit 是共享 pool 的子上限，即使个人尚未耗尽、pool 已空也无法使用，不能把 limit-current 当另一份独立可花 credits。

Central CLI 官方文档说明 OAuth 2.0 PKCE 对 JetBrains Account 登录，随后可选 workspace（mint AI calls、usage limits、governance tokens）、经典 license、Central Server。文档描述定期提前刷新，不提供第三方移动端 OAuth client/redirect 注册、quota HTTP URL、scope 与 response schema。其本机代理 bound 到 loopback 的 `/health` 不表示云端额度。没有读取 tokens.enc、系统 Keychain、IDE 文件，没有建立授权。

公开 Account API 仅面向启用 API、具备角色权限的已验证域组织，使用 `X-Customer-Code` 和 `X-Api-Key`。Token 无固定到期、可手动再生/撤销、丧失角色会失效。当前 13 paths 属于 account/license/team/product/token，公开 schema 没有 AI 余额；不能把任意 Account API key 填到猜想 quota URL。Hub/YouTrack REST OAuth 与 JetBrains AI 平台也不是同一凭证。官方 Junie 仓库公开树没有提供本次所需的完整 AI quota 原生客户端契约，未逆向闭源二进制。

- 已证实：本地 XML 快照不刷新；官方账户有远程 usage、Central CLI 有 usage token。
- 不可行：Pulse XML 读取/同步架构成为直连 provider。
- 未验证：个人 AI quota 的合法第三方 endpoint、自有移动端 client、个人与企业身份绑定、双端续期/撤销。不是“网络 API 绝不存在”的断言。

## 可重复的最小验证（本次未执行账号步骤）

1. 重取固定 XML parser 与公开 OpenAPI（同目录脚本）；审计 path/schema 是否新增 quota。只 GET 公共 schema，不运行文档里的删账号例子。
2. 从官方取得具体个人或企业 usage-limit API 与受支持客户端注册。记录适用套餐、scope、独立续期及账户/pool 标识，禁止把 license API 或 shared pool 自动当个人余额。
3. iPhone 完成自己的授权并只查询；记录 reported current/maximum/remaining、pool 与个人 limit、reset、采样时间，与官方 IDE/Account 额度面板对照。
4. Watch 使用有效可续期凭证，在手机离线、IDE/Central CLI 停止时直连查询，跨 token expiry 续期重读，记录具体设备、OS、时间与脱敏结果。
5. 验证角色撤销、套餐改变、top-up、shared pool 耗尽、账号切换和 stale cache 的表示。

缺少完整原生初始导入签发与认证 fallback 组合，当前 provider 尚未实现。按调整后的验收，只要求原生实现与图标；真实账号/Watch观察不再是实施前硬门槛。仍须保持 entitlement、shared/sub-limit、单位/周期、身份与生命周期正确。


## 2026-10-03 再核查：个人远程 quota 存在，但协议未交付

[官方 CLI commands](https://www.jetbrains.com/help/central-cli/cli-commands.html) 直接说明 `central limit` 显示 seat-based usage limit 或 license-based quota，以 AI credits 计量；`central quota` 是别名。因此不应再把“只有IDE本地quota”或“远程只面向企业”当结论。

[官方CLI setup](https://www.jetbrains.com/help/central-cli/cli-setup.html) 要求 active AI subscription，可以来自自己的license或组织；多来源时用户选择workspace或个人license。[in-depth](https://www.jetbrains.com/help/central-cli/cli-in-depth.html)，页面Last modified18 September2026，确认PKCE OAuth、license经典AIPlatform流程及workspace usage/governance令牌。公开的Grazie-Authenticate-JWT `/user/v5/llm/...`、Bearer `/llm/...`属于模型调用，没有说明 `central limit` 的具体HTTP路线、token-mint audience/scopes、quota结构或自有第三方iOS client注册。不能把这些字符串拼成假quota路径。

公开Account API再取仍13 paths且上述SHA不变；没有quota/credit/usage响应定义。这仅限定该公开schema，不证明供应商内部没有quota服务。官方[Junie README](https://github.com/JetBrains/junie/blob/10b769b013cf61da012b92ced2cc6946c1beeb41/README.md)和同版公开树暴露OAuth/JunieAPIKey入口，但公开源码为文档及集成包装，未提供这条个人quota网络客户端；代码搜索对 usage-limit-token/quota 的结果未给出完整发行+读取组合。搜索为空也不等同于不存在。

本次只GET公开文档/schema与官方GitHub源；没有运行Central/Junie、读取tokens.enc/系统Keychain、模拟其它OAuth客户端或请求真实账户。这次文档研究当时的缺口包括 method+URL+schema 与认证发行；下方静态发布包已补齐前者并建立 direct-refresh 线索，剩余缺口以本次静态结论为准。供应商只需提供协议即可解除代码阻碍；没有测试账号不是另一个阻塞理由。旧纵向真实观察计划保留为后续验证建议，不再是本票关票门槛。

可重复公开审计：读取上述命令/深入文档和公共OpenAPI，确认新增个人quota path/schema；若官方公布SDK或协议，再核对用户授权身份与对应quota请求，禁止以推理license token或XML current/maximum替代云端quota。原生实现前不新增假成功parser/授权入口或名义provider。


## 2026-10-03 官方发布包静态契约

从官方 [CLI setup](https://www.jetbrains.com/help/central-cli/cli-setup.html) 给出的 [install.sh](https://central-cli.labs.jb.gg/install.sh) 读取下载路径，**未执行 installer 或 central**。installer 自报发布 commit `893e3e10`、时间 `2026-09-28T08:28:10Z`，SHA-256 `db9af00c6a4e97eb06245ce2fd92fecfc50e592999901580e2ff64a89568d4f3`。stable/version.txt 实际为 `1.11.0`，不是固定证据本身；随后下载版本路径固定的 [central_1.11.0_linux_x86_64.tar.gz](https://jetbrains-central-cli.s3.eu-west-1.amazonaws.com/central/1.11.0/central_1.11.0_linux_x86_64.tar.gz)，archive SHA-256 `34c7e468870fdc57d60261034760f72b85c4a9e3f2dbfb9dec006b413f62ae4c`。archive 仅 README.md 与 central。binary SHA-256 `07d76becc367762e31f59ecbf744a967ce5ef1cbf395b4fc05835e6fb244a042`，ELF amd64、Go1.25.0，build info 的模块为 github.com/JetBrains/central-cli `v1.11.0+dirty`，vcs revision `893e3e103dac07cd29ab1b6b57c877adcaaf7351`、vcs.modified=true。因此源码 revision 不能替代 artifact hash；本次公开 GitHub repo API 返回404，不假定能复取同一源树。

只使用静态 ELF Go metadata、type tags 与已知系统 objdump，没有动态加载或执行下载程序。[只读复核工具与步骤](68-static-tools/README.md)、[固定提取摘要](68-static-tools/evidence.json)可重现。两个本次编写的标准库 inspector 按 binary SHA 固定输入；实际重复提取与首次结果完全相同。

### 已建立的额度请求与数据

| 来源 | 请求 | 身份头 | response |
| --- | --- | --- | --- |
| classic personal/license | POST https://api.jetbrains.ai/user/v5/quota/get，空 body | Grazie-Authenticate-JWT: AIPlatform JWT | current: Quota |
| classic refill 时间 | POST /user/v5/quota/metadata/refill，空 body，同 host | 同上 | current: {last, next} |
| cloud seat/workspace | GET https://api.jetbrains.ai/quota/api/quota/get | Authorization: Bearer usage credential | current: Quota |
| cloud refill 时间 | GET https://api.jetbrains.ai/quota/api/quota/refill | 同上 | current: {last, next} |

GetQuota 位于 `internal/auth/jbai/client.go:166`，静态地址 `0x8e2620...0x8e2760`；QuotaRefill 为183行；GetCloudQuota为204行。classic 通过 platformPost（286行）构造空体 POST，并设置 Accept application/json、Grazie-Authenticate-JWT 和 Grazie-Agent。cloud 构造 GET 加 Bearer。常量 staging host 也存在，但不是生产账号 fallback，不应将用户凭证遍历其它环境。

Go Quota schema（`internal/auth/jbai/quota.go`）为：license string；current/maximum QuotaAmount（custom UnmarshalJSON）；until int64；tariffQuota 和 topUpQuota 各自为 {current, maximum, available} QuotaAmount。GetQuota/cloud 外层是 {current: Quota}；refill 外层是 {current:{last:int64,next:int64}}。QuotaAmount 自定义 decoder 支持 {amount: Decimal}、数字字符串和 JSON number。Credits 方法调用 Decimal.Div，除数由 jbai.init 构造为100000；不能转成美元钱包。CLI writeQuotaJSON 仍有 usedDollars/maxDollars 历史字段名，这不改变官方命令所称 AI credits 语义。

FormatQuotaPeriod 静态实现将 last/next 除1000、余数乘1000000后构造 time，即毫秒 epoch；直到时间 until 不应替代 refill.next。tariff/top-up 各有独立 available，不能把企业 limit 和 shared pool 合成另一份可花钱包。当前公开 Account API 那13 paths没有quota，不再用它的缺失否定上述发布包路线。

### 已建立的 direct-refresh 与未闭合的初始输入

classic `Refresh`（`client.go:146`，`0x8e2440...0x8e2620`）调用同一个空体 platformPost，path `/user/v5/auth/jwt/refresh/v3`，使用旧 AIPlatform JWT 的 Grazie-Authenticate-JWT；response 有 token string，CLI本地为结果设置 now+24h。这已证明原生 token 重取的具体请求形态，不是只能提供一次性24h读数。没有证据表明这里消耗一个独立一次性 refresh secret；也没有服务器级证据保证旧 JWT 刷新一定不撤销另一设备 JWT，因此双端互不撤销是后续观察项，不能混写为已验证。

CLI `canUseJBAIFastRefresh` 的本地条件包含已有 AI token、无 org user token、AI JWT 已过期、JBA access JWT仍有效；jbaBackend.RefreshWithInfo 也包含 JBA OAuth refresh fallback。这是**客户端分支条件**，不能据此推断服务端 direct-refresh 必须接收 JBA token或必然失败（该 direct 请求没有 JBA Bearer 头）。它仅表明官方完整生命周期还有需移植的 fallback。

官方 `login export` 的 TokenTransfer v1 **不含 ai_token/AIPlatform JWT**。静态字段为 version、refresh_token、environment、server_url可选、ai_access {type, org_id, workspace_id, license_id}、EAPToSAccepted、analytics选择。编码为 `central-` + Base64 JSON，license输入要求 license_id 与已接受EAP terms；不能写成“把 login export 输出当 AI JWT 粘贴即可”。这次没有运行 export，也没有读取 tokens.enc/Keychain/IDE。

已找到 `ProvideAccess` 的 POST `/auth/jetbrains-jwt/provide-access/license/v2`、licenseId JSON 与 Bearer JBA access；`Register`、JBA RefreshTokens、importJCPTransfer 函数及 loopback OAuth callback `http://127.0.0.1:19515/callback`、central-cli audience线索也存在。**尚未把 TokenTransfer 导入→受支持 JBA OAuth client/token mint→Register/ProvideAccess→quota 及失败 fallback，完整固定为供本 App 直接使用的原生初始授权/配置协议。**当前不能用内置 CLI client 身份、猜想 client 参数或未审清的续期分支替代这段组合，也不能要求用户解密 IDE state来填名义provider。

稳定身份本身可以用合法初始登录/导入的 lineage 绑定，在原生续期时保持，不强行要求 quota.license 等于 token transfer.license_id，也不把未知个人JWT claims当新增硬门槛。代码缺口是完整合法初始发行和fallback契约；缺测试账号、Watch和稳定claims文档本身均不是当前关票理由。若以后补齐该链，可在不改变设备直连 ADR 的前提下实现个人原生 provider，并保留许可/seat来源、tariff/top-up与时间语义。

**本轮 status=protocol-gap。**没有新增一次性名义provider或只加图标；没有真实授权/查询、未知二进制执行、IDE/CLI状态或用户凭证读取。原生实现+图标仍是用户当前验收；真实账号/实体设备仅是后续观察。本次已将剩余障碍从“找不到quota endpoint/schema”缩小到“原生初始导入发行及完整认证fallback链未闭合”。
