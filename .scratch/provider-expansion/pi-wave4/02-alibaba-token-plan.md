# Alibaba Token Plan 接入冻结快照回归报告

- 快照：`/private/tmp/tokenpulse-wave4-pi/02-alibaba-token-plan/snapshot`
- 复现工作目录：`/tmp/tokenpulse-wave4-pi/02-alibaba-token-plan/work`（`src/` + `probe` 二进制）
- 方法：纯 Foundation 离线编译**真实生产源码**（`AlibabaTokenPlanProvider.swift`、`ProviderHTTP.swift`、`Domain/Models.swift` 逐字节复制，仅补齐 `VolcengineAccessKeys`/`ProviderCredentialEnvelope`/`ProviderTransport` 等非 UI 依赖的最小 stub），Swift 6.3.3 `swiftc` 编译执行 + Python 独立复算 golden 签名。未联网、未跑 Xcode/模拟器、未声称 XCTest 已执行。

## 已执行验证（probe 实际运行输出）

1. **ACS3 golden 签名**（`AlibabaTokenPlanSigner`，固定 date `2026-10-03T00:00:00Z` + nonce `00000000-0000-4000-8000-000000000001`）：
   - cn-beijing `6fe665…5280e` MATCH；ap-southeast-1 `877184…7fc374` MATCH（与测试 golden 及 Python 独立 HMAC 复算三方一致）。
   - 空 body（`httpBody == nil`）、`x-acs-content-sha256` 为空串 SHA256、URL/方法/头均正确。
2. **四 region/site 矩阵**：全部命中预期 host/action/api（`bailian-cs.console.aliyun.com`、`bailian-cs.console.alibabacloud.com`、`modelstudio-cs.console.aliyun.com`、`bailian-singapore-cs.alibabacloud.com`；`BroadScopeAspnGateway`/`IntlBroadScopeAspnGateway`），Bearer 短期 token、fingerprint 回填正确。
3. **form 编码**：`params=<urlencoded JSON>&region=cn-beijing|ap-southeast-1`，JSON 为 `Api/V/Data.cornerstoneParam`（sortedKeys、无斜杠转义），实测可 round-trip 解码。
4. **DataV2 嵌套**：`data.DataV2.data.data` 四层正确展开，ratio 0.25→25%、0.8→80%，毫秒 reset→`Date`；嵌套 JSON 字符串 envelope 也正确解析（0.5→50%）。
5. **NotLogined 仅一次重试**：首次失败→重新签名生成 token（nonce 不同）→共 4 请求后成功；连续两次 NotLogined→4 请求后 `invalidCredential`；`AccessDenied`→第 2 个请求即抛 `invalidCredential`，不重试；`success:false` 无 code→`server`。
6. **ratio/reset 语义**：`pct15/-0.1/true/"0.2"`、负 reset、未知结构均拒绝；`pct=0` 接受为 0%（不当作无限）；空 `data`→0 窗口 + “未提供个人 Token Plan 额度”；仅 reset 无 pct→保留未知。
7. **HTTP 状态**：401/403→`invalidCredential`、429→`rateLimited`、500→`server`；跨 host 响应拒绝（测试覆盖，静态核实 `send()` 中 scheme/host/port 比对）。
8. **凭证校验**：`sk-sp-`、空段、控制字符、含空格 SK 均拒绝；AK/SK+region+site 共同决定 fingerprint（`AlibabaTokenPlanProvider.swift:31-33`）。
9. **UI/持久化（静态推断，未运行 UI）**：`AccountSettingsView.swift:282,350-352` 与 `ContentView.swift:609,719-721` site picker 强制选择、切换清空凭证；`QuotaMonitor.swift:419` 换绑时同步 `tokenPlanSite` 到配置，`NewAPIProvider.swift:120` 忽略 claimed fingerprint 重算 identity。
10. **图标**：`ProviderAlibabaCloud.imageset`（含 `alibabacloud.svg` + `Contents.json`）存在，`Provider` 测试断言 `alibabaTokenPlan` 复用同一 iconAssetName。

## 发现

**无可复现问题。** 本轮所有离线可验证项（签名、矩阵、form、嵌套、重试、语义、状态码、凭证校验、图标存在性）全部通过，未发现上一轮遗留回归。

## 未覆盖（如实说明）

- 真实 AK/SK 登录、RAM 权限、console token TTL 行为、真实数值与官方面板对照、地区错配实测（需联网/真实凭证，按任务约束不执行）。
- XCTest 未经 Xcode 实际运行（测试文件逐行核对，断言与 probe 覆盖一致；不宣称通过）。
- App/Watch/widget 真机构建与 iCloud 同步、`QuotaMonitor`/`NotificationPlanner`/`DemoMode` 仅静态审阅 + 测试源码核对，未运行。
- UI 选择持久化为静态推断（代码路径清晰，但未在模拟器中操作验证）。
