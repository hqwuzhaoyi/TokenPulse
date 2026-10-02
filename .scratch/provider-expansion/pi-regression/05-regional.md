# 05-regional 回归报告：Xiaomi Coding Plan / QoderChina / Ollama Cloud / LongCat

快照：`/private/tmp/tokenpulse-pi-regression-20261002-222956/05-regional/snapshot`
范围：仅快照中已有源码。四个 provider 均为已实现并注册（ProviderIntegration.swift:187-199 有 Factory 分支；WebSessionContainer.swift:198-242 有登录 profile；project.pbxproj 中四个 client 均同时进入 App 与 Watch Sources），不存在“未覆盖 provider”。

## 一、发现

**没有发现可复现问题（0 项）。**

对四个 provider 的可执行逻辑（Cookie/账户 site 隔离、无套餐状态、用量与钱包分离、周期/过期/额度单位、缺失字段不假零、Decimal 路径）做了源码审查 + 真实生产源码独立编译 + 运行时探测，所有行为与各自集成文档（docs/xiaomi-coding-plan-integration.md、docs/qoder-mainland-integration.md、docs/ollama-cloud-integration.md、docs/longcat-integration.md）声明的契约一致，未发现与契约矛盾或可由具体输入触发的用户可见错误。未将推测或静态检查计为缺陷。

以下两条为**非缺陷边界观察**（共享 root 策略的既定严格性，无真实站点触发证据，不计入发现）：

