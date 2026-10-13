# 只给日期的重置边界

`QuotaWindow.resetDatePrecision: QuotaDatePrecision?` 新增可选 `.day`。旧归档/旧初始化默认 nil，沿用既有带时间边界行为；只有提供商实际给日期时才设置 day。日期在 `resetsAt` 中使用 UTC 日期锚点，但它不代表午夜时刻重置。

day 日期由通用 `QuotaFormatting` 按 UTC `yyyy-MM-dd` 显示，iPhone、Watch 与 Widget 使用相同窗口精度，不把 UTC 午夜转为本地前一天。下一事件若是独立 expiresAt/replenishment，则沿用该时间字段的既有格式。

day 不因锚点到达使 `needsUpdate` 判定重置，不生成精确时间的预计重置通知。时间经过本身不确认额度恢复；真实刷新后的 provider cycle/边界推进与用量观测仍由既有 NotificationPlanner 处理。它不改变 continuous replenishment 的独立规则。

新增3个合成回归方法覆盖多个时区、归档往返、day 不预排/不因时间到达确认、旧归档/精确时间兼容。2026-10-02 完整 App 的 Swift6 iOS module emit 与该完整 XCTest 文件 semantic typecheck通过，PBX lint/diff检查通过；XCTest执行及目标构建由root串行验证，工作者未启动模拟器或执行xcodebuild。
