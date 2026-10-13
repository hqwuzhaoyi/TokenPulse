# LiteLLM 用户和团队预算

账号配置虚拟 Key 与部署根地址，复用gateway安全保存/同步/独立双端查询/删除/地址+Key+provider隔离。`/v1`尾缀移除，路径前缀保留，地址userinfo/query/fragment拒绝，公网HTTPS或已支持的受限私网HTTP，跨origin重定向拒绝。虚拟Key作为Bearer发送；Key从不出现在URL。

先只读GET `/key/info`确定user_id/team_id（当前主源允许Key省略query、默认Authorization的Key）。存在用户时GET `/user/info?user_id=...`，否则存在团队时GET `/team/info?team_id=...`，使用URLQueryItem编码并单独编码+号，参数不能变成host/path或额外query。返回top-level和nested身份只要出现都必须一致，至少一个必须与请求身份匹配；user/info只取该Key绑定团队，其他团队不显示，重复匹配拒绝。明确blocked/expired/revoked/deleted拒绝凭证。

403/404表示本Key不能读取该预算，返回确认状态文字和空windows；无user/team同样明确未提供。无无限回退、花费报告或推理请求。用户与团队窗口分别保留Decimal spend/max_budget/remaining、USD预算单位、服务端budget_duration及budget_reset_at，缺正上限或用量不画使用率、不补0或已耗尽；已知花费可单独展示“已用”，不是钱包。团队预算和用户预算不相加。App/Watch/widget和隔离演示注册，比例与真实日期沿既有规则各窗提醒，钱包低余额设置不开放。

主源固定[BerriAI/litellm 615ed790 key_management_endpoints.py](https://github.com/BerriAI/litellm/blob/615ed7900f3bcfd09b324c38c5123eb6ed4769da/litellm/proxy/management_endpoints/key_management_endpoints.py)，确认/key/info默认header身份、Key status及预算字段；[internal_user_endpoints.py](https://github.com/BerriAI/litellm/blob/615ed7900f3bcfd09b324c38c5123eb6ed4769da/litellm/proxy/management_endpoints/internal_user_endpoints.py)与[team_endpoints.py](https://github.com/BerriAI/litellm/blob/615ed7900f3bcfd09b324c38c5123eb6ed4769da/litellm/proxy/management_endpoints/team_endpoints.py)为管理预算来源。兼容[Pulse397c8fc4固定形状](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/litellm.md)。不同部署可能限制这些管理路由，权限未提供不会被伪装成空余额。

新LiteLLMProviderTests覆盖身份矛盾/团队过滤、精确数量、缺上限、权限拒绝无回退、revoked/blocked、特殊query字符和固定host/header。必要小模块Swift6语义检查、parse/PBX/diff检查通过；实际XCTest/完整target构建由root统一。使用Apple SDK现成SF Symbols puzzlepiece.extension.fill通用网关图标，官方/既有Lobe没有合适模板vector来源，未复制位图；源许可记录于Notices。真实Key/部署/设备/iCloud未验证，按用户当前实现+图标标准不阻塞done。本分支没有xcodebuild/模拟器或真实凭证访问。
