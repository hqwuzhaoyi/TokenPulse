# 提供商与登录方式

[返回中文首页](../README.md) · [English](../README.en.md)

TokenPulse 支持 78 个 Provider 入口，涵盖订阅套餐、API 钱包和自托管网关。下表列出登录方式及可查询内容，地区、套餐和授权范围不同的入口可能需要分别配置。

部分接入使用非公开接口，真实账号兼容性及验证范围请查看对应文档；代码和模拟响应测试不代表所有服务均已完成真实账号端到端验证。

| 提供商 | 登录方式 | 桌面小组件主要内容 |
| --- | --- | --- |
| Claude | 应用内网页登录，选择组织 | 服务返回的额度窗口 |
| ChatGPT / Codex | 设备码授权 | Plus 显示 5 小时与每周已用；Pro 显示每周已用，详情附 Spark 额度 |
| OpenCode Go | API Key | 5 小时、每周与每月已用 |
| Z.ai / GLM | 国际 Coding Plan Key | 每周已用与 5 小时已用 |
| MiniMax 国内版 | Coding Plan Key | **5 小时已用额度** |
| SuperGrok | 设备码授权 | 每周已用与重置时间 |
| Qoder 国际版 | 浏览器设备授权 | 个人额度与组织资源包，分别展示 |
| DeepSeek | API Key | 所选币种的 API 钱包余额 |
| 智谱国内版 | 国内 Coding Plan Key | 服务返回的额度窗口，含 MCP |
| MiniMax 国际版 | 国际 Coding Plan Key | 服务返回的短周期与每周额度 |
| Kimi Code 国内版 | 设备码授权 | 5 小时、每周、每月及加量余额 |
| Poe | API Key | 剩余 points，非货币积分 |
| Vercel AI Gateway | AI Gateway API Key | USD 可用余额 |
| StepFun | 应用内网页登录，选择国内／国际站 | Token Plan 积分或 Coding Plan 窗口 |
| ElevenLabs | 具备 user_read 权限的 API Key | 账期字符额度与重置时间 |
| New API | 每账号服务器地址与网关 Key（公网 HTTPS／私网 HTTP） | 明确币种的钱包余额；无限 Key、Token 或未知单位按原意展示 |
| GitHub Copilot | GitHub 设备码授权（read:user） | Premium requests、Chat、Completions，按实际套餐分别显示 |
| [Moonshot API 钱包](moonshot-integration.md) | 明确国内/国际地区与对应 API Key | 国内 CNY／国际 USD 余额；与 Kimi Code 套餐分开 |
| [阿里百炼 Coding Plan](alibaba-coding-plan-integration.md) | 国内/国际 Coding Plan Key，控制台兼容性待验 | 5 小时、每周、账期额度；要求会话时明确报错 |
| [Factory](factory-provider-integration.md) | Factory API Key | 新 Standard/Core 或旧 Standard/Premium 池；附加 cents 不推断币种 |
| [Synthetic](synthetic-provider-integration.md) | Synthetic API Key | 持续补充的短周期/每周池与独立 Search 请求额度 |
| [V2EX](v2ex-provider-integration.md) | Personal Access Token | AI Chat tokens 窗口与永久补充包，未开始状态不造重置 |
| [Command Code](command-code-provider-integration.md) | Command Code API Key | 真实美元余额与独立滚动/组织限额，不按套餐价格推算总额 |
| [Amp](amp-provider-integration.md) | Amp Access Token | Free 持续补充、Agent 美元预算、Orb 小时与个人 USD 余额 |
| [Atlas Cloud](atlas-cloud-integration.md) | 有账户余额读取权限的 API Key | 按服务返回币种显示账户余额 |
| [Chutes](chutes-integration.md) | Chutes API Key | 当前契约的 4 小时固定与账期 USD 预算，保留明确无限状态 |
| [ClinePass](clinepass-integration.md) | ClinePass API Key | 5 小时、每周与每月窗口 |
| [Codebuff](codebuff-integration.md) | Codebuff API Key | Key 可见的 credits 额度及非货币剩余余额 |
| [DeepInfra](deepinfra-integration.md) | DeepInfra API Key | USD 钱包与实际给出的独立支出上限 |
| [DevPass](devpass-provider-integration.md) | 普通 LLM Gateway API Key | Premium、账期 USD credits 与 Key 累计限额；非钱包 |
| [GitKraken AI](gitkraken-provider-integration.md) | 会过期的账户会话 Token，可指定组织 ID | 个人与对应组织共享 credits，未提供组织名时明确标注 |
| [Hugging Face](hugging-face-provider-integration.md) | 具备账单读取权限的用户 Token | ZeroGPU GPU 秒；不含 Inference Providers 账单或钱包 |
| [Hyper](hyper-integration.md) | Hyper API Key | 非货币 Hypercredits（HC）余额 |
| [IBM Bob](ibm-bob-provider-integration.md) | General API Key 或登录 JWT | 各实例/团队 Bobcoins 用量与预算，未知预算不补分母 |
| [Kilo Code](kilo-code-integration.md) | Kilo Code 个人 API Key | USD 钱包与 Kilo Pass 账期额度，分别展示 |
| [Neuralwatt](neuralwatt-integration.md) | Neuralwatt API Key | kWh 订阅量、USD Key 限额及 USD 钱包 |
| [v0](v0-provider-integration.md) | v0 Platform API Key | 账期 credits 与独立消息限流，不推断美元钱包 |
| [Venice](venice-integration.md) | Venice API Key | 服务指定的 USD 或 DIEM/其他非货币 credits，不合计或换汇 |
| [Warp](warp-provider-integration.md) | Warp API Key；移动兼容待真实验证 | 套餐与按个人/工作区来源区分的 grants，到期不作重置 |
| [xKiro](xkiro-provider-integration.md) | xKiro API Key | USD 预算、免费 tokens 与 USD 钱包；与 AWS Kiro 无关 |
| [ZenMux](zenmux-provider-integration.md) | Management Key，非推理 Key | 套餐额度与按量钱包；旧余额保留独立采集时间 |
| [Aixy](aixy-integration.md) | 托管项目 Key | 适用的硬预算与监控预算，不当钱包资金 |
| [ClawRouter](clawrouter-integration.md) | OpenClaw 托管 Key | 托管微美元预算；不混同 BlockRun x402 钱包 |
| [xAI API](xai-api-provider-integration.md) | Team ID 与有账单权限的 Management Key | 已入账 USD 团队预付余额，可能不同于实时余额；与 SuperGrok 分开 |
| [火山方舟](volcengine-provider-integration.md) | AccessKey ID 与 SecretAccessKey | Coding Plan 与 Agent Plan（AFP）分别展示，设备独立签名 |
| [Cursor](cursor-mobile-integration.md) | 账号隔离的手机网页登录/原生轮询路线；到期重登 | Cursor Models、Other Models 与实际额外 USD 支出预算；非钱包 |
| [sub2api](sub2api-provider-integration.md) | 每账号部署地址与分组 Key | 钱包、分组/订阅额度及限流分别显示，单位不混用 |
| [Bifrost](bifrost-provider-integration.md) | 网关地址与虚拟 Key | Key、提供商与模型的独立 USD 预算，非钱包 |
| [LiteLLM](litellm-provider-integration.md) | 部署地址与虚拟 Key | 当前 Key 绑定的用户/团队预算，未知上限不称无限 |
| [LLM API Key Proxy](llm-proxy-provider-integration.md) | 每账号代理地址与 Key | 各上游 quota groups，已用百分比与真实 reset；不触发代理强制刷新 |
| [小米 Coding Plan](xiaomi-coding-plan-integration.md) | MiMo 控制台隔离网页登录 | Coding Plan 多窗口与服务明确单位的余额，辅助失败单独标注 |
| [Qoder 国内版](qoder-mainland-integration.md) | qoder.com.cn 隔离网页登录 | 个人与团队 credits 池；与国际设备授权入口分开 |
| [Ollama Cloud](ollama-cloud-integration.md) | ollama.com 账号页隔离网页登录 | Session 与 Weekly 使用率，仅采用可见额度块与报告日期 |
| [Devin](devin-provider-integration.md) | 隔离网页登录并明确选择组织 | 当前组织额度/钱包，来源与组织身份绑定 |
| [Abacus AI](abacus-integration.md) | 隔离网页登录 | 组织 compute points 与实际给出的账期；非美元钱包 |
| [Augment Code](augment-code-provider-integration.md) | 账号隔离网页登录 | 已用/剩余 credits 原数，未确认总额时不造百分比 |
| [LongCat](longcat-integration.md) | LongCat 控制台隔离网页登录 | 主 Token 包、补充燃料总包及到期子集，余额不相加为总池 |
| [Manus](manus-provider-integration.md) | 隔离网页登录，取得必要 session | 各类 credits 和有效分母，非货币余额不触发低余额提醒 |
| [Mistral](mistral-provider-integration.md) | Ory 会话网页登录，官方域名与 CSRF 绑定 | API/Vibe 各窗口与明确币种净余额；未提供组件不补零 |
| [Notion AI](notion-ai-integration.md) | 隔离网页登录，用户选择可见工作区 | 所选用户/工作区基础 AI allowance，与 Custom Agents/付费 credits 分开 |
| [Perplexity API](perplexity-integration.md) | 账单网页登录会话，支持完整分块 Cookie | API credits 钱包；反自动化/WK兼容仍保留限制说明 |
| [Qwen Cloud](qwen-cloud-integration.md) | Qwen Cloud 个人 Token Plan 控制台登录 | 5 小时/每周/账期套餐窗口，与百炼 Coding Plan 分开 |
| [Raycast AI](raycast-ai-integration.md) | 隔离网页登录 | AI credits 原数及实际续期时间，缺计数不补分母 |
| [Replicate](replicate-provider-integration.md) | 账单网页登录并选择个人/组织 | 对应账户预付 USD 余额，推理 API Token 不替代账单会话 |
| [Sakana AI](sakana-provider-integration.md) | 隔离网页登录，验证实际 Auth.js 会话/完整 chunks | 5 小时/每周额度与服务 credits；仅明确币种才启用货币提醒 |
| [T3 Chat](t3-chat-integration.md) | t3.chat 隔离网页登录 | 4 小时与月度使用率，仅解析指定 tRPC 流引用 |
| [TypeSafe](typesafe-integration.md) | TypeSafe 控制台隔离网页登录 | 余额及套餐；无明确币种时显示非货币 credits，不猜 USD |
| [Zed](zed-provider-integration.md) | Zed 网页账户隔离登录 | 编辑预测与实际支出预算，非现金钱包 |
| [ZoomMate](zoommate-integration.md) | Zoom 父域隔离网页登录 | AI credits/无限/停用/超额付费按实际状态分开 |
| [Grok Bot](grok-bot-provider-integration.md) | 独立的 Cursor 账号授权范围 | Grok Bot 额度，和 Cursor 模型池、SuperGrok 分开 |
| [Windsurf](windsurf-provider-integration.md) | Windsurf 本域隔离网页登录 | 自己的账号/组织 Connect 额度，不复用 Devin 的账号数据 |
| [OpenAI API（Legacy 余额）](openai-api-integration.md) | 用户主动配置 API Key，旧接口兼容性因账号与 Key 而异 | legacy 契约的 USD 可用余额；不将组织 Costs 消费统计当作余额 |
| [阿里百炼 Token Plan](alibaba-token-plan-integration.md) | AK/SK，明确北京／新加坡地区及国内／国际账号站点 | 个人 5 小时与每周已用比例及实际重置时间；不造月窗，与 Coding Plan 分开 |
| [Gemini Code Assist](../.scratch/provider-expansion/research/63-gemini.md) | 自备 Google iOS OAuth Client ID，原生 PKCE 授权；可指定 Cloud 项目 | 各模型限制窗口的使用率或剩余原数，按服务单位；不猜周期，客户端／项目须获服务许可 |
| [Antigravity](antigravity-integration.md) | 自备 Google iOS OAuth Client ID，原生 PKCE 授权；需已激活服务与项目 | 模型组独立额度；数量缺类型时明示未提供，不推断 tokens／USD；内部 scope 授予不保证 |
| [Kiro](kiro-provider-integration.md) | app.kiro.dev 个人账号隔离网页登录，支持 Google／GitHub／Builder ID | 订阅、试用、bonus／额外 credits 分开；非货币，试用到期不作重置，与 xKiro 无关 |
| [Nous Portal](nous-portal-provider.md) | OAuth 设备码授权，公开客户端标识 Hermes CLI；iPhone／Watch 分别授权同一用户与组织 | 订阅、购买与总可用非货币 credits；不重复合计，凭证仅留在授权设备 |
| [JetBrains AI](jetbrains-provider-integration.md) | 每设备独立导入官方 Central login export，个人 production license | tariff 与 top-up AI credits，分别显示已用/剩余/上限；不当美元钱包 |

