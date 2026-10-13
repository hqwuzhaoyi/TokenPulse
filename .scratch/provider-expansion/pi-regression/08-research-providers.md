# 08 Research Providers 回归报告：Mistral / Replicate / Sakana

范围：`TokenPulse/Providers/MistralProvider.swift`、`ReplicateProvider.swift`、`SakanaProvider.swift` 及其共享设施（`WebSessionContainer.swift`、`ProviderHTTP.swift`、`WalletProvider.swift`、`NotificationPlanner.swift`、`Domain/Models.swift`）。TypeSafe 按指示不检查。快照源码未修改；所有复现产物在 `work/`。

## 发现（3 项，均为低严重级别；无中/高危可复现问题）

### F1（低）Mistral 订阅页 flight 解析：多参数 `__next_f.push` 只解析第一个参数，后续 chunk 静默丢失
- 位置：`TokenPulse/Providers/MistralProvider.swift:113-125`（marker 扫描 + `containerEnd`）+ `:139-141`（`cursor = end` 后无回退）；现有测试仅覆盖单参数形式（`TokenPulseTests/MistralProviderTests.swift:19-22` 的 `page()` helper 只生成 `push([1,"…"])`）。
- 最小触发输入：订阅页 HTML 中一次调用携带 ≥2 个 chunk 参数，预算对象位于第 2+ 个参数：
  `self.__next_f.push([1,"{\"monthly_price\":\"$99\"}"],[1,"{\"api_budget\":{\"usage_percentage\":25}}"])`
- 预期：两个参数都应并入 flight 流。实际：`containerEnd` 在第一个参数的配对 `]` 处返回，`cursor` 前移后扫描不到下一个 marker，第二个参数被丢弃——`budgets` 缺 `api_budget`。
- 用户影响：API（或 Vibe）预算窗口静默消失。订阅页请求本身成功、`quota()` 中 subscription 解析错误也不设任何失败标记（`MistralProvider.swift:66` 仅吞错），快照照常"成功"展示剩余窗口；若钱包与另一预算也缺失则整体 `noQuotaWindows` 失败。与"错误响应不刷新为 0"的既有保障不同，此路径无 `walletFailure` 类标记。
- 证据（实际执行）：
  - `work/dbg.swift`（逐字复刻 `containerEnd` + 扫描循环）输出：`containerEnd OK, slice= [1,"{\"api_budget\":…}"]`（仅第一参数）、`parts: ["{\"api_budget\":…}"]`（单元素）。
  - `work/harness.swift` M8：两参数内容相同时能解析出 1 个预算（来自第一参数），第二参数不可见。
- 不确定性说明：Mistral 线上是否产出多参数 push 形式无法离线证实（未联网）；现有快照测试只断言单参数形式，故此为已证实的解析行为 + 依赖线上 DOM 的真实触发频率。

### F2（低）Sakana：对同一 `data-slot="card-title"` DOM 的两种互斥解析假设
- 位置：`TokenPulse/Providers/SakanaProvider.swift:196-206`（`sections()` 要求 Usage limit 卡标题为**裸文本**：捕获组 trim+lower 后必须等于 `"usage limit"`）与 `:168`（`providerPlanName` 正则**要求** `<span>` 包裹：`data-slot=…>\s*<span…>`）。
- 最小触发输入（span 统一形态）：`<div data-slot="card-title"><span>Usage limit</span></div><p>5-hour</p><p>92% used</p>…`
- 预期：任一合理 DOM 形态下两项功能至少稳定其一。实际：span 形态下 `sections()` 的标题判定拿到 `<span>Usage limit</span>` ≠ `"usage limit"` → 匹配数为 0 → 无任何窗口 → `snapshot` 抛 `unreadableResponse`（整个 provider 刷新失败）；反之若页面统一为裸文本，`providerPlanName` 正则永远匹配不到 → 计划名静默为 nil。两种正则在同一页面只能各自成立一半。
- 用户影响：控制台 DOM 样式统一调整（shadcn CardTitle 包一层 span 或去掉 span）后，要么 Sakana 整体额度刷新失败，要么计划名丢失。
- 证据（实际执行）：`work/harness.swift` S2：span 包裹 `Usage limit` → `windows=-1`（snapshot 抛错）、`plan=nil`。现有 fixture（`TokenPulseTests/SakanaProviderTests.swift:15`）恰是"计划卡带 span、Usage 卡裸文本"的混合形态，说明实现按抓取样本硬编码了两种互斥假设。
- 不确定性说明：fixture 混合形态可能确实来自真实抓取（则当前线上两功能均工作）；缺陷仅在 DOM 风格统一变化时触发，属健壮性问题而非当前已证实的线上故障。

### F3（低）Replicate 账单组织枚举：props JSON 容器节点 ≥4000 时整体抛错，即使账号已被 BFS 提前找到
- 位置：`TokenPulse/Providers/ReplicateProvider.swift:88`（`while index < queue.count, visited < 4_000`）与 `:99`（`guard visited < 4_000 else { throw RefreshFailure.unreadableResponse }`——循环后无条件抛出）。
- 最小触发输入：`react-component-props` JSON 含约 3900 条 `{row_i:{usage:i,meta:[a,b]}}`（≈7800 个容器节点），同时 `account` 位于根级。
- 预期：账号对象在根附近即被发现，防 DoS 上限不应使已成功枚举的结果作废。实际：BFS 先找到 `user:alice`，随后 `guard` 仍抛 `unreadableResponse` → 登录枚举（`makeCredentials`）与日常刷新都失败。
- 用户影响：账单 props 较大的账户（大量 usage 行/组织）无法添加或刷新 Replicate，报"响应不可读/服务端错误"，尽管会话有效。
- 证据（实际执行）：`work/harness.swift` R2：`throw=unreadableResponse even though account is at payload root`。
- 说明：4000 上限本身是防资源耗尽的合理设计；问题在于"上限触发即作废已枚举结果"的失败模式。真实页面是否超过该规模未证实（未联网）。

