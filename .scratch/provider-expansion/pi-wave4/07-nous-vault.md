# Nous 设备本地凭证/旋转安全回归报告（冻结快照 07-nous-vault）

范围：`DeviceOAuthCredentialVault`、`ProviderScopedCredentialStore`（TokenPulse/Platform/DeviceOAuthCredentialVault.swift）、`NousSessionCoordinator`/`NousPortalAuthenticator`/`NousPortalCredential`/`NousPortalProviderClient`（TokenPulse/Providers/NousPortalProvider.swift）、`Ports`（TokenPulse/Domain/Ports.swift）、`AccountQuotaClient`、`AppRuntime`、`QuotaMonitor`。只检查新机制：synced/local 命名空间分离、防 wrong-provider 降级、single-owner + 生成号 CAS / pending-before-POST / delete-ABA、晚到成功/失败不覆写新登录、崩溃/unknown 不重放一次性 RT、missing-auth 不污染共享快照、现有 provider 默认兼容。

## 结论

新机制的核心安全不变量在真实源码上全部通过可执行复现验证，**未发现违反上述任一安全不变量的可复现缺陷**。发现 2 个低危、可复现的边角问题（见“发现”），均不破坏一次性 RT、CAS 或命名空间隔离。

## 实际执行的检查（复现脚本 `/tmp/tokenpulse-wave4-pi/07-nous-vault/work/repro/`）

方法：将快照中的真实源文件原样编译（Swift 6, `-strict-concurrency=complete`，纯 Foundation/CryptoKit，macOS 本机）：
- `src/`：`DeviceOAuthCredentialVault.swift`、`NousPortalProvider.swift`、`Ports.swift`、`Models.swift`、`AccountConfiguration.swift`、`ReminderModels.swift`、`ProviderHTTP.swift`、`WalletExpansionHTTP.swift`、`ProviderIntegrationCore.swift`（从 ProviderIntegration.swift 原样摘取 Envelope/Session/Error/Transport/编解码器；另含 3 个明确标注的 harness 桩：URLSession transport、gatewayAddress/providerRegion/gatewayIdentity 存根——均非被测机制代码）。基础设施替换：内存版 `DeviceOAuthRecordStoring`（不触 Keychain）+ 脚本化 `ProviderTransport`（不联网）。
- `src2/`：另加真实 `QuotaMonitor.swift` + `sourceCredentialIdentity`（按 NewAPIProvider.swift 原路径摘取，含 nous 分支原样）驱动监控层场景。

命令与结果（全部实际执行）：
- `swiftc -strict-concurrency=complete -swift-version 6 -o repro src/*.swift && ./repro` → `ALL CHECKS PASSED`（39 项断言）
- `swiftc -strict-concurrency=complete -swift-version 6 -o repro2 src2/*.swift && ./repro2` → 12 PASS / 1 项为脚本断言误标（见下）

通过的安全断言（对应任务清单）：

| 不变量 | 场景 | 结果 |
|---|---|---|
| synced/local 命名空间分离 | S1：nous 凭证只进 vault；普通 provider 只进 synchronized；vault 使用独立 keychain service（`credentialService + ".device-oauth"`） | PASS |
| 防 wrong-provider 降级 | S1：nous envelope 经 `.claude` 的 scoped save 被拒（`ProviderScopedCredentialStore.save` 的 `isDeviceOnlyEnvelope` guard）；无 provider 的读取直接抛错且不回填 synchronized | PASS |
| single-owner + 生成号 CAS | S5：delete 留 tombstone 且 generation+1；旧 generation 的 CAS 无法复活已删凭证（无 ABA） | PASS |
| pending-before-POST | S2：POST refresh 发生前 vault 中已持久化 `rotationState=pending`（脚本在 transport 回调内读取 vault 验证顺序）；成功后回写 active 且仅 1 次 POST | PASS |
| 晚成功/失败不覆写新登录 | S4：refresh POST 挂起期间完成新设备登录（vault.save → generation 前进）；放行 POST 成功响应后旧任务 CAS 失败抛 `CancellationError`，vault 仍为新凭证（rt-new/at-new） | PASS |
| 崩溃/unknown 不重放一次性 RT | S3：崩溃遗留 pending 状态 → 后续调用 0 次 refresh POST，仍用有效 AT 查询；S3b：网络超时 → 持久化 `uncertain`，RT 保留但过期后 0 次 POST、0 次带死 AT 的 GET | PASS |
| 终态销毁 RT | S6：`invalid_grant`/401 → `terminal` + RT 置 nil；429 安全拒绝 → 回 `active` 且 RT 保留 | PASS |
| 远端身份漂移 | S7：`/api/oauth/account` 返回不同 privy_did/org → invalidCredential + terminal + RT 销毁 | PASS |
| 设备属主绑定 | S8：他人设备（ownerDeviceID 不符）或他人 localAccountID 的 envelope 无法装入本机 vault | PASS |
| missing-auth 不污染共享快照 | M1（QuotaMonitor 真实代码）：无本机凭证的 nous 配置 → 仅本地 `lastFailure = .invalidCredential`，不伪造快照；`mergeSynchronized` 只应用更新的非空快照（静态核对）；`AppRuntime.synchronizeNow` 跳过 `requiresDeviceLocalCredential` 的账号，不触发 keychain 同步读取 | PASS |
| 现有 provider 默认兼容 | M7：`.claude` API Key 经 scoped store 正常存取于 synchronized 命名空间；`CredentialStoring` 扩展默认路由保持旧语义 | PASS |
| 删除清理 | M6：删账号后 vault tombstone + synchronized 命名空间均为空 | PASS |