DeepSeek 直接展示 API 返回的币种与金额，不做汇率换算；详情包含总可用、赠送和充值余额。账号设置可选择概览及提醒币种，低余额默认阈值为 CNY 10 元或 USD 2 美元，可修改。持续低余额只提醒一次，余额恢复后再次降低才重新提醒；余额不足以调用 API 时也会提醒，并合并同次通知。钱包不显示已用百分比或周期重置时间。

混合账号的额度与钱包分别显示、分别设置提醒；只有服务明确给出的分母才产生使用率。货币金额与精确预算保留 Decimal，points、HC、Bobcoins、GPU 秒、小时和 kWh 不按名称或价格兑换为美元。部分查询失败时，成功的额度与保留的旧余额显示各自状态和采集时间，不用新时间掩盖旧数据。

New API 每个账号可配置不同的网关（公网 HTTPS，明确的私网地址可用 HTTP），地址末尾的 `/v1` 会自动移除；更新地址或 Key 后会清除旧余额和提醒身份。公共 `/api/status` 请求不携带 Key。USD/CNY 余额支持低余额提醒，TOKENS、CUSTOM 或未知币种不会被当作货币；不会用历史充值总量推断套餐百分比。私网连接的系统权限、iPhone/Watch 实机可达性、iCloud Keychain 到达和真实 Key 失效尚待验收。

