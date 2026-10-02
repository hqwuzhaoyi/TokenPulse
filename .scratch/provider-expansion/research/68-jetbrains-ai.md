# 68 JetBrains AI：账户级远程额度研究

调查日期：2026-10-02。结论：**Pulse 本地 XML 快照路线不满足独立刷新；最新官方 Central CLI 已有远程 usage-limit token 线索，但个人 AI quota endpoint 与移动端 client 契约未建立**。不能把个人订阅、企业共享 credit pool、公开许可证 API 混为一种账户额度。

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

缺少完整个人 quota/client 协议组合，当前 provider 尚未实现。按调整后的验收，只要求原生实现与图标；真实账号/Watch观察不再是实施前硬门槛。仍须保持 entitlement、shared/sub-limit、单位/周期、身份与生命周期正确。


## 2026-10-03 再核查：个人远程 quota 存在，但协议未交付

[官方 CLI commands](https://www.jetbrains.com/help/central-cli/cli-commands.html) 直接说明 `central limit` 显示 seat-based usage limit 或 license-based quota，以 AI credits 计量；`central quota` 是别名。因此不应再把“只有IDE本地quota”或“远程只面向企业”当结论。

[官方CLI setup](https://www.jetbrains.com/help/central-cli/cli-setup.html) 要求 active AI subscription，可以来自自己的license或组织；多来源时用户选择workspace或个人license。[in-depth](https://www.jetbrains.com/help/central-cli/cli-in-depth.html)，页面Last modified18 September2026，确认PKCE OAuth、license经典AIPlatform流程及workspace usage/governance令牌。公开的Grazie-Authenticate-JWT `/user/v5/llm/...`、Bearer `/llm/...`属于模型调用，没有说明 `central limit` 的具体HTTP路线、token-mint audience/scopes、quota结构或自有第三方iOS client注册。不能把这些字符串拼成假quota路径。

公开Account API再取仍13 paths且上述SHA不变；没有quota/credit/usage响应定义。这仅限定该公开schema，不证明供应商内部没有quota服务。官方[Junie README](https://github.com/JetBrains/junie/blob/10b769b013cf61da012b92ced2cc6946c1beeb41/README.md)和同版公开树暴露OAuth/JunieAPIKey入口，但公开源码为文档及集成包装，未提供这条个人quota网络客户端；代码搜索对 usage-limit-token/quota 的结果未给出完整发行+读取组合。搜索为空也不等同于不存在。

本次只GET公开文档/schema与官方GitHub源；没有运行Central/Junie、读取tokens.enc/系统Keychain、模拟其它OAuth客户端或请求真实账户。缺口具体为个人/license quota HTTPS method+URL+schema、合法client/redirect/scope、usage credential发行与续期、许可/seat/pool账户身份。供应商只需提供协议即可解除代码阻碍；没有测试账号不是另一个阻塞理由。旧纵向真实观察计划保留为后续验证建议，不再是本票关票门槛。

可重复公开审计：读取上述命令/深入文档和公共OpenAPI，确认新增个人quota path/schema；若官方公布SDK或协议，再核对用户授权身份与对应quota请求，禁止以推理license token或XML current/maximum替代云端quota。原生实现前不新增假成功parser/授权入口或名义provider。
