# LLM API Key Proxy 配额组

配置每个账号自己的proxy地址和Key，复用gateway规范化/安全Keychain/同步/删除/地址+Key+provider缓存和提醒隔离。服务根地址或/v1均GET `/v1/quota-stats`，Bearer发送到指定origin，拒绝userinfo/query/fragment和公网HTTP，受限私网HTTP沿既有规则。App和Watch直接请求自己的服务器；不调用POST refresh、不触发代理上游强制刷新或模型请求。

providers逐个读取，quota_groups可为命名对象或列表。每个有效0–100 remaining_percent独立转换100−remaining为已用比例，实际reset_time保留；上游与组名称分别标识，命名default不重复展示名称，列表按索引稳定标识。对象重排不会改id，命名组和列表索引id域不同。不把最小剩余值变成总额度，不合并请求/token/approx_cost为套餐数量。未返回period不猜1日周期，只有实际reset用于预排；缺失/越界/Boolean或畸形组局部跳过，不把它补0或污染其他上游；错误日期不制造时间。无有效组用quotaStatusText明确未提供，非虚构额度窗。

GET主源说明返回代理cache中的统计，本设备collectedAt是获取这份缓存的时刻，不代表每个上游已实时刷新。采集、过期和失败沿同一快照在App详情、Watch及widget保持一致；当前Key查询失败保留同scope旧成功快照，更换Key/server后不复用。百分比及实际reset各组独立提醒，非货币百分比不开放钱包低余额。隔离演示包含多个上游和不同reset。

主源固定[Mirrowel/LLM-API-Key-Proxy adef2d69 main.py](https://github.com/Mirrowel/LLM-API-Key-Proxy/blob/adef2d696024f6525887e032c92947581593659b/src/proxy_app/main.py)，核对Bearer verify_api_key、GET quota-stats cached-read与POST refresh区别；[rotating_client.py](https://github.com/Mirrowel/LLM-API-Key-Proxy/blob/adef2d696024f6525887e032c92947581593659b/src/rotator_library/client/rotating_client.py)为stats来源。兼容[Pulse397c8fc4](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/llm-proxy.md)对象/列表字段，并保持每组而非CodexBar最低值合并。

新LLMProxyProviderTests覆盖逐组比例/实际时间、格式失效局部处理、空status、重排identity、固定GET/header及Key改变。小模块Swift6语义、parse/PBX/diff通过，实际XCTest/全target由root统一。现成SF Symbols puzzlepiece.extension.fill为通用网关图标，官方固定树和既有Lobe未提供适合vector品牌资产，无外部艺术资源复制；来源许可在Notices。没有真实凭证/部署/设备/iCloud请求或验收，按当前实现+图标标准done，历史验证边界保留。本分支不启动xcodebuild或模拟器。