Qoder 采用参考项目的非公开接口。设备凭证的自动续期不可用，源码核验与真实账号验证边界见 [提供商接入说明](provider-integration.md)。到期时间只表示到期，不推断额度已重置。

网页登录为各服务账号新建临时容器，只提取允许域名、路径及必要Cookie/存储字段；多工作区或组织由用户选择，查询前复核范围。到期后重新登录，关闭或重启登录清理旧临时会话。明确未发额度、未配置预算或套餐不适用可显示服务确认的状态，和网络失败/未知字段区分，不制造0%或无限。

Gemini Code Assist 与 Antigravity 需要用户自行注册 Google iOS OAuth 客户端（Bundle ID `com.tokenpulse.app`），配置授权同意与所需权限；可用项目与服务资格也由 Google 决定。应用不借用 Google CLI 客户端或电脑上的令牌，不自动开通服务；强制 App Check／DPoP 的客户端配置目前不支持。Antigravity 所需内部 scope 是否授予自备客户端尚未真实验证。

Nous Portal 使用设备本地的旋转授权链：iPhone 和 Watch 分别完成设备码授权，同一用户与组织的配置、额度快照和提醒记录可以共享，access／refresh 凭证不会传到另一设备。Watch 在账号页点击“连接此 Watch”取得自己的授权；令牌轮换结果不确定或授权失效时需要重新连接。详情见[Nous 接入说明](nous-portal-provider.md)。

