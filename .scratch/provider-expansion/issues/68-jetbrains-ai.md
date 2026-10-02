# 68: JetBrains AI 远程额度可行性

**Status:** protocol-gap — native initial issuance/fallback chain incomplete; provider not implemented

**Type:** feasibility

**What to build:** 不依赖 IDE 本地快照或 CLI 常驻代理的原生账号级额度接入。

**Blocked by:** 原生可用的初始授权/TokenTransfer 导入签发及完整认证 fallback 组合未闭合。quota endpoint、JSON schema、金额转换和 direct-refresh 请求已从固定官方发布包建立；不是缺真实账号、硬件或稳定 claims 文档。

## 当前验收标准

- [ ] 完成原生接入实现，并确认 provider 图标存在。真实账号/实体设备观察不作关票条件。
- [x] 研究独立 HTTPS 路线并固定证据，区分已确认的额度协议与剩余认证组合；不以 IDE XML、license API 或本机代理代替接入。
- [x] 不执行下载的 installer/未知二进制，不读取 IDE/CLI state、Keychain 或真实用户凭证；研究工具只解析固定官方 artifact。

## 固定证据 — 2026-10-03

[研究报告](../research/68-jetbrains-ai.md) 与 [只读复核步骤/工具](../research/68-static-tools/README.md)记录本次检查。官方 setup 指向 installer，stable为1.11.0；下载固定版本 central_1.11.0_linux_x86_64.tar.gz，SHA-256 `34c7e468870fdc57d60261034760f72b85c4a9e3f2dbfb9dec006b413f62ae4c`，binary SHA-256 `07d76becc367762e31f59ecbf744a967ce5ef1cbf395b4fc05835e6fb244a042`。Go build自报revision `893e3e103dac07cd29ab1b6b57c877adcaaf7351` 与 modified=true，故artifact hash为固定证据；没有执行其代码。

已确认 classic personal/license POST api.jetbrains.ai/user/v5/quota/get、POST /user/v5/quota/metadata/refill：空body、Grazie-Authenticate-JWT。cloud seat使用Bearer GET /quota/api/quota/get和/refill。Go reflection与静态调用建立 current wrapper、current/maximum、tariffQuota/topUpQuota各自{current,maximum,available}；QuotaAmount为Decimal，Credits除100000，refill last/next为毫秒 epoch。不能合并企业池与个人子限额，不把AI credits变成美元钱包或将until当reset。

classic POST /user/v5/auth/jwt/refresh/v3使用旧AIJWT、空body，返回token，CLI本地设置24h。官方CLI本地fast-refresh检查还有JBA access有效与fallback；这不证明服务端direct-refresh必须JBA或必失败，也不证明双设备token不互相撤销。后者保留后续观察，不以缺设备阻塞。

## 剩余解锁环节

官方 login export/import TokenTransfer v1仅导出 JBA refresh_token、environment和ai_access身份等元数据，不含AIPlatform JWT；不能向用户写“直接将export粘成JWT”。已发现Register、ProvideAccess(licenseId JSON+JBA Bearer)、JBA refresh与importJCPTransfer调用，但尚未完整固定可供本App使用的初始授权/导入签发、受支持client参数和失败fallback链。不能借内置CLI身份、猜参数，或只做24h token名义provider来勾选接入。

登录 lineage 可用于稳定session身份，合法续期应保留它；不强求quota.license等于transfer.license_id或以未公开claims作为另一阻塞理由。一旦初始发行与fallback组合补齐即可原生实现，再补真实账号/实体设备观察。本次provider/图标接入项保持未勾选；没有把研究完整写成provider done。
