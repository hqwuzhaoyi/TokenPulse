# Sol 第二批执行记录

用户于 2026-10-02 要求继续。基线为首批最终提交6c12386（238项测试与完整构建通过）；当前集成快照为c082bba，第二批29张代码票均已落地，原有9个+首批8个+第二批29个=46个提供商入口。六个工作者与root使用独立wave2分支，保留首批历史分支。

| 工作者 | 本批队列 |
| --- | --- |
| sol_regional | 04 Moonshot API 钱包余额接入、05 阿里百炼 Coding Plan 额度接入、19 Chutes 订阅额度、60 Cursor 移动授权与模型池 |
| sol_wallet | 18 Atlas Cloud 钱包余额、22 DeepInfra 钱包与支出上限、28 Kilo Code 钱包与 Kilo Pass、26 Hyper Hypercredits 余额、31 Venice USD 与 DIEM 余额 |
| sol_copilot | 06 Factory 套餐额度接入、23 DevPass 套餐与 Key 限额、30 v0 账期额度与限流、32 Warp 套餐与附加 credits |
| sol_gateway | 39 火山方舟 Coding 与 Agent Plan、38 xAI API 团队预付余额、27 IBM Bob 团队 Bobcoins 预算 |
| sol_web | 07 Synthetic 多窗口额度接入、08 V2EX AI Chat 额度接入、33 xKiro 配额与钱包、34 ZenMux 管理额度与余额 |
| sol_research | 16 Command Code 美元余额与限额、17 Amp 套餐额度与余额、24 GitKraken AI 个人与组织额度、25 Hugging Face ZeroGPU 额度 |
| root | 20 ClinePass 多周期额度、21 Codebuff Key 模式 credits、29 Neuralwatt 订阅与钱包、35 Aixy 托管网关预算、36 ClawRouter 托管预算 |

表中全部29票代码已集成，统一为 `implemented-awaiting-real-validation`；它表示实现落地，不表示生产凭证/手机授权可用。25张后继依赖票尚未实施，7张63–69研究票继续awaiting-validation；没有票因本批代码或模拟数据关闭。

## 共享改动

- wallet 组先交付纯余额/混合额度展示与可选独立 walletAlertsEnabled，保留旧存档默认行为；同一账号套餐与钱包不互相覆盖。
- web 组交付连续恢复语义供 Synthetic 和 Amp 使用；恢复补充不生成完整重置通知，只有恢复到最低阈值以下后才重新允许下一次告警。
- 数值与布尔类型严格区分，金额使用 Decimal，时间不能溢出，未知或缺失字段不补零。
- provider 单独提交；root 统一处理共享注册、合并、完整构建与测试，工作者不并行运行 Xcode 或模拟器。
- 新增图标按 AGENTS 固定出处与许可。真实账号/物理设备验证仍分别记录，代码测试通过不关闭真实验收项。

## 已执行自动验证与待验收

- root 在c082bba实际执行完整XCTest，457 tests、0 failures；本机结果日志 `/tmp/tokenpulse-sol-wave2-full46.log`，结果包 `/tmp/tokenpulse-sol-wave2-full46.xcresult`。
- root 同一快照的unsigned TokenPulse target构建成功，覆盖App/Watch/两端Widgets及资源目录；日志 `/tmp/tokenpulse-sol-wave2-unsigned.log`。
- root已抽查全部新增账号卡片AX，重点截图核对混合钱包/单位/持续补充/日期/IBM缺分母/Warp到期，添加菜单可打开；这不表示完整各尺寸Widget/Watch/真实登录流程通过。首批演示截图和历史真机安装只属于各自版本的证据。
- review仍在处理混合提醒默认开关联动、Chutes部分计数、DevPass缺限额及矩形complication等边界。非周期额度文案已另行修正；这些后续提交及新增测试不属于上述457项的c082bba结果，最终计数/重新构建和UI结果留root更新。
- 真实账号、当前接口/权限/币种/单位、独立手机登录、凭证失效/续期、iCloud到达、关闭同步的本机生命周期、手机离线时物理Watch查询、后台通知和Widget/表盘仍需真实验收。详细命令、后续结果及UI证据由root维护[统一验证记录](validation-record.md)。

## 不能由代码落地推出的结论

- 05百炼：无效合成Key探测只确认ConsoleNeedLogin失败结构；有效Key能否读取控制台额度仍待实际验证，不发布为已验证登录路线。
- 60 Cursor：已有隔离移动登录与原生轮询协议代码，但真实WK/SSO/CAPTCHA、Cookie查询兼容及无窗口账号仍未通过，61 Grok Bot依赖门槛保持关闭。
- 32 Warp：参考客户端的桌面请求上下文不证明服务允许iOS/watchOS；生产字段和移动约束待验。
- 24 GitKraken/27 IBM Bob：手工会话JWT并非永久Key，未建立自动续期；明确过期需重新配置。
- 金额预算、非货币credits、GPU秒、Orb小时、kWh和钱包都保持各自计量。xKiro与AWS Kiro、Moonshot API与Kimi Code、xAI API与SuperGrok不互换身份；xAI已入账预付账本不承诺等于实时资金。
- 13–15/37仍依赖12的真实共享能力验收，41–59仍依赖40；44尚未落地，62依赖44。7张研究票只交付具体候选或架构限制及缺口，不当正式接入或验收完成。
