# 68 JetBrains 原生导入/续期：只读架构审查

2026-10-03，检查 root `2b530a3` 的 DeviceOAuthCredentialVault、ProviderScopedCredentialStore、QuotaMonitor 和 CloudAccountSyncStore，并与 sol_research 的 importPending → jbaReady → ready 提案对齐。本报告不重新调查 binary，也不修改生产源码。推荐保留设备本地 vault、generation CAS 和独立 JBA checkpoint；共享 grant marker 只能帮助拒绝已经观察到的重复导出，不能作为跨设备锁。

## 1. grant marker 与额度身份分开

初始导入可计算 `SHA256("TokenPulse/JetBrains/import-grant/v1\\0" + initialRefreshTokenUTF8)`。标记依据已解析的 refresh_token 原始值，不依据整个 central- export 文本（JSON 字段顺序、Base64 包装或可改 metadata 会绕过）；不包含 deviceID、licenseID 或 accountUUID，否则同 RT 用于另一个设备/账号时无法比较。拒绝空/control/不合法输入后再计算，不能把 token 值写进共享配置、日志或提示。高熵 token 的单向摘要不是可用授权秘密，但仍是关联标记，不需要展示给用户。

marker 只用于判断是否已经见到同一个初始 RT。它不证明账户身份，不判断同一 OAuth family 的不同 RT，也无法保证两设备离线/同时导入时，在任何一方发 HTTP 之前互相看到标记。不能用 marker 取代可信登录 lineage 或在联网查询里当 Authorization。

quota 的 sourceCredentialIdentity 应依据固定 HTTPS OAuth 响应建立的 subject（可加 issuer）、选定 license 和共享 localAccountID；两设备各自的 grant/RT/deviceID 不应让同一服务 scope 的快照不能同步。jba_login/email 可显示，但不替代 subject。合法续期保持已建立的 scope；收到身份不符的新认证结果要停止，不把旧 lineage 重新标成另一个 subject。无需将 quota.license 强行等同于导入 license_id。

### 最小共享数据选择

如果增加共享配置，建议可选、单调保留的非秘密记录集合 `{digest, ownerDeviceID}`；只存初始导入摘要，不共享 RT、JWT 或实时 token generation。每次导入增加记录，旧导入/删除账号记录仍可用于拒明显重放。即使不做历史集合，至少不要清除另一设备当前 marker。旧配置字段缺失时兼容解码为未知，不当作“已证新 grant”。

现 CloudAccountSyncStore.mergeConfigurations 使用整个 AccountConfiguration 的 modifiedAt LWW。仅新增 `[deviceID: marker]` 然后沿用该 merge，会被另一台设备的旧 map 覆盖，尤其两边同时修改提醒/收藏。若需要持久去重，应仅对 JetBrains grant 记录做 set-union，其它配置仍沿原 LWW/tombstone 规则；不要用本机时间戳判断 OAuth grant 先后。删除账户依旧删除账户，只保留去重事实，不恢复它的 tokens/配置。

若不愿修改共享 merge，较小方案是设备本地拒已处理的同 export，加两端独立登录导出的明确说明；可把已观察到的远端 marker 当额外 best-effort 检查，但不宣称强去重。共享 marker 即使有 union 仍不是分布式原子 claim。冲突后至少冻结匹配 marker 的本地轮换链并提示重新独立导入，而不是互相以新 RT 追赶。

UI 应提示“手机和 Watch 分别使用另一轮独立登录产生的导出”；再运行 export/再次复制同一登录状态不等于新 grant。无需用户阅读 digest，也不要因为标记不存在就表示双端不会相互失效。

## 2. checkpoint 必须早于 quota 成功

建议将初始导入和完整续期事务封装在同一 JetBrains module 内，由 UI/Monitor 调用 import/refresh，而不是由多个调用方自行排列 vault、网络、checkpoint 顺序。Vault 保存是凭证进度，成功快照保存是额度进度，两者不能组成“只有 quota 成功才保存凭证”的单个返回结果。

