# Sol 团队执行记录

启动日期：2026-10-02。用户要求创建 Sol teams 开始实施；6 个工作者使用 gpt-6.1-sol，独立 worktree 开发，root 统一集成。集成分支：feature/provider-expansion-sol。

| 工作者 | 分支 | 首批票 | 交付 |
| --- | --- | --- | --- |
| sol_regional | sol/regional | 01、02 | 智谱国内版与 MiniMax 国际版 |
| sol_wallet | sol/wallet | 09、10 | Poe、Vercel 与可缺失的钱包明细 |
| sol_copilot | sol/copilot | 03 | Copilot 设备授权及额度 |
| sol_gateway | sol/gateway | 12 | New API 与账号级网关地址 |
| sol_web | sol/web | 40 | StepFun 与隔离的网页登录 |
| root | feature/provider-expansion-sol | 11 | ElevenLabs、共享集成与串行验证 |
| sol_research | sol/research | 63–69 | 七家移动端独立查询可行性 |

工作树位于工作区旁的 TokenPulse-sol 目录。各组可在自己的工作树修改共享 switch，由 root 集成；Xcode 构建、模拟器测试串行调度，避免平台服务与输出目录冲突。

## 共享契约

- 钱包明细允许缺失，旧 DeepSeek 存档兼容；货币与 points 明确区分。
- 服务器地址与凭证绑定到具体服务账号；更换身份不能复用旧数据或提醒状态。
- 网页会话按账号隔离，保持 Claude 现有登录能力。
- 真实账号与物理 Watch 未验收的条目保留未勾选，不宣称已完成。

## 构建基线

- 原始代码 unsigned TokenPulse target 构建失败：资产编译要求 iOS 26.5 SDK 兼容运行时，机器仅安装 iOS 26.4 (23E244)。Xcode 26.6 / iOS SDK 26.5；watchOS 26.5 运行时已就绪。
- 已安装 iOS 26.5 arm64 (23F73) 运行时。SDK 实际补丁版本为 26.5.1 (23F81a)，Xcode 没有提供 26.5.1 运行时下载；使用 simctl 支持的运行时映射将当前 iphoneos26.5 / SDK build 23F81a 绑定到 23F73。原始代码完整 unsigned target 构建已通过（/tmp/tokenpulse-sol-baseline-matched.log）。如需恢复默认映射：`xcrun simctl runtime match set iphoneos26.5 --default --sdkBuild 23F81a`。

## 状态含义

in-progress 表示正在开发。实现通过自动检查后仍需保留真实账号、物理设备验证缺口；依赖票没有完成前不自动领取后继票。

## 基线及首批集成

- 测试工程原有 PlatformTests 引用另一机器绝对路径，已改为 SOURCE_ROOT 相对路径；原有 148 项 XCTest 全部通过（iPhone 17 Pro / iOS 26.5，结果 /tmp/tokenpulse-sol-baseline-portable-tests.xcresult）。
- 首批代码已合入：01、02、03、09、10、11、12、40；研究 63–69 报告已合入，均保留真实验证缺口。
- 交叉检查发现并处理 points 小组件货币标题、区域窗口详情丢字段、无限额度显示有限计数、异常重置时间转换溢出。ElevenLabs 极大时间戳回归测试先失败后修复，完整回归已通过。
- 集成时补齐 New API widget switch；三处 Swift 6 测试值跨 actor 传递／捕获已调整。未用 unchecked Sendable 绕过检查。
- 跨凭证身份 iCloud 合并／缓存保留、StepFun 畸形响应与登录取消修复已合入；私网 HTTP 的代码、ATS 和本机 fixture 已通过集成测试。

## 首批收束

- 238 项 XCTest 全部通过，0 failures；最终 unsigned 全 target 构建成功。
- iPhone 17 Pro / iOS 26.5 演示模式卡片已做原生截图/可访问性检查，真实账号与物理 Watch 验收未执行。
- 首批 8 张为 implemented-awaiting-real-validation；7 张研究票为 awaiting-validation；剩余 54 张保持 ready-for-agent，其中 29 张无阻塞。
- 工作者首批交付与交叉检查已结束；后继票保留原依赖门槛。完整命令、发现和限制见[统一验证记录](validation-record.md)。
