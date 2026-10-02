# 27: IBM Bob 团队 Bobcoins 预算

**Status:** done

**Type:** integration

**What to build:** 输入受支持凭证后查看各实例和团队的 Bobcoins 使用与预算。

**Blocked by:** None (can start immediately)

## 当前验收标准（用户于2026-10-02调整）

- [x] 图标存在：`ProviderIBMBob`，映射及资源已核对，见[图标验收记录](../icon-acceptance.md)。本票已关闭。

以下原检查表保留为历史实现/验证记录，不再作为本票关票条件；未勾选项不改写为已实测。

## 原 Acceptance criteria（历史）

- [ ] 识别 API Key 与登录 token 的认证差异；动态区域地址仅允许已核实的 IBM 服务域名。
- [ ] 每个实例与团队的额度单独标识，不将不同预算池或重置周期相加；无预算与查询失败明确区分。
- [ ] 从添加入口到安全凭证保存、账号管理、同步和删除完整可用；同一提供商多个账号隔离，iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别向服务端查询；Watch 获得配置和凭证后不依赖手机、Mac 或新增代查服务在线。
- [ ] 卡片、详情、iPhone 小组件、Watch 和演示数据覆盖新增计量方式；金额、积分、token、时长和预算单位不混淆。
- [ ] 适用的额度告警、重置或低余额提醒接入既有规则；不适用的设置不开放；失败保留旧数据与采集时间，缺失值不补零。
- [ ] 覆盖请求契约、字段边界、账号与站点隔离、成功与失败及适用提醒行为的测试；运行相关测试和 unsigned TokenPulse target 完整构建。
- [ ] 新增图标优先官方资源或既有 Lobe Icons，固定来源版本、记录版权许可，并验证矢量与模板渲染覆盖 App、Widgets 和 Watch。
- [ ] 保存真实登录、查询及 Watch 独立刷新验收结论；无账号凭证或设备时保留未验收项，不将合成响应测试当作真实接入证明。
- [ ] 更新支持范围、登录方式、字段含义和验证边界；研究来源固定版本，发现契约不可用时记录具体阻塞。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/ibm-bob.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。


## Implementation evidence (2026-10-02)

- Added `.ibmBob` and explicit secure `apikey:<GeneralKey>` / `token:<JWT>` entry, Apikey vs Bearer authentication, token structural/expiry checks and computed actual-secret source identity. No IAM/CLI/browser lookup and no real Key read. Uses existing account Keychain/local/cloud lifecycle and independent iPhone/Watch querying.
- Profile discovery fixed to `api.us-east.bob.ibm.com`; dynamic regions restricted to two verified literal hosts (us-east, eu-de). Both were checked using no-Authorization public HEAD profile requests and returned TLS-verified HTTP401. This verifies existence only. All profile host/ID descriptors are checked before regional requests; unknown even IBM-looking subdomains, URL/port/userinfo/path/query and encoded/header/path injection are refused. Redirects are completely rejected.
- Each instance+team+user is its own monthly Bobcoins window, no sum of different budgets or reset dates. Counts/budgets remain Decimal. No budget => usage-only exact count, absent remaining/total/percentage; explicit null doesn't inherit profile finite budget. Missing or malformed usage is a failure; zero budget doesn't divide or pretend unlimited. Actual 100% usage doesn't assert API blocking/PAYG status.
- Added scopes/detail rows, Watch names/quantity rows, widget metrics, independent demo pools, applicable percentage thresholds and exact-usage + explicit-time expected-reset eligibility; only appropriate controls show, no currency reminder for Bobcoins. Existing failure/identity cache retention and deletion paths reused.
- Shared quantity extension is separate `01f4485`, depending on original `8a752f9` (root already has that prerequisite). All three DecimalQuotaCounts fields optional, old full initializer compatible, each UI row unwraps, shared summary knows usage-only vs unknown rather than zero. No separate Double usedCount introduced.
- `IBMBobProviderTests` semantic typecheck in Swift6 uses a real temporary testable module of production Domain/all Providers/Monitor/Demo/Reminder/WidgetSnapshotStore/formatting and actual XCTest overlay. Added explicit credential/expiry, trusted-region/identifier, individual pool/Decimal/reset, unknown/zero budgets, failures/no subscription, persistence/key change and reminder/widget/demo coverage. SwiftUI parser, PBX lint and diff checks passed. No xcodebuild, simulator or XCTest target runtime by this agent; root integrated test and unsigned complete resource build pending.
- Pinned MIT IBM mark from Lobe Icons `a94750e3f5f8fc33757b839d85030e742284e43a`, `packages/static-svg/icons/ibm.svg`, notices and black explicit-size vector template image set added. Actual catalog compilation pending.
- No real Bob account/login, real profile/team reply, key/token failure, iCloud cross-device arrival or Watch offline independent refresh verified. Keep those acceptance criteria unchecked. Primary official docs, fixed source references, regional limitation and exact validation boundaries: [IBM Bob integration](../../../docs/ibm-bob-provider-integration.md).
