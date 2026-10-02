# 66 Alibaba Token Plan：独立云端路径研究

调查日期：2026-10-02。结论：**官方源码建立了无需 bl 进程的云端认证、续期和 Personal Token Plan 查询候选；移动端账号/权限、地区与双端实测仍未验证**。这是七票中最具体的实施前验证候选，尚不能宣称 provider 可用。

## 来源与版本

- [Pulse 文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/alibaba-token-plan.md)及[实现](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/AlibabaTokenPlanUsageService.swift)，固定 commit `397c8fc4f1bd52180a452d2f3f0c099def97cf69`，只启动 `bl usage token-plan`。
- 阿里官方 Model Studio CLI，核对 commit `8bbbbc722d70fb200641ef22b6f6d033aeae9f74`：[usage command](https://github.com/modelstudioai/cli/blob/8bbbbc722d70fb200641ef22b6f6d033aeae9f74/packages/commands/src/commands/usage/token-plan.ts)、[token generation/refresh](https://github.com/modelstudioai/cli/blob/8bbbbc722d70fb200641ef22b6f6d033aeae9f74/packages/core/src/auth/refresh-token.ts)、[gateway](https://github.com/modelstudioai/cli/blob/8bbbbc722d70fb200641ef22b6f6d033aeae9f74/packages/core/src/console/gateway.ts)、[签名](https://github.com/modelstudioai/cli/blob/8bbbbc722d70fb200641ef22b6f6d033aeae9f74/packages/core/src/client/acs.ts)、[client retry](https://github.com/modelstudioai/cli/blob/8bbbbc722d70fb200641ef22b6f6d033aeae9f74/packages/core/src/client/client.ts)。这是实际官方客户端契约，不依赖第三方代理。
- [官方安装与认证](https://docs.modelstudio.console.alibabacloud.com/en/model-studio/cli/installation)，调查日读取：API key 与 console 认证是不同能力。源码含更完整的 AK/SK 路线，文档与源码要分别记录。

## 认证、续期与地区契约

查询 command 的 auth 明确是 `console`。`sk-sp-` Token Plan API key 是模型调用凭证，不能据 inference key 可用就宣称 console usage 可用。Token Plan 不是 05 Coding Plan，不能借用其控制台 `commodityType` 或套餐三窗口路由。

独立候选为用户明确配置自己允许的 AK/SK，再按官方客户端交换 CLI console access token：POST `https://modelstudio.cn-beijing.aliyuncs.com/modelstudio/cli/generateAccessToken`，国际 host 为 `modelstudio.ap-southeast-1.aliyuncs.com`；action `GenerateCLIAccessToken`、version `2026-02-10`，ACS3-HMAC-SHA256 签名，query 为空，按 `openApiQueryJson` 的空请求体签名。返回字段 `cliAccessToken`。STS securityToken 可作为生成调用签名头，但过期 STS 并不是长期续期来源。

官方 client 收到 console `NotLogined` 后用配置里的 AK/SK 生成新 token，仅重试一次。不是共享一次性 OAuth refresh token，因此两端可分别生成 token 的协议形态已具备；是否生成新 token 会撤销别处 token、RAM 权限、实际 TTL、地区错配以及 watchOS TLS/响应均需实测。当前自动 refresh 实现只从存储读取 AK/SK，没有传回 securityToken，不能照搬为 STS 自动续期保证。长期 AK/SK 被撤销时应需重新配置。

地区/site 必须由账号配置显式选择，不能把 Pulse 依次国际/国内试错当账号绑定。官方 gateway 四组合为：cn-beijing/domestic `bailian-cs.console.aliyun.com`、cn-beijing/international `bailian-cs.console.alibabacloud.com`、ap-southeast-1/domestic `modelstudio-cs.console.aliyun.com`、ap-southeast-1/international `bailian-singapore-cs.alibabacloud.com`。前两者 action `BroadScopeAspnGateway`，后两者 `IntlBroadScopeAspnGateway`。生成 host 依据 model base URL 推断 cn/intl；quota 依据 consoleRegion/site，实施须让它们一致。

## 查询与额度契约

Bearer + form POST `/cli/api.json?action=<action>&product=sfm_bailian&api=<encoded API>`；API 为 `zeldaHttp.apikeyMgr./tokenplan/personal/api/v2/usage`。form 有 `region` 与 JSON `params`，包含 `Api`、`V=1.0`、`Data.cornerstoneParam`（protocol V2、console ONE_CONSOLE、productCode p_efm、switchUserType 3、consoleSite BAILIAN_ALIYUN；如账号需要 switchAgent，应明确绑定）。data 无业务参数。outer HTTP 200 仍可能内层 `success=false/errorCode=NotLogined`，须先展开 envelope/JSON 字符串，不直接解析百分比。

当前官方 command 输出 `per5HourPercentage/per5HourResetTime`、`per1WeekPercentage/per1WeekResetTime`；Pulse 另支持 month 字段，但此次官方 command 没输出 month，因此不能承诺三窗口。Pulse 假设比例 0…1，数值超 1 丢弃；真实单位必须与控制台核对，不能按字段名随意乘除 100。reset 按上游毫秒 epoch，但也缺实际回包确认。该 personal route 不证明 Team shared credits 可用，不读/改套餐、成员、购买或创建 key。

## ADR 与最小验证（本次未执行账号步骤）

符合 [设备直连 ADR](../../../docs/adr/0001-device-side-refresh.md) 的候选是原生 HTTPS+签名，不运行 bl、Mac 或代查服务。公开源码可用同目录脚本复取。

1. 在允许此移动端使用的测试账号明确配置地区/site、可用 AK/SK 权限；不要执行 `bl auth login --console`，该流程可能创建普通 API key。本验证只生成自己明确授权的 console session 并读取 usage。
2. iPhone 最小客户端按固定官方签名/token/gateway 契约查询，记录 HTTP/内层 code、5h/week 数值、reset、采样时间及官方面板对照，凭证不进日志。
3. 同步配置给 Watch，由它自己生成 token；手机离线、CLI 不运行时查询。再测 token 过期/NotLogined 后双端各自生成与重读，检查会否互相失效。
4. 对权限不足、STS 过期、AK 撤销、region/site 错配、无 plan、month 缺失、account switch 保存脱敏结论。RAM 最小权限及生成动作是否开放给此账号是实际阻塞项。

已确认云端协议候选，**可用性仍未验证，票未完成**。通过后才立实施票，范围包括地区/site/身份配置、AK 与 console token 保护/同步、受限续期、比例与 reset 实值、双端 direct fetch、multiaccount、缓存/失效、UI/组件/提醒与真实验收；不能与 Coding Plan 合并或自动扩大到 Team plan。
