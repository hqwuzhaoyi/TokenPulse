状态更新：complete。中央行为/原Home两语/最大辅助字号已真实验收，详见末尾，早期in-progress为历史。

# 07 Codex 重置预告双语体验

状态：in-progress。产品源、24 条资源与既有测试扩展 ready；中央实际 build、行为测试与双语可视验收待执行，不记 complete。

## 归属与已实施

- `TokenPulse/Providers/CodexResetFeed.swift`：只修改 `CodexResetStatus` 的展示/通知包装。新增 `hasVisiblePreview(at:)`、固定 `sourceURL` 与区域日期/百分比展示；不改 Payload/Announcement/Watch/Metadata 的字段、原文、ISO8601 decode 或 `CodexResetFeed` actor 的公共请求、ETag、失败重试/退避及跨账号共享请求实现。
- `TokenPulse/UI/ContentView.swift`：只修改 Codex 首页 gate 与 `CodexResetSection`，继续要求非 Demo 且存在 Codex 账号。Root 和 Section 都使用同一 `resetPreviewDate` 与 `hasVisiblePreview`；没有公告或未过期预测时不生成标题、footer、空态/loading/error占位。原“只有最近历史也隐藏”的 dirty 行为保留。
- 公告优先；预定时刻过去仍展示“等待执行确认”，不制造已确认的账号额度重置。概率仅接受实际 0...100，未知/非法不补零；日期与概率使用原 region locale。原始公告 text、forecastWindow 和来源 URL 保留。
- UI 包装、时间待定、预定时间已过、AI预测非官方承诺、概率、有效期、最近来源报告、更新时间、失败保留与来源提示均纳入 native catalog。
- 通知包装标题/正文走 L10n，补齐 forecast 的已报告概率和有效期，完整句模板插值来源原文与固定 URL。通知 identifier/kind、24h通知 freshness guard、提醒 settings gating、持久化去重 key `codexResetPreviewDelivered` 没有改变。
- `NotificationRuntime.swift` 与 `NotificationPlanner.swift` 无本票修改，06 其余逻辑完整保留；它们现有 Codex 分支调用兼容的 `status.previewNotification(at:)` 自动得到本地化包装。
- 本代理更改产品源时，ContentView 的 DEBUG 尾部逐字比较断言相同。之后负责人已明确自行加入 Codex 专用 DEBUG fixture route；不是本代理修改或覆盖。

## 资源

`fragments/07.json` 共 24 个平坦 app-owned key→English 条目，全部插值签名与 key 相符；原 catalog 同 key 英文遵循 canonical。未修改 `Localizable.xcstrings` 或 `project.pbxproj`。无新增 Swift source target。

## 既有行为测试扩展

`TokenPulseTests/CodexResetFeedTests.swift` 现在 12 个 Swift Testing 方法、17 个参数化实例；保留原公共请求与限流测试，扩展原预告与通知 settings/去重测试，不删除/skips 或更改弱断言。

- 中英 null、过期 forecast、history-only、取消响应均 `hasVisiblePreview=false` 且不通知；forecast 到 expiry 相等边界也隐藏。
- 两语已过 scheduled time 仍为 preview kind/announcement、正文明确等待确认；scheduled 优先于 watch；过旧缓存仍不通知。
- 公告 text，以及与现有 app key 同字的原始 forecastWindow“设置”、原文“取消 · 80% · %@ 原文”都保持；同 payload 切换 zh-Hans/en/fr fallback 后 identifier/kind/raw编码不变，通知正文完整保留 percent/printf样式源文字与 URL。
- scheduledFor nil 显示 Time to be determined/时间待定；unknown/非法 probability 不变零、不错误出现概率，保留实际 expiry/source正文。
- 0/80/100概率、en_US与de_DE区域 percent 格式保持。独立 Foundation probe 实测 German percent Unicode 为 `80 U+00A0 %`，不是凭空猜测预期。
- 用真实 DemoMode.makeMonitor 的独立 suite 和既有 `fetchCodexResets` 回调 seam，真实 `monitor.refresh` 先收到 forecast、再失败保留 status/unavailable、最后成功取消变为空；账号身份不变，无任何 Provider HTTP。
- 真实 NotificationRuntime settings gating/Adapter delivery 先 zh-Hans、再以 en 恢复 runtime，仍只有一次 `.deliver`，记录原固定 identifier，persisted dedup array不受语言切换影响。

