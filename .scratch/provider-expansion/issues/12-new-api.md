# 12: New API 自定义地址与余额查询

**Status:** done

**Type:** integration

**What to build:** 用户添加自定义网关地址和 Key，在双端查询 New API 钱包余额；同一提供商可配置多个服务器。

**Blocked by:** None (can start immediately)

## 当前验收标准（用户于2026-10-02调整）

- [x] 图标存在：`ProviderNewAPI`，映射及资源已核对，见[图标验收记录](../icon-acceptance.md)。本票已关闭。

以下原检查表保留为历史实现/验证记录，不再作为本票关票条件；未勾选项不改写为已实测。

## 原 Acceptance criteria（历史）

- [ ] 地址按服务账号持久化和同步，Watch 获得配置后可独立请求；地址或 Key 改变后旧缓存和提醒状态不能冒充新账号的数据。
- [ ] 规范处理常见带 /v1 的地址；拒绝含用户信息、查询或片段的地址；公网使用 HTTPS，私网 HTTP 遵循项目平台限制并实测；拒绝把凭证随跨域重定向发送。
- [ ] 核验 subscription、usage 与公共 status 的响应单位和分币换算，公共接口不携带 Key。
- [ ] 识别无限 Key 与非货币显示模式；不把历史充值总量当套餐上限，不虚构余额百分比；真实币种余额接入低余额提醒。
- [ ] 地址配置和绑定行为可供后续具体网关复用，同时验证固定地址提供商的配置与同步兼容。
- [ ] 完成添加、凭证安全保存、多账号隔离、重新打开后恢复、账号删除与同步；iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别直连提供商查询；Watch 已取得配置和凭证后，不依赖手机或 Mac 在线。
- [ ] 账号卡片、详情、iPhone 小组件和 Watch 展示保持数值、单位、采集时间与过期状态一致；支持演示数据并保持演示与真实账号隔离。
- [ ] 适用的额度告警、重置提醒或低余额提醒沿用现有规则；失败保留旧数据，缺失指标不补零，预计重置不等同于确认恢复。
- [x] 增加有意义的请求契约、解析边界、账号隔离和提醒行为验证；运行相关测试和完整 unsigned TokenPulse target 构建，覆盖 App、Widgets 与 Watch 资源。
- [ ] 新增图标优先官方资产或既有 Lobe Icons 来源，固定来源版本、记录版权许可，并验证模板渲染与矢量资产。
- [ ] 记录实际账号查询、凭证失效和双端独立刷新证据；没有凭证或设备时准确保留未验收项，模拟响应通过不能代替真实验收。
- [ ] 更新提供商支持范围、登录说明、领域用语与验证边界。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/newapi.md)。参考代码与模拟响应只作为契约线索，不能视为真实账号验证。


## Implementation evidence (2026-10-02, Sol gateway branch)

- Added `.newAPI`, direct-device provider routing, account-specific HTTPS server entry for add/update, and a public-status request without Authorization. The normalized address is encrypted with the Key in `ProviderCredentialEnvelope.metadata["serverAddress"]`; existing local/synchronizable Keychain storage remains the device query source. A non-secret copy and SHA256 source identity accompany account configuration and synchronization.
- Added `GatewayServerAddress` normalization (trailing slash and `/v1` removal, prefix preservation), user-info/query/fragment/path-traversal/encoded-separator/invalid-port refusal, and an ephemeral cookie-free gateway URLSession. Its redirect delegate refuses scheme, host or port changes before forwarding the request.
- Added Decimal `hard_limit_usd - total_usage / 100` conversion and the three-field unlimited sentinel. USD/CNY produce a wallet with unknown granted/topped-up fields; TOKENS are displayed as counts; CUSTOM/unknown units produce no monetary value. Lifetime totals never produce a percentage, cap or reset date.
- Added a common scoped-credential interface reusable by web-session providers: envelope `sourceCredentialIdentity`, configuration/state `credentialIdentity`, optional snapshot `sourceCredentialFingerprint`, in-flight generation guards, Keychain/config arrival-order checks, synchronized snapshot identity checks, and identity-scoped reminder history/merge filtering. Fixed-address credentials keep their original format and behavior.
- Added New API demo account, template-rendered vector asset, pinned Lobe Icons source/asset/copyright/MIT notice, login/support documentation and domain vocabulary.
- Added `NewAPIProviderTests`: cents and Decimal boundaries, unavailable breakdown, unknown/custom/token modes, unlimited recognition, malformed metrics, server validation, request headers/routes, redirect-delegate refusal, fingerprint scope, fixed-provider compatibility, local persistence/delete, stale synchronized cache, configuration-before-Keychain, held old request after key replacement, legacy decoding, low-balance rearming and stale-ledger rejection.

### Checks actually performed

- `swiftc -frontend -parse` on all modified Swift source and the new XCTest file: passed (syntax only; not target typechecking or XCTest execution).
- `plutil -lint TokenPulse.xcodeproj/project.pbxproj`: passed.
- `git diff --check`: passed.
- Build/test execution is intentionally delegated to root's single integration slot. No gateway agent xcodebuild or simulator was started. Pending: execute `NewAPIProviderTests` and relevant existing provider/monitor/reminder/demo/widget tests, and unsigned `TokenPulse` target build covering App/Widgets/Watch resources. The wallet optional-field shared prerequisite is cherry-picked from `4071bdf8f124719f5590fefe38acf7c91c86dc07`.