### 观察项（不列为缺陷）
- Mistral `Money` 字符串路径拒绝 >38 位有效数字（`ProviderDecimal`），数字路径（如 `1e40`）无此护栏（`MistralProvider.swift:104-111`）——精度护栏不对称，但 Decimal 可精确表示，无用户影响（harness M3）。
- Sakana "$ 1,212.34"（$ 后带空格）不识别为任何余额 → 无钱包窗口且 `walletFailure=nil`，UI 按"采集成功"展示但余额行消失；与 Mistral"组件缺失→标记 unreadableResponse"策略不一致（harness S1）。裸数字同理（测试已断言该设计为预期）。
- Sakana 非规范/小写月份的 "Resets on" 文本 → `resetsAt=nil` 但窗口仍展示（harness S3）。
- 存储凭据 header 中若出现 denied 前缀 cookie 名，`CookieWebSessionPolicy.values` 整体抛 `invalidCredential`（防御性；正常登录流程 `select` 已过滤，harness S4 末行）。
- 图标：三者均在 `ProviderIcons.xcassets` 中存在，SVG 矢量、`preserves-vector-representation`+`template-rendering-intent=template`、`viewBox 0 0 24 24`、`fill="#000000"` 无 `currentColor`；未在 repo 中找到外来资产来源许可记录（观察项，非缺陷）。

## 实际执行的检查
1. 通读三 provider 全文及 `WebSessionContainer.swift`（Cookie 策略/指纹校验）、`ProviderHTTP.swift`、`WalletProvider.swift`（ProviderDecimal）、`NotificationPlanner.swift`（钱包告警）、`Domain/Models.swift`、三个现有测试文件（共 340 行、18 个用例）。
2. `work/harness.swift`：**逐字提取**生产 parser（Mistral/Sakana/Replicate 全部解析函数 + `ProviderDecimal.amount` + `CookieWebSessionPolicy.values`，仅以签名相同的桩类型替代 UI 模型），`swiftc -suppress-warnings -o harness harness.swift` 编译成功后执行，退出码 0；30 组对抗输入（M1-M10 / S1-S4 / R1-R4）输出留存于 `work/harness-output.txt`。关键结论：
   - wallet 公式精度 ✓：`0.1+0.2-0.3` 数字路径精确为 0（无 Double 桥接）；字符串 18 位小数精确；`huge+tiny` 静默吸收被双逆恒等式拒绝（M1/M2/M3/M5）。
   - API/Vibe 分离 ✓：`mistral.api`/`mistral.vibe` 双窗口；`$D` 前缀 reset 日期解析成功；键序不同的重复对象正确去重；tRPC batch vibe 回退解析成功（M6/M9/M10）。
   - Sakana 币种证据 ✓：仅显式 `USD`/`US$`/`… USD` 记货币；裸 `$` → `"$ credits"` 且 `isMonetary=false`；无币种/裸数字 → 不显示钱包（S1）；钱包告警仅对 `isMonetary` 生效（`NotificationPlanner.swift:146-167`）。
   - Auth.js chunks ✓：单族 + 连续 `0..N-1`（含 12 分块）；混族、`.sig` 后缀、`.00` 前导零、缺块均拒绝；非族 cookie（如 csrftoken）可共存（S4）。
   - 账单组织枚举 ✓：user+organization 双候选、确定性排序、username 白名单拒绝 `../`、`?`、空格、129 长度（R1/R4）。
   - 错误响应不刷新为 0 ✓（代码路径核对 + 现有测试断言）：Mistral 主钱包失败→省略钱包窗口+`walletFailure` 标记（不伪造 0）；Sakana 辅助页 500→`walletFailure=.server` 且额度窗口保留；Replicate 字段缺失→抛错；`NotificationPlanner.walletMessages` 对 `walletFailure != nil` 的快照不产生/不重置钱包告警（"retained wallet is historical data"）。
3. `work/dbg.swift`、`work/dbg2.swift`：对 F1 的逐字符状态追踪（containerEnd 的引号/转义/括号栈均按预期工作，问题在多参数形式的扫描粒度）。
4. `work/ProviderRegressionExtrasTests.swift`：针对 F1/F2/F3 的 XCTest 补充建议（**未运行**，待 root 复核合入后随全套件串行执行；F1/F3 用例按"预期行为"断言，当前实现会失败，用于固化修复目标）。

## 未覆盖范围
- 未执行 XCTest / xcodebuild（按规则由 root 统一串行执行；本报告不声称任何 XCTest 通过）。
- 未联网访问真实 mistral.ai / console.sakana.ai / replicate.com：F1 的多参数 push 出现频率、F2 的真实 DOM 形态、F3 的真实 props 规模均无法离线证实，三项发现均为"已证实解析行为 + 条件触发"。
- 未做真实账号登录、真实 Auth.js 分块 cookie 抓取、物理 Watch/Widget 渲染验证（按验收标准不作为关票门槛）。
- 图标外来资产来源许可记录：repo 内未检索到（若记录在快照外文档则未覆盖）。
- 本任务未研究 Mistral/Replicate/Sakana 之外的 provider；TypeSafe 按指示跳过。
