# Sol 首批集成验证

日期：2026-10-02。分支：feature/provider-expansion-sol。模型：6 个 gpt-6.1-sol 工作者与 root 集成者。

## 范围与结果

已实现并集成 01 智谱国内版、02 MiniMax 国际版、03 GitHub Copilot、09 Poe、10 Vercel AI Gateway、11 ElevenLabs、12 New API、40 StepFun。提供商枚举从 9 个扩展到 17 个；本轮新增 8 个，未把全部 69 张票标完成。

- 全部 238 项 XCTest 通过，0 failures；原有基线为 148 项。
- unsigned TokenPulse target build 成功，包含 iPhone App、Watch App、两端 Widget 与资产目录编译。
- 真实的本机回环 HTTP fixture 通过生产 GatewayProviderTransport 请求成功，未发送账号 Key 或 Cookie；不代表物理设备私网权限已验收。
- iPhone 17 Pro / iOS 26.5 演示界面已用 Simulator 的截图和可访问性树检查：ElevenLabs 字符单位、Poe points、Vercel 缺失明细、智谱与 MiniMax 地区名称、StepFun 到期/重置区分、New API 余额、Copilot 三项额度与套餐名；添加入口可打开。只使用示例数据，没有登录提供商。
- 63–69 的 7 份源码研究已保存，公开证据的哈希复核由研究组执行。各报告保留手机/Watch 真实验证条件。

## 实际执行命令

```sh
xcodebuild test -project TokenPulse.xcodeproj -scheme TokenPulse \
  -destination 'platform=iOS Simulator,id=DE50A540-0662-4C76-BF55-6EADDDEF7B68' \
  -derivedDataPath /tmp/tokenpulse-sol-tests \
  -resultBundlePath /tmp/tokenpulse-sol-release-validation.xcresult \
  -parallel-testing-enabled NO

xcodebuild build -project TokenPulse.xcodeproj -target TokenPulse \
  -configuration Debug CODE_SIGNING_ALLOWED=NO \
  SYMROOT=/tmp/tokenpulse-sol-products OBJROOT=/tmp/tokenpulse-sol-objects
```

结果日志：`/tmp/tokenpulse-sol-release-validation.log`、`/tmp/tokenpulse-sol-final-build.log`。测试结果包：`/tmp/tokenpulse-sol-release-validation.xcresult`。这些是本机临时验证产物，不是仓库携带的跨机器附件。

## 发现并修复的问题

- 运行时缺失及 SDK build 映射错误：安装 iOS 26.5 arm64 (23F73)，为 SDK 23F81a 配置当前 Xcode 的运行时映射；细节与恢复默认命令在团队记录。
- 原工程 PlatformTests 固定另一机器绝对路径，改为 SOURCE_ROOT 相对路径。
- 多个 provider 集成时补齐共享枚举、查询、Widget 与演示分支，保留每家凭证和单位语义。
- 修复 Swift 6 XCTest actor 隔离，使用独立 UserDefaults 实例和 Date 值捕获。
- Poe 小组件显示非货币积分；区域 scoped 窗口保留详情，无限额度不显示伪造有限计数。
- ElevenLabs 极大重置时间溢出回归先失败后修复；解析边界和提醒规划均保护时间转换。
- Copilot 百分比完整但计数缺失的窗口得以保留；数字不能冒充布尔状态。两项回归先失败再修复，全套通过。
- StepFun 畸形响应不能清除旧套餐；关闭/切站取消登录验证，Cookie 读取完成后发送请求前重查当前会话。
- 云端合并按最终配置的凭证身份筛选快照和提醒记录，旧设备迟到数据不覆盖新账号；新快照先到、Keychain 仍旧时保留正确缓存。
- 启动时没有数据变更不重写真实存储，演示往返和取消刷新原有回归重新通过。Token 数量使用浮点容差断言；货币保持 Decimal 精确断言。

## 尚未验收

真实账号授权及 provider 当前兼容性、真实凭证失效和续期、iCloud Keychain 跨设备到达、物理 Watch 在手机离线时独立刷新、物理设备私网权限与可达性，以及各尺寸小组件/表盘的系统级完整验收。模拟器截图、响应 fixtures 和 unsigned build 不替代这些证据。

首批票均为 implemented-awaiting-real-validation，研究票为 awaiting-validation；后继票没有绕过真实依赖门槛启动。
