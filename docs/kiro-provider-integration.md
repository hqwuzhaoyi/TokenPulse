# Kiro provider

新增 `.kiro`（与第三方 `.xKiro` 分开）。入口使用账号独立的临时官方 portal 浏览器，导出严格 scope 的 Cookie；手机与 Watch 随后自己执行 HTTPS。个人 Google、GitHub、Builder ID 的默认 production portal 被支持；企业会话与其它区域不自动迁移账号。

协议来自官方 `app.kiro.dev` release `7641e207feab0c25`，详细 wire、SHA-256、schema 和研究限制见 [Kiro 新证据](../.scratch/provider-expansion/research/64-kiro.md)。GetToken、RefreshToken、GetUserUsageAndLimits 均为 Smithy RPC v2 CBOR；没有 ACP、本地进程、电脑代查或猜测云端 endpoint。

每次读取原生 GET 首页验证 head 中的个人身份/CSRF，再获得临时 Bearer 查询额度。Bearer不保存为永久key；401按阶段只重试一次RefreshToken。已知Cookieexpiry逐name保存，服务器Set-Cookie替换/删除后重算，未知session寿命由服务器认证结果决定。缓存identity绑定已核验个人user-id+profile+idp和本地账号，不随Cookie轮换变化。原始envelope仍有完整Cookie/scope完整性指纹。

订阅额度、active试用、bonus和明确可标识的额外credits分别显示。WithPrecision字段优先；Bool/字符串不当数值，未知计数不补0或算使用率。无分母仍可显示已用计数。试用/额外池显示expiry，不作为周期reset；credits不作货币钱包。CBOR codec在1MB、12层、4096节点和1024容器成员限额内，拒绝重复keys、非有限浮点、异常integer、未知tag/bytes/indefinite chunks。

App表单、详情、卡片、Watch直连、widget、demo和PBX生产/测试注册均沿通用能力。图标来自Lobe Icons固定MIT版本，见ProviderIconNotices。

本地验证：实际生产小module Swift6语义检查及23项macOS XCTest通过，另有iOS AccountQuotaClient+QuotaMonitor轮换/落盘/重启回归等待主线程统一跑；unsigned全目标结果也由主线程记录。未使用真实账号或Watch实机，用户当前完成门槛是实现与图标存在，未观察项不伪写成功。
