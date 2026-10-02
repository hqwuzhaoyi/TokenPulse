# 03-hosted-web 回归执行报告（RaycastAI / T3Chat / ZoomMate / QwenCloud / TypeSafe）

执行者：Pi 回归子任务（冻结快照 `/tmp/tokenpulse-pi-regression-20261002-222956/03-hosted-web/snapshot`，未修改任何源码）。
复现脚本位于 `/tmp/tokenpulse-pi-regression-20261002-222956/03-hosted-web/work/`，补充 XCTest 建议文件为 `work/HostedWebRegressionSupplementTests.swift`（供 root 复核合入后统一串行运行；本任务未运行 xcodebuild/XCTest）。

## 一、发现（共 2 项，均为低严重级别；未发现中/高危可复现问题）

### 发现 1（低）：T3Chat 4 小时窗口 reset 为 JSON `null` 时回退字段失效
- 位置：`TokenPulse/Providers/HostedWebProviders.swift:184`（`T3ChatProviderClient.snapshot` 的 fields 表：`customer["usageFourHourNextResetAt"] ?? customer["usageWindowNextResetAt"]`）。
- 最小触发输入（t3.chat `getCustomerData` 流式响应的最终 data 帧）：
  `{"usageFourHourPercentage":10,"usageFourHourNextResetAt":null,"usageWindowNextResetAt":1779366216920,...}`
- 预期：字段为 `null`（NSNull，非“缺失”）时应回退到同表已定义的 `usageWindowNextResetAt`；字段完全缺失时回退正常工作。
- 实际：`??` 不会穿透 `NSNull`，`numeric(NSNull)` 为 nil → 4 小时窗口 `resetsAt = nil`，重置倒计时丢失，尽管响应里有可用回退值。
- 用户影响：该窗口始终不显示重置时间（仅剩百分比），且无错误提示，用户难以判断额度何时刷新。
- 证据（对生产函数逐字提取后运行，`work/hosted_web_extract.swift`）：
  ```
  $ cd work && swift hosted_web_extract.swift
  PASS-OK  t3 null fourHour reset + present usageWindow fallback -> [("t3chat.four_hour", nil), ("t3chat.monthly", Optional(1780763009.0))]
  PASS-OK  t3 missing fourHour reset + present usageWindow fallback -> [("t3chat.four_hour", Optional(1779366216.92)), ...]
  ```
  建议补测：`work/HostedWebRegressionSupplementTests.swift::testT3NullFourHourResetFallsBackToUsageWindowReset`。

### 发现 2（低/信息）：QwenCloud “无套餐”分类状态可与套餐名并存，界面信息自相矛盾
- 位置：`TokenPulse/Providers/QwenCloudProvider.swift:183-184`（TotalCount=0 → `quotaStatusText="当前账号没有 Qwen Cloud 套餐"`）与 `:36-40`（订阅接口 `specCode` → `providerPlanName`，两者写进同一 snapshot）。
- 最小触发输入：usage 返回 `{"code":"200","data":{"Data":{"TotalCount":0,...},"Code":"Success","Success":true},"successResponse":true}`，随后订阅接口返回 `{"data":{"specCode":"lite"}}`。
- 预期：显示“当前账号没有 Qwen Cloud 套餐”时不应同时携带 `providerPlanName="Lite"`（或反之）。
- 实际：snapshot 同时包含 `quotaStatusText="当前账号没有 Qwen Cloud 套餐"` 与 `providerPlanName="Lite"`（两个端点数据可同时为真，但展示层并列会出现“没有套餐/计划 Lite”的矛盾观感）。
- 用户影响：轻微信号混乱；无功能损失、无错误额度展示（windows 为空，未伪造无上限窗口）。
- 证据（`work/qwencloud_flow.swift`，逐字提取 quota/securityToken/payload/snapshot）：
  ```
  OK      no plan account: TotalCount 0 categorical status: windows=[] plan=Lite
  ```
  建议补测：`work/HostedWebRegressionSupplementTests.swift::testQwenNoPlanStatusAndDiscoveredPlanNameCoexistence`（当前断言固化现状，root 决定是否改为抑制 planName）。

## 二、实际执行的检查（全部基于生产代码逐字提取，非等价重写）

工具约束：仅 `swift` 前端脚本 + Foundation；未运行 xcodebuild/simctl/XCTest；未联网；未访问用户环境。三个 harness：

