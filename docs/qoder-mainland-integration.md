# Qoder 国内网页 credits

`.qoderChina` 与既有 `.qoderInternational` 分开注册。国内选择账号隔离的 WK 网页登录，唯一 origin `https://qoder.com.cn`，入口 `/account/usage`；国际版原设备授权与 openapi.qoder.sh 查询未修改。没有地区自动重试、桌面目录读取、IDE 缓存或用户浏览器 Cookie 读取。

国内会话复用 root WebProviderSession/通用登录 profile，绑定本地账号 UUID、origin、实际 Cookie、expiry 与来源 SHA256。Qoder 未公布唯一 session Cookie 名，固定参考采用同域 Cookie 减第三方 analytics 前缀；本实现仅从临时容器的 qoder.com.cn 域选择，大小写分析前缀预过滤，保留 cna/isg/tfstk 等已知防护 Cookie，不保留 qoder.com 的国际会话或其它域 Cookie。这条动态同域 Cookie 契约仍可能随登录页面改变。

GET `/api/v2/me/usages/big_model_credits` 固定 Cookie、Origin、Referer、X-Requested-With=XMLHttpRequest、Bx-V=2.5.35 和固定参考浏览器 User-Agent。禁缓存、关闭自动 Cookie、所有重定向拒绝；3xx/401/403 明确重新登录，429 限流，其它 HTTP 服务失败保留上次同来源读数。独立 iPhone/Watch Client 不依赖另一设备在线。

只读 `totalQuota/total_quota.quotaSummary/quota_summary` 个人总池及 `sharedQuota/shared_quota` 团队池，逐字段兼容已知 camel/snake，不重复添加 plan/resource_package 已含在总池中的额度，也不把两池相加。used/limit 必须可读、非负；明确零发放池省略，整个账号零池是新鲜 quotaStatusText 而不是假0%或刷新故障，能够清掉已撤销的旧额度。明示的 remaining 是耗尽依据，缺失时只在已知 used/total 后计算剩余；数值及存档用 Decimal/exactCounts。

`nextResetAt` 支持已知 ISO 或 epoch s/ms；只保留未来值，过去试用时间不使可用 credits 消失。个人池包含不同期限资源包，所以不把某包的 expiresAt 放在整个总池上。正剩余、非明确 inactive 的未来 quota_detail 最早到期子集作为独立“个人额度子集”行，显示该精确时间即将失效的 credits，永不当重置。父池 nextResetAt 只显示，不启用全局40点下降推断或重置通知（nonResettingAllowance）；购买增额不会被误报恢复。国内版的无效重置开关隐藏，额度告警按真实已用比例沿用；没有货币钱包/低余额提醒。

Provider 图标复用原 `ProviderQoder`，固定 Lobe 来源/版权/MIT/矢量模板属性保持，notices 明确扩用于国内品牌。注册覆盖添加与重新登录、Keychain/iCloud 源身份、删除、card/detail、Watch、Widget 和国内两池演示。

新增七项测试覆盖国内 Cookie/防护/分析/跨域/账号绑定、字段混用、个人团队不相加、试用旧重置/资源子集到期、零池状态及 malformed-summary失败、detail不影响有效 summary、HTTP/请求头、购买非重置、编码/Widget/演示。parse、真实 Swift6 必要 client/session/parser 小模块 typecheck、PBX plist/diff 均通过；根模块合并测试及 unsigned 资源构建由 root 串行执行，未运行 xcodebuild/模拟器。

当前用户要求完整实现且图标存在，已满足，票 done。真实账号、反机器人屏蔽、已付费周期、SSO/验证码、iCloud 与物理 Watch/通知未声称通过，不再作为当前关闭门槛。证据为 [固定 Pulse 文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/qoder.md)、[client/parser](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/QoderUsageService.swift) 及 `qoder-credits-trial-stale-reset.json` 去秘密的第三方实际 trial capture。没有转述它为本应用真实验证。
