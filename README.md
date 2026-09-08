# TokenPulse

在 iPhone 和 Apple Watch 上查看多个 AI 订阅账号的套餐额度，支持设备独立刷新、额度提醒与桌面小组件。

> **原参考仓库：[qunqin24/Pulse](https://github.com/qunqin24/Pulse)**
>
> TokenPulse 的产品设计、提供商接入研究及渠道图标参考了 Pulse，并实现了面向 iOS / watchOS 的原生应用。接入研究的参考版本为 [8d7fd60](https://github.com/qunqin24/Pulse/tree/8d7fd60454ce383dd0a136a30790c1e277f8069b)。

## 功能

- **多提供商、多账号**：Claude、ChatGPT/Codex、Z.ai 国际 Coding Plan（GLM）、MiniMax 国内版与 SuperGrok。
- **独立查询**：iPhone 和 Watch 各自向提供商查询；Watch 获取配置及凭证后，无需手机代查额度。
- **账号顺序**：首页通过 Edit 拖动账号卡片排序；Watch 同步全部账号，每个账号保留独立额度窗口。
- **同步控制**：iCloud 同步开关、手动同步、上次提交与接收时间、失败提示。
- **额度告警**：提供应用级通知开关；默认阈值为 80%、95%、100%，按账号配置，多个窗口同时触发时合并提醒。
- **重置提醒**：显示预计重置时间，支持预排系统通知；到时后旧数据标记“待更新”。
- **小组件与表盘入口**：iPhone 主屏幕、锁屏，以及 Watch 表盘复杂功能和智能叠放。
- **数据状态**：保留上次成功数据、采集时间和查询失败提示，重置时间按设备地区与时区显示。

## 提供商与登录方式

| 提供商 | 登录方式 | 桌面小组件主要内容 |
| --- | --- | --- |
| Claude | 应用内网页登录，选择组织 | 服务返回的额度窗口 |
| ChatGPT / Codex | 设备码授权 | 每周已用、重置时间、剩余手动重置次数 |
| Z.ai / GLM | 国际 Coding Plan Key | 每周已用与 5 小时已用 |
| MiniMax 国内版 | Coding Plan Key | **5 小时已用额度** |
| SuperGrok | 设备码授权 | 每周已用与重置时间 |

小组件只需选择账号，所需周期在同一个组件内展示，各周期用量不会相加。小尺寸表盘入口显示精简摘要。

Codex 的手动重置次数读取接口的 `rate_limit_reset_credits.available_count`，仅展示，不消耗重置次数。提供商没有返回的指标显示“未提供”，不会默认为 0；SuperGrok 的手动重置次数目前没有核实的对应字段。

## 开始使用

1. 打开 iPhone 上的 TokenPulse，点击右上角 **＋**，选择提供商并完成登录或输入 Key。
2. 需要调整顺序时，点击首页左上角 **Edit** 并拖动账号卡片；在 **设置** 中打开通知，并按账号配置提醒类型和阈值。
3. 在 **账号设置 → 同步** 中开启 iCloud 同步，或点击“立即同步”。
4. 安装并打开 Watch 端，等待配置到达后刷新额度。
5. 添加 iPhone 小组件；手表上可长按表盘，进入 **编辑 → 复杂功能 → TokenPulse 额度**。

同步开关控制本机主动同步，关闭后保留本机及已同步数据。“上次同步请求”表示本机提交成功，不代表 Watch 已收到；“上次收到云端更新”单独记录数据到达。

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

- 已有 **69 项自动测试**，覆盖账号隔离、持久化、提供商契约、授权恢复、同步控制、提醒规则和小组件数据选择。
- 完整 iOS/watchOS 签名构建、iPhone 真机安装与启动已通过。
- 用户已反馈 MiniMax 与 GLM 真实查询成功，Watch App 可启动。
- 其余提供商真实接入、双端凭证续期、iCloud 到达、后台通知及各类小组件仍需完整实机验收。

详细范围与证据见 [实现验收记录](docs/implementation-status.md) 和 [提供商接入说明](docs/provider-integration.md)。

## 数据与运行边界

凭证保存在 Keychain 中，账号配置和额度快照单独保存；无需自建查询服务器或 Mac 常驻采集进程。

后台刷新、iCloud 传送和 Widget 更新由系统调度，不保证固定间隔或即时到达。当前配置同步使用 iCloud，尚未接入 WatchConnectivity 手机直传通道。设备离线或同步延迟时可能分别发出通知。

部分提供商使用非公开客户端接口，接口变化可能影响登录和额度查询。预计重置时间到达只会让旧数据进入“待更新”，不会据此宣称额度已经恢复。

## 许可证

除单独标注许可的第三方资源外，TokenPulse 的代码采用 **[Apache License 2.0](LICENSE)**。

版权及来源说明见 [NOTICE](NOTICE)。渠道图标保留 Lobe Icons 的 MIT 许可，完整条款见 [ProviderIconNotices.txt](TokenPulse/Resources/ProviderIconNotices.txt)。

## 致谢与参考

- **[Pulse 原仓库](https://github.com/qunqin24/Pulse)**：产品体验、提供商接入研究与渠道图标的参考来源。
- **[Lobe Icons](https://github.com/lobehub/lobe-icons)**：渠道矢量标识，经 Pulse 引入；许可及改动说明见 [ProviderIconNotices.txt](TokenPulse/Resources/ProviderIconNotices.txt)。
- **[OpenAI Codex](https://github.com/openai/codex)**：设备授权与剩余手动重置次数的接口依据。

品牌名称及标识归各自权利人所有，其使用仅用于识别兼容服务。

## 项目文档

- [功能规格](docs/spec.md)
- [领域术语](CONTEXT.md)
- [设备独立刷新设计](docs/adr/0001-device-side-refresh.md)
- [任务清单](openspec/changes/ios-watch-quota-monitor/tasks.md)
