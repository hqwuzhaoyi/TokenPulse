# Mistral API、Vibe 与钱包

`.mistral`接root通用隔离WK登录视图和WebProviderSession身份框架。登录从admin.mistral.ai/subscription进入，允许auth/console.mistral.ai及Google身份导航；只采集mistral.ai根域Ory session前缀Cookie与可选CSRF，不导出Google或其他网站会话。ory_session_必须有实际deployment后缀。origin/local账号UUID、到期和来源hash纳入envelope，安全存储/同步/删除沿公共路径；到期重新登录，无CLI或虚构续期。

只读admin `/api/billing/credits`、admin `/subscription`，必要时console `/api-ui/trpc/billing.vibeUsage`。根域Cookie可供两官方子域使用；只属于console的csrftoken单独保存到加密凭证元数据，只在console辅助请求使用，绝不发给admin。CSRF过期不使用。请求禁缓存/自动Cookie，production拒绝重定向；primary 302/401/403立即判会话失效，不从页面价格凑成功数据。

credits三项wallet_amount/credit_notes_amount/ongoing_usage_balance都实际返回且currency为明确三字母代码，才以Decimal计算可用净余额；未知组件不补零，不定价/换汇，真实负净额保留。页面只拼接已知self.__next_f.push的类型1字符串流，再取api_budget/vibe_budget；重名的不同对象不任意选一个。usage_percentage按0–100已用刻度，超过100保留耗尽；initial_budget和价格不当分母。reset_at只取ISO或React $D日期，不合成30天周期。

当页面没Vibe且CSRF可用才调用固定tRPC读取，GET/query input及X-CSRFToken沿源码。辅助页面/路由失败不会抹掉有效钱包或另一额度；余额失败但API/Vibe成功时设置walletFailure，公共monitor只按同指纹保留旧余额及其旧采集时间，该轮不造零或重新武装低余额。两类全部失败时保留真正余额错误。UI/Watch/Widget/Demo使用mixed窗口，额度与货币低余额设置/策略分别作用，钱包无比例/reset。

契约源：[Pulse397c8fc4 Mistral文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/mistral.md)及[客户端](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/MistralUsageService.swift)。私有余额/页面形状仍是二手契约。调查日官方[文档入口](https://docs.mistral.ai/)列出console.mistral.ai的Studio入口；旧credits/billing文档路径已404，未把404或公开SDK当账单JSON验证。官方mistralai/client-python固定e8dfa1c8a2d0975cebfc0136b2d9060ff555494d树没有SVG；图标采用Lobe79b551cf的packages/static-svg/icons/mistral.svg，MIT与版权/path全记录于notices，矢量模板存在。

新增5个合成方法覆盖Decimal/币种/缺失、Flight重复与错误旗标、Vibe CSRF/辅助失败保留、primary失效与余额partial、Cookie域、本地绑定、mixed widget/提醒。工作者只执行parse/PBX lint/diff，不Xcode/模拟器/重复大typecheck；root执行真实测试/整体构建。未访问真实Cookie，没有当前生产登录、账单、物理Watch/iCloud验收证据；按用户2026-10-02“实现+图标”标准关票，限制仍如实保存。
