# 火山方舟 Coding / Agent Plan

选择“火山方舟”，在安全输入框填 `AccessKeyID:SecretAccessKey`。使用英文冒号，按第一个冒号分割；SK 内的冒号保留。AK/SK 作为同一 `ProviderCredentialEnvelope` 存入本机 Keychain，沿现有已启用的 iCloud Keychain 路径同步。它们不会写入账号配置、额度缓存或日志。配置只持有凭证的 SHA256 身份；AK 或 SK 更新会重置旧缓存和提醒历史。关闭 iCloud 仍可本机保存和查询。地址、区域与服务不接受用户输入或服务端重定向。

iPhone 和 Watch 各自执行 CryptoKit HMAC-SHA256 签名，直接 GET：

- `https://open.volcengineapi.com/?Action=GetCodingPlanUsage&Version=2024-01-01`
- `https://open.volcengineapi.com/?Action=GetAFPUsage&Version=2024-01-01`

签名范围固定为 UTC 日历日、`cn-beijing/ark/request`；签名头按小写排序为 `content-type;host;x-content-sha256;x-date`，空请求体也计算 SHA256。两项读取并发执行，均不调用 arkcli、Mac、代查服务或产生模型推理。默认传输拒绝全部重定向，错误响应不会带着签名去另一个地址。

Coding Plan 使用 `Result.QuotaUsage` 的 `Level / Percent / ResetTimestamp`，保留已用比例。Agent Plan 使用 `AFPFiveHour / AFPWeekly / AFPMonthly` 中的 `Quota / Used / ResetTime`，按各窗口计算使用率及剩余 AFP（Agent Flow Points）。两个套餐各自带独立 scope 和窗口 ID，不合并预算池。Quota=0 表示没有该额度窗口，缺少 Used 或 Percent 保持未知。未知周期不猜测；月度不推算为固定 30 天的重置周期。重置时间只采用服务返回的秒或毫秒 Unix 时间，0 表示未提供；预计重置仍不代表查询确认。

一个套餐未订阅、无额度或失败时，不抹去另一个成功返回的套餐。两个都失败时凭证拒绝优先于网络问题；两个都无套餐返回 `subscriptionRequired`。整个刷新失败沿现有监控规则保留同一凭证身份的旧成功数据与采集时间。新凭证身份的失败不恢复旧账号余额。卡片、详情、Watch、小组件直接使用同一快照；演示包含 Coding Plan 和 Agent Plan。已用比例和明确重置时间使用现有额度告警/预计重置通知，AFP 不是货币，不开放钱包低余额设置。

## 独立签名验证与契约证据

- 参考 [Pulse 397c8fc4 固定研究](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/volcengine.md)。它明确没有真实 Ark Coding Plan，套餐回复形状来自 CodexBar 解析研究与合成 fixtures；本次也没有把这些 fixtures 当真实捕获。
- 直接核对火山官方 [Python SDK SignerV4.py d88be4d8](https://github.com/volcengine/volc-sdk-python/blob/d88be4d8028e35563b27ff1bafe3c1f7ed1ab656/volcengine/auth/SignerV4.py) 和 [Util.py](https://github.com/volcengine/volc-sdk-python/blob/d88be4d8028e35563b27ff1bafe3c1f7ed1ab656/volcengine/util/Util.py)，确认 HMAC 派生顺序、`request` 终止符、头排序与规范编码。
- `scripts/verify-volcengine-signing.py` 是根据官方方案独立编写的离线 Python 计算，输入均为合成测试 Key。它生成 Coding、Agent 和非 ASCII 查询三个完整 Authorization 向量。执行生产 Swift 签名代码的离线 macOS driver，与 Python 输出逐字比较已通过；不访问网络、环境凭证或 Keychain。
- `VolcengineProviderTests` 覆盖这些固定向量、请求契约、格式/控制字符、缺失和畸形字段、秒/毫秒重置、单套餐未订阅/部分失败、两端共用快照、凭证变更隔离、本机恢复/删除、双套餐提醒及演示。生产 Domain/Providers/Monitor/Demo/Reminder 代码和新增测试在临时 macOS 模块里以 Swift 6 语义 typecheck 通过。此项不等于 iOS/watchOS target 构建。

本分支未运行 xcodebuild 或模拟器；XCTest 执行与完整 unsigned App/Widgets/Watch 资源构建交由 root 的统一验证槽。没有读取真实用户 AK/SK，也没有火山真实账号、权限、签名服务接受结果、凭证失效、iCloud 到达或 Watch 离线独立刷新证据。真实验收仍待用户授权提供账号和设备后执行。

图标来自既有 Lobe Icons 源 commit `a94750e3f5f8fc33757b839d85030e742284e43a` 的 `packages/static-svg/icons/volcengine.svg`，MIT，来源/版权/许可已记入 `ProviderIconNotices.txt`。保留 SVG 路径，设黑色与显式尺寸并启用矢量保留及模板渲染。图标三个产品目标的实际资源编译待统一构建验证。
