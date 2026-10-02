# Perplexity API credits 钱包

账号专用临时 WK 登录容器捕获 Perplexity 会话，完成固定 credits 查询验证后才保存凭证。只提取 www.perplexity.ai/perplexity.ai 适用路径中的 __Secure-next-auth.session-token，或连续 .0/.1 等数字块；缺块/非规范序号/过期/外域拒绝。普通 Cookie 存在时只保留普通值；分块不混入追踪 Cookie。会话绑定当前提供商、账号 UUID、origin 与实际内容指纹；Web数据在完成/取消后清理，配置与Keychain沿用同步、恢复、删除，Watch直接查询。

GET https://www.perplexity.ai/rest/billing/credits?version=2.18&source=default 使用 Cookie、Origin、usage Referer 和页面参考 User-Agent。没有自动 Cookie jar 或重定向；3xx/401/403为会话失效，Cloudflare 403也可能表现相同。Cloudflare/WK会话生产兼容尚未实测，不宣称能绕过平台验证。

balance_cents（兼容balanceCents）以Decimal读取并精确除100得到USD，明确零有效、缺失/负值不补零。credit_grants 必须数组。只展示账户API credit余额；忽略未声明资金池消费顺序、历史支出/renewal字段，不生成订阅百分比、聊天次数或reset。货币低余额提醒按USD阈值及既有去重/恢复规则处理，演示数据隔离。

私有路径和Cookie名称来自 [固定Pulse契约](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/perplexity.md) 的二手线索；[官方API billing](https://www.perplexity.ai/help-center/en/articles/10354847-api-payment-and-billing) 明确API credits独立于Computer Credits，账户余额是预付API资金。这些主源不证明私有endpoint/Cookie当前生产版本。官方Perplexity代码仓库未提供所需品牌SVG，使用Lobe Icons固定perplexity.svg（MIT），来源/版权/模板矢量属性见ProviderIconNotices与asset catalog。

5个PerplexityProviderTests覆盖精确分币/零/缺失和字段错误、连续Cookie块及外域/过期、GET/Origin/Cookie、错误账号和拒重定向。当前用户调整的实现+图标验收已完成；真实账号/设备/iCloud兼容未取得证据，root统一执行XCTest与资源构建。本次未访问真实密钥或正常浏览器会话。
