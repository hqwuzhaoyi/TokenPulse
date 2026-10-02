# sub2api 分组计量

选择 sub2api，输入部署地址和分组 Key。复用账号级 Keychain envelope 的 serverAddress、同步、删除及服务器+Key+provider 摘要隔离；支持根地址、/v1、/v1/usage，保留部署路径前缀。省略 scheme 时仅补 HTTPS；公网 HTTP、userinfo/query/fragment/path traversal 拒绝，已支持的本机/私网 HTTP 规则沿 New API。两端取得凭证后各自 GET `/v1/usage`，Bearer 仅发送给配置 origin，拒绝跨 origin 重定向，不发送模型请求。

四种返回独立解析：钱包 balance 优先，只有没有 quota/subscription 时 root remaining 才能成为钱包；有效 ISO 币种才是货币，points/tokens/未知单位保持非货币。官方当前实现缺单位为 USD。quota、订阅 daily/weekly/monthly 和 rate_limits 各自保留 Decimal 数量、真实分母和范围；正的真实分母才算比例。正文 isValid=false 是凭证拒绝，不是空账号。未返回的 used/remaining/reset 不补零；quota 不推断周期，订阅不猜重置时刻，仅 rate_limits 的实际 reset_at 可预排通知。已用尽只采用明确 remaining<=0，不从余额或历史消费猜调用状态。

卡片、详情、Watch、widget 和隔离演示注册均已覆盖。钱包及带真实上限的 quota 可同时展示，不合并额度池。既有货币低余额和百分比提醒按实际指标工作，非货币余额没有低余额告警。更新服务器或 Key 先清除旧身份缓存和提醒；同身份查询失败保留旧成功快照与采集时间。旧固定提供商的 region、organizationID 和 metadata identity 路径没有改变。

主源依据：[Wei-Shaw/sub2api b8dece9000c68815a5b867ca5a1e6f236e173905 gateway_handler.go](https://github.com/Wei-Shaw/sub2api/blob/b8dece9000c68815a5b867ca5a1e6f236e173905/backend/internal/handler/gateway_handler.go)，直接核对 usageQuotaLimited/usageUnrestricted 的字段、单位、status 和 reset_at。参考 [Pulse 397c8fc4](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/sub2api.md)。没有访问真实用户 Key 或部署；真实账号、设备、iCloud 和后台通知仍未验证，按用户当前验收标准不阻塞本票完成。

图标是官方 `assets/logo.svg` 的两条矢量 glyph，固定上述 source commit；剥离背景/gradient/filter/transform并改黑色 stroke、24×24模板，路径保持原样。来源、修改和 LGPL-3.0 文本记入 ProviderIconNotices.txt。资源文件存在并已映射 App/Watch/Widgets。新 XCTest 覆盖四种计量、正文拒绝、缺值/单位/零分母、请求路径/头、地址+Key+provider fingerprint及提醒边界；小模块 Swift6语义检查、Swift parse、PBX和diff检查通过。XCTest实际执行和target构建交由root统一，本分支不启动xcodebuild或模拟器。