## 发现（2 个，均为低危）

### F1（已执行复现）非 active 状态凭证过期后永不升级 terminal，一次性 RT 在本机 keychain 无限期滞留
- 位置：`TokenPulse/Providers/NousPortalProvider.swift:298-301`（`perform`）：`if state != "active" { guard state != "terminal", expires > now() else { throw RefreshFailure.invalidCredential } }` 该 throw 发生在第 331-339 行的 do/catch 之外，不会触发 `rotationState = "terminal"` / `refreshToken = nil` 的收尾写。
- 最小复现（`./repro` S3b，已执行）：vault 存入 ttl=1s 的 active 凭证 → refresh POST 抛 `URLError(.timedOut)` → vault 变为 `uncertain`（RT 保留）；时钟 +60s 后再次调用 → 抛 `invalidCredential`，**0 次 POST、0 次 GET**（不重放，安全目标达成），但 vault 内容保持 `uncertain` + 原 RT，此后每次调用同样提前抛错，除用户重新登录/删账号外无任何路径销毁该 RT。
- 预期：过期且非 active 的凭证应升级为 terminal 并销毁 RT（与 331-339 行对 quota 阶段 invalidCredential 的处理一致）。实际：secret 永久滞留。
- 用户影响：不产生重放或错误展示（每次刷新都提示凭证无效），仅设备安全存储中长期保留一个已不可用的 refresh token（密钥卫生问题）。

### F2（静态推断 + 复现脚本证实行为）iPhone 重新登录路径缺少 Watch 端强制执行的 expectedIdentity 一致性守卫
- 位置：守卫在 `TokenPulse/Application/QuotaMonitor.swift:301-308`（`replaceCredential` 的 `if let expectedIdentity` 分支），但 iOS 调用点 `TokenPulse/UI/AccountSettingsView.swift:368`（及 331）以 `replaceCredential(value, accountID: accountID)` 调用、`expectedIdentity` 恒为 nil；Watch 端 `TokenPulseWatch/WatchAccountPagesView.swift:289-291` 显式传入 `expectedIdentity`。iOS 登录页 `ProviderSignInView` 的 `DeviceLoginModel.authorize`（ProviderSignInView.swift:174-181）完成时不校验 `sourceCredentialIdentity`。
- 最小复现（`./repro2` M2，已执行）：已有 nous 服务账号（identity = 用户 A 指纹）在 iPhone 上经“重新登录”完成用户 B 的设备授权 → 新 envelope 直接落 vault、`credentialIdentity` 改绑为 B、旧快照被正确丢弃（无跨身份缓存复用）。
- 预期 vs 实际：Watch 端同操作会被拒（“请授权与此服务账号一致的 Nous 用户和组织。”）；iPhone 端静默改绑。防御深度不一致——若这是“iPhone 为属主可改绑”的意图，则 Watch 文案与其守卫表达的是更强约束。
- 用户影响：误用另一 Nous 账号重新授权会把既有服务账号（名称、提醒设置）静默换绑到另一身份；无跨身份数据泄漏（指纹改绑时旧快照被清空，M2 验证）。

## 复现脚本中 1 项断言误标说明

`./repro2` 中 `M2 old-user snapshot not reused` 显示 FAIL：系脚本断言写错——replaceCredential 后监控层会立即用新凭证刷新，得到的快照属于**新**身份（`sourceCredentialFingerprint` 已改绑为 B），并非旧用户快照被复用。核对代码路径（QuotaMonitor.swift:345-353 `bindScopedCredential(replacing: true)` 丢弃不匹配快照）后确认行为正确。

## 未覆盖

- 未运行 XCTest/`xcodebuild`/模拟器（按任务约束）；`TokenPulseTests/` 中新增测试未执行，不在本报告结论内。
- iCloud 同步真实链路（`ICloudSyncRuntime`/CloudKit）与真实 Keychain/iCloud keychain 行为未联网验证；`mergeSynchronized` 的跨设备合并仅静态核对 + 单机内存 actor 验证。
- Widget/Watch UI 层（`WidgetSnapshotStore` 写入 app group 的展示细节）仅静态检查 demo/正式 key 分离。
- `NousPortalAuthenticator.begin/poll`（device_code 流程）未做端到端复现（需要真实轮询交互）；其 envelope 构造与 `validateLocal`/fingerprint 一致性通过 S1/S8 的构造路径覆盖。
- 性能/并发压力（多账号并发刷新下的 vault 吞吐）未测。