78 个入口均已接入现有品牌资源或可用通用图标，完整无签名构建已编译 App、Watch 与两端小组件的资源。通用图标不冒称官方品牌 logo；来源与许可见 [ProviderIconNotices.txt](../TokenPulse/Resources/ProviderIconNotices.txt)，全部入口的分类核验见[图标记录](../.scratch/provider-expansion/icon-acceptance.md)。

Copilot 授权页会显示 VS Code / Copilot 客户端身份，TokenPulse 使用该公开客户端进行非官方接入。只请求 `read:user`，无需粘贴 `gh` 或其他应用的 token。额度查询使用非公开内部接口；未发放项省略，无限项显示“无限”，超额付费与耗尽分别显示。凭证失效后可从账号设置重新授权，详见 [接入与验证边界](provider-integration.md#github-copilot)。

小、中、大组件都从主屏幕已配置账号列表中选择，分别最多选择 1、2、4 个具体账号，选择顺序就是展示顺序。中尺寸按账号分栏并对齐额度信息；大尺寸按账号纵向排列，每个账号的额度周期横向并列。每个账号的额度周期分别以文字和横向进度条显示，并保留各自的重置或到期时间，各周期用量不会相加。钱包余额、无限额度及未提供的用量不绘制百分比进度条。Codex 与 SuperGrok 的可手动重置次数属于账号级信息，只显示一次；没有可信字段时显示“未提供”。

Codex 套餐根据额度响应中的 `plan_type` 识别为 Plus 或 Pro；缺失或未知值显示为未提供，不自行猜测。Codex 的手动重置次数读取接口的 `rate_limit_reset_credits.available_count`，仅展示，不消耗重置次数。提供商没有返回的指标显示“未提供”，不会默认为 0；SuperGrok 的手动重置次数目前没有核实的对应字段。
