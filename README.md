# TokenPulse

个人使用的 iPhone / Apple Watch 多账号套餐额度应用。支持 MiniMax 国内版、Claude、Codex、Z.ai 国际 Coding Plan 和 SuperGrok，包含关注排序、iCloud 同步、按窗口提醒及两端 Widget。

需要 iOS 17+、watchOS 10+；开发环境使用 Xcode 26.2 / Swift 6。

## 构建

打开 `TokenPulse.xcodeproj`，选择 `TokenPulse` scheme。工程包含 iPhone、Watch、iPhone Widget、Watch Widget 和 XCTest 五个 targets。

无需开发者签名的完整设备代码构建：

```sh
xcodebuild build -project TokenPulse.xcodeproj -target TokenPulse \
  -configuration Debug CODE_SIGNING_ALLOWED=NO \
  SYMROOT=/tmp/tokenpulse-products OBJROOT=/tmp/tokenpulse-objects
```

不要为上述多平台构建全局指定 `-sdk`，各 target 使用自身的 iOS 或 watchOS SDK。

已安装 Xcode 所需的 iOS/watchOS 模拟器组件后运行测试：

```sh
xcodebuild test -project TokenPulse.xcodeproj -scheme TokenPulse \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Keychain 测试需保留模拟器默认本地签名；不要在测试命令中设置 `CODE_SIGNING_ALLOWED=NO`。

## 使用

- MiniMax 国内版及 Z.ai 输入 Coding Plan Key；Claude 在应用内登录并选择组织；Codex 和 SuperGrok 使用设备授权。
- 在“账号设置”中选择及排序 Watch 关注账号，调整每个账号的告警阈值和独立重置提醒开关，并申请系统通知权限。
- “账号设置 → 同步”提供本机 iCloud 同步开关、立即同步、上次同步请求和上次收到云端更新的时间。关闭后保留本机和已同步数据；再次开启可继续同步。提交时间不表示 Watch 已收到，失败会显示原因且保留上次成功记录。
- Widget 只需选择账号：Codex/SuperGrok 汇总每周额度与本地格式重置时间，Z.ai（GLM）同时显示每周及 5 小时额度，MiniMax 桌面小组件显示 5 小时已用额度。旧数据超过预计重置时间显示待更新；不把不同周期额度相加。
- 真机部署需要在 Xcode 为所有 targets 配置同一开发团队及相应 App Groups、Keychain、iCloud KVS 能力。凭证只在应用界面输入，不进入版本库。

后台刷新与 Widget 更新遵循系统调度。两端离线时允许分别提醒。第三方非公开接入契约以及两端令牌轮换尚须真实账号验证，详见 [接入证据](docs/provider-integration.md) 和 [实现验收记录](docs/implementation-status.md)。
