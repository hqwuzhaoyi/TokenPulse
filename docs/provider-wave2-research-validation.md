# 16、17、24、25 最终静态验证

2026-10-02，工作分支 `sol/wave2-research`。四票各自有入口/客户端、持久化与同步路由、Demo/Widget/Icon、专属测试和说明；状态均为 implemented-awaiting-validation。中央 README/manifest/CONTEXT 未修改。

提供商提交：Command Code `cd35867`、Amp `cba5637`、GitKraken `2e180b9`、Hugging Face `39c332c`；Command Code/Amp 身份绑定修正 `6e16271`。共享日期精度 `0ce7a70` 供 Amp 使用。混合钱包/独立提醒、continuous 与可选 Decimal counts 使用团队共享提交，不作为本组再次交付。

最后跟进 DecimalQuotaCounts 后，Command Code 实际USD限额与Amp美元/Orb小时保存完整 Decimal exactCounts；百分比只作Double显示/告警，旧Double数量保持兼容。CommandCode新增第8个测试方法，四provider共27个；另有本组day精度3个、共享Decimal counts3个测试方法。

实际通过的检查：

- 所有 TokenPulse app Swift source：Swift6、arm64 iOS Simulator SDK、emit-module，包含完整UI语义；没有用parse代替。
- 四provider + QuotaDatePrecision + DecimalQuotaCounts 六个完整XCTest文件：对已生成测试可见App module进行Swift6 semantic typecheck。
- 所有App支持源（排除App的@main）加完整iPhone Widgets源：Swift6 module emit通过。
- 从PBX实际Watch target的sources phase解析44个源文件，使用watchsimulator SDK、arm64 watchOS10 target进行Swift6 module emit通过。
- PBX `plutil -lint`、`git diff --check`；四套SVG明确尺寸、无currentColor、preserves-vector-representation和template intent检查通过。资产目录实际编译仍待unsigned target build。

临时日志在 `/tmp/tokenpulse-wave2-research-check/`，包括 `decimal-adaptation-app-typecheck.log`、`decimal-adaptation-all-tests-typecheck.log`、`related-widget-source-typecheck.log`、`watch-target-source-typecheck.log`。这是编译器语义检查，不是XCTest执行、链接或完整目标构建。

没有执行xcodebuild、启动模拟器、发起外部登录或读取用户Token/Keychain/CLI凭证。没有真实账号/实际iPhone/Watch/iCloud查询或通知证据。root集中执行完整测试与unsigned App/Widgets/Watch build；当前API compatibility、真实金额/单位/组织授权、续期或撤销、配置分批同步、物理Watch手机离线直连、组件视觉与真实提醒均保留未验收。
