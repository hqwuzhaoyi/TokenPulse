# Watch toolbar 最小 A/B 构建

状态：root 已通过真实 CUA A/B 验证并决定保留 `.topBarTrailing`；08/09 仍未关闭。

本次唯一代码修改：`TokenPulseWatch/WatchAccountPagesView.swift:59` 将 `ToolbarItem {` 改为 `ToolbarItem(placement: .topBarTrailing) {`。保留全部既有未提交改动、TabView、导航内容与业务逻辑。读取 write-swift 后实施。

命令：

```sh
xcodebuild -project TokenPulse.xcodeproj -scheme TokenPulseWatch -configuration Debug -destination 'generic/platform=watchOS Simulator' -derivedDataPath /tmp/tokenpulse-i18n-build -jobs 1 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build > .scratch/internationalization/08-toolbar-ab-build.log 2>&1
ditto /tmp/tokenpulse-i18n-build/Build/Products/Debug-watchsimulator/TokenPulseWatch.app /tmp/tokenpulse-watch-toolbar-ab.app
```

结果：BUILD SUCCEEDED。仅 Watch app 与其 Watch widgets 依赖两个目标，未构建 iPhone scheme，复用既有 derivedData，jobs=1。未安装、启动模拟器、运行 UI 测试或进行 GUI 操作。

候选包：`/tmp/tokenpulse-watch-toolbar-ab.app`。
Bundle ID: `com.tokenpulse.app.watchkitapp`；binary SHA256: `f377270fb04f01f4a05f74d270e5545a45b6be4ba61ebf64669d54c38edde118`。

## root 真实 CUA 最终决定（2026-10-13）

以下为 root 提供的真实操作/截图结果，本构建代理未操作 GUI 或模拟器：旧 automatic 页没有可见入口；显式 topBarTrailing 包右上 gear 可见，英文实际点击进入 Complication Settings。英文进一步选择 DeepSeek、返回确认、恢复 Claude 并 Exit Demo 到 No Accounts；中文同入口选择 DeepSeek与退出演示恢复空状态均真实截图通过。保留唯一 placement 修复，不改导航/分页/业务逻辑。完整本轮跨入口 CUA 证据由 root 管理在 `08-09-cua-continuation.md`，本代理未修改该文件。

分页横向输入仍未验证、内部 AX 仅暴露 Simulator 外壳；真实 Watch 英文钟面及 corner/inline/Smart Stack 宿主没有新增证据。本次 toolbar 验证不能替代这些范围，不关闭 08/09。

最终 Release 专用增量命令：

```sh
xcodebuild -project TokenPulse.xcodeproj -scheme TokenPulseWatch -configuration Release -destination 'generic/platform=watchOS Simulator' -derivedDataPath /tmp/tokenpulse-i18n-release -jobs 1 CODE_SIGNING_ALLOWED=NO build > .scratch/internationalization/08-toolbar-final-release-build.log 2>&1
git diff --check
```

Release 最终结果：`08-toolbar-final-release-build.log` 为 **BUILD SUCCEEDED**，仅 Watch app 与 Watch widgets 依赖两个目标；diffcheck 已通过。此轮仅构建，未安装/启动任何模拟器、未运行 UI 测试、未提交或发布。
