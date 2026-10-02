# Sol 团队执行记录

启动日期：2026-10-02。用户要求创建 Sol teams 开始实施；6 个工作者使用 gpt-6.1-sol，独立 worktree 开发，root 统一集成。集成分支：feature/provider-expansion-sol。

| 工作者 | 分支 | 首批票 | 交付 |
| --- | --- | --- | --- |
| sol_regional | sol/regional | 01、02 | 智谱国内版与 MiniMax 国际版 |
| sol_wallet | sol/wallet | 09、10 | Poe、Vercel 与可缺失的钱包明细 |
| sol_copilot | sol/copilot | 03 | Copilot 设备授权及额度 |
| sol_gateway | sol/gateway | 12 | New API 与账号级网关地址 |
| sol_web | sol/web | 40 | StepFun 与隔离的网页登录 |
| sol_research | sol/research | 63–69 | 七家移动端独立查询可行性 |

工作树位于工作区旁的 TokenPulse-sol 目录。各组可在自己的工作树修改共享 switch，由 root 集成；Xcode 构建、模拟器测试串行调度，避免平台服务与输出目录冲突。

## 共享契约

- 钱包明细允许缺失，旧 DeepSeek 存档兼容；货币与 points 明确区分。
- 服务器地址与凭证绑定到具体服务账号；更换身份不能复用旧数据或提醒状态。
- 网页会话按账号隔离，保持 Claude 现有登录能力。
- 真实账号与物理 Watch 未验收的条目保留未勾选，不宣称已完成。

## 构建基线

- 原始代码 unsigned TokenPulse target 构建失败：资产编译要求 iOS 26.5 SDK 兼容运行时，机器仅安装 iOS 26.4 (23E244)。Xcode 26.6 / iOS SDK 26.5；watchOS 26.5 运行时已就绪。
- 正在通过 Xcode 安装 iOS 26.5 arm64 运行时，随后复跑相同构建。日志位于 /tmp/tokenpulse-sol-baseline-build.log 与 /tmp/tokenpulse-sol-runtime-install.log。

## 状态含义

in-progress 表示正在开发。实现通过自动检查后仍需保留真实账号、物理设备验证缺口；依赖票没有完成前不自动领取后继票。