### Explicitly incomplete / unverified

- **Private-network HTTP implementation has been added in the follow-up below.** Its simulator URLSession test and physical-device permission/ATS behavior still require execution and verification; authored tests do not satisfy runtime acceptance.
- No real New API credential was read or used. Real account success, invalid/expired Key, iPhone and Watch independent refresh with the other device offline, iCloud Keychain/config arrival and credential deletion propagation, and real widget/notification display remain unverified.
- Only static checks have passed on this branch; request-contract and parsing tests are authored but not yet executed. The remaining dependency gate for tickets 13/14/15/37 is not satisfied merely by this implementation.

### Pinned sources examined with agent-reach GitHub backend

- Pulse contract study: [397c8fc4 Docs/providers/newapi.md](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/newapi.md) and corresponding service source.
- Primary accounting implementation: [QuantumNous/new-api 1a4166d8 controller/billing.go](https://github.com/QuantumNous/new-api/blob/1a4166d8e8ba9802d2ca56fe8ecf0ed5404e80d5/controller/billing.go). Confirms `remain + used`, usage multiplied by 100, display conversion and sentinel, while account-vs-key scope depends on a server setting not returned by these replies.
- Icon: [Lobe Icons a94750e3 packages/static-svg/icons/newapi.svg](https://github.com/lobehub/lobe-icons/blob/a94750e3f5f8fc33757b839d85030e742284e43a/packages/static-svg/icons/newapi.svg), Copyright (c) 2023 LobeHub, MIT. Explicit 24×24 dimensions, black fill, preserve-vector and template intent. Official repository chiefly provides raster brand art; the existing vector source is used.


## Private HTTP follow-up (2026-10-02)

- HTTP root validation now allows only strict dotted-decimal loopback `127.0.0.0/8`, RFC1918 `10/8`, `172.16/12`, `192.168/16`, IPv4 link-local `169.254/16`, exact `localhost`, explicit well-formed `.local` DNS names, and IPv6 loopback/ULA/link-local (`::1`, `fc00::/7`, `fe80::/10`). IPv6 uses `inet_pton` validation and `inet_ntop` canonicalization. Trailing DNS dots/case and HTTP port 80 normalize; HTTPS defaults remain port 443. Public HTTP, DNS names merely resolving to private space, short/decimal/octal/hex/encoded IPv4, mapped/compatible IPv6 and IPv6 scope IDs are refused. Scoped IPv6 literal URLs are intentionally unsupported; use an explicit `.local` address for a link-local deployment requiring an interface scope.
- Gateway transport checks the initial URL itself and rejects public HTTP before URLSession. Same-origin checks compare protocol-specific defaults, retaining the scheme/host/port redirect boundary. Ephemeral sessions wait for connectivity while the first local-network permission decision is pending, with a bounded 30-second resource timeout.
- Both querying app plists declare `NSAllowsLocalNetworking` and bounded `NSExceptionDomains` entries with `NSExceptionAllowsInsecureHTTPLoads` for the exact private CIDRs above. No `NSAllowsArbitraryLoads`, WebView exception, public-domain exception or broad `0.0.0.0/0` range is added. iPhone adds `NSLocalNetworkUsageDescription`; widgets consume snapshots and receive no network exceptions. Watch carries the ATS declarations; Apple TN3179 says watchOS has no local-network privacy permission gate, which does not establish real Watch reachability.
- Added tests for accepted/rejected range boundaries and obfuscated literals, IPv6/default-port canonicalization, production-transport public HTTP refusal, the built app's bounded ATS dictionary, and a temporary `NWListener` bound only to `127.0.0.1`. The last test sends `/api/status` through production `GatewayProviderTransport`, verifies HTTP 200/public fixture data and absence of Authorization/Cookie headers, and cancels the listener after the test. It uses no stored Key or real account and makes no LAN/provider request.
- Follow-up static checks actually passed: Swift syntax parse for provider/tests; isolated address/transport and loopback fixture semantic typecheck in Swift 6 mode against the local macOS Foundation/Darwin/Network SDK; App/Watch plist lint; `git diff --check`. No xcodebuild, simulator or XCTest execution was run by this agent. Root must execute the added loopback test within its integration slot and retain physical-device permission/Watch/real-account acceptance as pending.
- Shared add/update UI was left untouched per root instructions; root must replace the first implementation's “HTTPS only / HTTP unsupported” text with the supported bounded private HTTP behavior when integrating this commit.

### Apple official references examined through agent-reach's webpage backend

- [NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking): local names and IPv4/IPv6; iOS 17 IP default restriction and local-network declaration of intent.
- [NSExceptionDomains](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsexceptiondomains): iOS 17 supports IP and CIDR dictionary keys, with per-domain insecure HTTP settings.
- [TN3179 Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy): iPhone usage description, permission handling and `waitsForConnectivity`; watchOS has no local-network privacy feature. These docs justify the bounded declarations but do not substitute for runtime verification.

## 集成验证（2026-10-02，root）

本轮完整 238 项 XCTest 全部通过，unsigned TokenPulse target 构建成功，覆盖 App、两端 Widgets 和 Watch；iPhone 模拟器演示卡片完成查看。分组提交时记录的“待中央构建/测试”已由本次结果补齐，详见[统一验证记录](../validation-record.md)。真实提供商登录/查询、物理 Watch 独立刷新和跨设备 iCloud 到达尚未验收，因此未标完成。
