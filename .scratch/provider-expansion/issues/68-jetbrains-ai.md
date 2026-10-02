# 68: JetBrains AI 远程额度可行性

**Status:** protocol-gap — research complete; native provider not implemented

**Type:** feasibility

**What to build:** 验证是否存在不依赖 IDE 本地额度文件的账户级查询。

**Blocked by:** 个人/license AI quota 的 HTTPS endpoint、响应 schema、支持自有原生客户端的 OAuth 注册/usage-token mint 与刷新契约未公开；不是缺少真实账号或硬件。

## 当前验收标准（用户于2026-10-02调整）

- [ ] 完成原生接入实现，并确认 provider 图标存在。真实账号/设备验证不是关票条件。
- [x] 调查独立 HTTPS 路线，明确实际协议缺口；不把 license API、IDE XML 同步或本机 CLI 代理当额度接入。

原真实账号纵向测试要求仅为历史观察计划，不作为本票当前硬门槛。本次没有访问真实凭证、IDE文件或执行账户登录。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/jetbrains-ai.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。

## Research result — 2026-10-02

固定 Pulse XML 架构不可用；官方 Central CLI 有远程 usage token 线索，公开 Account API 未提供 AI quota。

研究报告：[认证、查询、生命周期、平台限制与最小验证](../research/68-jetbrains-ai.md)。只进行公开文档/固定源码研究，未读取用户凭证、未建立外部登录、未完成真实账号或 Watch 验收。

状态 `awaiting-validation` 表示研究交付已产出，整票未完成。第3项真实纵向验收和第6项通过后实施票仍未满足；已勾选的否定/缺口项仅代表报告清楚区分既有架构限制与实际未验证项。


## Further verification — 2026-10-03

官方 Central CLI 的 `central limit` 明确个人 license-based quota 与 seat-based usage limit，单位 AI credits；这修正旧调查“只有 enterprise usage token 线索”的表述。个人远程 quota 确实存在，但没有形成可供本应用实现的 URL/token/client/scope/schema 组合。`/user/v5/llm/...` 仅是推理路由，不能冒充 quota。

公开 Account OpenAPI 重取 SHA仍 e822f15658bf56535037ed10256a7141c8d4c7e540e5c38049171b76611bdd78，13 paths无usage/credit/quota schema。官方Junie10b769b013cf61da012b92ced2cc6946c1beeb41公开树/README有OAuth与JunieAPIKey，但没有个人quota HTTP客户端源码；JetBrains官方code search也未找到完整 quota/mint 协议。未执行/安装闭源CLI、不提取任何token/Keychain。

具体解锁项：官方给出个人quota读取URL+method、所需credential发行/刷新流程与自有iOS客户端注册规则、额度/current/maximum/reset响应schema和个人license/企业seat/pool的身份区分。无需要求本次真实账号验收才能实施；一旦上述组合完整即可代码接入，再补观察。

完整来源和边界在../research/68-jetbrains-ai.md。研究完整不等于provider已实现，当前图标/接入项不勾选。
