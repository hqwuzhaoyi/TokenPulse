# iOS 环状额度小组件任务

Approved: yes

用户批准原话：“可以”。批准对象为 A — Pulse Rail 实现基线、按账号列表顺序由中/大组件自动显示前 2/4 个账号、6 张任务的粒度与阻塞关系；记录日期：2026-09-09。

完成后用户纠正：“发现中/大小组件无法选择展示哪些ai”，并明确选择来源为“主屏幕配置的list里面的”。据此用账号集合配置替代自动前 2/4 规则：小/中/大分别从主屏幕已配置账号列表选择最多 1/2/4 个具体账号，按选择顺序展示。

任务仅发布到本地，未创建远端 Issue。本 change 是 `ios-watch-quota-monitor` 中既有 Widget 实现的后续设计变更，不改写原 11/12 号历史票。

## Apply gate

- 按阻塞关系推进；只有验收条件全部通过后才能勾选任务。
- 保留现有渠道 SVG 与 `ProviderIcon` 模板渲染方式，环形布局不得用字母占位符替代正式图标。
- 小、中、大组件分别从主屏幕已配置账号列表选择最多 1、2、4 个具体账号，按选择顺序展示并去重。
- MiniMax 显示 5 小时单环；GLM 与适用套餐的 Codex 分别显示 5 小时和周额度；SuperGrok 显示其实际额度窗口。不同窗口不得合并。
- 重置时间属于额度窗口并跟随对应环；可手动重置次数属于账号且每个账号只显示一次。
- SuperGrok 没有可信次数来源时必须显示“未提供”，不得使用原型示意值或推算值。
- 不直接操作或合并 master；需要合并时由用户人工确认。

## Tickets

- [x] [01 — 建立按组件尺寸选择账号与额度的展示策略](tickets/01-widget-presentation-policy.md) — 阻塞：无。
- [x] [02 — 实现单账号环形组件与锁屏／Watch 入口](tickets/02-single-account-ring-widgets.md) — 阻塞：01。
- [x] [03 — 实现中组件双账号展示](tickets/03-medium-multi-account-widget.md) — 阻塞：01、02。
- [x] [04 — 实现大组件四账号展示](tickets/04-large-multi-account-widget.md) — 阻塞：01、02。
- [x] [05 — 接通 Codex 与 SuperGrok 账号级重置次数](tickets/05-reset-count-pipeline.md) — 阻塞：01。
- [x] [06 — 完成跨外观与设备验收并收束原型](tickets/06-widget-validation-and-prototype-closeout.md) — 阻塞：02、03、04、05。

依赖关系：01 → {02、05}；02 → {03、04}；{02、03、04、05} → 06。

## Completion evidence

- Watch 四角支持修正后 82/82 XCTest 通过；结果包：`/tmp/tokenpulse-corner-final/Logs/Test/Test-TokenPulse-2026.09.09_20-37-02-+0800.xcresult`。
- iOS/watchOS 全部生产 targets 无签名设备构建通过；日志：`/tmp/tokenpulse-corner-build.log`，产物：`/tmp/tokenpulse-corner-products/Debug-iphoneos/TokenPulse.app`。
- iPhone 17 Pro / iOS 26.3.1 模拟器已检查系统 Widget Gallery 的小、中、大三种尺寸；大组件配置页能从主屏幕账号列表逐项添加账号，两个选定账号区域分别深链到各自详情。
- SuperGrok 当前公开账单结构没有可信的手动重置次数字段，保持“未提供”且不推算；证据已写入提供商接入文档。
- 完整原型保存在非 master 分支 `prototype/ios-quota-ring-widgets`，提交 `dda276a25d9ccf2cc6b6ab045670061615a1f605`；当前实现分支已移除原型文件。
- 实体 iPhone 当前不可用；实体 Watch 虽可见但未完成本轮添加/显示验证，按 Ticket 06 的 `[~]` 条目保留为实机差距。
- Watch 四角槽位已新增 `accessoryCorner`、专用 Gauge/标签及单账号配置；实体 Watch 签名构建和覆盖安装通过，表盘最终选择与显示待用户确认。
