# LongCat Token 与补充燃料包

`.longCat` 完整注册通用隔离 WK 登录与本机/Watch 查询。入口固定 `https://longcat.chat/platform/usage`，只保留同域必要 passport_token 和可选 uid；CookieWebSessionPolicy/WebProviderSession 提供账号 UUID/origin/实际会话/expiry/来源 SHA256 防护，拒绝普通 API Key、其它域 Cookie、串账号和改写指纹。不会读取真实用户浏览器或桌面状态。

按固定平台流程：先 GET `/api/v1/user-current` 必须成功，认证返回中的电话/会话 token 只验证 envelope 后丢弃，不进入快照/持久化。POST `/api/pay/quota/metering/token-packs/summary`（{}）为受限的 best-effort；只有无有效 ACTIVE 正 totalToken currentLot 时才回退 GET `/api/lc-platform/v1/tokenUsage`，不因 missing consumed 在有效主包上额外回退。GET `/api/lc-platform/v1/pending-fuel-packages` best-effort。所有请求同 origin、显式 Cookie/Origin/Referer，关闭自动 Cookie、禁缓存、生产传输拒绝重定向；必须路线的3xx/401/403要求重登，429/服务错误保持真实错误。

主包计量是 Decimal tokens，不是货币 credits。currentLot.consumedToken 或 legacy usage.usedToken/availableToken 优先实际数，忽略 consumedRatio 和 extData 模型明细，绝不递归搜索替代总额。主包缺少消耗字段时保留明确 total 和未知 usage/remaining，静态提示，不能补0。legacy缺 total 是无法读取响应；explicit zero 表示未授予当前主额度，optional fuel 未取得时也明确保留未知，不能据此宣称两类包都不存在。

燃料总包以 totalQuota 与所有 list[].availableToken 的完整集合计算，任一成员未知就保持合计使用/剩余/百分比未知，而非把缺项当0。原数均 exactCounts/Decimal。父燃料总额和主包分开，不相加；各补充包最早未来 expireTime 及该精确时点金额作为独立“补充包子集”行，不把整个父包错误标成到期。已核实 ISO、epoch s/ms 和 yyyy-MM-dd HH:mm:ss 日期形状可读；无时区旧形状沿固定参考的设备时区解析，界面仅显示到期，不推算重置。没有固定30/60天计量长度或重置日期，nonResettingAllowance 抑制假重置，设置中不开放无效重置开关；只保留适用 Token 额度阈值，无钱包/低余额提醒。

注册覆盖 Provider/Factory/profile/安全保存/Source身份/重新登录/删除/Keychain/iCloud既有流程、card/details/Watch/Widget/三行演示。图标 ProviderLongCat 存在，来源 Lobe Icons 2e76c487… 的 packages/static-svg/icons/longcat.svg；Copyright2023 LobeHub/MIT及黑色模板、原矢量路径声明在 notices/image set。

新增八项测试：初始会话验证/身份数据不保存、summary权限失败→精确legacy顺序、有效包缺消耗不零、不完整fuel集合不虚构使用量、到期子集非父包失效/重置、legacy字段缺失/当前未发放与fuel未知、Cookie/账号源/鉴权停止、编码/Widget/演示/提醒。四个新 parser/client/session 的真实 Swift6 必要小模块 typecheck、parse/PBX plist/diff 已通过；全量 XCTest 和 unsigned App/Widgets/Watch 资源编译由 root 串行执行，本 worker未运行xcodebuild/模拟器。

当前完整实现+图标存在验收已 done。真实 LongCat 账号、SSO/验证码、权限拦截、Keychain/iCloud到达、物理双端查询/通知未声称通过，不再是本票关票条件。固定 [Pulse 文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/longcat.md)、[client](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/LongCatUsageService.swift) 与 longcat fixtures 是第二手契约证据。私有路线/会话、无时区日期或包形状变化可能需适配；明确未取得字段不等价于确认无额度。
