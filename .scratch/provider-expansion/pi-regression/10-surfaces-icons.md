# 回归报告：跨端与图标（10-surfaces-icons）

日期：2026-10-02 · 快照：/private/tmp/tokenpulse-pi-regression-20261002-222956/10-surfaces-icons/snapshot（未修改源码）

## 发现

没有发现可复现问题（本轮静态/脚本核查范围内）。以下为验证过的关键不变量与证据。

## 实际执行的检查

### 1. ProviderIcon 资产映射与资产目录（脚本：work/check_assets.py）
`TokenPulse/UI/ProviderIcon.swift` 中引用的全部 53 个 `Provider*` imageset 均存在于 `TokenPulse/Resources/ProviderIcons.xcassets/`，无缺失、无孤儿 imageset。全部 imageset 的 Contents.json 均：
- 含 `preserves-vector-representation: true`（SVG vector 保留）；
- `template-rendering-intent: "template"`；
- SVG 文件内无 `currentColor`；
- 每个引用路径均在 `iconAssetName`/`systemIconName` 二选一覆盖（nil 者走 SF Symbol，如 `typeSafe`→`puzzlepiece.extension.fill`、`abacus`→`square.grid.3x3.fill` 等，满足"通用 SF 也可"的验收标准）。
- 失败兜底：`questionmark.circle`。

### 2. Provider enum ↔ ProviderIntegration.quotaResult 穷举（脚本比对）
用 Python 从 `TokenPulse/Domain/Models.swift:11` 的 `enum Provider` 提取全部 case，与 `TokenPulse/Providers/ProviderIntegration.swift:154-361` `quotaResult` switch 比对：除 helper enum（mixed/none/walletOnly）外仅 `zhipu` 未单独出现，但 `ProviderIntegration.swift:181` `case .zai, .zhipu:` 已合并处理——穷举完备。

### 3. quotaStatusText / isNoPlan 不遮正常窗口
- `TokenPulse/Platform/WidgetSnapshotStore.swift:42-44`：`displayMetrics` 仅当 `metrics` 中没有任何带 window 的指标时才用 `quotaStatusText` 替换展示——有正常窗口时窗口保留，quotaStatusText 仅作附加行。
- `isNoPlan == true`（`:49`）返回"按量计费，无上限"静态指标，与 quotaStatusText 路径互不覆盖（DevPass 源头 `Providers/DevPassProvider.swift:64` 只在 `windows.isEmpty` 时置 true）。
- `TokenPulseWidgets/QuotaWidgetContent.swift:936-938`：`AccountStatus` 中 quotaStatusText 是独立 `Text`，排在失败/钱包/超额徽章之后追加，不遮挡时间行。
- `ContentView.swift:202/346`、`AccountSettingsView.swift:195`、`WatchAccountPagesView.swift:167`：各 surface 均单独渲染 quotaStatusText，非替换式。
- partial wallet：`AccountStatus` 顺序为 lastFailure > walletFailure > walletAvailable==false > quotaExceeded > 更新时间，钱包部分失败文案经 `QuotaFormatting.walletCollectionStatus`（"余额为旧数据"兜底），不会丢更新时间行。

### 4. 跨端引用一致性（grep）
`ProviderIcon` 被 iOS Widgets（QuotaWidgetContent.swift 7 处）与 Watch（WatchAccountPagesView.swift 2 处）共用；`WidgetSnapshotStore`（Platform/WidgetSnapshotStore.swift:226）被 Widgets、Watch Widgets intent、AppRuntime 共用，`load()` 在 QuotaTimelineProvider/WatchQuotaTimelineProvider/QuotaWidgetIntent 中均通过 actor 访问。

### 5. Swift 语法解析（xcrun swift -frontend -parse，全部退出码 0）
覆盖文件：ProviderIcon.swift、Models.swift、ProviderIntegration.swift、WidgetSnapshotStore.swift、QuotaWidgetContent.swift、AccountSettingsView.swift、ContentView.swift、WatchAccountPagesView.swift。均解析通过。

### 6. DemoMode
`runtime.isDemoMode` 在 iOS（AccountSettingsView/ContentView）与 Watch（TokenPulseWatchApp.swift:43 `.id(runtime.isDemoMode)` 强制切换视图树；WatchAccountPagesView）均有入口/退出，且 `.id(isDemoMode)` 确保切换时状态重建。

### 7. Notices
`TokenPulse/Resources/ProviderIconNotices.txt`（1760 行）记录全部外来 SVG 来源（Lobe Icons commit 哈希、MIT 许可、区域复用说明）。

## 未覆盖范围
- 未运行 XCTest（按规则由 root 统一串行执行）；未运行 xcodebuild/simctl。
- 未做真实账号/物理 Watch 验证（按改后验收标准非关票门槛）。
- Widgets/Watch 的实际渲染（SwiftUI layout 溢出等）只能静态核查，未在模拟器目视。
- 快照中若有源码不存在的 provider，未研究（未发现此类枚举 case）。
