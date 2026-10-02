# 06: Factory 套餐额度接入

**Status:** implemented-awaiting-real-validation

**Type:** integration

**What to build:** 用户输入 Factory Key，在双端查看账号采用的计费模式及对应套餐额度。

**Blocked by:** None (can start immediately)

## Acceptance criteria

- [ ] 核验新额度接口与旧计费接口的选择条件，分别覆盖新模式的 Standard/Core 和旧模式的 Standard/Premium。
- [ ] 不同额度池和周期分别展示；额外用量余额与套餐限额分开，未经核实的币种不生成货币余额。
- [ ] 测试限额缺失、无限、过期窗口以及缓存比例与明确计数矛盾的情形；仅在有依据时启用对应提醒。
- [ ] 完成添加、凭证安全保存、多账号隔离、重新打开后恢复、账号删除与同步；iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别直连提供商查询；Watch 已取得配置和凭证后，不依赖手机或 Mac 在线。
- [ ] 账号卡片、详情、iPhone 小组件和 Watch 展示保持数值、单位、采集时间与过期状态一致；支持演示数据并保持演示与真实账号隔离。
- [ ] 适用的额度告警、重置提醒或低余额提醒沿用现有规则；失败保留旧数据，缺失指标不补零，预计重置不等同于确认恢复。
- [ ] 增加有意义的请求契约、解析边界、账号隔离和提醒行为验证；运行相关测试和完整 unsigned TokenPulse target 构建，覆盖 App、Widgets 与 Watch 资源。
- [ ] 新增图标优先官方资产或既有 Lobe Icons 来源，固定来源版本、记录版权许可，并验证模板渲染与矢量资产。
- [ ] 记录实际账号查询、凭证失效和双端独立刷新证据；没有凭证或设备时准确保留未验收项，模拟响应通过不能代替真实验收。
- [ ] 更新提供商支持范围、登录说明、领域用语与验证边界。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/factory.md)。参考代码与模拟响应只作为契约线索，不能视为真实账号验证。


## Implementation evidence

- Factory public Key flow, controller routing, direct dual-device query, UUID-isolated shared lifecycle, both billing schemes, scoped UI, widget mapping and two isolated demo accounts implemented.
- New Standard/Core and old Standard/Premium have distinct IDs; no guessed extraUsage USD wallet. Unknown currency cents stay separate, without low-balance alerts.
- Eight Factory XCTest cases cover request contract/new selection/fallback, malformed Bool/metrics/time overflow, cache-lag correction, unknown limits/unlimited/expired windows, reminder/widget semantics, and local multi-account restoration/reauthorization/delete/failure retention. Swift 6 App module and test typecheck passed; no real credentials used.
- Official Factory Droid SVG pinned to 6a5d674f5e106d63ff25346c3d1e607db525e2f0 under Apache 2.0; vector/template/dimensions validated, full notice recorded.
- Details and remaining production validation in docs/factory-provider-integration.md. No central README/CONTEXT/manifest changes.

Acceptance remains open for central unsigned App/Widgets/Watch build and XCTest execution, plus all real-account, physical device, iCloud, lifetime and widget visual evidence. Source fixtures are second-hand and do not establish live compatibility or currency.

额外验证：生产 Factory 解析代码的 macOS 合成响应 smoke 通过新旧池身份、零缓存比例修正、Core 省略、真实 Bool、有限数/时间溢出拒绝、过期窗口和未知币种余额检查。未执行模拟器 XCTest。


## Key scope / reminder lifecycle correction

本组 Factory、DevPass、v0、Warp 的 credential identity 直接从 provider + 实际 API Key 重算 SHA-256，不信 metadata 声称的指纹；错误 kind 或空 Key 没有有效身份。统一 monitor/配置/ledger 用它隔离更换凭证和乱序同步，换 Key 后清掉旧 Key 的数量，即使新 Key 查询失败也不展示原 Key 的额度。其他提供商的身份策略保持不变，由 root 合并统一 getter。

复用共享 `QuotaWindow.resetSemantics`，DevPass 的 Key 累计上限和每个 Warp one-off grant 设为 `.nonResettingAllowance`；真实使用回落只内部重新允许阈值提醒，不推断、确认或预排重置。API余额/不明币种没有混入这一策略。演示同步采用该语义。

追加四个回归方法验证实际 Key/metadata/空值与kind、四提供商换 Key失败清旧数据及恢复、all-time Key额度恢复不通知重置、grant恢复不通知重置。最终 Factory10/DevPass8/v0 7/Warp8 共33个provider XCTest方法完成Swift6 typecheck，完整App模块与共用partial/reset tests一起typecheck通过；补丁最后的无效kind/空Key防御分支已经语法检查但未额外运行模拟器。root统一执行最终编译、全部XCTest和unsigned构建。

合成 Foundation smoke 通过实际Key identity及 nonResetting Key恢复不通知/不排重置；它不能代替Keychain/iCloud/物理设备或真实API验收。验收仍保持pending。
