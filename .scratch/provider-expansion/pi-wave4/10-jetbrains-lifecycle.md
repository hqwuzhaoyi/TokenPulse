# JetBrains 独立设备生命周期回归报告（冻结快照）

- 冻结时间：2026-10-03T02:59:59.416201；源码 commit：dece27b74aab5d9c613088fd09dce8e902e402db
- 范围：`JetBrainsSessionCoordinator`、`DeviceOAuthCredentialVault`（grant ledger / activateReceipt）、`ProviderScopedCredentialStore`、`JetBrainsImportView`、`WatchAccountPagesView`、`AccountQuotaClient`、`QuotaMonitor`
- 方式：只读 snapshot 源码；在 `/tmp/tokenpulse-wave4-pi/10-jetbrains-lifecycle/work` 下用 Swift 6 + 纯 Foundation 编译**真实生产源码**（`JetBrainsProvider.swift`、`DeviceOAuthCredentialVault.swift`、`Models.swift`、`PlatformConstants.swift`、`ProviderHTTP.swift`、`QuotaMonitor.swift`、`Ports.swift`、`AccountConfiguration.swift` + 少量与生产无关的桩：envelope/transport/decimal 桩，不替换被测逻辑）并实际执行 17 组场景。未联网、未跑 Xcode 测试、未做 git 写操作。

## 结论：未发现可复现缺陷（发现数为 0）

所有 prompt 列出的不变量在真实源码上复现通过（已执行，非静态推断）：

| 不变量 | 验证方式与结果 |
|---|---|
| prepare 只写 candidate，实际 Save 才 active | S1（已执行）：`importTransfer` 后 `vault.version(for: accountID).credential == nil`；`activateJetBrainsReceipt` 后 active stage=ready 且无 candidate 元数据（`JetBrainsProvider.swift:120-137`、`DeviceOAuthCredentialVault.swift:117-153`） |
| active 旧 Ready 在新导入失败/取消时保留 | S2（已执行）：新 RT 导入在 mint 网络失败后，active 记录字节与 generation 完全不变；S12（已执行）：`cancelImport` 后 active 不变，仅 candidate 被 tombstone（`JetBrainsProvider.swift:85-99`） |
| 真实 RT hash 本机跨 UUID 防重放 | S3（已执行）：同一 RT 在第二账号 UUID 下 `reserveGrantMarker` 抛 `invalidCredential`；ledger tombstone 在账号删除后仍保留（`DeviceOAuthCredentialVault.swift:73-85`） |
| 新 RT checkpoint 先于身份/mint | S4（已执行）：mint 返回 rotated RT 后下一步失败时，vault 中已持久化 `refreshToken == rotated`（先 checkpoint 再继续）；`jba()` 内 `issued` checkpoint 在 `verifyMint` 之前（`JetBrainsProvider.swift:171-186`） |
| 未知 result 不盲重发 | S16（已执行）：`oauth2/token` 超时 → active 标记 `uncertain`；下一次 `quota()` 0 次网络请求直接拒绝；换新 export 可恢复。S4（已执行）：`provide`(register) 网络失败后 resume 只重发幂等的 register（200/201 accepted），不再触碰 RT 消耗端点 |
| candidate resume 新 lease 先 claim | S11（已执行，事件日志）：事件序列 `WRITE-candidate, WRITE-candidate, NET:register…` — claim checkpoint 先于首个网络请求（`JetBrainsProvider.swift:141-144`） |
| 旧 cleanup 不删新 | S5/S12（已执行）：删除/取消后 `compareAndSwap` 用 stale generation 一律失败，不能复活；`QuotaMonitor.replaceCredential` 的 `saved.credential == credential` CAS 删除守卫只在仍为本次写入时清理（`QuotaMonitor.swift:341-350`，静态核对） |
| baseline CAS/删除/晚 receipt 不得复活 | S5（已执行）：prepare 与 save 之间删除 active 后，receipt 激活被拒，active 保持空 |
| stale UI raw 不能覆盖新 RT | S6（已执行）：后台刷新 rotate RT 后，用旧 receipt 再次 `activateJetBrainsReceipt` 走早退分支（同 marker 同 fingerprint），rotated RT 保留（`DeviceOAuthCredentialVault.swift:120-125`） |
| Watch matched scope 与 actual 保存成功 | monitor 级（已执行）：真实 `QuotaMonitor.replaceCredential → ProviderScopedCredentialStore.save → activateJetBrainsReceipt` 链路，第二份独立 export 激活成功：存储 RT=`watch-rt-2`、candidate 元数据清除、fingerprint 与 expectedIdentity 匹配、generation 递增；不同 license（不匹配 scope）的 import 在 `verifyMint` 即被拒 |
| AccountQuotaClient 路由 | 静态核对 `AccountQuotaClient.swift:30-33`：jetBrainsAI 强制 `DeviceOAuthVaultProviding` 并走 coordinator，忽略传入 raw credential |
| 每设备独立 export 的文案 | 静态核对 `JetBrainsImportView.swift:16-18`：明确"每台设备必须分别登录并导出新的独立授权"，未假设 ledger 跨设备去重（ledger 注释亦声明 device-local） |
| 图标 | `ProviderIcon.swift:90` jetBrainsAI 无品牌资产时回退 SF Symbol `terminal`（实现存在；按验收标准非缺陷） |

## 实际执行的命令/结果

- `swiftc -swift-version 6 src/*.swift scenarios_main.swift -o harness2 && ./harness2` → 30 项断言，27 PASS；3 个 FAIL 均为**本复现脚本自身的 fixture/断言错误**，非产品缺陷：
  - S4 "uncertain"：产品只对 RT 消耗端点（`oauth2/token`）未知结果标 uncertain；register/provide 失败保持 jbaReady，重发的是幂等请求——事件日志与代码路径均确认未重发 `oauth2/token`。
  - S4 "hits=1"：该 1 次命中即上述 register。
  - S11：断言字符串写成 `stage=identityPending`，实际首跑停在 `jbaReady`（mint+verify 成功、register 失败），事件日志本身证明 claim 先于网络。
- monitor 级：`./monitor` → `WATCH-SAVE-ACTUAL: PASS`、`monitor-path activation bumps generation: PASS`、`mismatched-scope import refused: PASS`、`WATCH-SAVE-MISMATCH-REFUSED: PASS`。
- 复现脚本与桩位于 `work/src`、`work/scenarios.swift`、`work/monitor_harness.swift`（桩仅覆盖未拷贝的无关 provider 基础设施）。

## 设计上值得知晓（非缺陷）

1. `JetBrainsSessionCoordinator.attemptRecords` 在成功导入后不清除（仅 cancel 清除），进程内缓慢累积 UUID→UUID 条目；无功能影响。
2. 同一 export 在取消/未知结果后被本机永久拒绝（ledger tombstone），必须新导出——与导入页文案一致，属刻意策略。
3. active 记录（同 marker 复导入路径）在 refresh 未知结果时会被标 `uncertain` 从而停用直至换新 export；这是 rotation 安全的取舍，candidate 路径不受影响（S2 已验证）。

## 未覆盖

- XCTest/Xcode 目标、真实 Keychain/iCloud、真实 JetBrains/Grazie 网络、实体 Watch 与真实登录（按任务约束不联网、不跑模拟器；未声称 XCTest 已跑）。
- `NousSessionCoordinator`/`KeychainDeviceOAuthRecords` 的真实 Security.framework 行为（仅静态核对写入原子性与 `kSecAttrSynchronizable=false`）。
- UI 渲染层（SwiftUI 视图本体）仅静态审阅，未做快照/渲染测试。
