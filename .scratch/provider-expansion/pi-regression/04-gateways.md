# 04-gateways 回归审查报告（Sub2API / Bifrost / LiteLLM / LLM API Key Proxy / New API / GatewayQuotaSupport / QuotaMonitor）

快照：`/private/tmp/tokenpulse-pi-regression-20261002-222956/04-gateways/snapshot`
工作目录：`/tmp/tokenpulse-pi-regression-20261002-222956/04-gateways/work`
方法：只读快照源码；将生产实现逐字抽取为独立 Foundation harness，用 fixture（假 Key、假响应）执行真实解析/绑定逻辑。未访问任何真实账号、Keychain、home、环境变量或网络。

## 一、发现

**没有发现可复现问题。** 在本子任务的重点面（baseURL/query/redirect、Key 与站点身份、单位/分母/额度禁用/无限、Decimal 与多 scope 不相加）上，135 项动态检查全部通过，未发现具有具体触发输入和用户影响的缺陷。以下为审查中注意到、经评估不属于缺陷的行为（附理由，非漏洞清单）：

1. `TokenPulse/Providers/NewAPIProvider.swift:199-209` — `quota_display_type=TOKENS` 时 `remainingCount` 为 `NSDecimalNumber(13.155).doubleValue = 13.155000000000001`。`remainingCount` 本身就是 Double 展示字段（精确值另有 `exactCounts` 通道的 Decimal），既有测试按 1e-12 精度断言，属已知转换噪声。
2. `TokenPulse/Providers/NewAPIProvider.swift:186-190` — `api/status` 请求失败（如网关未暴露该路由返回 404/500）会使整次 New API 刷新失败为 `.server`。这是刻意的 fail-closed 设计（单位未知时不得伪造货币余额），docs/newapi 集成文档与“余额单位未知”分支语义一致。
3. `TokenPulse/Providers/LiteLLMProvider.swift` / `Sub2APIProvider.swift` 对无法解析的 reset/expires 日期字符串抛 `unreadableResponse` 整次失败，而 `LLMProxyProvider.swift:34` 用 `try?` 局部跳过。各 provider 文档分别声明了各自策略（LLMProxy 明确“畸形组局部跳过”），属逐 provider 设计差异。
4. JSON 数字（非字符串）形式的 Decimal 在本机 Foundation 上解码无精度损失（实测 `16.335382880000000001` 逐字保留），叠加 `GatewayAmount` 字符串路径的 38 位有效数字校验，无实际风险。
5. Foundation 行为差异实测：`URLComponents.host` 对 IPv6 返回带方括号 `"[::1]"`，`URL.host` 返回 `"::1"`。快照在解析时只用 `URLComponents.host`（`NewAPIProvider.swift:17-77` 的方括号分支依赖它，实测成立），`sameOrigin` 只比较两个 `URL`（两侧一致），无混用错配。

## 二、实际执行的检查

### 2.1 审计的源码（快照内路径）

- `TokenPulse/Providers/GatewayQuotaSupport.swift`（地址规范化入口、fingerprint、GatewayAmount、checkedAdd、percentage、date、reply/data 请求契约）
- `TokenPulse/Providers/NewAPIProvider.swift`（GatewayServerAddress、localHTTPHost、sameOrigin、GatewayProviderTransport、GatewayRedirectDelegate、NewAPIProviderClient）
- `TokenPulse/Providers/Sub2APIProvider.swift`、`BifrostProvider.swift`、`LiteLLMProvider.swift`、`LLMProxyProvider.swift`
- `TokenPulse/Providers/ProviderIntegration.swift`（envelope/transport 选择）、`ProviderHTTP.swift`、`WalletProvider.swift` 的 `ProviderDecimal`
- `TokenPulse/Application/QuotaMonitor.swift`（bindScopedCredential、refresh 指纹防线、mergeSynchronized、replaceCredential、addAccount）
- 对应测试：`TokenPulseTests/{Sub2API,Bifrost,LiteLLM,LLMProxy,NewAPI}ProviderTests.swift`、`QuotaMonitorTests.swift`、docs/{sub2api,bifrost,litellm,llm-proxy}-provider-integration.md（语义对照）

