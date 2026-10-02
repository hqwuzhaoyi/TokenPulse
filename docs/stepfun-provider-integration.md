# StepFun 套餐和网页登录

实现范围为 StepFun（`Provider.stepFun`）的 Step Plan，不包含推理 API 预付钱包。iPhone 在添加账号或账号设置的“重新登录”中选择国内站 `platform.stepfun.com` 或国际站 `platform.stepfun.ai`，在账号专用临时 WKWebView 中登录，点“完成登录并验证”。验证请求成功后保存凭证；账号没有 Step Plan 时也可保存，并展示该次查询返回的空套餐结果。

每次登录的 WebKit 容器按提供商、服务账号 UUID 和站点隔离，使用 `WKWebsiteDataStore.nonPersistent()`。关闭、切站、重新登录会停止导航并清理临时网站数据，不读取 Safari 或其他 App 的登录信息。重新登录只替换当前服务账号的凭证。现有 Claude 网页登录和组织选择保留，复用临时容器。删除账号沿用已有凭证、快照、提醒的删除与同步墓碑机制；WebKit 临时容器在登录界面关闭时已清理。

凭证存入现有安全存储；iCloud 关闭时保持本机可用。开启同步后由现有 synchronizable Keychain 将同一凭证同步给 Watch。Watch 取得配置和凭证后使用相同 POST 契约独立查询，不需要 iPhone、Mac 或新增代查服务在线。网页容器仅供 iPhone 配置，刷新客户端不依赖 WebKit。

## 凭证和请求契约

只提取匹配站点域名（准确控制台 host 或相应的 `stepfun.com` / `stepfun.ai` 父域）、匹配 API 路径且未过期的 Cookie：`Oasis-Token` 必须存在；`Oasis-Webid`、`INGRESSCOOKIE` 存在时转发。不同值的同名 Cookie、控制字符、不安全值、其他 Cookie 名称不能进入请求。通过 `WKHTTPCookieStore` 读取，包含 HttpOnly Cookie。

`oasis-webid` 来自 `Oasis-Webid` 或会话 token 的 `device_id` claim（支持 access...refresh 组合）。只读取并向签发服务器回传此 claim，不据此验证身份。缺失、Cookie 与 token claim 冲突、或多个 token claim 冲突时拒绝请求，不生成或猜测设备 ID。凭证同时保存站点、host、账号 UUID 和设备 ID；每次刷新重新验证。Cookie 到期和 HTTP 401/403／200 中 auth/token 错误要求重新网页登录，未发现可核实的自动刷新会话端点。

请求为 `POST https://{host}/api/step.openapi.devcenter.Dashboard/QueryStepPlanRateLimit`，JSON body `{}`。明确附带 `oasis-appid: 10300`、`oasis-platform: web`、匹配的 `oasis-webid`、Cookie、Origin、`/plan-usage` Referer 和固定浏览器 User-Agent。禁用系统自动 Cookie；默认网络 transport 拒绝跨 origin 重定向，避免把会话带到其他站。暂不请求仅用于套餐名称的 `GetStepPlanStatus`，套餐类型依据额度字段识别。

凭证 metadata 的 `sourceCredentialFingerprint` 与快照同名字段为站点＋受限 Cookie Header 的 SHA-256。通用配置／状态身份机制用此指纹隔离不同凭证的快照、进行中的查询、同步数据和提醒历史。指纹不包含可读 Cookie；额度缓存、iCloud 配置和日志不保存会话值。

## 字段与提醒

Token Plan 的 `credit_buckets` 中 `credit_total` 和 `credit_residual` 相加得到总积分与剩余积分，以“积分”显示，绝不当作 token 数或金额。桶的最早未来 `next_reset_at` 作为重置，带剩余积分的桶中最早未来 `expire_at` 显示为“最早积分到期”。到期是部分积分最早失效的时间，不表示整个汇总池到期，也不触发重置提醒。桶字段缺失、非数字或残额超过总量时拒绝完整响应，避免展示不完整汇总。无桶但有比例时优先套餐比例，其次充值包比例，不相加，不补总量或剩余量；单独的零比例无法区分没有此计划与已用尽，保留固定上游的无套餐语义。

Coding Plan 依据存在的五小时／每周重置字段识别，不依据 `plan_family`。`*_usage_left_rate` 是剩余比例，已用为 `1-left`；零重置时间表示无窗口。明确额度和重置接入既有阈值与重置规则。Token Plan 无明确重置时不开放重置提醒开关；Credits 到期从不预排重置通知。两种套餐都不开放钱包低余额或手动重置次数设置。

成功的无套餐响应记录新采集时间和空窗口，清除旧套餐。网络、限流、服务端和不可读响应保留同凭证的上次成功数据与采集时间。iPhone 卡片与详情、Watch、小组件均使用同一领域窗口与单位；演示同时提供 Token Plan 和 Coding Plan 账号。

## 固定研究来源

- [Pulse 接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/stepfun.md)，固定 commit `397c8fc4f1bd52180a452d2f3f0c099def97cf69`。
- [Pulse StepFunUsageService.swift](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/StepFunUsageService.swift)，同一固定版本。实现为按契约独立适配，未复制其服务实现。
- [Lobe Icons StepFun SVG](https://github.com/lobehub/lobe-icons/blob/ef22550bbbdc0350e40596ee6e9097024f2eeda7/packages/static-svg/icons/stepfun.svg)，固定 `ef22550bbbdc0350e40596ee6e9097024f2eeda7`，MIT；许可见 `ProviderIconNotices.txt`。

## 验证边界（2026-10-02）

本工作没有访问真实账号或已有浏览器凭证。固定上游报告在 2026-09-24 测过国内站 Plus Token Plan、套餐状态和退出后的 401；Coding Plan 形状源于 CodexBar，国际站只有退出后的 401，不能据此声称真实登录兼容。

本地合成契约测试覆盖字段边界、域名／路径／账号／设备隔离、请求头、HTTP 和业务错误、无套餐、独立 WebKit 容器、积分到期不重置、Coding Plan 提醒、演示及小组件。静态检查：`swiftc -frontend -parse` 已通过新增客户端、UI及测试源；`plutil -lint TokenPulse.xcodeproj/project.pbxproj` 通过。未在本分支运行 xcodebuild 或启动模拟器；相关测试执行和 unsigned 全目标构建由 root 串行整合验收补齐，目前均未验证。

**仍未真实验收：** iPhone 国内站完整网页登录与保存；国际站授权后的响应；Coding Plan 实际响应（含用尽）；充值桶；季度／年度计划 `next_reset_at`；同一 Web 会话在 iPhone 与 Watch 上兼容，以及关闭手机后的 Watch 独立刷新；删除后真机 Keychain 同步和容器清理。无账号和硬件意味着这些项保持未验收，合成测试和 unsigned build 不等价于真实接入完成。
