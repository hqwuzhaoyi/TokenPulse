# 完成跨外观与设备验收并收束原型

**Status:** `complete`

## What to build

把已完成的环形小组件作为整体进行跨尺寸、跨外观和双平台验收，确认 A — Pulse Rail 的信息层级、渠道图标、账号容量、深链及新旧数据语义在真实 WidgetKit 环境中成立。将获批结论写入实现记录，把完整 HTML 原型作为一级设计证据保存在非 master 的 throwaway 分支，并从正式实现分支移除原型代码。

## Acceptance criteria

- [~] iPhone 主屏幕小/中/大已完成系统 Gallery 与主屏幕检查；锁屏 circular/rectangular/inline 以及 Watch corner/circular/rectangular/inline/Smart Stack 的 Preview 定义及 targets 构建通过，Watch App 已覆盖安装，真实四角槽位显示留待用户确认。
- [~] 深色 Gallery、固定状态 Preview、未知/无限状态测试和无障碍标签已覆盖；浅色、iOS 着色/单色、StandBy、极端 Dynamic Type 与 VoiceOver 完整矩阵留待实机验收。
- [x] 小/中/大分别允许选择最多 1/2/4 个主屏幕账号，按选择顺序展示并支持各区域深链；验证：选择策略覆盖超量与重复账号，模拟器真实配置并逐一点击两个账号区域。
- [x] 全量 XCTest 和 iOS/watchOS 所有生产 targets 构建通过，凭证与脱敏前响应未进入日志、截图或版本库。
- [~] 在实际 iPhone 与 Apple Watch 上验证添加、刷新调度、锁屏/表盘可读性和点击行为；自动等价覆盖为时间线、展示策略、深链和状态测试，剩余差距必须继续标记为待实机验收。
- [x] 原型问题、最终选择和偏离项写入实现记录；完整原型提交到非 master throwaway 分支，正式实现分支仅保留生产实现与设计结论。

## Blocked by

- [02 — 实现单账号环形组件与锁屏／Watch 入口](02-single-account-ring-widgets.md)
- [03 — 实现中组件双账号展示](03-medium-multi-account-widget.md)
- [04 — 实现大组件四账号展示](04-large-multi-account-widget.md)
- [05 — 接通 Codex 与 SuperGrok 账号级重置次数](05-reset-count-pipeline.md)
