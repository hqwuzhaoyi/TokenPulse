# 实现单账号环形组件与锁屏／Watch 入口

**Status:** `complete`

## What to build

按已批准的 A — Pulse Rail 方向实现共享的原生 SwiftUI 环形额度视图，并把它接入主屏幕小组件、iPhone 锁屏 accessory widget 和 Watch 四角、圆形、矩形、行内 complication。环形只改变额度的表达方式，必须继续使用项目现有渠道 SVG 和 `ProviderIcon` 模板渲染风格。

单周期账号显示一个主环；双周期账号分别显示两个环。百分比位于环内或紧邻环，额度名称与该窗口自己的重置时间绑定。账号级可手动重置次数只显示一次，不复制到各个额度窗口。

Apple Watch complication 不提供账号配置参数，统一读取 TokenPulse Watch App“表盘设置”保存的账号；不得复用 iPhone 多账号数组或产生“添加新项目”二级交互。

Watch App 必须在账号 ID 写入共享 App Group 并完成跨进程同步后定向刷新 complication，再退出账号选择页；不能依赖 Picker 的异步 `.onChange` 时机。

## Acceptance criteria

- [x] MiniMax 单环以及 GLM/Codex 双环均能显示正确百分比、窗口名称和各自重置时间；验证：使用固定快照运行 SwiftUI Preview 或截图检查，并运行展示测试。
- [x] 渠道图标继续读取现有矢量资源并使用模板渲染，不出现字母占位、重复渠道名或重复“5 小时”；验证：检查五个渠道预览和无障碍树。
- [x] 缺失百分比、无限额度、待更新和最近刷新失败拥有明确且不依赖颜色的表达；验证：逐状态运行 Preview/截图检查和可访问性断言。
- [x] accessory corner 以渠道图标为主体并沿表盘边缘显示额度 Gauge/重置标签；circular 只显示一个主额度，rectangular 显示额度与重置摘要，inline 保持可读文本；验证：检查所有已支持 family 的 Preview 和 Watch targets 构建。
- [x] iOS 与 watchOS Widget targets 均无签名构建通过，且全量 XCTest 通过。

## Blocked by

- [01 — 建立按组件尺寸选择账号与额度的展示策略](01-widget-presentation-policy.md)