1. `WebSessionContainer.swift:24-40`（共享 `WebSessionCookiePolicy.select`）：同名 Cookie 在两个允许域上值不同（探测 G）或任一同域 Cookie 值含 `,`/`"`/`\`/非可打印字符（探测 H，对 `includeAllNames` 的 QoderChina 更敏感）时，整次登录以 `invalidCredential` 拒绝。这是刻意的歧义拒绝，不是四个 provider 的缺陷；是否放宽属 root 决策。
2. `OllamaCloudProvider.swift:106-110`（Ollama 标签匹配）：meter 标签文本被内联元素拆开时（如 `<h3>Session <b>usage</b></h3>`）会以 `unreadableResponse` 明确失败而非误读。文档已声明“页面结构改变会明确失败，需要适配”，属既定设计。

## 二、实际执行的检查

未运行 xcodebuild/simctl/XCTest（由 root 统一串行执行）；以下均在冻结快照 + `/tmp/.../05-regional/work` 内完成，未访问 home/环境变量/Keychain/网络。

### 1. 源码审查（未修改快照）
- `TokenPulse/Providers/XiaomiCodingPlanProvider.swift`、`QoderChinaProvider.swift`、`OllamaCloudProvider.swift`、`LongCatProvider.swift`
- 共享机制：`WebSessionContainer.swift`（Cookie 选择/账户绑定/指纹）、`WalletExpansionHTTP.swift`（WalletDecimalValue/WalletNumericDecimal/Decimal 运算）、`WalletProvider.swift`（ProviderDecimal 严格字符串）、`ProviderHTTP.swift`（isoDate/queryFailure/redirect→错误映射）、`Models.swift`（QuotaWindow/WalletBalance/retainingWalletAfterPartialFailure）、`NotificationPlanner.swift`（nonResettingAllowance 抑制假重置，NotificationPlanner.swift:197-213）
- 既有测试：`TokenPulseTests/{XiaomiCodingPlan,QoderChina,OllamaCloud,LongCat}ProviderTests.swift`（无 skip/TODO）
- 集成注册：ProviderIntegration.swift:187-199/463/545；WidgetSnapshotStore.swift:95；DemoMode.swift:47,110-133；AccountSettingsView.swift:377（qoderChina/longCat 隐藏无效重置开关）

### 2. 真实生产源码独立编译探测（swift 6.3.3，纯 Foundation，无网络）
编译单元 = 原样生产文件 `Domain/Models.swift`、`Providers/{ProviderHTTP,WalletExpansionHTTP,WalletProvider,XiaomiCodingPlan,QoderChina,OllamaCloud,LongCat}Provider.swift` + `WebSessionContainer.swift`（仅删去与本任务无关的其它 provider 登录 case，四个 provider 的 case 与 Cookie/会话核心逐字保留）+ 从 ProviderIntegration.swift 提取的 envelope/transport 声明。命令与产物见 `work/`（`shim.swift`、`WebSessionContainer_trimmed.swift`、`final/`、`isolation/`、`xiaomi/`）。

运行结果要点（全部与契约一致）：
- **Xiaomi**：baseline 两窗口（37.5% tokens + CNY 钱包 42.750000000000001 Decimal 字符串精确）；多桶各自成窗、used>total 夹 100%/剩余 0；`used` 为字符串或负数→`unreadableResponse`（不假零）；limit=0 桶跳过；负余额 -5.50 原样保留；detail 500 仅降级 plan 元数据（resetsAt/planName 未知），balance 500 独立标 `walletFailure=.server` 且不标 walletCollectedAt；任一路 envelope 401→`invalidCredential`；expired=true 经完整 quota() 只留钱包 + 状态文案“没有当前 Coding Plan；余额与套餐额度分开显示”。
- **QoderChina**：个人/团队/到期子集三窗；个人 0 发放+团队有效→仅团队窗、无状态文案（新鲜）；团队 malformed→整读失败（不假零）；nextResetAt ISO/epoch-ms 均可读且只保留未来值；过期或 isActive=false 的 detail 不生成到期窗；remaining 与 used/total 矛盾时以服务端 remaining 展示。
- **LongCat**：ACTIVE 主包优先、缺 consumedToken 不补零（提示“未提供消耗量”）；fuel 成员缺字段或负值→聚合 used/remaining 未知、total 保留；expireTime ISO/epoch-ms 均解析；legacy 无 total→失败、total=0→无窗+状态；fuel 未取得→状态注明，不宣称不存在。
- **Ollama**：两 meter 0–100 直读、缺失 reset 为 nil；祖先容器额外 "N% used" 文本、script/template 注入、CSS width、实体、超 2MiB、重复/非法时间均按测试声明行为（拒绝或忽略）；第三个未知 meter 标签被忽略。
- **隔离**（`work/isolation` 输出）：Xiaomi/LongCat 外来域 Cookie 拒绝；LongCat 仅 uid 拒绝；QoderChina 国际域 qoder.com Cookie 与大写 `_GA` 排除、仅 `cna=…; session=…`；Ollama 仅数字分片（`wos-session.x`、子域排除）；Xiaomi envelope 当 qoderChina 校验拒绝；改写 accessToken 后指纹校验拒绝。

### 3. 图标验收（按“实现完成+图标存在”标准）
`TokenPulse/Resources/ProviderIcons.xcassets/`：`ProviderXiaomiMiMo/xiaomimimo.svg`、`ProviderOllama/ollama.svg`、`ProviderLongCat/longcat.svg`、`ProviderQoder/qoder.svg`（qoderChina 复用，ProviderIcon.swift:35/79-81 映射正确）。四个 Contents.json 均 `preserves-vector-representation:true` + `template-rendering-intent:template`；SVG 均显式 `width/height=24` + viewBox，`grep -ci currentcolor` 全部为 0。外来资产来源许可记录在 `TokenPulse/Resources/ProviderIconNotices.txt:1705-1711`（Lobe Icons 固定提交、Copyright 2023 LobeHub、MIT、currentColor→黑色与尺寸声明）。

### 4. 构建接线
project.pbxproj：四个 provider 源文件均有 App+Watch 两个 Sources 条目（行 1097-1100、1285-1288）；四个测试文件在测试 target。未执行真实构建（root 负责）。

## 三、XCTest 补充建议（未运行，供 root 复核合入）

`work/RegionalProvidersSupplementaryTests.swift`：8 个纯 Foundation 用例，覆盖本次探测验证过但既有测试未覆盖的分支——Xiaomi 负余额保留、expired 套餐经 quota() 的钱包保留、零 limit 桶+detail 降级、QoderChina 个人零+团队有效/过期与 inactive detail、LongCat 负值 fuel 成员聚合未知、Ollama 第三未知 meter、四 provider 会话隔离边界。已做独立 swiftc typecheck（XCTest 自 SDK framework 解析），**未声称执行**。

## 四、未覆盖范围

- 真实账号/网络端点（xiaomimimo.com、qoder.com.cn、ollama.com、longcat.chat 的实际 Cookie 形状、反机器人要求、页面布局、业务码）未访问；契约依据仅为快照文档引用的固定 Pulse 第二手证据，API 变化仍可能需适配。
- 完整 XCTest、xcodebuild、App/Watch/Widget 资源构建、模拟器与物理设备、Keychain/iCloud 同步、真实通知——由 root 统一串行执行，本报告不声称通过。
- Xiaomi 无时区 `yyyy-MM-dd HH:mm:ss` 按 GMT 解析、LongCat 无时区旧形状按设备时区解析：均为文档既定行为，未按真实服务时区验证。
- 共享策略观察项（同名冲突/含逗号 Cookie 值→登录拒绝）与 Ollama 标签拆分失败：见“发现”节说明，无真实触发证据，不作为缺陷。
