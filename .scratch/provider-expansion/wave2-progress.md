# Sol 第二批执行记录

用户于 2026-10-02 要求继续。基线为首批最终提交 6c12386，238 项测试及 App/Watch/Widgets 构建已通过。继续在 feature/provider-expansion-sol 集成，六个工作者均从该提交创建新的 wave2 分支，保留首批分支。

| 工作者 | 本批队列 |
| --- | --- |
| sol_regional | 04 Moonshot API 钱包余额接入、05 阿里百炼 Coding Plan 额度接入、19 Chutes 订阅额度 |
| sol_wallet | 18 Atlas Cloud 钱包余额、22 DeepInfra 钱包与支出上限、28 Kilo Code 钱包与 Kilo Pass、26 Hyper Hypercredits 余额、31 Venice USD 与 DIEM 余额 |
| sol_copilot | 06 Factory 套餐额度接入、23 DevPass 套餐与 Key 限额、30 v0 账期额度与限流、32 Warp 套餐与附加 credits |
| sol_gateway | 39 火山方舟 Coding 与 Agent Plan、38 xAI API 团队预付余额、27 IBM Bob 团队 Bobcoins 预算 |
| sol_web | 07 Synthetic 多窗口额度接入、08 V2EX AI Chat 额度接入、33 xKiro 配额与钱包、34 ZenMux 管理额度与余额 |
| sol_research | 16 Command Code 美元余额与限额、17 Amp 套餐额度与余额、24 GitKraken AI 个人与组织额度、25 Hugging Face ZeroGPU 额度 |
| root | 20 ClinePass 多周期额度、21 Codebuff Key 模式 credits、29 Neuralwatt 订阅与钱包、35 Aixy 托管网关预算、36 ClawRouter 托管预算 |

60 Cursor 暂未分配，待一个工作者释放后进行独立移动授权接入。其他依赖票保留原阻塞门槛。

## 共享改动

- wallet 组先交付纯余额/混合额度展示与可选独立 walletAlertsEnabled，保留旧存档默认行为；同一账号套餐与钱包不互相覆盖。
- web 组交付连续恢复语义供 Synthetic 和 Amp 使用；恢复补充不生成完整重置通知，只有恢复到最低阈值以下后才重新允许下一次告警。
- 数值与布尔类型严格区分，金额使用 Decimal，时间不能溢出，未知或缺失字段不补零。
- provider 单独提交；root 统一处理共享注册、合并、完整构建与测试，工作者不并行运行 Xcode 或模拟器。
- 新增图标按 AGENTS 固定出处与许可。真实账号/物理设备验证仍分别记录，代码测试通过不关闭真实验收项。
