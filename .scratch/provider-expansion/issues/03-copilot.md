# 03: GitHub Copilot 设备授权与额度查询

**Status:** done

**Type:** integration

**What to build:** 用户从 iPhone 完成 GitHub 设备授权，同步后可在 Watch 独立查看 Copilot 额度。

**Blocked by:** None (can start immediately)

## 当前验收标准（用户于2026-10-02调整）

- [x] 图标存在：`ProviderCopilot`，映射及资源已核对，见[图标验收记录](../icon-acceptance.md)。本票已关闭。

以下原检查表保留为历史实现/验证记录，不再作为本票关票条件；未勾选项不改写为已实测。

## 原 Acceptance criteria（历史）

- [ ] 设备授权支持等待、取消、过期和重新授权；验证所用客户端身份、scope 与内部额度接口的兼容性。
- [ ] 按账号套餐分别呈现 premium interactions、chat、completions；未发放、无限、超额付费与耗尽状态不混淆。
- [ ] 使用实际账号重置时间；验证凭证持久使用和失效处理，额度接口的非公开性质记录在接入说明中。
- [ ] 完成添加、凭证安全保存、多账号隔离、重新打开后恢复、账号删除与同步；iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别直连提供商查询；Watch 已取得配置和凭证后，不依赖手机或 Mac 在线。
- [ ] 账号卡片、详情、iPhone 小组件和 Watch 展示保持数值、单位、采集时间与过期状态一致；支持演示数据并保持演示与真实账号隔离。
- [ ] 适用的额度告警、重置提醒或低余额提醒沿用现有规则；失败保留旧数据，缺失指标不补零，预计重置不等同于确认恢复。
- [x] 增加有意义的请求契约、解析边界、账号隔离和提醒行为验证；运行相关测试和完整 unsigned TokenPulse target 构建，覆盖 App、Widgets 与 Watch 资源。
- [ ] 新增图标优先官方资产或既有 Lobe Icons 来源，固定来源版本、记录版权许可，并验证模板渲染与矢量资产。
- [ ] 记录实际账号查询、凭证失效和双端独立刷新证据；没有凭证或设备时准确保留未验收项，模拟响应通过不能代替真实验收。
- [ ] 更新提供商支持范围、登录说明、领域用语与验证边界。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/copilot.md)。参考代码与模拟响应只作为契约线索，不能视为真实账号验证。


## Implementation evidence (Sol Copilot worker)

- Added `.copilot`, `CopilotProviderClient` and `CopilotProviderAuthenticator`; wired common login/query controllers, UUID-isolated Keychain/account lifecycle, iPhone/Watch UI, widget selection and isolated demo data.
- Source inspection through agent-reach GitHub / gh used the exact upstream commit `397c8fc4f1bd52180a452d2f3f0c099def97cf69`. `GitHubDeviceLogin.swift` confirms public client `Iv1.b507a08c87ecfe98` and `read:user`. `CopilotUsageService.swift` confirms token authorization scheme and all three editor headers. No existing `gh` credential was read or repurposed.
- Added optional `QuotaWindow.overagePermitted` / `overageCount` and `QuotaSnapshot` / `WidgetAccountSnapshot.providerPlanName`, preserving compatibility with older JSON caches. Finite issued, unissued, unlimited, exhausted and paid-overage states remain distinct. Missing measurements remain unknown; account reset date is used without a fabricated 30-day duration.
- Added 13 `CopilotProviderTests` methods covering the request contract, pending/slow-down/cancel/deny/expire/retry, credential reuse, cross-provider isolation, quota parsing, errors, reminder behavior, widgets/cache coding, and synthetic two-account Keychain restore/reauthorization/deletion with cloud disabled.
- Passed: Swift 6 `emit-module` of all app sources targeting arm64 iOS Simulator 17.0; Swift 6 typecheck of the complete new XCTest file; Swift parser, `plutil -lint` PBX and `git diff --check`.
- Passed: a macOS executable smoke harness using the production provider implementations and synthetic responses, exercising device contract/pending/slow-down/token completion, three quota lanes, overage/unlimited/counts, unissued vs exhausted boundaries, Boolean/non-finite rejection, editor request headers, notification deduplication and snapshot coding. This was not an authenticated production call or a simulator XCTest execution.
- Copilot SVG comes from existing Lobe Icons source commit `2e76c48721e91b9aaa40803a0fa2eb8aca7399c4`, `packages/static-svg/icons/githubcopilot.svg`; MIT copyright/license and provenance recorded. Dimensions are 24×24, paths unchanged, template rendering and vector preservation enabled. The inspected official `github/copilot.vim` tree did not contain a provider SVG mark.
- Updated README, CONTEXT and provider integration notes for support scope, public editor consent identity, narrow scope, private quota endpoint and validation boundary.

## Outstanding acceptance evidence

The checklist above remains open where it requires complete unsigned App/Widgets/Watch build, simulator execution or real-account/device evidence. Central integration worker owns the serialized build and simulator run; this worker did not run xcodebuild or launch a simulator. The 13 XCTest cases have been typechecked but not executed here. Real GitHub consent/token acquisition, current read:user/internal-endpoint compatibility, real plan responses/reset date, persistence/revocation, iCloud credential arrival, physical dual-device independent refresh, widget visual QA and real reminders still require authorized accounts/devices. No real credential was accessed, printed or fabricated as evidence.

## 集成验证（2026-10-02，root）

本轮完整 238 项 XCTest 全部通过，unsigned TokenPulse target 构建成功，覆盖 App、两端 Widgets 和 Watch；iPhone 模拟器演示卡片完成查看。分组提交时记录的“待中央构建/测试”已由本次结果补齐，详见[统一验证记录](../validation-record.md)。真实提供商登录/查询、物理 Watch 独立刷新和跨设备 iCloud 到达尚未验收，因此未标完成。
