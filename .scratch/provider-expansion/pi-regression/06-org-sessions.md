# 06-org-sessions 回归报告：Devin / Manus / Windsurf

执行者：Pi 回归执行者（独立冻结快照 `snapshot/`，未修改任何源码）。
复现产物：`work/repro.swift`（生产解析器逐字复制 + 最小领域桩）、`work/repro-output.txt`、`work/SuggestedOrgSessionTests.swift`（建议补充 XCTest，由 root 复核合入后串行执行）。

## 发现

### 1.（低）Manus：remaining > size 时 used 被钳制为 0，窗口自相矛盾（0% 已用、剩余>总额度）

- **位置**：`TokenPulse/Providers/ManusProvider.swift` — `exactUsage(size:left:)` 中 `guard left <= size else { return 0 }`（约 L124）；窗口构造在 `snapshot(_:accountID:collectedAt:)` L86–95。
- **触发输入**（最小）：`{"proMonthlyCredits":"200","periodicCredits":"300"}`（服务端若返回剩余大于额度上限，例如跨周期补偿或字段错位）。
- **预期 vs 实际**：该文件自身约定"不发明计数"（见 `testInexactDecimalDifferenceDoesNotInventUsedCount…`），剩余>总额度应视为不可信（used=nil / 不可读）更一致；实际返回 used=0。
- **实际**：`exactCounts = used 0 / remaining 300 / total 200`，`usedPercentage = 0.0`，`isExhausted = false`。
- **影响**：UI 显示"每月额度 0% 已用，剩余 300 / 总 200"，数据自相矛盾；不崩溃、不误报耗尽、不影响其他窗口。
- **证据**（`work/repro-output.txt` M5 行，生产代码逐字复制后编译运行）：
  ```
  -> used=0, remaining=300, total=200, used%=0.0
  PASS  M5 left > size (server inconsistency) actual behavior
  ```
- **建议**：在 `exactUsage` 将 `left > size` 改为返回 `nil`（与不可精确减法分支一致），或保留现状并由产品确认；建议测试见 `SuggestedOrgSessionTests.testManusRemainingAboveSizeClampsUsedToZeroAndKeepsCounts`（先钉住现行为）。

除此之外，三个 provider 在本任务关注面上未发现可复现缺陷。附一条不计入发现的观察：Manus 极端精度下（remaining=1e-38 of 3）`usedPercentage` 经 Double 舍入显示 100.0 而 `isExhausted=false`（M4b 证据行）；NSDecimal 128 位尾数使 38 位有效数字全程精确（M4a：`used=1e-38` 精确），`ProviderDecimal` 的 38 位上限与底层一致，无现实用户影响。

## 实际执行的检查

`work/repro.swift`：`swiftc`（纯 Foundation，macOS 本机）编译退出码 0，运行退出码 0。包含的生产逻辑逐字来源：`ManusProvider.swift`（RefreshTime/Credits/Envelope/snapshot/exactUsage）、`DevinProvider.swift`（Timestamp/Reply/snapshot）、`WindsurfProvider.swift`（WindsurfProto/snapshot）、`WalletProvider.swift`（ProviderDecimal）、`WalletExpansionHTTP.swift`（WalletDecimalValue/WalletDecimalArithmetic）、`ProviderHTTP.swift`（isoDate）。共 24 项断言/证据全部符合预期（详见 `repro-output.txt`）：

- **storage 有限键提取 / token-user 同源**（静态核对 + 现有测试引用，未执行 XCTest）：Devin 登录 profile 仅提取 `auth1_session` + `last-internal-org-for-external-org-v1-` 前缀键（`WebSessionContainer.swift` L215–218），token 与 userId 取自同一 `auth1_session` JSON 根（`DevinProvider.swift` L9–12）；Windsurf 四键（token/auth1/account/org）同一次 `readStorage` JS 单次求值快照（`WebSessionContainer.swift` L351–377，值上限 128、大小 256KB）。Manus 仅 `session_id` cookie，域/路径/过期校验在 `CookieWebSessionPolicy`。
- **org 显式选择**：Devin 对每个合法内部 org 生成独立凭据选项（id=org、标题"组织 org_…"、`credentials()` L13–23，≤64、去重、排序），配额请求带 `x-cog-org-id` 与 org 作用域 URL。
- **HTTP 重试边界**（静态核对）：`ProviderHTTP.send` 无重试；Devin 仅在首个拼写 404 时请求第二拼写一次（`DevinProvider.swift` L55–63），401/403/429/5xx 不触发第二次；Manus/Windsurf 单请求、20s 超时。
- **Manus Decimal 推导与持续恢复**：数值时间戳不猜 epoch（M2：`resetsAt=nil`）；ISO 字符串正常解析（M3）；38 位边界精确（M4a）；1/3 百分比精确十进制（M9）；负数/无数字段拒绝（M6/M7）；包裹信封优先取首个有数字段（M8）。
- **未分配额度状态**：Devin `has_quota_allocation=false` → 空窗口 + 状态"当前组织未分配套餐额度"（D1），保留 overage 钱包（D2）；Manus 仅 `totalCredits:"0"` → 单一总余额窗口不判失败（M1）；隐藏字段状态文案（D5）。
- **Windsurf protobuf**：剩余/重置字段、缺失=未知而非耗尽（W2）、101 越界拒绝（W3）、无字段→noQuotaWindows（W4）、11 字节超长 varint 拒绝（W5）、重置越界拒绝（W6）、重复字段拒绝（W7）、计划名/重置时间/耗尽判定（W1）。
- **Devin 其他**：秒/毫秒数值时间戳双解析（D3）、0→无重置且 100%→耗尽（D4）、百分比越界拒绝（D6）、cents 精确除 100（D7）。

补充建议测试（未被现有用例覆盖的三处）：`work/SuggestedOrgSessionTests.swift`。

## 未覆盖范围

- XCTest 未由本执行者运行（按规则由 root 统一串行执行）；`DevinProviderTests` / `ManusProviderTests` / `WindsurfProviderTests` 既有用例（含 404 双拼写、凭据指纹/账号隔离、请求头）未验证，仅静态引用。
- 客户端层 async 逻辑（真实 transport、WKWebView 登录流程、cookie 过期续期、UI 展示）未执行；复现仅覆盖三个 `snapshot` 解析器与 protobuf/Decimal 纯函数。
- 真实账号、真实网络响应、Manus `nextRefreshTime` 真实格式（毫秒 vs 秒）与 Windsurf 实际线上 protobuf 布局未验证。
- 其他 provider 未研究；快照内无这三个 provider 之外的注册/文档问题检查。
