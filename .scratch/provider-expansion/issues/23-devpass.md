# 23: DevPass 套餐与 Key 限额

**Status:** implemented; static verification passed; central build/test and real-account acceptance pending

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
