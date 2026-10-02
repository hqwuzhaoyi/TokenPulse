# TokenPulse

在 iPhone 和 Apple Watch 上查看多个 AI 服务账号的套餐额度与 API 钱包余额，支持设备独立刷新、额度与低余额提醒、桌面小组件。

> **原参考仓库：[qunqin24/Pulse](https://github.com/qunqin24/Pulse)**
>
> TokenPulse 的产品设计、提供商接入研究及渠道图标参考了 Pulse，并实现了面向 iOS / watchOS 的原生应用。接入研究的参考版本为 [8d7fd60](https://github.com/qunqin24/Pulse/tree/8d7fd60454ce383dd0a136a30790c1e277f8069b)。

## 功能

- **多提供商、多账号**：Claude、ChatGPT/Codex、OpenCode Go、Z.ai 国际版、智谱国内版、MiniMax 国内／国际版、SuperGrok、Qoder 国际版、DeepSeek、Kimi Code 国内版、Poe、Vercel AI Gateway、ElevenLabs、StepFun、New API 与 GitHub Copilot。
- **独立查询**：iPhone 和 Watch 各自向提供商查询；Watch 获取配置及凭证后，无需手机代查额度。
- **账号管理**：首页通过 Edit 拖动账号卡片排序；左滑卡片或进入账号设置可删除账号，清理凭证、额度和提醒，并通过 iCloud 同步删除结果。Watch 同步全部账号，每个账号保留独立额度窗口。
- **同步控制**：iCloud 同步开关、手动同步、最近同步时间、失败提示；点击同步时图标旋转反馈。
- **额度告警**：提供应用级通知开关；默认阈值为 80%、95%、100%，按提供商和套餐的可通知窗口判断，多个窗口同时触发时合并提醒。
- **重置提醒**：仅为已有实际用量的可通知窗口预排系统通知；到时后旧数据标记“待更新”。
- **额度小组件与表盘入口**：iPhone 主屏幕使用文字与横向进度条展示额度；锁屏及 Watch 表盘四角、圆形、矩形、行内复杂功能和智能叠放保留原有展示，均保留渠道图标。
- **数据状态**：保留上次成功数据、采集时间和查询失败提示，重置时间按设备地区与时区显示。

## 提供商与登录方式

| 提供商 | 登录方式 | 桌面小组件主要内容 |
| --- | --- | --- |
| Claude | 应用内网页登录，选择组织 | 服务返回的额度窗口 |
| ChatGPT / Codex | 设备码授权 | Plus 显示 5 小时与每周已用；Pro 显示每周已用，详情附 Spark 额度 |
| OpenCode Go | API Key | 5 小时、每周与每月已用 |
| Z.ai / GLM | 国际 Coding Plan Key | 每周已用与 5 小时已用 |
| MiniMax 国内版 | Coding Plan Key | **5 小时已用额度** |
| SuperGrok | 设备码授权 | 每周已用与重置时间 |
| Qoder 国际版 | 浏览器设备授权 | 个人额度与组织资源包，分别展示 |
| DeepSeek | API Key | 所选币种的 API 钱包余额 |
| 智谱国内版 | 国内 Coding Plan Key | 服务返回的额度窗口，含 MCP |
| MiniMax 国际版 | 国际 Coding Plan Key | 服务返回的短周期与每周额度 |
| Kimi Code 国内版 | 设备码授权 | 5 小时、每周、每月及加量余额 |
| Poe | API Key | 剩余 points，非货币积分 |
| Vercel AI Gateway | AI Gateway API Key | USD 可用余额 |
| StepFun | 应用内网页登录，选择国内／国际站 | Token Plan 积分或 Coding Plan 窗口 |
| ElevenLabs | 具备 user_read 权限的 API Key | 账期字符额度与重置时间 |
| New API | 每账号服务器地址与网关 Key（公网 HTTPS／私网 HTTP） | 明确币种的钱包余额；无限 Key、Token 或未知单位按原意展示 |
| GitHub Copilot | GitHub 设备码授权（read:user） | Premium requests、Chat、Completions，按实际套餐分别显示 |

DeepSeek 直接展示 API 返回的币种与金额，不做汇率换算；详情包含总可用、赠送和充值余额。账号设置可选择概览及提醒币种，低余额默认阈值为 CNY 10 元或 USD 2 美元，可修改。持续低余额只提醒一次，余额恢复后再次降低才重新提醒；余额不足以调用 API 时也会提醒，并合并同次通知。钱包不显示已用百分比或周期重置时间。

New API 每个账号可配置不同的网关（公网 HTTPS，明确的私网地址可用 HTTP），地址末尾的 `/v1` 会自动移除；更新地址或 Key 后会清除旧余额和提醒身份。公共 `/api/status` 请求不携带 Key。USD/CNY 余额支持低余额提醒，TOKENS、CUSTOM 或未知币种不会被当作货币；不会用历史充值总量推断套餐百分比。私网连接的系统权限、iPhone/Watch 实机可达性、iCloud Keychain 到达和真实 Key 失效尚待验收。

Qoder 采用参考项目的非公开接口。设备凭证的自动续期不可用，源码核验与真实账号验证边界见 [提供商接入说明](docs/provider-integration.md)。到期时间只表示到期，不推断额度已重置。

Copilot 授权页会显示 VS Code / Copilot 客户端身份，TokenPulse 使用该公开客户端进行非官方接入。只请求 `read:user`，无需粘贴 `gh` 或其他应用的 token。额度查询使用非公开内部接口；未发放项省略，无限项显示“无限”，超额付费与耗尽分别显示。凭证失效后可从账号设置重新授权，详见 [接入与验证边界](docs/provider-integration.md#github-copilot)。

小、中、大组件都从主屏幕已配置账号列表中选择，分别最多选择 1、2、4 个具体账号，选择顺序就是展示顺序。中尺寸按账号分栏并对齐额度信息；大尺寸按账号纵向排列，每个账号的额度周期横向并列。每个账号的额度周期分别以文字和横向进度条显示，并保留各自的重置或到期时间，各周期用量不会相加。钱包余额、无限额度及未提供的用量不绘制百分比进度条。Codex 与 SuperGrok 的可手动重置次数属于账号级信息，只显示一次；没有可信字段时显示“未提供”。

Codex 套餐根据额度响应中的 `plan_type` 识别为 Plus 或 Pro；缺失或未知值显示为未提供，不自行猜测。Codex 的手动重置次数读取接口的 `rate_limit_reset_credits.available_count`，仅展示，不消耗重置次数。提供商没有返回的指标显示“未提供”，不会默认为 0；SuperGrok 的手动重置次数目前没有核实的对应字段。

## 开始使用

无需服务账号即可在首次启动页点击 **体验演示 / Try Demo**，也可从 **设置** 进入。演示模式提供各家服务及 Codex Plus / Pro 示例，支持刷新、添加、排序、删除、提醒设置和小组件。示例数据与真实账号隔离，不连接第三方服务或同步到 iCloud；点击 **退出演示** 恢复真实账号。Watch 可在空白页或 **表盘设置** 中独立进入演示。

1. 打开 iPhone 上的 TokenPulse，点击右上角 **＋**，选择提供商并完成登录或输入 Key。
2. 需要调整顺序时，点击首页左上角 **Edit** 并拖动账号卡片，编辑期间收起详情并关闭点击展开。删除时左滑卡片露出 **删除** 按钮，点击并确认后移除；也可进入 **设置 → 具体账号 → 删除账号**。在 **设置** 中打开通知，并按账号配置提醒类型和阈值。
3. 在 **账号设置 → 同步** 中开启 iCloud 同步，或点击“立即同步”。
4. 安装并打开 Watch 端，等待配置到达后刷新额度；在右上角 **表盘设置** 中选择表盘要显示的账号。
5. 添加 iPhone 小组件；手表上可长按表盘，进入 **编辑 → 复杂功能 → TokenPulse 额度**。

Apple Watch 首次启动会自动请求系统通知权限；允许后额度告警和重置提醒默认开启，不需要在 Watch App 内单独配置。

同步开关控制本机主动同步，关闭后保留本机及已同步数据。右侧时间表示本机最近一次成功提交或收到云端更新的时间，不代表 Watch 已收到。

## 构建与真机安装

环境：**iOS 17+、watchOS 10+、Xcode 26.2 / Swift 6**。工程包含 iPhone App、Watch App、两端 Widget 和 XCTest 五个 targets。

```sh
git clone https://github.com/hqwuzhaoyi/TokenPulse.git
cd TokenPulse
open TokenPulse.xcodeproj
```

使用自己的开发账号部署时：

1. 在 Xcode 的 **Settings → Apple Accounts** 登录账号。
2. 为所有 targets 选择同一开发团队，并配置 App Groups、Keychain Sharing 和 iCloud Key-Value Storage。
3. 替换项目中的开发用团队及共享组标识；`PlatformConstants.swift` 与两端 entitlements 中的 App Group 必须一致。
4. 连接并信任 iPhone，开启开发者模式，选择 `TokenPulse` scheme 运行。
5. 手表先与 iPhone 配对，再连接到 Xcode、开启开发者模式；选择 `TokenPulseWatch` scheme 和实体手表运行，确保签名配置包含该手表。

只验证完整工程编译、不进行真机签名：

```sh
xcodebuild build -project TokenPulse.xcodeproj -target TokenPulse \
  -configuration Debug CODE_SIGNING_ALLOWED=NO \
  SYMROOT=/tmp/tokenpulse-products OBJROOT=/tmp/tokenpulse-objects
```

多平台构建不要全局指定 `-sdk`，各 target 使用自己的 iOS 或 watchOS SDK。

## 测试与验证状态

安装所需的 iOS/watchOS 模拟器组件后：

```sh
xcodebuild test -project TokenPulse.xcodeproj -scheme TokenPulse \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Keychain 测试需要模拟器默认本地签名，测试时不要设置 `CODE_SIGNING_ALLOWED=NO`。

- 已有 **238 项自动测试**，覆盖账号隔离、删除与排序、展开布局、持久化、提供商契约、授权恢复、同步控制、提醒规则、小组件数据选择，以及演示模式的数据与通知隔离。
- 本轮 unsigned App / Watch / Widgets 完整构建及 iPhone 模拟器测试通过；既有版本的 iOS/watchOS 签名构建、iPhone 真机安装与启动曾通过。
- 用户已反馈 MiniMax 与 GLM 真实查询成功，Watch App 可启动。
- 新增 8 个提供商及其余未验证接入的真实账号、双端凭证续期、iCloud 到达、后台通知与各类小组件仍需完整实机验收；本轮记录见 [provider 扩展验证](.scratch/provider-expansion/validation-record.md)。

详细范围与证据见 [实现验收记录](docs/implementation-status.md) 和 [提供商接入说明](docs/provider-integration.md)。

## 数据与运行边界

凭证保存在 Keychain 中，账号配置和额度快照单独保存；无需自建查询服务器或 Mac 常驻采集进程。

后台刷新、iCloud 传送和 Widget 更新由系统调度，不保证固定间隔或即时到达。当前配置同步使用 iCloud，尚未接入 WatchConnectivity 手机直传通道。设备离线或同步延迟时可能分别发出通知。

部分提供商使用非公开客户端接口，接口变化可能影响登录和额度查询。预计重置时间到达只会让旧数据进入“待更新”，不会据此宣称额度已经恢复。

## 许可证

除单独标注许可的第三方资源外，TokenPulse 的代码采用 **[Apache License 2.0](LICENSE)**。

版权及来源说明见 [NOTICE](NOTICE)。渠道图标分别保留 Lobe Icons 的 MIT 许可与 Vercel 官方资源的 Apache-2.0 许可，完整条款见 [ProviderIconNotices.txt](TokenPulse/Resources/ProviderIconNotices.txt)。

## 致谢与参考

- **[Pulse 原仓库](https://github.com/qunqin24/Pulse)**：产品体验、提供商接入研究与渠道图标的参考来源。
- **[Lobe Icons](https://github.com/lobehub/lobe-icons)**：渠道矢量标识，经 Pulse 引入；许可及改动说明见 [ProviderIconNotices.txt](TokenPulse/Resources/ProviderIconNotices.txt)。
- **[OpenAI Codex](https://github.com/openai/codex)**：设备授权与剩余手动重置次数的接口依据。

品牌名称及标识归各自权利人所有，其使用仅用于识别兼容服务。

## 项目文档

- [功能规格](docs/spec.md)
- [各提供商额度展示与通知设计](docs/quota-source-design.md)
- [OpenCode Go Provider 接入研究](docs/opencode-provider-research.md)
- [Claude Fable 额度研究](docs/claude-fable-research.md)
- [领域术语](CONTEXT.md)
- [设备独立刷新设计](docs/adr/0001-device-side-refresh.md)
- [TestFlight 演示模式审核说明](docs/beta-review-demo.md)
- [任务清单](openspec/changes/ios-watch-quota-monitor/tasks.md)
