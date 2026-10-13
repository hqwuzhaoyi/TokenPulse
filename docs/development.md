# 构建与测试

[中文首页](../README.md) · [English](../README.en.md)

## 环境

- Xcode 26.x / Swift 6；最低 iOS 17、watchOS 10。
- 工程包含 iPhone App、Watch App、两端 Widget 和 XCTest targets。
- 模拟器验证需要安装对应的 iOS / watchOS runtime。

## 本地运行

```sh
git clone https://github.com/hqwuzhaoyi/TokenPulse.git
cd TokenPulse
open TokenPulse.xcodeproj
```

1. 在 Xcode 的 **Settings → Apple Accounts** 登录自己的开发账号。
2. 为各 target 选择同一开发团队，配置 App Groups、Keychain Sharing 和 iCloud Key-Value Storage。
3. 使用自己的 Bundle ID 和共享组标识。`PlatformConstants.swift` 与两端 entitlements 中的 App Group 必须一致；授权回调配置也应与 Bundle ID 对应。
4. 选择 `TokenPulse` scheme 和 iPhone 模拟器运行。安装到真机时，先连接并信任设备、开启开发者模式。
5. Watch 真机需先与 iPhone 配对，再连接 Xcode、开启开发者模式，使用 `TokenPulseWatch` scheme 运行。

## 构建

验证完整工程编译、不进行真机签名：

```sh
xcodebuild build -project TokenPulse.xcodeproj -target TokenPulse \
  -configuration Debug CODE_SIGNING_ALLOWED=NO \
  SYMROOT=/tmp/tokenpulse-products OBJROOT=/tmp/tokenpulse-objects
```

多平台构建不要全局指定 `-sdk`，各 target 使用自己的 iOS 或 watchOS SDK。

## 测试

先用 `xcrun simctl list devices available` 确认本机设备，再替换下面的模拟器名称：

```sh
xcodebuild test -project TokenPulse.xcodeproj -scheme TokenPulse \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Keychain 测试需要模拟器本地签名，不要设置 `CODE_SIGNING_ALLOWED=NO`。

需要免登录体验时，使用应用内的 **体验演示 / Try Demo**。示例数据与真实账号隔离，不连接第三方服务或通过 iCloud 传送。

## 更多文档

- [Provider 列表与登录要求](providers.md)
- [接入契约与验证边界](provider-integration.md)
- [额度展示与提醒规则](quota-source-design.md)
- [领域术语](../CONTEXT.md)
- [设备独立刷新设计](adr/0001-device-side-refresh.md)
- [国际化验收记录](../.scratch/internationalization/10-final-acceptance-summary.md)
- [TestFlight 发布记录](releases/2026-10-13-testflight.md)
- [演示模式审核说明](beta-review-demo.md)
