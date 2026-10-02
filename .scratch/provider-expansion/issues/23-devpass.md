# 23: DevPass 套餐与 Key 限额

**Status:** implemented-awaiting-real-validation

**Type:** integration

**What to build:** 输入 LLM Gateway Key 后查看 premium 每周额度、套餐 credits 与 Key 限额。

**Blocked by:** None (can start immediately)

## Acceptance criteria

- [ ] 三个窗口独立标识和提醒，十进制字符串精确解析。
- [ ] 无套餐、无 Key 上限及未知计划类型明确处理，非周期限额不创建重置提醒。
- [ ] 从添加入口到安全凭证保存、账号管理、同步和删除完整可用；同一提供商多个账号隔离，iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别向服务端查询；Watch 获得配置和凭证后不依赖手机、Mac 或新增代查服务在线。
- [ ] 卡片、详情、iPhone 小组件、Watch 和演示数据覆盖新增计量方式；金额、积分、token、时长和预算单位不混淆。
- [ ] 适用的额度告警、重置或低余额提醒接入既有规则；不适用的设置不开放；失败保留旧数据与采集时间，缺失值不补零。
- [ ] 覆盖请求契约、字段边界、账号与站点隔离、成功与失败及适用提醒行为的测试；运行相关测试和 unsigned TokenPulse target 完整构建。
- [ ] 新增图标优先官方资源或既有 Lobe Icons，固定来源版本、记录版权许可，并验证矢量与模板渲染覆盖 App、Widgets 和 Watch。
- [ ] 保存真实登录、查询及 Watch 独立刷新验收结论；无账号凭证或设备时保留未验收项，不将合成响应测试当作真实接入证明。
- [ ] 更新支持范围、登录方式、字段含义和验证边界；研究来源固定版本，发现契约不可用时记录具体阻塞。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/devpass.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。


## Implementation evidence

- `.devPass` public Key/controller/direct-query/account lifecycle routing, exact premium/cycle/key-limit quantities, no-plan state, Watch/widget/demo and non-brand Apache2 vector asset implemented.
- Pinned Pulse397c8fc4 and current official Usage API documentation at theopenco/llmgateway8e280f73 were checked through agent-reach GitHub/gh. Ordinary Key, three USD decimal budgets and null weekly reset semantics are documented.
- `DecimalQuotaCounts` shared API retains exact original amounts; budgets are not WalletBalance. Known PAYG without limits is successful `isNoPlan`, invalid or unknown shapes fail without clearing old data.
- Seven DevPass tests cover contracts, exact decimals beyond Double precision/old cache coding, none/unknown-plan distinction, invalid types/overflow, independent alerts/reset policy/widgets/demo and isolated account restoration/replacement/deletion.
- Full App module and test Swift6 typecheck passed; no central README/CONTEXT/manifest change. More in docs/devpass-provider-integration.md.

Central unsigned App/Widgets/Watch build and simulator XCTest execution, real API Key, iCloud arrival, physical standalone Watch, quota reset/lifetime and visual notification/widget evidence remain unaccepted; fixtures never count as production proof.

生产 DevPass 解析代码 macOS 合成 smoke 另通过：超出 Double 整数精度的 Decimal 原值、精确相减、快照编码、已知 no-plan、非有限/负数/溢出/下溢拒绝。此检查不是模拟器 XCTest 或真实 Key 查询。


## Key scope / reminder lifecycle correction

本组 Factory、DevPass、v0、Warp 的 credential identity 直接从 provider + 实际 API Key 重算 SHA-256，不信 metadata 声称的指纹；错误 kind 或空 Key 没有有效身份。统一 monitor/配置/ledger 用它隔离更换凭证和乱序同步，换 Key 后清掉旧 Key 的数量，即使新 Key 查询失败也不展示原 Key 的额度。其他提供商的身份策略保持不变，由 root 合并统一 getter。

复用共享 `QuotaWindow.resetSemantics`，DevPass 的 Key 累计上限和每个 Warp one-off grant 设为 `.nonResettingAllowance`；真实使用回落只内部重新允许阈值提醒，不推断、确认或预排重置。API余额/不明币种没有混入这一策略。演示同步采用该语义。

追加四个回归方法验证实际 Key/metadata/空值与kind、四提供商换 Key失败清旧数据及恢复、all-time Key额度恢复不通知重置、grant恢复不通知重置。最终 Factory10/DevPass8/v0 7/Warp8 共33个provider XCTest方法完成Swift6 typecheck，完整App模块与共用partial/reset tests一起typecheck通过；补丁最后的无效kind/空Key防御分支已经语法检查但未额外运行模拟器。root统一执行最终编译、全部XCTest和unsigned构建。

合成 Foundation smoke 通过实际Key identity及 nonResetting Key恢复不通知/不排重置；它不能代替Keychain/iCloud/物理设备或真实API验收。验收仍保持pending。


## Integration review correction

noPlan 仅允许显式 JSON null Key limit；unknown/missing usage with positive cap、missing cap 和未核实的零预算不再误判无上限。畸形 PAYG 保留旧额度与采集时间。矩形 complication 优先呈现已有 statusText，其他字段/形态保持既有逻辑。新增两项回归；最终统一编译/XCTest及视觉验收由 root 执行，真实账号仍未验收。
