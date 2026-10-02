# Alibaba Personal Token Plan

TokenPulse 的 `alibabaTokenPlan` 与 `alibabaCodingPlan` 分开注册。App 和 Watch 使用原生 HTTPS：在本设备用 AK/SK 生成短期 CLI console token，再读取个人 Token Plan。没有 bl 进程、Mac 转发或第三方代查；不读取、创建、删除或购买模型 Key/套餐。

账号必须明确选择服务地区（北京 `cn-beijing` 或新加坡 `ap-southeast-1`）及账号站点（国内 `domestic` 或国际 `international`）。SecureField 格式为 `AccessKeyID:AccessKeySecret`，按首个冒号切分，SK 内冒号保留；控制字符/空段/不可用字符拒绝。`sk-sp-` 推理 Key 不适用于此 console 路线。当前仅长期 AK/SK，不提供 STS session token 输入或自动续期承诺。所需 RAM 权限由账号持有人配置，SDK 不探测其他站点。

AK/SK 与 region/site 存在同一 secure credential envelope。配置中的地区与站点用于恢复 UI，envelope 为查询目标的权威来源；同步沿既有安全凭证与账号配置通道进行。缓存、云快照和提醒绑定 provider+实际 AK/SK+region+site 的单向 SHA256，忽略 claimed fingerprint。更换任何一项后旧 scope 读数不可复用，失败会保留错误状态。CLI token 仅存在当前请求链，不保存、不同步；手机与 Watch 各自生成。

## 固定官方协议

唯一实现依据为阿里官方 [modelstudioai/cli `8bbbbc722d70fb200641ef22b6f6d033aeae9f74`](https://github.com/modelstudioai/cli/tree/8bbbbc722d70fb200641ef22b6f6d033aeae9f74)。[refresh-token.ts](https://github.com/modelstudioai/cli/blob/8bbbbc722d70fb200641ef22b6f6d033aeae9f74/packages/core/src/auth/refresh-token.ts) 生成 `cliAccessToken`；[acs.ts](https://github.com/modelstudioai/cli/blob/8bbbbc722d70fb200641ef22b6f6d033aeae9f74/packages/core/src/client/acs.ts) 和 [client.ts](https://github.com/modelstudioai/cli/blob/8bbbbc722d70fb200641ef22b6f6d033aeae9f74/packages/core/src/client/client.ts) 明确空 body（不是 `{}`）、ACS3-HMAC-SHA256、直接 SK HMAC、不含 SigV4 派生链。

生成请求：POST `https://modelstudio.<region>.aliyuncs.com/modelstudio/cli/generateAccessToken`，`x-acs-action=GenerateCLIAccessToken`、`x-acs-version=2026-02-10`，空 query、空 body。签入 content-type、host、全部 x-acs-* 头，UTC 秒精度 date、每请求 UUID nonce。HTTP 和 token 内容均先验证。

[console/gateway.ts](https://github.com/modelstudioai/cli/blob/8bbbbc722d70fb200641ef22b6f6d033aeae9f74/packages/core/src/console/gateway.ts) 定义四组固定目标：

| 服务地区 | 账号站点 | HTTPS host | action |
| --- | --- | --- | --- |
| cn-beijing | domestic | bailian-cs.console.aliyun.com | BroadScopeAspnGateway |
| cn-beijing | international | bailian-cs.console.alibabacloud.com | BroadScopeAspnGateway |
| ap-southeast-1 | domestic | modelstudio-cs.console.aliyun.com | IntlBroadScopeAspnGateway |
| ap-southeast-1 | international | bailian-singapore-cs.alibabacloud.com | IntlBroadScopeAspnGateway |

Bearer form POST `/cli/api.json`，query 包含 action、`product=sfm_bailian`、`api=zeldaHttp.apikeyMgr./tokenplan/personal/api/v2/usage`；form 包含 region 与 JSON params。params 的 `Api`、`V=1.0`、`Data.cornerstoneParam` 按官方常量构造（protocol V2、console ONE_CONSOLE、productCode p_efm、switchUserType 3、consoleSite BAILIAN_ALIYUN）。不加入 switchAgent，不扩大为团队预算。默认 transport 拒绝全部重定向，响应还必须匹配请求 HTTPS host/port。

每层先检查 success/errorCode，然后仅展开官方 DataV2/data 路径及 result/JSON 字符串 envelope（最大深度有限）。NotLogined 重新生成 token 后最多再读一次；权限、签名、限流和其他失败不重试。没有自动地区 fallback，不发送 AK/SK 到 console host；console 请求只有短期 token。

[usage/token-plan.ts](https://github.com/modelstudioai/cli/blob/8bbbbc722d70fb200641ef22b6f6d033aeae9f74/packages/commands/src/commands/usage/token-plan.ts) 只读取 per5HourPercentage/ResetTime 和 per1WeekPercentage/ResetTime。[quota-box.ts](https://github.com/modelstudioai/cli/blob/8bbbbc722d70fb200641ef22b6f6d033aeae9f74/packages/commands/src/commands/usage/quota-box.ts) 明确 percentage 为已用比例 `[0,1]`（显示乘 100），reset 为毫秒 epoch。仅输出 5h/week，无虚构月窗、数量或钱包；不从比例单独断言供应商拒绝调用。缺少比例保留未知，空个人响应显示“未提供个人 Token Plan 额度”，不把缺失解释成零或无限；越界、Boolean、数值字符串和未知结构失败。独立窗口 ID 保留提醒 scope，reset 按真实值供 App/Watch/widget 使用。

## 离线验证与边界

本次只使用公开源码与 synthetic AK/SK/console token/响应。Swift 6 isolated Foundation module（真实 Models、ProviderHTTP、Volcengine key parser、Alibaba client）语义检查通过；实际离线 probe 通过官方签名 golden、四组目标、DataV2 比例/毫秒、一次 token 重取、错误与缺失语义。核心 XCTest 已对同一小模块 Swift6 typecheck；完整 XCTest、App/Watch/widget unsigned build 交 root 统一执行，未在本 worktree 启动 Xcode 或模拟器。

签名 golden 使用官方 acs.ts 原文件，**仅**将 `new Date()` 替换为 `new Date("2026-10-03T00:00:00Z")`、`randomUUID()` 替换为 `00000000-0000-4000-8000-000000000001`，Node 26 原生 TypeScript 执行 `signAcsRequest`。输入 AK `LTAIFixture`、SK `fixture-secret`、action/version/path/空 body 如上。北京 signature 为 `6fe665d5c65913a385e8e0268919d9449e0f8014aa199bc1e84eefb56085280e`，新加坡为 `877184d11610a528eaf6a9a5f7f72edf2c9d6901afe5871c01dcd2f5477fc374`。这两个固定结果写入 XCTest，不由 Swift 签名器反算期望值。测试还覆盖 form payload、凭证与 scope、失败换绑清缓存/配置恢复、提醒、图标/演示/widget、旧配置兼容。

图标复用已有 ProviderAlibabaCloud SVG：Lobe Icons 固定 `2e76c48721e91b9aaa40803a0fa2eb8aca7399c4`，`packages/static-svg/icons/alibabacloud.svg`，Copyright (c) 2023 LobeHub、MIT。原有 vector/template image set 与 Notices 已记录，新 provider 复用映射，不引入新艺术资源。

按用户最新“实现+图标存在”验收，本接入完成。真实账号 RAM 最小权限、console token TTL/生成是否撤销另一设备 token、真实数值与面板对照、地区错配、iCloud 同步及实体 Watch 观察尚未执行，均属于后续观察，不作为本票关票门槛；不宣称真实账号或设备验收通过。
