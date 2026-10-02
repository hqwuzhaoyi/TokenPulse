# 智谱国内版与 MiniMax 国际版接入

两项接入已实现，等待集成构建、XCTest 和真实账号/设备验收。这里只记录实现契约与验证边界，不将上游测量或模拟响应当成 TokenPulse 的真实验收。

| 提供商 | 添加账号所需凭证 | 查询地址 | 凭证保存 |
| --- | --- | --- | --- |
| 智谱国内版 `.zhipu` | 国内 Coding Plan Key | `https://open.bigmodel.cn/api/monitor/usage/quota/limit` | 绑定 `.zhipu` 的 API Key envelope |
| Z.ai 国际版 `.zai` | 国际 Coding Plan Key | `https://api.z.ai/api/monitor/usage/quota/limit` | 保留现有 `.zai` envelope |
| MiniMax 国际版 `.miniMaxInternational` | 国际 Coding Plan Key | `https://api.minimax.io/v1/token_plan/remains` | 绑定 `.miniMaxInternational` 的 API Key envelope |
| MiniMax 国内版 `.miniMaxChina` | 国内 Coding Plan Key | `https://api.minimaxi.com/v1/token_plan/remains` | 保留现有原始 Key 兼容性 |

添加时选择准确的地区条目，再输入该地区的 Key。相同品牌的账号不能共用地区配置。新地区凭证进入既有按账号 UUID 隔离的 Keychain 存储，不写入额度缓存或日志；凭证 envelope 的 provider 不符时，查询在发送请求之前失败。手机与手表均由 `AppRuntime → AccountQuotaClient → ProviderQuotaClient` 自行请求，没有手机代查或 Mac 依赖。同步到达和离线直连仍需真实设备证据。

## 智谱响应契约

`ZaiProviderClient(provider:transport:now:)` 由 provider 明确选择 host，并检查 HTTP 状态和 `success=true`、`code=200`。已知业务认证码 401/403/1000/1001 映射凭证无效，429 映射限流；拒绝消息中的 `coding plan` 映射未开通/已失效套餐，其他拒绝保留服务错误。该服务的业务码不是 HTTP 状态。

仅解析 `TOKENS_LIMIT`、`CREDIT_LIMIT`、`TIME_LIMIT`。周期单位为日(1)、小时(3)、分钟(5)、周(6)，`number` 必须为正整数；未知、非整数、布尔值、非有限或溢出的周期字段不被猜测。MCP 的 `TIME_LIMIT`、unit=5、number=1 是月额度标记。计数优先于百分比，`currentValue` 表示已用，`remaining` 表示剩余；缺失指标保持 nil。窗口保留提供商身份，时间只取有效的 epoch 毫秒 `nextResetTime`；五小时窗口没有重置时间时不合成时间。新地区小组件显示实际返回的所有窗口，包括 MCP。

## MiniMax 国际响应契约

`MiniMaxInternationalProviderClient` 只请求国际 host。仅当当前接口返回 HTTP 404 时，同 host 回退 `/v1/api/openplatform/coding_plan/remains`。认证、业务错误、限流、网络断开、取消、解析失败和无窗口均不回退；旧接口失败使用旧接口实际错误。国内客户端原有不回退行为继续保留。

上游文档声称仅 404 回退，但同固定版本源码对任何失败都会尝试旧接口。本实现采用文档明确条件；真实旧套餐是否需要更宽的回退条件仍待实测，不将认证错误视作兼容信号。

解析复用国内客户端的字符串/数字字段和根层/`data` 两种响应形状。`*_remaining_percent` 反转为已用比例；`*_usage_count` 表示剩余额度，只有明确总量和剩余量时才计算百分比。非有限和布尔数值不接受。新国际解析按窗口移除明确的 status=3、total=0、remaining_percent=100 未分配池，不把缺失总量或百分比补成零。其它 status=3 的无限状态沿用现有映射，仍需真实账号明确无限与未包含池的差异。

短周期有有效 start/end 才归一为实际周期，否则保留“短周期额度”与 `.other`，不虚构五小时；明确的剩余时间毫秒相对于采集时间计算预计重置。周窗口只在周字段存在时生成。每个返回窗口在卡片、详情、小组件与 Watch 沿用统一快照、采集时间和过期规则；失败保留上一份快照。

## 验证记录

2026-10-02 静态验证通过：修改文件的 Swift parser、provider/domain 的 `swiftc -typecheck`、14 个新增 `RegionalProviderTests` 的临时 macOS module type check，以及 `git diff --check`。静态 module check 不等同于 App/Watch target 构建。

新增测试覆盖：智谱真实参考形状的模拟响应；地区 host 和 Bearer 契约；跨地区凭证在网络调用前拒绝；状态码/套餐区分；周期和非有限字段边界；计数优先与 MCP；MiniMax 新旧接口、仅 404 回退、原错误与取消；未包含池/未知指标；widget 全窗口和采集时间；多账号创建、恢复、凭证/缓存隔离、删除和失败保留；另一个 monitor 接收配置后自行查询；缺失使用量不触发阈值提醒，过期时间不等同于已确认恢复。

待 root 集成后执行：`TokenPulseTests/RegionalProviderTests`、`MiniMaxQuotaClientTests`、`ProviderTests`、`DemoModeTests`、`PlatformTests` 和完整 unsigned `TokenPulse` target build。尚未运行这些 XCTest，不声称已通过。

真实验收仍开放：实际国内智谱和国际 MiniMax 套餐查询；失效、撤销与错误地区 Key；旧 MiniMax 套餐回退；本机安全凭证恢复与删除；iCloud 关闭时本机使用；iCloud 配置/凭证到达手表；手机离线后 Watch 新采集时间；真实通知、小组件和 Watch 显示。所有测试凭证是合成占位内容，没有访问用户真实密钥。

固定参考版本：Pulse `397c8fc4f1bd52180a452d2f3f0c099def97cf69` 的 [Z.ai/智谱文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/zai.md)、[智谱实现](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/ZaiUsageService.swift)、[MiniMax 文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/minimax.md)、[MiniMax 实现](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/MiniMaxUsageService.swift)。两个额度接口均为未公开契约，后续变更仍可能需要适配。
