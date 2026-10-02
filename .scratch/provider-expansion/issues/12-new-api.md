# 12: New API 自定义地址与余额查询

**Status:** implemented-awaiting-integrated-validation (private HTTP deferred; real-account/device acceptance pending)

**Type:** integration

**What to build:** 用户添加自定义网关地址和 Key，在双端查询 New API 钱包余额；同一提供商可配置多个服务器。

**Blocked by:** None (can start immediately)

## Acceptance criteria

- [ ] 地址按服务账号持久化和同步，Watch 获得配置后可独立请求；地址或 Key 改变后旧缓存和提醒状态不能冒充新账号的数据。
- [ ] 规范处理常见带 /v1 的地址；拒绝含用户信息、查询或片段的地址；公网使用 HTTPS，私网 HTTP 遵循项目平台限制并实测；拒绝把凭证随跨域重定向发送。
- [ ] 核验 subscription、usage 与公共 status 的响应单位和分币换算，公共接口不携带 Key。
- [ ] 识别无限 Key 与非货币显示模式；不把历史充值总量当套餐上限，不虚构余额百分比；真实币种余额接入低余额提醒。
- [ ] 地址配置和绑定行为可供后续具体网关复用，同时验证固定地址提供商的配置与同步兼容。
- [ ] 完成添加、凭证安全保存、多账号隔离、重新打开后恢复、账号删除与同步；iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别直连提供商查询；Watch 已取得配置和凭证后，不依赖手机或 Mac 在线。
- [ ] 账号卡片、详情、iPhone 小组件和 Watch 展示保持数值、单位、采集时间与过期状态一致；支持演示数据并保持演示与真实账号隔离。
- [ ] 适用的额度告警、重置提醒或低余额提醒沿用现有规则；失败保留旧数据，缺失指标不补零，预计重置不等同于确认恢复。
- [ ] 增加有意义的请求契约、解析边界、账号隔离和提醒行为验证；运行相关测试和完整 unsigned TokenPulse target 构建，覆盖 App、Widgets 与 Watch 资源。
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

- **Private-network HTTP is not implemented.** All HTTP addresses are refused with UI explanation. No ATS exception or arbitrary-load relaxation was introduced. The private HTTP portion of acceptance criterion 2 remains open until device/simulator ATS and local-network behavior is validated and a bounded policy is implemented.
- No real New API credential was read or used. Real account success, invalid/expired Key, iPhone and Watch independent refresh with the other device offline, iCloud Keychain/config arrival and credential deletion propagation, and real widget/notification display remain unverified.
- Only static checks have passed on this branch; request-contract and parsing tests are authored but not yet executed. The remaining dependency gate for tickets 13/14/15/37 is not satisfied merely by this implementation.

### Pinned sources examined with agent-reach GitHub backend

- Pulse contract study: [397c8fc4 Docs/providers/newapi.md](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/newapi.md) and corresponding service source.
- Primary accounting implementation: [QuantumNous/new-api 1a4166d8 controller/billing.go](https://github.com/QuantumNous/new-api/blob/1a4166d8e8ba9802d2ca56fe8ecf0ed5404e80d5/controller/billing.go). Confirms `remain + used`, usage multiplied by 100, display conversion and sentinel, while account-vs-key scope depends on a server setting not returned by these replies.
- Icon: [Lobe Icons a94750e3 packages/static-svg/icons/newapi.svg](https://github.com/lobehub/lobe-icons/blob/a94750e3f5f8fc33757b839d85030e742284e43a/packages/static-svg/icons/newapi.svg), Copyright (c) 2023 LobeHub, MIT. Explicit 24×24 dimensions, black fill, preserve-vector and template intent. Official repository chiefly provides raster brand art; the existing vector source is used.
