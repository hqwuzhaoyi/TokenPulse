# 65: Antigravity 原生独立额度查询

**Status:** done

**Type:** integration（自有客户端、权限受限的原生接入）

**What to build:** 不依赖编辑器/CLI 进程，使用用户自有 Google iOS OAuth client 获取已激活项目的远程模型组 quota。

**Blocked by:** 无实现阻塞。Google 是否向特定自有 client 授予 Antigravity scope/entitlement 未实测，没有通用兼容承诺。

## 当前验收标准（用户于2026-10-03确认）

- [x] 完成接入实现并确认图标存在；真实账号和设备不再是硬关票条件。
- [x] 准确区分已核实远程 wire contract、第三方 client 的权限边界和未实测事实。

## 实施记录 — 2026-10-03

- [x] 固定 Pulse loopback/随机端口/CSRF 路线仍不采用。静态解析官方 CLI 1.2.15 manifest校验后的公开归档，未运行官方二进制。
- [x] CLI内嵌descriptor证实POST `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary`，body `project`；真实groups/buckets schema不再未知。
- [x] 复用Google原生OAuth、用户自备iOS client、PKCE/state/offline刷新；按官方consumer登录scope集合请求7scope，不复制Google-owned clientID/secret，不冒官方IDE，不读取本机keyring或token。
- [x] 只读取`loadCodeAssist`已激活current/paid tier与返回/已配置项目，随后验证quota再保存；allowedTiers不等于已开通，不调用onboardUser或注册/购买接口。
- [x] 凭证绑定provider/localUUID/subject/clientID/project，轮换token不变身份；scope不足、错账号/项目、401/403/429/服务失败保留准确错误与已有缓存。
- [x] fraction仅合法0...1；int64剩余数量精确保存，没有数量类型则不称token/货币，不推算未知分母。oneof冲突/溢出/非法reset失败，禁用或缺失数值不造100%/0；保留真实reset。
- [x] App新增/重登、详情/Watch/Widget/额度提醒/演示、enum/dispatch/auth/PBX完整注册；App+Watch独立HTTPS，无常驻Mac或代查服务。
- [x] ProviderAntigravity SVG存在，来源Lobe固定MIT资产，vector/template与notice记录完成。
- [x] 七项合成XCTest覆盖fraction/int64/unknown/disabled/oneof、schema边界、native授权/项目发现/不onboard、身份刷新、账号隔离/缓存/重启/删除、Widget/demo/提醒；共享GoogleOAuth另有独立回归。
- [x] Swift parse/PBX lint/diff check通过，小型实际Foundation parser边界运行通过，provider/OAuth小module及5项parser/auth XCTest Swift6语义检查通过。
- [ ] 本分支未跑Xcode/模拟器或完整XCTest，交root串行验证；未读取真实Key、未进行真实Google授权、第三方scope授予/账号额度/Watch独立实测。

## Evidence

[研究报告](../research/65-antigravity.md)与[接入说明](../../../docs/antigravity-integration.md)记录官方归档版本/摘要、descriptor offsets、scope和权限边界。旧真实设备验证要求不再作为当前关票条件；合成测试不证明供应商对所有第三方客户端开放。

## Pi05 follow-up — 2026-10-03

非法配置项目现在在共享原生浏览器准备和AG直接authorize入口前校验并显示输入提示；Gemini相同入口同步修正，provider原规则保持独立。空白group scope归一nil、bucket名trim后fallback稳定ID。补四项回归：AG零请求+提示、名称边界、Gemini直接/发现零请求、共享准备顺序/归一值/不同provider规则。实际Foundation回归执行零请求与名称fallback通过；Swift parse、小module和共享准备XCTest语义检查通过。完整XCTest交root串行，不运行Xcode。
