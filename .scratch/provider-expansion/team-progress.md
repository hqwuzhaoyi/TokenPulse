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

`implemented-awaiting-real-validation` 表示代码已集成但整票未通过真实验收；`awaiting-validation` 表示研究已交付但实际可行性未通过。`ready-for-agent` 是票据准备状态，有未完成 blockers 时仍不可领取。自动测试、unsigned build、静态语义检查和真实账号/物理设备证据分别记录，不互相替代。

## 基线及首批集成

- 测试工程原有 PlatformTests 引用另一机器绝对路径，已改为 SOURCE_ROOT 相对路径；原有 148 项 XCTest 全部通过（iPhone 17 Pro / iOS 26.5，结果 /tmp/tokenpulse-sol-baseline-portable-tests.xcresult）。
- 首批代码已合入：01、02、03、09、10、11、12、40；研究 63–69 报告已合入，均保留真实验证缺口。
- 交叉检查发现并处理 points 小组件货币标题、区域窗口详情丢字段、无限额度显示有限计数、异常重置时间转换溢出。ElevenLabs 极大时间戳回归测试先失败后修复，完整回归已通过。
- 集成时补齐 New API widget switch；三处 Swift 6 测试值跨 actor 传递／捕获已调整。未用 unchecked Sendable 绕过检查。
- 跨凭证身份 iCloud 合并／缓存保留、StepFun 畸形响应与登录取消修复已合入；私网 HTTP 的代码、ATS 和本机 fixture 已通过集成测试。

## 首批收束（历史基线 6c12386）

- 238 项 XCTest 全部通过，0 failures；最终 unsigned 全 target 构建成功。
- iPhone 17 Pro / iOS 26.5 演示模式卡片已做原生截图/可访问性检查，真实账号与物理 Watch 验收未执行。
- 当时首批 8 张为 implemented-awaiting-real-validation；7 张研究票为 awaiting-validation；剩余 54 张未实施，其中 29 张无前置阻塞。这29张随后进入第二批，不能继续沿用该历史剩余数描述当前状态。
- 工作者首批交付与交叉检查已结束；后继票保留原依赖门槛。完整命令、发现和限制见[统一验证记录](validation-record.md)。

## 第二批集成快照（c082bba）

- 已集成第二批29票，含后续交付的60 Cursor；加首批8票共37张代码票，9个原有入口加37个新增入口共46个。
- root 已实际执行完整 XCTest：457 tests、0 failures，日志 `/tmp/tokenpulse-sol-wave2-full46.log`；unsigned全目标构建成功，日志 `/tmp/tokenpulse-sol-wave2-unsigned.log`。这是c082bba基线，后续审查修复可能增加测试。
- 新增卡片AX与重点截图（混合钱包、单位、持续补充、日期、IBM未知分母、Warp到期）已由root抽查，添加菜单可打开；完整UI/组件与真实账号/权限/生产契约、凭证生命周期、iCloud到达、手机离线后的物理Watch直查、真实通知未因此完成。后续review修复与回归结果由root记录，不用457基线冒充新修改已验证。
- 37张代码票统一 `implemented-awaiting-real-validation`，7张研究票继续 `awaiting-validation`，25张依赖票未实施并保留blockers。没有completed票；自动验证未放行依赖验收门槛。
- 共享改动覆盖混合额度/钱包与独立提醒、持续补充/非周期额度、只给日期的边界、Decimal精确计数、部分余额失败的旧观测时间和身份隔离；详细交付见[第二批记录](wave2-progress.md)。最终命令/结果/UI与限制由root继续写入[统一验证记录](validation-record.md)。
