# Nous 设备本地旋转凭证与共享额度架构审查

审查基线：root `5c0fb99`，分支 `sol/review-device-local-credentials`。2026-10-03 只读检查代码，未执行 Xcode/模拟器、Keychain API、真实账号或凭证访问。唯一新增文件是本记录；协议事实由 sol_web 67 研究负责，以下是已有调用链与最小正确扩展要求。

## 结论

现架构已经把账号配置、额度快照和提醒 ledger 与秘密 Keychain 分开，因此可继续共享 Nous 的配置/快照。它尚不支持在同一 provider 下让每台设备独立保留旋转 refresh chain：现存同步凭证 adapter 只有全局开关，会双写并读取最新项后回填，且 refresh 的晚到保存缺少凭证 CAS。应给 Nous 单独设备本地 adapter/coordinator，不改变其它 provider 的既有同步与刷新行为，也不引入当前没有调用场景的跨进程锁。

## 代码证据

- [SynchronizableCredentialStore](../../../TokenPulse/Platform/SynchronizableCredentialStore.swift):36-40 无条件本地写入，开启同步时再写 `synchronizable=true`；47-76 同时读取两种项，按 modificationDate 选择最新并双向回填。`syncEnabled` 是整个 store 的开关，没有 provider/账号策略。只在 envelope 放 local-only metadata 不够：读取、回填、云同步预热都可能传播秘密。
- [AppRuntime](../../../TokenPulse/Application/AppRuntime.swift):42/58-64 把同一同步 store 交给 monitor 和所有 AccountQuotaClient。177-182 用户 iCloud 开关直接修改整个 store；185-200 synchronizeNow 对所有账号执行凭证读取，再共享配置/状态/ledger。需要按 provider 跳过 Nous 秘密读取/同步，不能为 Nous 关闭其它账号 iCloud。
- [AccountQuotaClient](../../../TokenPulse/Application/AccountQuotaClient.swift):12-17 在异步 refresh 后无条件保存旋转凭证，并在 quotaResult.updatedCredential 后再次无条件保存。若 A refresh 请求在等待时用户已保存重登录 B，A 的晚结果会覆写 B。
- [QuotaMonitor](../../../TokenPulse/Application/QuotaMonitor.swift):137-180 的 refreshingAccountIDs 防重复 snapshot refresh；credentialRevisions 仅在异步 client 完成之后检查。296-320 的 replaceCredential 先保存 B 再增加 revision，能阻止旧快照落库，不能阻止上述 client 先覆写 Keychain。删除路径虽会最终清理已移除账号，CAS 仍应阻止晚保存重新制造旧条目。
- QuotaMonitor:386-424 用 credentialIdentity 保护来源并写入共享配置；324-370 合并共享配置/状态时以同 identity 筛选快照。[ICloudSyncRuntime](../../../TokenPulse/Platform/CloudAccountSyncStore.swift) merge/mergeStates 同样用配置 identity 丢弃不匹配状态，并重新绑定提醒 ledger。若 Nous 的 identity 取 access/refresh token hash，两设备独立 grant 及每次 token 轮换都会被当成换账号，破坏共享与提醒去重。
- [KeychainCredentialStore](../../../TokenPulse/Infrastructure/KeychainCredentialStore.swift) 已有 ThisDeviceOnly 的本地实现，但 runtime 不使用它；它不是提供商路由或 rotation coordinator。新 adapter 可复用其平台思路，使用独立 service、显式 synchronizable=false 和 AfterFirstUnlockThisDeviceOnly，不能混入同步 store 的同一项/回填逻辑。

## 实际刷新进程与 owner

iPhone `TokenPulseApp` 创建一个 AppRuntime，BGAppRefreshAdapter 执行该 runtime 的 refresh。Watch delegate 持有一个 AppRuntime，前台按钮/sceneActive 与 WK background task 都调用同一 runtime/monitor。已有 monitor gate 对该实例 accountID 防重复刷新。

两个小组件 target 没有 AccountQuotaClient、ProviderQuotaClient、AppRuntime 或网络 quota 调用：`QuotaTimelineProvider.entry`、`WatchQuotaTimelineProvider.entry` 与 WidgetAccountQuery 只 load WidgetSnapshotStore，timeline 仅改变显示日期；AppIntent 仅配置/选择实体。[QuotaWidgetContent](../../../TokenPulseWidgets/QuotaWidgetContent.swift):45-56/104-120 是实际读取位置。PBX 的应用 client/monitor/runtime 只进入 iOS App/Watch App source phases。因此当前 Nous rotation owner 可以是每设备应用中的一个长期存活 coordinator，无需 Keychain 锁/跨进程 lease。

一个 actor 的异步方法会重入，并不自动把跨 await 的 load-refresh-save 变成事务。新的 Nous coordinator 必须有 accountID 的 in-flight/pendingTask gate，且不能在每次 AccountQuotaClient 值初始化时新建独立 owner。登录后验证若会刷新 active chain，也必须走这个 owner；Widget 保持只读，未来如加入 extension 网络刷新再重新审查进程所有权。

