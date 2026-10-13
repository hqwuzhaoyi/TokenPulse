# 05 账号设置与同步管理：实施证据

## 当前结论（2026-10-13）

2026-10-13 用户明确指示“跳过这个”，豁免本轮 iPhone 与 Watch 的 VoiceOver 实际听辨及语音导航验收。此项记为用户豁免，未执行、未声称测试通过。已完成的辅助功能标签/AX 检查保留；不豁免普通 Watch 触控、Crown、滚动、表盘宿主或最终中文锁屏复验。 本票按更新后的范围 complete。中央构建/回归与后续原生 UI、大字号证据见本文件后文和 progress.md；下文早期“待执行/未验证”为保留的历史阶段，不代表当前状态。

状态：in-progress，源与翻译片段 ready，待负责人整合构建与 UI 验收。

## 已实施

- `UI/AccountSettingsView.swift`：设置主页、演示模式说明、通知开关/示例通知结果、iCloud 同步及 VoiceOver 同步中状态、账号设置、额度/低余额阈值、Watch 关注开关、凭证更新指导、验证错误、删除确认与演示/真实数据边界。静态 SwiftUI 文案由原生 String Catalog 查询；变量/条件选择和错误文案用既有 `L10n`。
- 设置列表和标题使用既有演示账号展示边界；真实自定义名原样。账户 Provider 名称、模型套餐名及第三方内容保持其相应展示边界。已接入04共享窗口名和 Provider 白名单套餐状态展示。
- `Application/QuotaMonitor.swift`：本地载入、账号/顺序/设置/刷新结果/同步数据保存失败、删除失败、已删除本地缓存清理失败、凭证回滚清理失败及重试反馈均本地化。
- `Application/AppRuntime.swift`：演示退出清理、小组件/通知更新失败、同步收到后更新失败和既有 Codex 预告提醒投递失败文案本地化。保留全部既有同步/隔离/凭证/预告行为。
- `Platform/CloudAccountSyncStore.swift`：应用自有 `CloudSyncError` 与通用失败恢复指导本地化，键与成功/失败时间记录不变。
- `fragments/05.json`：93 条简体中文/英文文案，包括系统通知权限反馈。没有修改共享 xcstrings 或工程文件，没有新增 Swift 文件。

## 已做静态检查

- `swiftc -frontend -parse` 设置/Runtime/Monitor/CloudSync 四源文件及 QuotaMonitorTests / AccountConfigurationTests / PlatformTests：通过，仅语法解析，不等于构建或执行测试。
- 源中中文静态字面量与片段覆盖：全部可对应（原生插值重新登录 `%@` 单独已收录）。片段 `%@` 参数数量匹配：通过。
- diff 检查：不修改 provider identifier、credential identity/scope、存储键、同步数据形状、threshold 解析或计算、排序/删除/通知语义。原有阈值验证文案更准确地说明 `>0 && <=100`，条件没有改变。

## 实际行为测试待执行

复用现有 XCTest 入口，负责人合并翻译后串行运行：

- QuotaMonitorTests：既有删除凭证失败可重试及保存失败/凭证回滚失败/两次清理重试场景扩为 zh-Hans/en，两语断言恢复文案及凭证最终删除状态。其他错误断言改为有效语言展示。
- AccountConfigurationTests：既有钱包提醒 + Watch 选择保存恢复及排序/阈值恢复场景扩为两语，校验真实中文混合自定义名、Provider、UUID、credential identity、阈值及顺序保持一致。
- PlatformTests：既有请求失败/重试/收到同步时间场景扩为两语，断言 iCloud 不可用/数据版本不匹配/通用错误恢复文案，同时验证未知原始 error 不被用作翻译 key、失败不推进成功时间，重试成功清空错误。
- DemoModeTests：复用既有真实持久化/Widget 隔离、演示设置及删除场景。本票未运行模拟器，遵守负责人串行整合要求。

测试语言隔离使用04 TaskLocal `L10n.withLanguage`；同步及 async overload 已确认落地。

已按负责人协调追加02的两项API Key保存/回滚场景到既有QuotaMonitorTests私有fixture边界，并加async语言作用域；未增加测试文件或target。Provider凭证指导5个共享条目与02片段统一，以保持新增/设置两入口文案一致。

## 未验证

- app/Watch/两端 widgets 的实际编译、String Catalog 资源整合以及上述 XCTest 执行结果。
- zh-Hans/en 两语言设置主页、长凭证指导、低余额/额度阈值输入、删除确认、错误恢复提示的真实点击、VoiceOver 和最大辅助字号截屏。
- 设置主页 UI 遍历需同时包含真实模式的 iCloud 同步入口与演示模式的数据边界说明。新通知弹窗由系统权限呈现；应用自有反馈文案已覆盖。

未提交、推送或发布。仅语法与片段检查不能将此票标为 complete。

## 设置样例名称展示复核

- 账号列表第41行及账号设置导航标题第347行已使用 `L10n.demoAccountName(configuration.account)`。没有其他设置页 `account.name` 展示或名称输入 Binding。
- 删除确认使用整句应用指导，不插值 raw 账号名；无需额外更改。复核时04 helper 已限制固定样例 UUID 与已知样例名称，真实/自定义演示账号名保留原文。

## 原生 UI 定位诊断

两轮 Settings UI 未通过，保留 `02-05-ui-actions-recovery.log` 与 `05-ui-settings-confirmation.log`。真实界面树显示额度开关父行内嵌原生 Switch；确认弹窗在当前 iOS 使用 compact Sheet `Delete Account?`，无独立 Cancel 按钮。已将 UI locator 改为内嵌 Switch，并断言真实 Sheet 后点外部取消，不放宽状态变化与恢复断言。`05-06-ui-native-controls.log` 重验中，产品源码未因定位失败变更。

## 原生设置操作收敛

`05-06-ui-native-controls.log` 中 SettingsAcceptance 2 个中英文测试真实执行并通过（整轮另有英文系统通知分组失败，不能整轮称绿）。实际操作内嵌UISwitch并保持变化/恢复强断言；真实compact删除Sheet显示后点外部取消，图/树已导出，确认页两图实际查看。源码只读诊断未发现配置写入回滚：setter在await前发布配置，Demo不sync、不重建配置。最大辅助字号重验进行中，实际VoiceOver听辨尚未验证。

## 最大辅助字号真实操作与内容

系统content_size=accessibility-extra-extra-extra-large，`02-05-06-ui-large-verified.log` 两语Settings真实操作均过（62.814s/71.940s），删除compact Sheet最大字正文内部真实swipe之后，已实际查看D90722AC...截图：完整说明后半段 Real accounts are unaffected 可读，原生滚动条存在，未通过强制降低字号掩盖。普通/大字号图与native AX树已导出。实际VoiceOver音频与触控语音导航仍未录制，AX语义检查另行记录。
