# TokenPulse

在 iPhone 和 Apple Watch 上查看多个 AI 服务账号的套餐额度、预算、积分、GPU 时长和钱包余额，支持设备独立刷新、额度与低余额提醒、桌面小组件。

> **原参考仓库：[qunqin24/Pulse](https://github.com/qunqin24/Pulse)**
>
> TokenPulse 的产品设计、提供商接入研究及渠道图标参考了 Pulse，并实现了面向 iOS / watchOS 的原生应用。原始参考版本为 [8d7fd60](https://github.com/qunqin24/Pulse/tree/8d7fd60454ce383dd0a136a30790c1e277f8069b)；本次提供商扩展以 [397c8fc4](https://github.com/qunqin24/Pulse/tree/397c8fc4f1bd52180a452d2f3f0c099def97cf69) 和各接入文档固定的官方来源为契约线索。

## 功能

- **多提供商、多账号**：78 个代码入口，涵盖订阅、API 钱包和自托管网关；同一提供商可配置多个账号。69 张扩展票已按用户“完整实现+图标存在”标准全部完成。
- **独立查询**：iPhone 和 Watch 各自向提供商查询；Watch 取得配置及适用凭证后，无需手机代查额度。Nous 的两端凭证各自授权，不通过 iCloud 传送。
- **账号管理**：首页通过 Edit 拖动账号卡片排序；左滑卡片或进入账号设置可删除账号，清理凭证、额度和提醒，并通过 iCloud 同步删除结果。Watch 同步全部账号，每个账号保留独立额度窗口。
- **同步控制**：iCloud 同步开关、手动同步、最近同步时间、失败提示；点击同步时图标旋转反馈。
- **额度告警**：提供应用级通知开关；默认阈值为 80%、95%、100%，按提供商和套餐的可通知窗口判断，多个窗口同时触发时合并提醒。
- **重置与补充**：只有服务给出精确重置时刻、且已有实际用量的窗口才预排通知；持续补充不当成重置。仅给日期的账期保持日期精度，不按午夜推断恢复。
- **额度小组件与表盘入口**：iPhone 主屏幕使用文字与横向进度条展示额度；锁屏及 Watch 表盘四角、圆形、矩形、行内复杂功能和智能叠放保留原有展示，均保留渠道图标。
- **数据状态**：保留上次成功数据、采集时间和查询失败提示；混合账号保留各自额度与余额状态，余额查询失败时不会把旧余额标成新观测。精确时间按设备时区显示，仅给日期的边界保持原日期。

## 提供商与登录方式

下表列出 **78 个已落地代码入口**：此前71个，加 OpenAI API Legacy、阿里百炼 Token Plan、Gemini Code Assist、Antigravity、Kiro、Nous Portal 与 JetBrains AI。图标均存在，69张扩展票全部完成；真实账号、手机登录或物理 Watch 观察边界分别保留在接入文档中。

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
| [Moonshot API 钱包](docs/moonshot-integration.md) | 明确国内/国际地区与对应 API Key | 国内 CNY／国际 USD 余额；与 Kimi Code 套餐分开 |
| [阿里百炼 Coding Plan](docs/alibaba-coding-plan-integration.md) | 国内/国际 Coding Plan Key，控制台兼容性待验 | 5 小时、每周、账期额度；要求会话时明确报错 |
| [Factory](docs/factory-provider-integration.md) | Factory API Key | 新 Standard/Core 或旧 Standard/Premium 池；附加 cents 不推断币种 |
| [Synthetic](docs/synthetic-provider-integration.md) | Synthetic API Key | 持续补充的短周期/每周池与独立 Search 请求额度 |
| [V2EX](docs/v2ex-provider-integration.md) | Personal Access Token | AI Chat tokens 窗口与永久补充包，未开始状态不造重置 |
| [Command Code](docs/command-code-provider-integration.md) | Command Code API Key | 真实美元余额与独立滚动/组织限额，不按套餐价格推算总额 |
| [Amp](docs/amp-provider-integration.md) | Amp Access Token | Free 持续补充、Agent 美元预算、Orb 小时与个人 USD 余额 |
| [Atlas Cloud](docs/atlas-cloud-integration.md) | 有账户余额读取权限的 API Key | 按服务返回币种显示账户余额 |
| [Chutes](docs/chutes-integration.md) | Chutes API Key | 当前契约的 4 小时固定与账期 USD 预算，保留明确无限状态 |
| [ClinePass](docs/clinepass-integration.md) | ClinePass API Key | 5 小时、每周与每月窗口 |
| [Codebuff](docs/codebuff-integration.md) | Codebuff API Key | Key 可见的 credits 额度及非货币剩余余额 |
| [DeepInfra](docs/deepinfra-integration.md) | DeepInfra API Key | USD 钱包与实际给出的独立支出上限 |
| [DevPass](docs/devpass-provider-integration.md) | 普通 LLM Gateway API Key | Premium、账期 USD credits 与 Key 累计限额；非钱包 |
| [GitKraken AI](docs/gitkraken-provider-integration.md) | 会过期的账户会话 Token，可指定组织 ID | 个人与对应组织共享 credits，未提供组织名时明确标注 |
| [Hugging Face](docs/hugging-face-provider-integration.md) | 具备账单读取权限的用户 Token | ZeroGPU GPU 秒；不含 Inference Providers 账单或钱包 |
| [Hyper](docs/hyper-integration.md) | Hyper API Key | 非货币 Hypercredits（HC）余额 |
| [IBM Bob](docs/ibm-bob-provider-integration.md) | General API Key 或登录 JWT | 各实例/团队 Bobcoins 用量与预算，未知预算不补分母 |
| [Kilo Code](docs/kilo-code-integration.md) | Kilo Code 个人 API Key | USD 钱包与 Kilo Pass 账期额度，分别展示 |
| [Neuralwatt](docs/neuralwatt-integration.md) | Neuralwatt API Key | kWh 订阅量、USD Key 限额及 USD 钱包 |
| [v0](docs/v0-provider-integration.md) | v0 Platform API Key | 账期 credits 与独立消息限流，不推断美元钱包 |
| [Venice](docs/venice-integration.md) | Venice API Key | 服务指定的 USD 或 DIEM/其他非货币 credits，不合计或换汇 |
| [Warp](docs/warp-provider-integration.md) | Warp API Key；移动兼容待真实验证 | 套餐与按个人/工作区来源区分的 grants，到期不作重置 |
| [xKiro](docs/xkiro-provider-integration.md) | xKiro API Key | USD 预算、免费 tokens 与 USD 钱包；与 AWS Kiro 无关 |
| [ZenMux](docs/zenmux-provider-integration.md) | Management Key，非推理 Key | 套餐额度与按量钱包；旧余额保留独立采集时间 |
| [Aixy](docs/aixy-integration.md) | 托管项目 Key | 适用的硬预算与监控预算，不当钱包资金 |
| [ClawRouter](docs/clawrouter-integration.md) | OpenClaw 托管 Key | 托管微美元预算；不混同 BlockRun x402 钱包 |
| [xAI API](docs/xai-api-provider-integration.md) | Team ID 与有账单权限的 Management Key | 已入账 USD 团队预付余额，可能不同于实时余额；与 SuperGrok 分开 |
| [火山方舟](docs/volcengine-provider-integration.md) | AccessKey ID 与 SecretAccessKey | Coding Plan 与 Agent Plan（AFP）分别展示，设备独立签名 |
| [Cursor](docs/cursor-mobile-integration.md) | 账号隔离的手机网页登录/原生轮询路线；到期重登 | Cursor Models、Other Models 与实际额外 USD 支出预算；非钱包 |
| [sub2api](docs/sub2api-provider-integration.md) | 每账号部署地址与分组 Key | 钱包、分组/订阅额度及限流分别显示，单位不混用 |
| [Bifrost](docs/bifrost-provider-integration.md) | 网关地址与虚拟 Key | Key、提供商与模型的独立 USD 预算，非钱包 |
| [LiteLLM](docs/litellm-provider-integration.md) | 部署地址与虚拟 Key | 当前 Key 绑定的用户/团队预算，未知上限不称无限 |
| [LLM API Key Proxy](docs/llm-proxy-provider-integration.md) | 每账号代理地址与 Key | 各上游 quota groups，已用百分比与真实 reset；不触发代理强制刷新 |
| [小米 Coding Plan](docs/xiaomi-coding-plan-integration.md) | MiMo 控制台隔离网页登录 | Coding Plan 多窗口与服务明确单位的余额，辅助失败单独标注 |
| [Qoder 国内版](docs/qoder-mainland-integration.md) | qoder.com.cn 隔离网页登录 | 个人与团队 credits 池；与国际设备授权入口分开 |
| [Ollama Cloud](docs/ollama-cloud-integration.md) | ollama.com 账号页隔离网页登录 | Session 与 Weekly 使用率，仅采用可见额度块与报告日期 |
| [Devin](docs/devin-provider-integration.md) | 隔离网页登录并明确选择组织 | 当前组织额度/钱包，来源与组织身份绑定 |
| [Abacus AI](docs/abacus-integration.md) | 隔离网页登录 | 组织 compute points 与实际给出的账期；非美元钱包 |
| [Augment Code](docs/augment-code-provider-integration.md) | 账号隔离网页登录 | 已用/剩余 credits 原数，未确认总额时不造百分比 |
| [LongCat](docs/longcat-integration.md) | LongCat 控制台隔离网页登录 | 主 Token 包、补充燃料总包及到期子集，余额不相加为总池 |
| [Manus](docs/manus-provider-integration.md) | 隔离网页登录，取得必要 session | 各类 credits 和有效分母，非货币余额不触发低余额提醒 |
| [Mistral](docs/mistral-provider-integration.md) | Ory 会话网页登录，官方域名与 CSRF 绑定 | API/Vibe 各窗口与明确币种净余额；未提供组件不补零 |
| [Notion AI](docs/notion-ai-integration.md) | 隔离网页登录，用户选择可见工作区 | 所选用户/工作区基础 AI allowance，与 Custom Agents/付费 credits 分开 |
| [Perplexity API](docs/perplexity-integration.md) | 账单网页登录会话，支持完整分块 Cookie | API credits 钱包；反自动化/WK兼容仍保留限制说明 |
| [Qwen Cloud](docs/qwen-cloud-integration.md) | Qwen Cloud 个人 Token Plan 控制台登录 | 5 小时/每周/账期套餐窗口，与百炼 Coding Plan 分开 |
| [Raycast AI](docs/raycast-ai-integration.md) | 隔离网页登录 | AI credits 原数及实际续期时间，缺计数不补分母 |
| [Replicate](docs/replicate-provider-integration.md) | 账单网页登录并选择个人/组织 | 对应账户预付 USD 余额，推理 API Token 不替代账单会话 |
| [Sakana AI](docs/sakana-provider-integration.md) | 隔离网页登录，验证实际 Auth.js 会话/完整 chunks | 5 小时/每周额度与服务 credits；仅明确币种才启用货币提醒 |
| [T3 Chat](docs/t3-chat-integration.md) | t3.chat 隔离网页登录 | 4 小时与月度使用率，仅解析指定 tRPC 流引用 |
| [TypeSafe](docs/typesafe-integration.md) | TypeSafe 控制台隔离网页登录 | 余额及套餐；无明确币种时显示非货币 credits，不猜 USD |
| [Zed](docs/zed-provider-integration.md) | Zed 网页账户隔离登录 | 编辑预测与实际支出预算，非现金钱包 |
| [ZoomMate](docs/zoommate-integration.md) | Zoom 父域隔离网页登录 | AI credits/无限/停用/超额付费按实际状态分开 |
| [Grok Bot](docs/grok-bot-provider-integration.md) | 独立的 Cursor 账号授权范围 | Grok Bot 额度，和 Cursor 模型池、SuperGrok 分开 |
| [Windsurf](docs/windsurf-provider-integration.md) | Windsurf 本域隔离网页登录 | 自己的账号/组织 Connect 额度，不复用 Devin 的账号数据 |
| [OpenAI API（Legacy 余额）](docs/openai-api-integration.md) | 用户主动配置 API Key，旧接口兼容性因账号与 Key 而异 | legacy 契约的 USD 可用余额；不将组织 Costs 消费统计当作余额 |
| [阿里百炼 Token Plan](docs/alibaba-token-plan-integration.md) | AK/SK，明确北京／新加坡地区及国内／国际账号站点 | 个人 5 小时与每周已用比例及实际重置时间；不造月窗，与 Coding Plan 分开 |
| [Gemini Code Assist](.scratch/provider-expansion/research/63-gemini.md) | 自备 Google iOS OAuth Client ID，原生 PKCE 授权；可指定 Cloud 项目 | 各模型限制窗口的使用率或剩余原数，按服务单位；不猜周期，客户端／项目须获服务许可 |
| [Antigravity](docs/antigravity-integration.md) | 自备 Google iOS OAuth Client ID，原生 PKCE 授权；需已激活服务与项目 | 模型组独立额度；数量缺类型时明示未提供，不推断 tokens／USD；内部 scope 授予不保证 |
| [Kiro](docs/kiro-provider-integration.md) | app.kiro.dev 个人账号隔离网页登录，支持 Google／GitHub／Builder ID | 订阅、试用、bonus／额外 credits 分开；非货币，试用到期不作重置，与 xKiro 无关 |
| [Nous Portal](docs/nous-portal-provider.md) | OAuth 设备码授权，公开客户端标识 Hermes CLI；iPhone／Watch 分别授权同一用户与组织 | 订阅、购买与总可用非货币 credits；不重复合计，凭证仅留在授权设备 |
| [JetBrains AI](docs/jetbrains-provider-integration.md) | 每设备独立导入官方 Central login export，个人 production license | tariff 与 top-up AI credits，分别显示已用/剩余/上限；不当美元钱包 |

DeepSeek 直接展示 API 返回的币种与金额，不做汇率换算；详情包含总可用、赠送和充值余额。账号设置可选择概览及提醒币种，低余额默认阈值为 CNY 10 元或 USD 2 美元，可修改。持续低余额只提醒一次，余额恢复后再次降低才重新提醒；余额不足以调用 API 时也会提醒，并合并同次通知。钱包不显示已用百分比或周期重置时间。

混合账号的额度与钱包分别显示、分别设置提醒；只有服务明确给出的分母才产生使用率。货币金额与精确预算保留 Decimal，points、HC、Bobcoins、GPU 秒、小时和 kWh 不按名称或价格兑换为美元。部分查询失败时，成功的额度与保留的旧余额显示各自状态和采集时间，不用新时间掩盖旧数据。

New API 每个账号可配置不同的网关（公网 HTTPS，明确的私网地址可用 HTTP），地址末尾的 `/v1` 会自动移除；更新地址或 Key 后会清除旧余额和提醒身份。公共 `/api/status` 请求不携带 Key。USD/CNY 余额支持低余额提醒，TOKENS、CUSTOM 或未知币种不会被当作货币；不会用历史充值总量推断套餐百分比。私网连接的系统权限、iPhone/Watch 实机可达性、iCloud Keychain 到达和真实 Key 失效尚待验收。

Qoder 采用参考项目的非公开接口。设备凭证的自动续期不可用，源码核验与真实账号验证边界见 [提供商接入说明](docs/provider-integration.md)。到期时间只表示到期，不推断额度已重置。

网页登录为各服务账号新建临时容器，只提取允许域名、路径及必要Cookie/存储字段；多工作区或组织由用户选择，查询前复核范围。到期后重新登录，关闭或重启登录清理旧临时会话。明确未发额度、未配置预算或套餐不适用可显示服务确认的状态，和网络失败/未知字段区分，不制造0%或无限。

Gemini Code Assist 与 Antigravity 需要用户自行注册 Google iOS OAuth 客户端（Bundle ID `com.tokenpulse.app`），配置授权同意与所需权限；可用项目与服务资格也由 Google 决定。应用不借用 Google CLI 客户端或电脑上的令牌，不自动开通服务；强制 App Check／DPoP 的客户端配置目前不支持。Antigravity 所需内部 scope 是否授予自备客户端尚未真实验证。

Nous Portal 使用设备本地的旋转授权链：iPhone 和 Watch 分别完成设备码授权，同一用户与组织的配置、额度快照和提醒记录可以共享，access／refresh 凭证不会传到另一设备。Watch 在账号页点击“连接此 Watch”取得自己的授权；令牌轮换结果不确定或授权失效时需要重新连接。详情见[Nous 接入说明](docs/nous-portal-provider.md)。

78 个入口均已接入现有品牌资源或可用通用图标，完整无签名构建已编译 App、Watch 与两端小组件的资源。通用图标不冒称官方品牌 logo；来源与许可见 [ProviderIconNotices.txt](TokenPulse/Resources/ProviderIconNotices.txt)，全部入口的分类核验见[图标记录](.scratch/provider-expansion/icon-acceptance.md)。

Copilot 授权页会显示 VS Code / Copilot 客户端身份，TokenPulse 使用该公开客户端进行非官方接入。只请求 `read:user`，无需粘贴 `gh` 或其他应用的 token。额度查询使用非公开内部接口；未发放项省略，无限项显示“无限”，超额付费与耗尽分别显示。凭证失效后可从账号设置重新授权，详见 [接入与验证边界](docs/provider-integration.md#github-copilot)。

小、中、大组件都从主屏幕已配置账号列表中选择，分别最多选择 1、2、4 个具体账号，选择顺序就是展示顺序。中尺寸按账号分栏并对齐额度信息；大尺寸按账号纵向排列，每个账号的额度周期横向并列。每个账号的额度周期分别以文字和横向进度条显示，并保留各自的重置或到期时间，各周期用量不会相加。钱包余额、无限额度及未提供的用量不绘制百分比进度条。Codex 与 SuperGrok 的可手动重置次数属于账号级信息，只显示一次；没有可信字段时显示“未提供”。

Codex 套餐根据额度响应中的 `plan_type` 识别为 Plus 或 Pro；缺失或未知值显示为未提供，不自行猜测。Codex 的手动重置次数读取接口的 `rate_limit_reset_credits.available_count`，仅展示，不消耗重置次数。提供商没有返回的指标显示“未提供”，不会默认为 0；SuperGrok 的手动重置次数目前没有核实的对应字段。

## 开始使用

无需服务账号即可在首次启动页点击 **体验演示 / Try Demo**，也可从 **设置** 进入。演示模式提供各家服务及 Codex Plus / Pro 示例，支持刷新、添加、排序、删除、提醒设置和小组件。示例数据与真实账号隔离，不连接第三方服务或同步到 iCloud；点击 **退出演示** 恢复真实账号。Watch 可在空白页或 **表盘设置** 中独立进入演示。

1. 打开 iPhone 上的 TokenPulse，点击右上角 **＋**，选择提供商并完成登录或输入 Key。
2. 需要调整顺序时，点击首页左上角 **Edit** 并拖动账号卡片，编辑期间收起详情并关闭点击展开。删除时左滑卡片露出 **删除** 按钮，点击并确认后移除；也可进入 **设置 → 具体账号 → 删除账号**。在 **设置** 中打开通知，并按账号配置提醒类型和阈值。
3. 在 **账号设置 → 同步** 中开启 iCloud 同步，或点击“立即同步”。
4. 安装并打开 Watch 端，等待配置与适用凭证到达后刷新额度；Nous 账号还需在 Watch 账号页点击 **连接此 Watch** 独立授权。在右上角 **表盘设置** 中选择表盘要显示的账号。
5. 添加 iPhone 小组件；手表上可长按表盘，进入 **编辑 → 复杂功能 → TokenPulse 额度**。

Apple Watch 首次启动会自动请求系统通知权限；允许后额度告警和重置提醒默认开启，不需要在 Watch App 内单独配置。

同步开关控制本机主动同步，关闭后保留本机及已同步数据。右侧时间表示本机最近一次成功提交或收到云端更新的时间，不代表 Watch 已收到。

## 构建与真机安装

环境：**iOS 17+、watchOS 10+、Xcode 26.x / Swift 6**。本轮验收使用 Xcode 26.6。工程包含 iPhone App、Watch App、两端 Widget 和 XCTest 五个 targets。

```sh
git clone https://github.com/hqwuzhaoyi/TokenPulse.git
cd TokenPulse
open TokenPulse.xcodeproj
```

使用自己的开发账号部署时：

1. 在 Xcode 的 **Settings → Apple Accounts** 登录账号。
2. 为所有 targets 选择同一开发团队，并配置 App Groups、Keychain Sharing 和 iCloud Key-Value Storage。
3. 替换项目中的开发用团队及共享组标识；`PlatformConstants.swift` 与两端 entitlements 中的 App Group 必须一致。
4. 连接并信任 iPhone，开启开发者模式，选择 `TokenPulse` scheme 运行。
5. 手表先与 iPhone 配对，再连接到 Xcode、开启开发者模式；选择 `TokenPulseWatch` scheme 和实体手表运行，确保签名配置包含该手表。

只验证完整工程编译、不进行真机签名：

```sh
xcodebuild build -project TokenPulse.xcodeproj -target TokenPulse \
  -configuration Debug CODE_SIGNING_ALLOWED=NO \
  SYMROOT=/tmp/tokenpulse-products OBJROOT=/tmp/tokenpulse-objects
```

多平台构建不要全局指定 `-sdk`，各 target 使用自己的 iOS 或 watchOS SDK。

## 测试与验证状态

安装所需的 iOS/watchOS 模拟器组件后：

```sh
xcodebuild test -project TokenPulse.xcodeproj -scheme TokenPulse \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Keychain 测试需要模拟器默认本地签名，测试时不要设置 `CODE_SIGNING_ALLOWED=NO`。

- 源码 `379d5dd` 已完成78入口的完整 iPhone 模拟器 XCTest：**773项通过，0 failures**。日志 `/tmp/tokenpulse-wave4-final.log`、结果 `/tmp/tokenpulse-wave4-final.xcresult`。
- unsigned App／Watch／两端 Widgets 构建成功，日志 `/tmp/tokenpulse-wave4-final-unsigned.log`；全部78个图标映射无缺失。
- 69张扩展票按用户“完整实现+图标存在”标准全部完成。Google入口需要自配iOS OAuth client；Nous与JetBrains各设备独立授权，后者需要主动导入官方export。生产兼容及真实账号/设备观察仍分别记录。
- 本批10组Pi全部交付并处理确认问题；上一批10组保留为历史。见[第四批Pi](.scratch/provider-expansion/pi-wave4/README.md)及[统一验证记录](.scratch/provider-expansion/validation-record.md)。旧截图与合成响应不冒充真实登录或完整视觉验收。
- 用户已反馈 MiniMax 与 GLM 真实查询成功，Watch App 可启动；这一历史观察不扩展为其他提供商的真实账号或设备验收。

详细范围与证据见 [实现验收记录](docs/implementation-status.md) 和 [提供商接入说明](docs/provider-integration.md)。

## 数据与运行边界

凭证保存在 Keychain 中，账号配置和额度快照单独保存。原有可同步凭证沿 iCloud Keychain 通道同步；Nous 与 JetBrains 旋转凭证只保存在授权设备，开启同步也不改变这一限制。无需自建查询服务器或 Mac 常驻采集进程。

后台刷新、iCloud 传送和 Widget 更新由系统调度，不保证固定间隔或即时到达。当前配置同步使用 iCloud，尚未接入 WatchConnectivity 手机直传通道。设备离线或同步延迟时可能分别发出通知。

部分提供商使用非公开客户端接口，接口变化可能影响登录和额度查询。预计重置时间到达只会让旧数据进入“待更新”，不会据此宣称额度已经恢复。

## 许可证

除单独标注许可的第三方资源外，TokenPulse 的代码采用 **[Apache License 2.0](LICENSE)**。

版权及来源说明见 [NOTICE](NOTICE)。渠道图标分别保留 Lobe Icons 的 MIT 许可与 Vercel 官方资源的 Apache-2.0 许可，完整条款见 [ProviderIconNotices.txt](TokenPulse/Resources/ProviderIconNotices.txt)。

## 致谢与参考

- **[Pulse 原仓库](https://github.com/qunqin24/Pulse)**：产品体验、提供商接入研究与渠道图标的参考来源。
- **[Lobe Icons](https://github.com/lobehub/lobe-icons)**：渠道矢量标识，经 Pulse 引入；许可及改动说明见 [ProviderIconNotices.txt](TokenPulse/Resources/ProviderIconNotices.txt)。
- **[OpenAI Codex](https://github.com/openai/codex)**：设备授权与剩余手动重置次数的接口依据。

品牌名称及标识归各自权利人所有，其使用仅用于识别兼容服务。

## 友情链接

- [LINUX DO 社区](https://linux.do/)

## 项目文档

- [功能规格](docs/spec.md)
- [各提供商额度展示与通知设计](docs/quota-source-design.md)
- [OpenCode Go Provider 接入研究](docs/opencode-provider-research.md)
- [Claude Fable 额度研究](docs/claude-fable-research.md)
- [领域术语](CONTEXT.md)
- [设备独立刷新设计](docs/adr/0001-device-side-refresh.md)
- [TestFlight 演示模式审核说明](docs/beta-review-demo.md)
- [任务清单](openspec/changes/ios-watch-quota-monitor/tasks.md)
