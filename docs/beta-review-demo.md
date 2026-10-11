# TestFlight 演示模式

演示模式供首次体验与 App Review 使用，入口对所有用户可见，无需用户名、密码、API Key 或第三方订阅。它通过本地示例数据运行现有功能界面，不代表提供商的实时用量，也不用于验证真实授权或云端传输。

## 审核步骤

1. 打开 TokenPulse，在首次启动页面点击 **体验演示 / Try Demo**。已有账号时从 **设置 → 体验演示 / Try Demo** 进入。
2. 首页展示六家服务的示例账号，包含 Codex Plus 和 Pro。展开卡片查看各额度窗口、重置时间和套餐信息；下拉或点击账号刷新按钮更新示例用量。
3. 点击 **＋**，选择提供商、输入账号名称并保存，不需要真实凭证。通过 **Edit** 排序；左滑删除或进入 **设置 → 具体账号 → 删除账号**。
4. 在 **设置** 中开启通知，点击 **发送演示通知** 测试系统通知；在具体账号中修改额度告警、重置提醒和阈值。退出演示会取消尚未触发的演示提醒。
5. 在 iPhone 主屏幕添加 TokenPulse 小组件，编辑组件并选择带“演示”字样的账号。中、大尺寸组件可选择多个账号；锁屏组件也可选择演示账号。
6. 在 Apple Watch 打开 TokenPulse，从空白页或 **表盘设置** 点击 **体验演示 / Try Demo**。滑动查看账号、刷新额度；在 **表盘设置** 选择演示账号后添加 TokenPulse 复杂功能或智能叠放组件。Watch 演示独立启用，不要求 iCloud 登录。
7. 点击 iPhone 首页 **退出演示** 或 **设置 → 退出演示 / Exit Demo**；Watch 从 **表盘设置** 退出。真实账号恢复显示。

示例账号、配置与小组件数据独立存储。演示期间不上传 iCloud，也不要求审核员登录任何提供商。真实 iCloud 同步需要退出演示后使用自己的账号；系统通知和组件更新仍受系统权限与调度控制。

## 验证记录（2026-09-13）

- Xcode 26.2，iPhone 17 Pro / iOS 26.1 Simulator：完整 `TokenPulse` scheme 测试通过，103 项、0 失败，包含 4 项新增演示回归；iOS、watchOS 和两端 Widget targets 编译成功。
- 新增回归覆盖所有提供商及 Codex 两套餐、刷新、添加、删除、排序和提醒设置持久化、退出恢复真实账号和小组件数据、Watch 选择隔离、演示通知清理和停用后拒绝旧回调。
- 实际 iPhone 界面已验证：首次启动可见入口、一键进入、示例额度刷新（36% → 45%）、添加表单无需凭证、重启保留演示模式。
- 实际 Watch Ultra 3 / watchOS 26.2 Simulator 界面已验证：首次启动入口、进入演示、显示 MiniMax 示例额度。
- 模拟器 UI 自动化返回 `noWindowsAvailable` / `elementHasNoFrame`，未完成表单保存、通知弹出、组件放置和 Watch 滚动/退出的界面验收；相关数据行为有自动测试，不能替代完整实机验证。

本机测试日志：`/tmp/tokenpulse-demo-runtime-fixed2.log`；结果包：`/tmp/tokenpulse-demo-runtime-fixed2.xcresult`；界面截图：`/tmp/tokenpulse-demo-evidence/`。

## 构建上传记录（2026-09-13）

- 已上传 **0.1.0 (2026091321)**，App Store Connect 应用 ID `6809847584`。Apple 于 21:51:58（UTC+8）返回 `Upload succeeded`，命令结果 `EXPORT SUCCEEDED`。上传成功不代表处理完成或审核通过；尚未提交审核回复。
- Release 归档成功，iPhone、Watch 和两个 Widget 的构建号一致，四个包均通过签名验证。
- 上传时收到四个包缺少 dSYM 的警告。首次事后生成的文件仅有匹配 UUID、没有实际调试信息；后续已用 `2026091322` 归档生成、且 UUID 与原可执行文件一致的完整 dSYM 替换。项目 Release 配置已改为 `dwarf-with-dsym`。
- 归档：`/Users/admin/Library/Developer/Xcode/Archives/2026-09-13/TokenPulse-2026091321.xcarchive`。
- 日志：`/tmp/tokenpulse-release-2026091321-archive.log`、`/tmp/tokenpulse-release-2026091321-upload.log`。

### 完整符号构建 2026091322

- Apple 公开工具没有为已成功上传构建单独补传 dSYM 的入口；按[官方符号分发流程](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information)，重新归档并将符号随新构建上传。
- **0.1.0 (2026091322)** 已于 22:25:14（UTC+8）上传成功，`EXPORT SUCCEEDED`，没有 `Upload Symbols Failed` 警告。Apple 回执为包已进入处理；处理完成及审核状态尚未确认。
- 四个包签名、版本和 dSYM UUID 均验证通过，额外检查每份符号都包含 `DW_TAG_compile_unit`、`DW_TAG_subprogram`、`DW_AT_decl_line`；主应用含 88 个编译单元、9,064 个函数条目。符号 UUID 同时匹配 `2026091321`，已为旧本地归档保留完整符号。
- 新归档：`/Users/admin/Library/Developer/Xcode/Archives/2026-09-13/TokenPulse-2026091322.xcarchive`。
- 证据：`/tmp/tokenpulse-release-2026091322-archive.log`、`/tmp/tokenpulse-release-2026091322-upload.log`、`/tmp/tokenpulse-release-2026091322-symbol-verification.json`。