## 最小扩展点（已与 sol_web 对齐）

1. **提供商拥有的秘密存储策略。** 保留默认 shared/synchronizable；Nous 为 deviceLocal。web 组计划给 CredentialStoring 增加 provider-aware 方法并提供旧方法的默认适配，Nous device-local vault 独立 namespace。调用处只接 QuotaMonitor 的新增/读取/替换/清理、AccountQuotaClient 写入和 runtime 同步过滤；不让所有 provider 修改认证代码。读取时必须从当前 account/config 得到 provider，不能先读同步秘密才能判 local-only；新增账号配置落库前的 save 已有 provider 参数。delete/失败添加清理需要保留 provider context，或对 UUID 做有界的两个 namespace 清理。
2. **可共享的稳定账号来源。** web 组确认准备使用官方 account 响应 `user.privy_did` 与 `organisation.id`（或 `access.organisation_id`）作为 Nous account/workspace scope。按 provider/已核实 issuer-origin/subject/workspace 算稳定 identity；不包含设备 ID、grant ID 或 token 字节。provider 每次授权/刷新必须核验实际服务器身份与当前共享配置相符，不能只相信可编辑 metadata 的 hash。不同登录用户/工作区必须改 binding 并清缓存/提醒；同一 scope 的设备独立 grant 和自动 rotation 不更新配置 modifiedAt 或重置 ledger。
3. **新 provider 专用 CAS 旋转流程。** 长期 owner load 本地 credential + generation → refresh → 原子 CAS(expected 原串/generation) 保存新链 → quota。200 已旋转令牌先安全保存，后续 quota 失败不能丢掉新 refresh token。CAS 失败不覆盖新登录，也不发布旧 snapshot。状态标记同样 CAS：timeout/401/unknown-result 的 needs-relogin 不能把晚到旧 A 错误套到新 B。delete 后保留 generation/tombstone 直到旧 in-flight 结束，避免只比较原串的 ABA。
4. **不可重放的未知结果与重启。** 单次旋转协议的 POST 发出后进程被杀，也属于未知结果。建议 vault 在 POST 前持久化极小 pending/uncertain 标记；200 CAS 新链时原子清除。重启遇 pending 不自动重放旧 refresh，可继续使用仍有效 access 并请求再授权。web 组也计划将未知 POST 结果标 needs-relogin、明确 WAF 挑战不删除原链；判定“请求未被认证服务消费”必须有协议证据，不能将任意 timeout 当安全重试。
5. **Watch 独立授权。** 当前 Watch 页面只有等待同步配置/显示/手动刷新，没有独立登录 UI。设备本地秘密不从 iPhone 移交时，Watch 必须有 Nous 专用 device-code 授权入口（已有共享 Foundation 认证协议可复用）；授权结果必须匹配完成时的当前配置 identity，再保存 Watch 本地 grant。绑定在授权中途被手机/iCloud 改变也应拒旧结果。未授权 Watch 可显示共享快照，但需明确“此设备需授权/暂不可刷新”，不能称其已经独立刷新。该本地状态不应被共享成全账号凭证失效或清掉其它设备有效数据。

## 测试要求

全部使用 isolated service/fixtures/in-memory store，不访问真实用户 Keychain。真实 Keychain fixture 测试由 root 在隔离 namespace 执行。

| 范围 | 最小有效用例 |
| --- | --- |
| store residence | 开启/关闭/重开 iCloud 后 Nous 永不写、读、回填 synchronizable=true；现有 synced provider 三种既有 backfill 测试仍通过；provider/envelope 不匹配不能把 local-only token误写 shared；重启读取与删除清理隔离 |
| stable identity | iPhone grant A、Watch grant B、A→A2 rotation 均匹配同 user/workspace identity；配置/额度/ledger正常共享且不清除；其他 subject/workspace 的 grant严格拒绝，不复用缓存 |
| owner/gate | 同时 foreground/background/手动刷新只消费一次 RT；独立 AppRuntime/验证调用应共享同 Nous owner；Widgets timeline/query保持无 token/网络副作用 |
| late-save | 人为挂起 refresh A，期间保存重登录 B、删除账号、或变更共享 binding；A的成功/失败/unknown-result全部不能写回 B、制造条目、改 auth 状态或落旧snapshot；含 ABA 与 CAS失败 |
| durable rotation | 200旋转先保存，后续quota失败后重开仍使用A2；POST前pending写失败不发送POST；请求发出后崩溃/timeout留uncertain且不自动重放；明确挑战与真实invalid_grant分开，仍有效access不被误清 |
| Watch/merge | Watch只有共享config/snapshot且无local secret时显示缓存和需授权；独立device grant后手机离线可请求；中途配置变更拒旧授权；同scope快照/ledger合并不碰secret，设备缺凭证失败不污染另端授权状态 |

没有必要新增通用跨进程锁、改变所有 OAuth provider 的 token身份、关闭全局 iCloud 或复制一次性 refresh chain到 Watch。最小正确改动集中在 Nous 的 residence/rotation owner 与少数 owner-aware 调用 seam；root 统一审查并运行回归。
