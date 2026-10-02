# JetBrains AI provider

`.jetBrainsAI`支持默认production个人license。用户自行登录官方Central、选择license并主动提供central login export。手机和Watch各自导入新登录的独立export；查询和续期随后直接HTTPS，不需要电脑继续运行、IDE快照或代查服务。

协议来源为官方Central1.11.0固定artifact及只读ELF提取，见[研究和wire契约](../.scratch/provider-expansion/research/68-jetbrains-ai.md)。原发行public client_id=central-cli只用于已授权export的兼容refresh，不创建冒充CLI登录、复制secret或自动接受条款。初始请求为JBA refresh→auth.grazie.ai Register/ProvideAccess→api.jetbrains.ai quota/refill；返回新的JBA RT必须先持久化，再做后续签发。direct AI refresh及失败重签复用同一已验证scope，异常结果不回滚或盲重放旧链。

credentials只进每设备vault，不进同步secret store。缓存身份是服务HTTPS mint所得subject+issuer+selectedlicense+shared UUID；device和grant不混入快照scope。高熵RT摘要ledger仅用于本机已观察重放检测，删除仍保留；它不提供跨离线设备global family锁。Watch独立SecureField导入并验证expectedIdentity和真实active接管结果。

新grant先写独立candidate，保存旋转结果和可恢复中间态。验证页返回prepare receipt，既有active保持原值；账号表单真正点击保存/已有账号replace时，ScopedStore才在actor内按active baseline代际CAS接管。候选签发/额度失败或取消不损坏旧授权，旧回执、晚UI保存、删除后回执不得复活或覆盖更新的RT。候选可激活期一小时，超期访问清除secret、spent marker保留。授权sheet成功返回表单不等于完成保存。

quota.current是已用，maximum是分母，CLI展示运算直接证明。100000原始单位等于1 AI credit，Decimal除数及逆乘检查保留计数；tariff/top-up各自current/maximum/available显示，aggregate不再重复画作独立额度。未知不补0或推套餐价，不把AI credits当美元钱包；refill.next才是reset，until不用作reset或推断top-up expiry。

初始和direct mint统一处理expiresAt：正数按毫秒且拒过期/超界，nil/非正沿固定CLI的24h默认；这是客户端默认，不声称服务器精确期限。真实rotation/撤销/长期双端独立行为尚未观察。

App/Watch/widget/demo/provider注册齐备，通用SF terminal图标与Notices记录存在；官方JetBrains mark许可不适合template染色，未导入外部标志。31项本地实际XCTest0fail，主线程工程组合54/0fail是此前dece27b基线；最终全量、unsigned及Pi由主线程记录。用户当前完成门槛为实现+图标，真实账号缺失不再是关票阻塞。
