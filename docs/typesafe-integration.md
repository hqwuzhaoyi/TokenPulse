# TypeSafe 控制台余额

使用账号隔离的临时WK登录console.typesafe.ai/settings/billing，选择该host或父typesafe.ai域、账单path可用的会话Cookie，过滤统计项；未知session名不靠猜测固定allowlist。查询前按本地UUID、provider、origin及实际凭证验证指纹。服务端拒绝或登录落地页显示重新登录，失败保留旧数据。

读取账单页列出的同源JavaScript（最多60个、每个5秒、2MiB），公共脚本不携Cookie，不执行下载代码。仅匹配getBillingOverviewResult相邻的40–128位hex action id，多冲突id拒绝；POST账单页带Next-Action和[]调用只读账单查询。标识只在内存缓存12小时，无凭证缓存；仅x-nextjs-action-not-found:1明确响应时重新发现一次。普通404、认证拒绝不变成重复登录探测。

React stream沿0:a指定的$@结果id读取，不匹配无关ok对象。余额直接从该frame原始JSON用Decimal解码，bool/非法数/缺值不变成0。没有额度分母，不以spent或resetsInDays伪造套餐及重置。服务显式currency为有效ISO币种时作为货币余额；固定fixture没有currency，显示“credits（币种未提供）”并禁低余额通知。官网公开价格只有美元符号，不足以将这项balance一律标为USD。plan按原字段展示。

证据：[固定Pulse文档与源码](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/typesafe.md)和同commit的TypeSafeTests合成流及action发现fixture。2026-10-02公开读取typesafe.ai主页有价格符号，没有独立余额currency字段说明。未登录真实账号，动态action/当前站点兼容性未实测；用户不将真实验收作为关票门槛。

6项TypeSafeProviderTests已在iOS Simulator实际通过，涵盖正确结果引用、精确数值/未知币种、动态action缓存和明确重新发现、脚本无Cookie、origin/重复id/布尔/拒绝边界。图标是通用SF Symbol puzzlepiece.extension.fill，按存在标准验收。最终全量测试与unsigned多目标构建随整批执行。
