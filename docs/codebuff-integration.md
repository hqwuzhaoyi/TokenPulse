# Codebuff Key 模式

POST https://www.codebuff.com/api/v1/usage 使用 Bearer Key 和固定客户端 fingerprintId。只查询 Key 可见的 credits，不借用 CLI 会话或承诺每周订阅额度。真实 quota/usage 同时存在才给比例；剩余 credits 作为非货币余额，不触发货币低余额告警。额度和余额同时展示，不相加。

字符串金额和数量用 Decimal 保留，未知/格式错误不补零；秒/毫秒或 ISO 重置解析有范围保护。多个服务账号的 Key、状态和告警身份分离。新增请求、边界、精度、Widget 和提醒测试，运行与真实 Key/双端/iCloud 验收仍待统一记录。

参考 [Pulse 397c8fc4](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/codebuff.md)。官方 CodebuffAI/codebuff tree 没有可复用 SVG 品牌资源；当前使用原生 terminal 通用图形，不伪造品牌标志。
