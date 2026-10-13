# JetBrainsProvider / Tests 协议与额度回归报告（冻结快照）

- 冻结时间：2026-10-03T02:59:59.416812；源码 commit：`dece27b74aab5d9c613088fd09dce8e902e402db`
- 快照（只读）：`snapshot/`；复现脚本：`/tmp/tokenpulse-wave4-pi/09-jetbrains-protocol/work/repro/`（纯 Foundation + CryptoKit，Swift 6.3.3 `swiftc` 编译执行）
- 审查对象：`TokenPulse/Providers/JetBrainsProvider.swift`（337 行）、`TokenPulseTests/JetBrainsProviderTests.swift` 及其依赖（`ProviderHTTP.swift`、`WalletProvider.swift` 的 `ProviderDecimal`、`WalletExpansionHTTP.swift` 的 `WalletDecimalValue`、`DeviceOAuthCredentialVault.swift`、`AccountQuotaClient.swift`、`JetBrainsImportView.swift`、`ProviderSignInView.swift`）
- 声明：未联网、未读取任何真实凭证/环境变量/用户 home；未运行 XCTest（无 Xcode 构建），所有"已执行"结论来自下述 harness 对**逐字复制**的生产源码片段（sed 按行号提取）的真实运行；快照未做任何修改。

## 发现（可复现问题）

### 1.（低危，静态推断）AI JWT 续期路径丢弃服务端 `expiresAt`，固定假设 24 小时有效期

- 位置：`TokenPulse/Providers/JetBrainsProvider.swift:263-272`（关键行 269），对比同文件 255-257 行的 provide 路径。
- 最小输入：stage 为 `ready` 且 AI token 临近过期时，`POST https://api.jetbrains.ai/user/v5/auth/jwt/refresh/v3` 返回 `{"token":"t","expiresAt":300000}`（真实有效期 5 分钟，毫秒）。
- 预期：与 256 行 provide 路径一致，按服务端毫秒值换算 `expiresAt`（带 `<=32_503_680_000_000`、`>0`、`>now` 校验），下次在真实过期前 60 秒续期。
- 实际：269 行 `ready.expiresAt = now().addingTimeInterval(86_400)`，`AIMint.expiresAt`（77 行，已解码）被无条件忽略；60 秒预续期窗口（263 行）基于假设值计算。
- 用户影响：若刷新出的 AI JWT 实际有效期短于 24 小时，其后每次额度查询都会带过期 token 命中 401，只能走 `catch RefreshFailure.invalidCredential → provision()` 兜底（每次额外触发 register + provide-access/license/v2，JBA 过期时再加一轮 `/oauth2/token`），数据仍能取回但每次查询多 2+ 个请求、更慢，且对 grazie 端点产生不必要的重复注册流量；反向（真实有效期 >24h）仅多一次无害提前刷新。
- 复现方式：静态代码比对（`grep -n "expiresAt" ...`，见下）；未执行——该分支在 `JetBrainsSessionCoordinator.perform` 内，需完整 vault/actor 测试装置，本组 harness 仅覆盖无副作用的纯函数与 client 层。
- 建议：269 行改为复用 255-256 行同款服务端毫秒换算与上界校验，缺失/非法时再回退 24 小时。

其余审查项（协议路由、请求头、敏感值位置、export 门禁、额度 parser、日期单位、错误映射、opaque token 边界）**未发现可复现问题**。

## 实际检查与命令结果（已执行）

harness：`swiftc -swift-version 6 -o repro stubs.swift frag_providerdecimal.swift frag_walletdecimal.swift frag_http.swift frag_client.swift frag_parser.swift main.swift && ./repro` → **ALL CHECKS PASSED（58 项断言 + 12 项抛错断言）**。片段均由 sed 从快照原文件按行号逐字提取（`work/repro/frag_*.swift`），stub 仅替代 `QuotaWindow/QuotaSnapshot/Envelope` 等数据结构与 `ProviderTransport`。

1. **额度 parser（JetBrainsQuotaParser.snapshot，292-337 行）**
   - 官方 fixture（tariff+topUp）：2 个窗口，不重复合计总量；`current`=已用 2、`available`=剩余 8、`maximum`=总量 10（÷100000 精确缩放）；`usedPercentage=20`；`resetsAt` 取 refill `next` 毫秒（86400000→86400s），不使用 quota 的 `until`；`cycleID="1000000"`（refill `last`）；topup 无重置语义（`nonResettingAllowance`、`resetsAt/cycleID=nil`）；单位 "AI credits"、无 wallet。
   - 缺失不假 0：`{"tariffQuota":{"current":"123456.789"}}` → used=1.23456789，percentage/total/remaining 均为 nil；仅 `maximum` 的桶照常显示；空 topUp 桶被跳过；无任何桶 → 0 窗口 + 状态文案，不造窗口。
   - 拒绝项（均抛 `unreadableResponse`）：`true`、`-1`、`{"amount":false}`、`{"amount":null}`、`{"other":1}`、字符串科学计数 `"2E5"`、refill `next<=last`；裸 JSON 数字 `2E5` 合法接受（=200000，属正常 JSON）。
   - 边界：38 位有效数字精确换算，40 位被往返校验拒绝；`used=1,total=3` → 33.333333333333336（Double 显示层正常舍入）；refill `next` 为过去时间会被接受（`resetsAt` 落在过去，见"边界观察"）。