| 已持久化状态 | 下一步允许的操作 | 错误/重启后的行为 |
| --- | --- | --- |
| 未发送的合法新导入 | CAS 为 importPending 后发一次 JBA OAuth POST | CAS失败不发HTTP；pending写失败也不发HTTP |
| importPending / refreshPending | 等本次在途请求结果；禁止另一次同旧RT POST | timeout、断网、进程死亡、解析失败等都不能自动重放旧RT；进入/保留 uncertain并需新导入 |
| jbaReady（新RT、JBA access、有效期、已验证subject） | 用有效JBA access继续Register/ProvideAccess | mint失败、quota失败或重启均从该checkpoint继续，不回到初始RT |
| jbaReady但JBA access已失效 | 以该checkpoint保存的新RT，再CAS pending后开始下一次OAuth | 每次新消费仍先持久pending，绝不取回原导入RT |
| ready（本地AI JWT和同一verified scope） | 查询quota或按官方完整生命周期续期 | quota HTTP/格式错误只更新失败状态，不回滚已checkpoint的OAuth/JWT |
| tombstone / 被新导入替换 | 不允许旧任务提交 | 旧generation CAS失败后丢弃结果，不读取最新generation后盲save覆盖 |

成功 OAuth 响应一旦返回新 RT，必须在 Register/ProvideAccess/quota之前持久保存它。若新 RT/IDToken 解析、scope校验或保存失败，旧 RT已经可能被消费，不能退回ready让旧RT可重试。最小安全处理是保持pending/uncertain，需要新导出；可选择额外未验证响应checkpoint保存新secret，但不得据未验证subject发布scope/快照。无需为恢复而保留可再次发送的旧RT。

UI取消在消费可能已发生后也不恢复旧RT。已收到的可用新RT应先尝试durable CAS checkpoint，再停止后续mint/quota；如果Task取消使响应未知，pending状态已足以禁止重放。删除/替换期间返回的任务不能复活被删凭证。checkpoint成功后JSON/Quota失败也不改变已建立的source identity；同scope旧快照仍可作为带失败状态的历史读数。

现vault actor中的read/CAS/write在同一个同步actor段落完成，适合进程内CAS。OAuth网络await使actor可重入，所以调用者必须用CAS预先占住generation；仅在响应后CAS不能阻止两个调用者已经发送同RT。每账号in-flight合并可以减少重复，但相同RT被导入另一local UUID还需要grant marker拒重放。若未来让多个进程/多个vault实例主动轮换同一Keychain record，actor CAS不是跨进程原子锁；当前应保持一个设备内一个共享coordinator，widgets只读快照。

## 3. bootstrap 与 Monitor 绑定

初始未验证的导入不应作为“ready credential”交给 AddAccount/replaceCredential 后再在 quota查询时悄悄从未知identity变成subject+license。优先先在设备vault完成原生导入/发行并验证scope，然后把ready envelope交给既有账号绑定流程；固定accountUUID让取消/重试只触及同一导入事务。Watch导入已有共享账号时应匹配该账号expected identity，错误的个人license/subject不能改写共享配置。

初次bootstrap失败可以保留设备本地pending checkpoint供恢复或提示重新导入，但不要发布未验证scope，不沿用别的账号快照。对已存在账号重新导入，在新身份验证并绑定之前保持旧账号标签；绑定新scope后即使quota失败，既有Monitor应清除旧scope快照。

## 4. 最有价值的小范围回归

| 触发 | 应观察到的结果 |
| --- | --- |
| 同一generation两个refresh/导入调用 | OAuth POST最多一次；另一调用合并或CAS失败后停止 |
| HTTP返回新RT后Register失败；构造新的module模拟重启 | vault有新RT/JBAready；再次mint，不再发送初始RT |
| OAuth成功后quota 401/500/畸形JSON | 新RT与ready JWT仍保存，quota失败不回滚凭证 |
| POST timeout/解析失败/成功响应后的Keychain写失败 | pending/uncertain禁止旧RT；再次粘同export不能绕过 |
| pending之后删除或更换导入，旧响应晚到 | generation/tombstone获胜，无凭证或快照复活 |
| 续期scope一致 / OAuth subject改变 | 一致保留identity；改变拒绝，不能给旧账号换身份 |
| 已观察另一device使用同RT，改变export JSON顺序/license字段 | marker仍相同，发HTTP之前拒重复 |
| 两device先各自离线导入 / 同family不同RT | 不宣称可检测；UI说明与冲突后冻结行为准确 |
| cloud两份配置各新增marker，另有提醒/收藏修改 | 若实现共享union，两marker都保留，原配置LWW语义不变 |

本审查给出设计建议，不表示这些回归或真实OAuth并发已实跑。由负责实现的agent/root安排相关mock与统一XCTest；本次未启动Xcode或模拟器，也未读用户凭证。
