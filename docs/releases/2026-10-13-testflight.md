# TestFlight 0.1.0（2026101301）

状态：发布完成。构建 VALID，Beta 审核 APPROVED，Internal Beta 与 Public Beta 均 IN_BETA_TESTING。

## 源码与变更

- `703c367`：简体中文/英文国际化、Codex 重置预告、Provider 选择及相关 Watch/Widget 显示修复，包含工单与可复用验收源码。
- `f13cd48`：声明仅使用系统加密能力，避免 TestFlight 停留在缺少出口合规说明。IPA 源码固定于此提交。
- App、Watch 和两个 Widget 版本统一为 `0.1.0 (2026101301)`。
- 二进制未包含测试日志、录像、截图、xcresult 或本地密钥；本地原始验收产物不进入版本控制。

## 验证

沿用本次功能验收：此前 798 XCTest + 33 Swift Testing 完整回归通过；最后修改通过 29 项 Platform/WatchPresentation 行为回归与 2 项长金额可视 OCR 回归。四产品 Debug/Release 构建以及双语模拟器系统宿主已验收。VoiceOver 听辨由用户明确豁免，水平 swipe 未获可靠工具输入的限制仍留在国际化验收记录，未声称测试通过。

本次重新完成设备 Release archive。四个产品的版本、签名、中英文资源和 dSYM UUID 已逐项验证；导出 IPA 内含 `Symbols`，iPhone 与 Watch 的 `ITSAppUsesNonExemptEncryption` 为 false。代码核查使用 URLSession HTTPS、系统 Keychain 与 Apple CryptoKit 的 SHA-256/HMAC，没有引入第三方或自有加密算法实现。此声明依据 [Apple 的加密文档要求](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption)，未来加密用途变化时需重新核查。

## 构建与上传

- App Store Connect App ID：`6809847584`，Bundle ID：`com.tokenpulse.app`。
- Archive：`/Users/wuzhaoyi/Library/Developer/Xcode/Archives/2026-10-13/TokenPulse-2026101301.xcarchive`。
- IPA：`/tmp/tokenpulse-release-2026101301-export/TokenPulse.ipa`，15,394,227 bytes。
- IPA SHA-256：`261f98e8de4a9b9c76bcfbeb84f38bcce6f64a64fb1283fd54bff9a0622a3b3c`。
- `asc 5.14.1`，System Keychain 中的 TokenPulse profile；未使用明文仓库凭据。
- 实际上传记录：`726c0728-27cf-40b3-97ff-7e6e2ae4e6ba`，Apple 接收时刻 `2026-10-13 19:39:04 +08:00`。
- 初次 `publish --upload-only --test-notes` 被 CLI 参数检查拒绝，未作为上传成功计入；改为先上传、处理完成后单独配置测试说明。
- 已更新 Beta 审核的免登录演示说明，保留既有联系信息。

本机日志及核查结果：`/tmp/tokenpulse-release-2026101301-archive-final.log`、`/tmp/tokenpulse-release-2026101301-export.log`、`/tmp/tokenpulse-release-2026101301-verification.json`、`/tmp/tokenpulse-release-2026101301-asc-upload.json`、`/tmp/tokenpulse-release-2026101301-asc-upload.log`。原始 API 返回与联系人数据保留在临时目录，不纳入本记录。


## 最终分发结果

- Build ID：`726c0728-27cf-40b3-97ff-7e6e2ae4e6ba`，处理状态 `VALID`，`usesNonExemptEncryption=false`。
- Beta 审核状态：`APPROVED`；内部与外部状态均为 `IN_BETA_TESTING`。
- Internal Beta：`a737baff-4811-41d6-a89b-41eecc07ec95`，沿用全部构建自动访问设置。显式添加被 Apple 以 HTTP 422 拒绝；随后回读确认此组已有该构建访问权限，无需更改其设置。
- Public Beta：`223db017-c484-4fad-8f7c-f5b115056f49`，添加成功并提交 Beta 审核，随后回读批准状态；组关联最终核对为2组且complete=true。
- 中英文 What to Test 均已保存，审核说明明确可使用免登录演示模式。
- 公测安装：[TestFlight](https://testflight.apple.com/join/jrHbrKmH)。沿用现有公开链接，没有新增测试员或手动发送通知。
- 最终状态证据：`/tmp/tokenpulse-release-2026101301-distribution-final.json`、`/tmp/tokenpulse-release-2026101301-beta-review-final.json`、`/tmp/tokenpulse-release-2026101301-groups-final.json`、`/tmp/tokenpulse-release-2026101301-test-notes.json`。

Git 提交完成，本次未执行远端 push。此次发布是 TestFlight，不包含正式 App Store 上架操作。
