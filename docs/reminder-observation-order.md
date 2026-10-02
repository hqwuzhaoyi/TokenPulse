# 额度提醒的观测顺序

同一账号的额度观测只接受严格晚于已处理额度时间的新快照。旧或相同时间的周期、阈值和缺失窗口不回写账本，不取消或重排较新观测建立的计划。钱包仍独立使用既有余额观测时间和失败保留规则，不随额度时间边界整体丢弃。

ReminderLedger.quotaObservationTimes 是可选账号级时间字段；旧账本缺失时退回窗口状态 observedAt 的最大值。成功空额度帧也记时间，因此之后较旧的窗口不能复活已移除的计划。合并按既有凭证兼容规则取最新时间；更换凭证身份清除该账号的时间字段与窗口状态，其他账号不受影响。现有历史保留策略未扩展。

设置更新不以旧/缺失快照重排计划；明确关闭提醒仍可取消，使用最新缓存数据重新启用仍正常。周期推断优先较新的 ledger，避免新鲜同周期读数因为 caller 提供了旧 previousSnapshot 而误报重置。

2026-10-03 从 0477a43 的真实 Models/ReminderModels/NotificationPlanner 编译 Foundation 复现：修复前“旧周期回放静默且账本不变”“旧缺失窗口保留计划”两项失败；修复后同程序及空帧清理/旧计划不复活、新鲜周期/同周期、旧设置和更换身份检查全部通过。程序位于 /tmp/tokenpulse-reminder-order-fix。没有运行 Xcode 或模拟器。

新增 OrderedQuotaObservationTests 覆盖旧/等时周期、计划与缺失窗口、新鲜升级/重置、设置开关、钱包独立、多账号/合并/旧 Codable 和身份清理。原 NotificationTests 的每次新 snapshot 默认增加一秒，显式时间仍可构造回放，避免把同时间改变数值误当新观测。运行 XCTest 由 root 串行验证。