### 窗口翻转修复构建 2026092201

- **0.1.0 (2026092201)** 已于 2026-09-22 15:30:57（UTC+8）上传成功。Apple 返回 `Uploaded package is processing` 和 `Upload succeeded`，命令结果为 `EXPORT SUCCEEDED`，没有 `Upload Symbols Failed` 警告。
- 构建包含统一额度窗口翻转规则：没有 provider 周期 ID 时，重置时间推进超过 60 秒或用量下降至少 40 个百分点会重新武装额度阈值。
- iPhone、Watch 和两个 Widget 的版本均为 `0.1.0 (2026092201)`；四个可执行文件 UUID 均与对应 dSYM 匹配，归档签名验证通过。
- 归档：`/Users/admin/Library/Developer/Xcode/Archives/2026-09-22/TokenPulse-2026092201.xcarchive`。
- 证据：`/tmp/tokenpulse-release-2026092201-archive.log`、`/tmp/tokenpulse-release-2026092201-upload.log`。
- 上传完成后 App Store Connect 网页会话未登录，因此尚未从 TestFlight 页面确认 Processing 完成或测试组可用状态。

### Kimi Code 与 Widget 改版构建 2026092202

- **0.1.0 (2026092202)** 已于 2026-09-22 22:19:15（UTC+8）上传成功。Apple 返回 `Uploaded package is processing` 和 `Upload succeeded`，命令结果为 `EXPORT SUCCEEDED`，没有符号上传警告。
- 构建包含主屏幕 Widget 文字/横向进度条改版，以及 Kimi Code 国内版设备授权、额度查询、续期、演示数据和 Lobe Icons 渠道图标。
- 发布提交为 `65fb676`；隔离 worktree 完整 XCTest 148 项通过，0 失败。
- iPhone、Watch 和两个 Widget 的版本均为 `0.1.0 (2026092202)`；四个包签名有效，所有可执行文件 UUID 均与对应 dSYM 匹配。
- 归档：`/Users/admin/Library/Developer/Xcode/Archives/2026-09-22/TokenPulse-2026092202.xcarchive`。
- 证据：`/tmp/tokenpulse-release-2026092202-tests.log`、`/tmp/tokenpulse-release-2026092202-archive.log`、`/tmp/tokenpulse-release-2026092202-upload.log`、`/tmp/tokenpulse-release-2026092202-verification.json`。
- 上传成功表示 App Store Connect 已接收并开始处理；处理完成及测试组可用状态仍需在 TestFlight 页面确认。

### Provider 扩展构建 2026101101

- **0.1.0 (2026101101)** 已于 2026-10-11 20:35:51（UTC+8）上传成功。Apple 返回 `Uploaded package is processing`、`Upload succeeded`，命令结果为 `EXPORT SUCCEEDED`。
- 发布源码提交 `b63b700`，包含 78 个 provider；沿用该提交此前完整 XCTest 773 项通过、0 失败的结果，本次未重复运行测试。
- 本次 Release 归档成功；iPhone、Watch 和两个 Widget 的版本一致，四个包均通过签名验证，对应 dSYM UUID 全部匹配。上传日志没有符号上传失败警告。
- 归档：`/Users/wuzhaoyi/Library/Developer/Xcode/Archives/2026-10-11/TokenPulse-2026101101.xcarchive`。
- 证据：`/tmp/tokenpulse-release-2026101101-archive.log`、`/tmp/tokenpulse-release-2026101101-upload.log`、`/tmp/tokenpulse-release-2026101101-verification.json`。
- Apple 已接收并开始处理；尚未确认处理完成、测试组可用或外部测试审核状态。

## 提交说明

先完成新构建上传并选择该构建，再把下面的英文说明填写到 Beta App Review Information 的 Notes 中，并在审核消息中回复。不要把示例文字当作用户名或密码填写。不要在旧构建仍被审核时声称演示模式已经可用。

> Thank you for your feedback. The updated build includes a built-in demo mode that does not require an account, password, API key, or third-party subscription.
>
> On first launch, tap “体验演示 / Try Demo”. Alternatively, open Settings (“设置”) and tap “体验演示 / Try Demo”. The app displays clearly labeled sample accounts for all six supported providers, including Codex Plus and Pro.
>
> You can expand quota cards, refresh sample usage, add and delete demo accounts, reorder accounts using Edit, and configure quota alerts and reset reminders in Settings. Tap “发送演示通知” (Send Demo Notification) to test a system notification and allow notifications when prompted. To test widgets, add a TokenPulse widget and select an account whose name includes “演示” (Demo).
>
> The Apple Watch app also has its own “体验演示 / Try Demo” entry on the empty screen and in Watch Face Settings (“表盘设置”). You can browse and refresh sample accounts and select one for complications and widgets.
>
> Demo mode uses local sample data; it does not authenticate with third-party services or transfer demo data through iCloud. Tap “退出演示 / Exit Demo” to return to normal use. Please use the updated build for review.