### 2.2 动态 harness（真实生产代码，非平行实现）

`work/build_core.py` / `work/build_monitor.py` 按行号把上述文件逐字抽取为 `gateway_core.swift` / `gateway_core_monitor.swift`（唯一改动：`NewAPIProvider.swift:113-127` 的 `sourceCredentialIdentity` 非 gateway 分支在独立构建中裁剪为 gateway 分支，已标注）。

命令与结果（macOS Foundation，无网络）：

```
cd .../04-gateways/work
python3 build_core.py && python3 build_monitor.py
swiftc -O -o checks mainsrc/all.swift && ./checks          # 118 PASS / 0 FAIL
swiftc -O -o monitor_checks mainsrc/mon_all.swift && ./monitor_checks  # 17 PASS / 0 FAIL
```

输出存档：`work/out.txt`、`work/mon_out.txt`。

### 2.3 覆盖的检查点（全部 PASS）

**baseURL / query / redirect**
- 地址规范化：大小写、默认端口剥离（https:443、本地 http:80）、尾点 host、尾部斜杠、`/v1` 与 sub2api 专属 `/v1/usage` 后缀剥离、部署前缀保留；省略 scheme 自动补 HTTPS；userinfo/query/fragment、路径穿越（`/a/../b`、`%2F`、`%2e%2e`）、公网 HTTP 全部拒绝；本机/私网 IPv4（含拒绝 `127.00.0.1` 变体、`0177.*`、`2130706433` 等）与 IPv6（`[::1]`、`fc00::/7`、`fe80::/10` 接受；`fec0::1`、公网 v6 拒绝）判定；`http://[0:0:0:0:0:0:0:1]:80/v1 → http://[::1]` 压缩规范化；`GatewayProviderTransport.data` 的重验证路径接受规范化 IPv6 端点。
- query：经 `GatewayQuotaSupport.reply` 发送含 `+ & 空格 / # %` 的 user_id，实际 URL `...?user_id=user%2B1%26team_id%3Dother%20team/id%23frag%3Dx%2520y`，单一 query item，逐字往返还原，host/path 不受影响，无 fragment 泄漏。
- redirect：`sameOrigin` 对 scheme/host/port 变化全部拒绝（含默认端口等价）；`GatewayRedirectDelegate` 跨 origin 返回 nil（既有 XCTest 静态覆盖，本次静态复核）；`GatewayProviderTransport` 对公网 HTTP 在发送前抛 `invalidCredentialData`（实测不触网）。
- New API 请求契约：`/prefix/v1/dashboard/billing/subscription`、`/prefix/v1/dashboard/billing/usage`、`/prefix/api/status` 三连，前两个带 `Bearer`，status 不带凭证。

**Key 与站点身份**
- `fingerprint = SHA256(provider.rawValue + 规范化地址 + Key)`：`https://RELAY.example:443/prefix/v1/` ≡ `relay.example/prefix`；Key、站点、provider 任一不同 → 指纹不同；`base()` 拒绝跨 provider envelope；envelope 重编码后指纹稳定；Key 含空格/空 Key 拒绝。
- QuotaMonitor（17 项动态检查）：addAccount 绑定规范化地址+指纹、缺 serverAddress 的 gateway envelope 拒绝；refresh 对外来指纹快照拒绝且不落盘（`QuotaMonitor.swift:169` 防线实测命中）；Keychain 滞留旧 Key 而配置身份已更新时零查询、旧服务器快照清除、失败为 invalidCredential；mergeSynchronized 无法复活旧身份快照；replaceCredential 更新地址、清除旧快照、拒绝垃圾凭证。

