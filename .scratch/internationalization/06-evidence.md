# 06 通知与语言切换后的待发提醒：实施证据

状态：complete。17条资源与10个新行为场景已中央整合/实际执行；两語真实系统通知内容已验收，最新英文quota UI通过，详见下方中央证据。早期待执行条目保留为历史。

## 实施内容

- `Notifications/NotificationPlanner.swift`：额度告警、钱包低余额/不可调用、确认重置、预计重置使用完整本地化句子。按共享窗口语义 + Provider 上下文展示名称，保留自定义账号名、模型名和非应用自有文本。金额使用共享 Decimal 货币展示，不转换币种；比例遵循设备区域格式。
- `Application/NotificationRuntime.swift`：系统权限结果与显式示例通知自动按本设备有效语言展示；真实账号名原样，固定示例账号走既有演示名展示边界。未改07的 Codex 预告投递/去重逻辑。
- `Notifications/ReminderModels.swift`：待发重置计划新增可选 `notification` 渲染缓存和 `notificationWindows` 最小名称语义缓存，旧 Codable ledger 无此字段仍可解码。通知 ID、重置时刻、windowID、cycle 和各去重键均不包含语言。
- 计划比较保留原时间/窗口比较，同时新增“同一计划仅内容变化”分支：仅 `.schedule` 替换未来的同ID请求，更新本地待发内容缓存，不移除/重记 expectedReset、confirmedReset、quotaAlert 或 walletAlert 历史。未来缺失旧内容缓存时仅补一次，随后同内容不重复安排。
- 本地 pending 不接受远端 ledger 的内容覆盖，复用既有 `merging` 边界；已过去时刻不重新安排，不通过语言变化重播已送达通知。
- `QuotaMonitor.onActivation` + `AppRuntime` 绑定：激活时先使用本地缓存重排待发通知，再刷新；启动恢复后亦在联网前重排；模式/source 检查与 weak 引用保留。投递失败保留先前 ledger 并继续原错误恢复路径。
- 没有改共享 L10n / xcstrings / pbxproj，没有新增 Swift 源或测试目标。翻译为 `fragments/06.json`。

## 已执行检查

- 上述四类源与 `NotificationTests.swift` 的 `swiftc -frontend -parse` 通过；仅语法解析，不代表 typecheck 或测试执行。
- `git diff --check` 通过。
- 17条翻译参数数量匹配，Planner/Runtime 所有 L10n key 均收录。

## 新增行为测试（待中央执行）

在既有 `NotificationTests.swift` 测试边界新增：

1. zh-Hans/en × US/Germany 区域，额度/低余额/预计重置通知保留用户名、Fable、真实 USD 和小数。
2. zh→en 相同时间/窗口内容替换，ID/time/expected/threshold 记录不变，不复播；到期后切换回中文不重新发送。
3. 删除旧归档的渲染字段模拟 legacy ledger，解码并只替换未来请求一次，重启后保持去重。
4. 两个账号隔离及双设备 ledger merge 不覆盖各设备待发内容。
5. 0/1/2窗口及两种语言确认重置，确认与预计区分，多窗口语句分隔正确。
6. Runtime 内容替换失败不提交新 ledger，重启保持旧历史，重试成功更新一次，原 delivered 操作保持原文。
7. 两种支持语言及fr英文回退的权限反馈和显式演示通知。
8. monitor 激活先改缓存通知，再离线查询失败，保留最后成功额度数据。
9. 远端更高 observation fence 使当前读数变旧/缺失时，仅依本地待发名称语义更新未来 content；原 time/window/history/fence 保持，不根据旧数据改计划。
10. 极老档无快照/无名称 metadata：有 observation fence 时原本受保护的 future pending 使用准确泛化预计重置指导；无 fence 时沿用原取消决定。两种语言不改变 retain/cancel 资格，过期事件不重发。

继续复用现有全套通知阈值、Decimal边界、重置/观测时间 fence、总开关、账号开关、删除取消与权限场景作为行为回归。

## 待验收/边界

- 待负责人中央合并17条资源，再执行签名模拟器 NotificationTests + PreciseQuotaThresholdTests / QuotaObservationFenceTests / WalletTests 以及相关 Runtime/Demo/Monitor 回归。
- 需要 zh-Hans/en 实际演示通知标题/正文、权限指导及最大辅助字号可读性证据。后台通知仍由系统安排；源不引入调度保证。
- 原 stale/missing snapshot 的计划保护门槛完整保留（resetRemindersEnabled + 既有 observation fence + 当前snapshot更旧/缺失）：有名称语义缓存时单独翻译future内容；极老档未保存名称时使用“该账号额度预计已重置，请刷新确认。”泛化指导，不猜测窗口名字或造观测。
- 无snapshot且无observation fence不属于原保护分支，继续按原策略取消pending；国际化不放宽通知续存资格。关闭提醒/移除账号仍执行原取消策略。原来已受保护的未来计划仅content更新，失败提交与重试复用Runtime同一adapter/ledger提交路径。
- 当前只有静态检查；在中央测试/UI验收通过前不标 complete。

未提交、推送、发布。

## 中央全量验证回报与单断言修正

- 负责人回报06-09签名全量执行798项XCTest + 18项Swift Testing；06新增10项行为场景全部通过。全量尚有4处断言失败，其中1处为Copilot旧通知文案断言，另3处为09旧编译期望（由各负责人重跑）。此信息来自中央验证，非本代理独立执行。
- `CopilotProviderTests.testNotificationsUseIncludedQuotaThresholdsAndOneExpectedResetWithoutUnlimitedAlerts` 的单个旧整句 `Completions达到100%` 断言改为分别验证 Completions 的语义显示名和区域百分比100%，保留已有“不包含无限Chat”、通知kind、预计重置与再次处理不重复的断言。
- 没有改产品查询/planner/请求/ID/阈值/计划行为，保留03代理在同文件的授权场景改动。语法解析与diff whitespace检查通过，等待中央focused重跑结果。

## 最新中央行为验证

`06-09-focused-recovery.log`：101 XCTest、0 failures、TEST SUCCEEDED，实际包括 NotificationTests、CopilotProviderTests、PlatformTests、WatchPresentationTests、QuotaMonitorTests、DemoModeTests。已有四个旧文本断言修复确认通过。对应产品 UI 缺口继续独立记录，行为通过不等同于完整可视验收。

## 06 complete：实际系统 payload

中文示例提醒真实系统 UI 测试通过，06-ui-system 下图/树已看；英文真实额度通知 CBE51F95-0654-4314-8B16-CA77691F6A07.png 已实际查看完整英文title/body（Demo · Codex Plus Quota Alert / Weekly Quota reached 80%），与runtime双语完整输出、语言更换计划身份去重恢复行为绿共同完成本票。英文demo-specific自动UI因系统多条通知分组定位失败仍保留、未计为通过；独立英文quota UI继续补证。最大辅助字号系统short-look会截断标题，通知原始内容与AX保持完整，未改写用户名称/强制系统通知字号。

## 独立英文真实 quota UI

`02-05-06-ui-large-verified.log` 的 `NotificationAcceptance.testEnglishQuotaNotification` 实际执行并通过（58.780s），在最大辅助字号系统通知中心只读真实卡片、精确匹配已有完整title/body pair，保留actual payload与图/树。未展开group、不改变旧英语demo-specific失败test，补强已查看英文实际quota payload证据。整轮其余case尚在运行，不提前计总轮绿。
