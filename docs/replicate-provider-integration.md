# Replicate 预付余额

`.replicate` 使用账号隔离的应用内网页登录与root共享WebProviderSession框架，不使用推理API Token、不读取Safari/CLI/真实用户凭证。完成网页登录后仅采集replicate.com根路径的sessionid及可选csrftoken；GitHub登录页可用于授权导航，但其Cookie不被导出。会话带本地账号UUID、允许origin、已知到期和来源指纹，保存/同步/删除沿既有Keychain与账号配置路径。到期/302/401/403要求重新登录，没有编造refresh协议。

账单页GET `/account/billing`只在application/json且id为react-component-props的script中寻找account.kind/user或organization及安全username。读取限制2MB/4000节点；发现多个个人/组织候选时由用户明确选择，不按字典顺序选第一个。选择范围纳入指纹。每次刷新重新确认当前会话页面仍含所选account，再GET `/api/users/{username}/unused-credit`或organizations对应路径；username为单一安全标识，无法注入其他路径。请求禁缓存/自动Cookie/重定向，生产transport拒绝跳转，不携带Bearer或查询其它账单账户。

unused_credit为已报告的非负Decimal字符串或数字，缺失/null不补零，Bool/畸形/科学记数法字符串拒绝。钱包独立USD余额，不生成比例、总额、周期或reset，支出/发票不当余额。账单页面只用来识别账户，不采用无证据的HTML金额回退；JSON失败保留同身份旧成功数据。卡片/详情/Watch/Widget/Demo和USD低余额去重/恢复规则走共享钱包路径，Watch获得该账号会话后自行直连。

契约来源：固定Pulse `397c8fc4f1bd52180a452d2f3f0c099def97cf69` 的[Replicate说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/replicate.md)与[客户端](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/ReplicateUsageService.swift)。[官方Billing](https://replicate.com/docs/topics/billing)及[Prepaid credit](https://replicate.com/docs/topics/billing/prepaid-credit)于2026-10-02读取，确认预付用量扣余额和账单设置位置；私有unused-credit形状来自固定客户端，不宣称为公开API保证。官方replicate-python树未提供SVG标记，图标使用Lobe Icons `79b551cf26aab9ea4ac701fb807160950a5b860f` `packages/static-svg/icons/replicate.svg`，MIT/版权/固定路径见ProviderIconNotices，黑色矢量模板。

新增5个合成XCTest方法覆盖候选与路径、精确金额/缺失、selected账户指纹、请求/本地身份/expiry/HTTP拒绝、Cookie scope、Widget及低余额提醒。工作者执行Swift parse、PBX lint、diff检查，通过；没有重复大型typecheck、执行XCTest、Xcode或模拟器，root统一实际验证。未使用真实会话，没有真实登录/生产账单/物理Watch/iCloud证明；这些限制保留说明，但依据2026-10-02最新用户标准不再阻塞本票关票。