1. `work/hosted_web_extract.swift` — 逐字提取 5 个 provider 的 `snapshot`/`customer`/`token`/`payload`/`securityToken(inPage:)`/`request`/`actionID`/`isLoginLanding` 及共享 `HostedWebHTTP`/`HostedQuotaAmount`/`HostedQuotaMath`/`ProviderDecimal`。
   - 快照自带 fixture 全部复现通过（Raycast 精确计数 24.875/75.125/100、Pro+；Zoom 超额付费 100、resets 1793613600；T3 12.5/34.25 且两个 reset 分离；Qwen 3%/120%；TypeSafe 4.980000000000000001 非货币）。
   - 流式引用不误匹配：链后 decoy(id 99)、未被引用 decoy(id 9)、伪造平行 result/data 链(id 3/4) 均不影响结果；重复 frame id 抛 `unreadableResponse`（fail-closed）。
   - CSRF/表单编码：`sec_token=a+b&c=d` → `a%2Bb%26c%3Dd`；`x-xsrf-token`/`x-csrf-token` 双 header 传 `x+y=z` 原值；csrf 含控制字符被拒（invalidCredential）。
   - 页面 token 正则：标准 `secToken` 提取正确；`userSecToken`（大写 S）不误匹配。
   - 未知币种：`"XYZ"`/缺省 → `credits（币种未提供）`、isMonetary=false；`"usd"` → USD 货币。
   - 日期边界：`epoch(1e30, ms)` nil；秒值不被当毫秒（无 millisecondsOnly 时启发式正确）。
2. `work/hosted_web_flow.swift` — 逐字提取 `ZoomMateProviderClient.quota` + `HostedWebHTTP.get` + `HostedWebProfiles`/`WebProviderSession`/`CookieWebSessionPolicy` 绑定链，脚本化 transport：
   - ai.zoom.us 503 或传输层网络错误 → 重试 zoommate.zoom.us 成功（hosts 顺序正确）；401/429 在首 host 即终止（各 1 个请求）；双 host 5xx → server；账号不匹配 → 0 个请求。
   - 临时 token：`Bearer temporary-two` 只用于 status 请求，`updatedCredential=nil`（不落盘）。
   - 取消：第二 host 登录挂起时 cancel → 传播 `CancellationError`（未被映射成 network）。
3. `work/typesafe_flow.swift` + `work/qwencloud_flow.swift` — 逐字提取 TypeSafe `quota/discover/wire/post/TypeSafeActionCache` 与 QwenCloud `quota/securityToken/request/payload/snapshot`：
   - TypeSafe：缓存命中只发 1 个 POST（两次调用共 4 请求，GET,GET,POST,POST）；chunk 请求不携带 Cookie；`x-nextjs-action-not-found` 才重新发现且仅一次；普通 404/302/429/登录页分别 fail-closed；chunk 404 继续下一个 chunk；chunk 429 中止；取消传播 CancellationError。
   - QwenCloud：页面 token → 表单编码进 usage POST；页面无 token → cookie `sec_token` 回退（不调 info.json）；页面网络错误 → cookie 回退且额度保留；页面+cookie 皆空 → `/tool/user/info.json` 提取 secToken；登录页 1 个请求即停；usage 302/登录 HTML → invalidCredential 不重试；订阅 503 不抹掉已得额度；取消传播 CancellationError；`specCode="weird-plan"` 原样透传。
   - 协议绑定（提取 `WebProviderSession.fingerprint/validate` + 三个 cookie policy）：provider/本地 UUID/origin 任一不符即 `invalidCredential` 且不发请求；cookie 选择尊重 domain/path/过期/禁用前缀（`_ga*`）。

图标（按修改后的验收标准）：
- `ProviderQwenCloud.imageset`：SVG 存在、`preserves-vector-representation` + template、`viewBox="0 0 24 24"` 且显式 width/height、fill=black、无 `currentColor`；来源许可记录于 `TokenPulse/Resources/ProviderIconNotices.txt:837`（Lobe Icons commit 79b551c…, MIT）。
- RaycastAI/T3Chat/ZoomMate/TypeSafe 使用 SF Symbol 通用图标（`UI/ProviderIcon.swift:84-87`），按已修改的验收标准（图标存在）不计为缺陷。

快照自带专项测试文件已核对存在于 `TokenPulseTests/{HostedWebProviderTests,QwenCloudProviderTests,TypeSafeProviderTests}.swift`（共 15 个用例），其 fixture 断言与提取代码行为一致；实际 XCTest 结果以 root 统一串行运行为准。

## 三、未覆盖范围
- 未运行 xcodebuild/iOS Simulator/完整 XCTest（规则禁止；由 root 统一执行）。`work/HostedWebRegressionSupplementTests.swift` 未经编译验证，合入前需 root 复核 API 名称与 transport 形状。
- 未做真实账号/真实网络验证：五个 provider 的线上接口当前是否真会返回发现 1/发现 2 的触发形态（`usageFourHourNextResetAt:null`、TotalCount=0+specCode 并存）无法离线确认；接口契约来自快照内 fixtures/文档（二手契约）。
- ZoomMate `cycle_end_date` 若以秒（而非契约的毫秒）返回会得到 1970 年日期（已用提取代码确认 `1793613600` → 1970-01-21），属契约外输入，未计为缺陷。
- QwenCloud 页面正则对 HTML 属性形态 `csrfToken='x'` 会取属性值（已确认），未见现实页面出现该形态，未计为缺陷。
- QwenCloud usage 只含已过期窗口且无 TotalCount 时 fail-closed 为 `noQuotaWindows`（已确认，补充测试 `testQwenAllWindowsPastResetFailsClosed` 固化该设计），是否符合预期由 root 判断。
- Watch/Widgets UI 展示、iCloud 同步、`DemoMode` 快照内容未逐项验证；五个 provider 之外的范围未研究。