**单位 / 分母 / 额度禁用 / 无限**
- New API：分单位换算 `25.5 − 1234.5/100 = 13.155` 精确；USD/CNY 货币、TOKENS→tokens 单位+remainingCount、CUSTOM/空/display_in_currency=false→无钱包不造百分比；无限需三个哨兵同时为 100000000（部分哨兵不算）；负余额 −12.345 如实保留；success=false、负值、null、boolean 响应全部拒绝。
- Sub2API：字符串余额 38 位精确；points/tokens 等非货币单位 `isMonetary=false`；只有无 quota/subscription 时 root remaining 才作为钱包；`isValid:false` → invalidCredential 而非空账号；月度 limit 0 不构成分母；只有明确 `remaining<=0` 才标已用尽。
- Bifrost：`is_active=false` → 空窗口 + “虚拟 Key 已停用”状态文本，无 0%；无预算 → “未配置可读取预算”；零上限跳过；缺 current_usage 保持未知不补 0。
- LiteLLM：blocked/expired/revoked/deleted → invalidCredential；key/info 403/404 → 确认状态文本 + 空窗口且只发 1 个请求；max_budget 缺失 → 保留已花费、无百分比、无虚构耗尽。
- LLM Proxy：每组独立 `100−remaining`；0 才是 exhausted；越界/布尔/缺失组局部跳过；对象重排 id 稳定。

**Decimal 与多个 scope 不相加**
- Bifrost 三层（key/provider/model）预算为 3 个独立窗口、id 互不相同；override 仅在 forever/cycles>0 时 `checkedAdd` 入同一预算，负数/未知模式/过期 cycles 不生效；1h 子日周期按 last_reset+duration 仅投射未来，24h 及以上、过旧 last_reset 不投射；同 id 出现在不同 scope 共存、同一 budgets 数组内重复 id 拒绝。
- LiteLLM 团队与用户预算两个窗口（40% 与 12%）互不相加，返回身份矛盾（foreign user_id）拒绝；remaining 用 `checkedAdd(limit, -spent)` 保留 18 位小数。
- Sub2API quota/限流/订阅钱包各自窗口；LLM Proxy 不把最小剩余值合并成总额度；`checkedAdd` 溢出（`Decimal.greatestFiniteMagnitude + 1`）抛错；`percentage` 负分子拒绝、零分母返回 nil；`ProviderDecimal` 39 位、指数形式拒绝。

## 三、未覆盖范围

- 完整 XCTest 未由本任务执行（按约定由 root 统一串行运行）；本报告不声称 XCTest 已跑。
- 未发起任何真实网络请求：跨 origin 重定向只做了 delegate/sameOrigin 静态与逻辑级验证，真实服务器 30x 行为、`waitsForConnectivity` 本地网络权限竞态未实测（既有 `testProductionGatewayTransportReachesLoopbackHTTPWithoutCredentials` 覆盖 IPv4 回环实连）。
- harness 在 macOS Foundation 上运行；iOS Foundation 的 `URL/URLComponents` 边缘差异（如 IPv6 host 形态）以快照既有 XCTest 在 root 处复核为准。
- UI/Watch/Widget 展示与 NotificationPlanner 提醒链路仅静态浏览；DemoMode、`retainingWalletAfterPartialFailure` 对 gateway 路径无操作（gateway 快照不带 walletFailure），未单独动态验证。
- 快照中不存在实现的其他 provider 未研究；图标验收不属于本子任务。

## 四、XCTest 补充建议

`work/GatewayRegressionSupplementTests.swift`（仅语法 parse 验证，未执行）新增 4 项现有套件未覆盖的防线：
1. QuotaMonitor 对外来指纹快照的拒绝（现有测试只走 network 失败路径）；
2. Bifrost 负 override 不得改变上限、source_name 只进展示名不进身份、同数组重复 id 拒绝；
3. GatewayProviderTransport 重验证路径接受规范化 IPv6 端点；
4. `GatewayQuotaSupport.reply` 查询编码对 `+ & / # %` 的逐字往返。

— 审查完毕，未扩大研究范围。
