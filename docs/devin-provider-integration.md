# Devin 网页账号额度

Devin 从添加或设置里的网页登录入口进入账号独立的临时 WKWebView。通用 WebProviderSessionLoginView 只在固定 `https://app.devin.ai` origin 读取指定localStorage项：`auth1_session` 对象内的token与userId必须同属一项；组织只取 `last-internal-org-for-external-org-v1-*` 值中的规范内部org ID，绝不拿key的外部slug或null后缀猜组织。多个组织作为单独choice由用户选择，所选组织的额度请求成功后才保存。无组织、错误结构、token缺失、control字符或不匹配origin不会发不完整查询。

凭证通过WebProviderSession绑定provider、本机服务账号UUID、origin、远端userId和organizationID；fingerprint从实际token及全部scope元数据重算，查询时再次验证。添加、重新登录、安全保存、本机恢复、配置／Keychain同步、删除采用现有monitor/runtime路径。临时容器关闭或重新登录即清理；token被401/403拒绝、会话显式过期或查询被redirect时要求重新登录。

iPhone与Watch直接 `GET https://app.devin.ai/api/<internal-org>/billing/quota/usage`，以Bearer token与 `x-cog-org-id` 绑定所选组织。只在404时尝试同组织的 `api/organizations/<id>` 路径；认证、限流、网络或服务器失败不试别的组织，保留同身份旧snapshot／采集时间。没有读取Mac/editor数据库、缓存计划或借用其plan name的路径。

`daily_percentage`、`weekly_percentage` 为已用0–100百分比，真实0.4保持0.4%，不乘100，不当剩余比例。只对未隐藏且has_quota_allocation未明确false的窗口展示额度，明确false是无分配，绝不画两枚假满额度环。reset使用明确ISO offset／epoch秒或毫秒；缺值不猜。套餐名只用远程响应；overage_balance是USD余额，明确cents字段才除100，保持Decimal、不合并到quota百分比。mixed卡片、详情、Watch、widget保留两种quota及余额；额度和货币提醒独立。

官方来源：[Devin API Overview](https://docs.devin.ai/api-reference/overview)与[官方介绍／登录入口](https://docs.devin.ai/)在2026-10-02读取。官方公开v3 API使用cog_ service-user凭证和组织／企业scope；本票app.devin.ai网页会话路由不是公开v3 API，也不使用公开API Key替代网页登录。网页key结构、组织请求和响应语义依照[Pulse固定397c8fc4 Devin说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/devin.md)及同版本DevinUsageService、测得的devin-quota-usage fixture。按契约独立适配，未复制LevelDB／编辑器读取器；固定上游曾在2026-09-14测过此网页路由，本文不将其冒充本机账号验证。

Devin图标存在：Lobe Icons commit `c23e42baf04f1749d7a1c78d807f20cd40cae97e`，`packages/static-svg/icons/devin.svg`，Copyright (c) 2023 LobeHub，MIT；仓库/路径/许可记录于ProviderIconNotices.txt。ProviderDevin imageset保留vector与template intent，currentColor改黑、尺寸24x24。

按用户2026-10-02调整后的验收标准，本票实际auth/query/UI/Watch/widget/demo/register/PBX与图标存在已实现。7个Devin测试覆盖固定key/origin、多组织choice、scope篡改／过期、百分比／隐藏／无分配、组织请求及404 fallback、错误单次请求、本机生命周期与demo/widget/icon。Swift parser、PBX lint、diff与资产存在/XML/JSON检查通过；worker未运行Xcode或模拟器，root负责统一编译与测试。

未执行真实Devin登录、组织成员权限或设备刷新验证；没有读取真实token、Mac app数据库或正常浏览器资料。真实账号/设备不再阻塞当前关票，真实证据与合成测试仍明确区分。