## 已执行静态检查（不冒充产品测试）

- `07-source-parse.log`：产品两个源语法 parse exit 0。
- `07-source-tests-parse.log`：产品源与既有 CodexResetFeedTests 语法 parse exit 0。
- `07-tests-parse.log`：扩展测试语法 parse exit 0。
- `07-diff-check.log`：本票相关文件 `git diff --check` exit 0。
- Foundation Date.FormatStyle(date:time:locale:timeZone:) API 独立执行成功；German percent 和 launch argument scope 实测见 `07-foundation-probe.log`。
- 没有自行启动 xcodebuild、Simulator，也没有提交、推送或发布。

## 负责人中央真实 UI 注入 seam 与待验收

CodexResetStatus/Payload/Metadata/Announcement/Watch 都可用内部 memberwise initializer 按实际 Date.now±时间构造，无需新 public API。专用 monitor 使用 DemoMode.makeMonitor 独立 suite、start(refresh:false)，现有 @MainActor fetchCodexResets closure + refresh(Codex账号ID) 注入 status。canceled/retainedFailure 用闭包第二次返回empty/抛URLError配合真实刷新操作。

专用 UI fixture 必须使用非 Demo runtime 的实际 ContentView gate、同时有 Codex state，且不用单独复制渲染。CLI -demoModeEnabled YES 会覆盖新 named UserDefaults suite：实测 standard=true/isolatedSuite=true，所以不能把 unique suite 的 false 持久值当成防护；负责人已采用专用 `-demoModeEnabled NO`、`-cloudSyncEnabled NO` 与独立未start runtime，专用 Simulator 的 real accounts 空，nested fixture不启动真实runtime。

中央待验：签名四产品 build、17个参数化 CodexResetFeedTests 实例、真实 scheduled/forecast（两语、长原文与大字号）、historyOnly/empty/expired/canceled/retainedFailure 的完整首页标题/页脚可见/隐藏，以及实际 preview通知 payload/去重与当前资源。通过前本票保持 in-progress。

## 中央行为与原生可视开始

`07-native-behavior-verified.log`：70 XCTest +12 Swift Testing函数（Codex12函数含17参数化实例），0 failures、TEST SUCCEEDED。首轮debug fixture独立Widget UserDefaults跨actor错误已修为单独构造独占store，原07-native-behavior-tests.log失败保留、不计测试；生产逻辑未改。UI实际用原ContentView/原Home gate+原Section与仅Codex fake monitor，独立runtime !Demo/未start/禁sync，原始announcement/window中文英文不译，无公共HTTP或凭证。UI第一class轮Executed0（runner安装缓存），未计绿；仅卸载自有harness runner后以明确()方法滤镜重跑 scheduled 两语。

## 原生 Home 首批可视证据

`07-ui-home-verified.log` 真实14case执行，其中scheduled/forecast/empty/historyOnly/expired中英10case通过，10张顶层截图全部view_image查看：原文保留、AI非官方区分、past scheduled明确尚未确认、来源Footer完整；empty/historyOnly/expired标题/页脚整块隐藏。另4个canceled/retainedFailure的pull手势未触发fixture刷新，保留失败；改用原账号native Refresh a11y标签（带账号名），DEBUG外层sheet禁误拖关闭后重新验，不改生产业务。一次错误裸Refresh定位已主动停止，不计通过。

## 07 complete

`07-ui-refresh-verified.log` 4真实账号Refresh两语UI全部通过，取消后标题/footers整块隐藏，source失败后旧forecast保留且显示本地化更新失败；4图已全部view_image。与07-ui-home-verified中10通过场景合计14中英nativeHome场景，14图全部看。`07-ui-large-preview.log` 最大辅助字号公告/forecast两语4UI0fail，8张initial/source原生滚动图全部看，长段与原文无截断、未强行降字号。nativeSourceLink真tap走原Link，debugOpenURLhandled保证不发HTTP。实际VoiceOver音频未验证，不计听辨；nativeAX图树已保存。公共请求、通知权限、源ID与06未来提醒排程语义不变，无有效Codex预告依旧整块隐藏，未提交/发布。