2. **ID token 身份（JetBrainsCredential.identity，55-70 行）**：`sub` 优先于 `jba_login`（前缀 `sub:`/`jba_login:`）；`exp` 按秒；拒绝：非 JWT、空 sub、`exp` 缺失/0/负/超 32503680000、非 ASCII sub、`a..b` 空段。身份来源仅 `metadata["mintedIDToken"]`，该值只在 `jba()` 由固定 HTTPS `/oauth2/token` 响应写入（静态确认）。
3. **export 门禁（JetBrainsTokenTransfer.decode，13-27 行）**：仅 version=1、`environment=prod`、`ai_access.type=license`、无 org_id/workspace_id/server_url、`eap_tos_accepted=true`、非空 license/refresh 通过；version 2/staging/带 server_url/组织/错误布尔/空 refresh/`central-@@@`/超长（>65536B 文本或 >49152B 载荷）全部拒绝；`grantMarker` 只绑定真实 refresh token（换 license 包装不变、含 hash 不含明文）。
4. **路由/请求头/敏感值（JetBrainsProviderClient.send + refreshJBA/provide/refreshAI，79-127 行）**：
   - `POST https://oauth.account.jetbrains.com/oauth2/token`：URL 无 query、无 Authorization；form 体仅 `client_id=central-cli&grant_type=refresh_token&refresh_token=…`，`& = + %` 正确百分号编码，无 `secret/redirect_uri/code_verifier`（公共客户端）。
   - register：`POST https://auth.grazie.ai/auth/jetbrains-jwt/register`，体 `{}`，`Authorization: Bearer <jba>`；provide-access：`.../license/v2`，体 `{"licenseId":"L"}`；opaque license id 从不进 URL。
   - `POST https://api.jetbrains.ai/user/v5/auth/jwt/refresh/v3` 与 quota 两路由：`Grazie-Authenticate-JWT` 头、空体、无 Authorization；带认证的请求统一 `Grazie-Agent: TokenPulse/1.0`；全部 POST、禁 cookie、禁缓存。
   - 错误映射（走真实 `ProviderHTTP.send`）：401/403→`invalidCredential`、429→`rateLimited`、500→`server`、200 之外的 204→`unreadableResponse`；跨源/重定向响应（finalURL 不同）→拒绝；>1MB 响应体→拒绝。
5. **接线（静态确认）**：`AccountQuotaClient.quota`（AccountQuotaClient.swift:21-25）走 `JetBrainsSessionCoordinator.shared.quota` + `rejectingRedirects` 传输；`ProviderSignInView.swift:15` 登录入口直达 `JetBrainsImportView`（SecureField 粘贴、导入后即清空输入框），`begin/continueLogin` 对 jetBrainsAI 均抛"请主动导入官方 Central login export"，与"用户主动官方 central export"边界一致。

## 边界观察（非缺陷，已执行或静态确认）

- `identity()` 不检查 JWT 头（`alg=none` 也接受）且不验签——该 token 仅用于解析 sub/exp，且只来自固定 HTTPS 发行方响应，不承载签名安全决策；`mintedIDToken` 在 verify 后仍留在设备本地 vault metadata 中（仅本机 Keychain，未出网）。
- refill `next` 早于当前时间会被接受，`resetsAt` 落在过去（UI 会立即判定需更新）；正常服务端不会返回。
- `{"amount":null}` 会使整份 quota 响应解析失败（而非视为缺失）；服务端省略字段时为缺键，可正常容忍。
- `docs/implementation-status.md:7` 仍写"JetBrains AI 仍在最后协议实施调查，尚未计入入口数"，与快照内已实现的 Provider/测试/入口接线不一致（文档滞后，非产品缺陷）。

## 未覆盖

- 未运行 XCTest/`xcodebuild`（按任务约束禁止）；`JetBrainsSessionCoordinator.perform` 的 actor/vault/CAS 生命周期（checkpoint、tombstone、candidate 激活、并发合并）未在 harness 中执行，属授权生命周期组范围；JetBrainsProviderTests.swift 中 24 个用例仅做了与生产代码的逐项对照阅读，其断言与本 harness 已执行结果无冲突。
- 无真实 JetBrains 账号/网络验证，未验证服务端真实响应形状（quota v5、refill、register/provide-access、id_token claims）与官方 central export 实际字段；快照 `docs/` 内无 JetBrains 专项官方证据文档可引用。
- 发现 1 为静态推断，未在 `perform` 装置中实际执行复现。
