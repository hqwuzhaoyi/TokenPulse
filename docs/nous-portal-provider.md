# Nous Portal：独立设备授权与额度

Nous Portal 已实现原生OAuth device flow。添加／重新连接时在浏览器输入服务返回的user code，使用官方公开客户端标识`hermes-cli`与默认`inference:invoke` scope；授权页可能显示Hermes CLI，UI明确告知。不是TokenPulse自有注册品牌，也不复制client secret或读取任何Hermes文件／环境变量／现有会话。官方源码为公开device请求，未找到要求本票先注册自有client的证据；没有据第三方client ID推导权限限制。

固定HTTPS Portal `https://portal.nousresearch.com`：form POST `/api/oauth/device/code`，poll `/api/oauth/token`的device grant，然后Bearer GET `/api/oauth/account`核实服务端user.privy_did与organisation.id（或paid_service_access.organisation_id），两处org同时存在必须一致。额度请求每次再校验真实服务端subject/org与本地绑定。来源身份以Portal、服务账号UUID、真实subject/org计算，不包含access token、refresh token或设备ID；同一账号的两端独立grant、同端令牌轮换仍具有同一来源。

手机与Watch分别建立授权链。Nous凭证由provider-aware store路由到独立service、显式synchronizable=false、AfterFirstUnlockThisDeviceOnly的Keychain；原有提供商继续原同步store。不同provider参数不能把实际Nous envelope降级写入iCloud。账户配置、关注、额度快照与提醒ledger可以同步，Nous secret读写及AppRuntime同步backfill全部跳过同步store。Watch在已同步Nous账号页有“连接此Watch”，显示verification链接／user code／等待状态并直接poll；只有与现有账号scope匹配才保存本地授权。取消或配置中途改变不接纳迟到结果，不依赖手机完成后代查。

刷新为form POST `/api/oauth/token`，body仅grant_type=refresh_token/client_id，单次refresh secret在**x-nous-refresh-token header**。Nous专用coordinator以pending task gate序列化本设备账号的整段load/rotate/persist/query；vault版本CAS保护所有晚到的成功／错误，删除留无secret的generation tombstone，不能用旧A结果覆盖重登B或删除后的重建。POST前先持久化pending；200必须先原子保存新chain再查询额度。网络未知结果或进程在POST后消失后保留uncertain/pending，未过期access仍可GET account，不能重放旧refresh；需要新的设备授权才能继续续期。明确edge/WAF/429拒绝不清会话，terminal invalid_grant/invalid_token/reuse清掉refresh并要求连接。expiry只用服务expires_in，不硬编码一小时。

订阅授予／残额／明确账期、购买credits、总可用credits各自展示，不把总量与分项再相加。数值以Decimal exactCounts保存，差额用逆减法验证，不能表示时只used/percentage=nil，保留真实left/size。账期只读明确ISO，不补日期。API未声明currency，因此显示非货币`credits`，不借Pulse美元假设生成低余额通知。套餐额度告警与明确重置沿既有规则，购买／总量无假的总百分比。失败保留正确scope旧快照／采集时间。

官方固定源码：[NousResearch/hermes-agent b7200ef auth_constants](https://github.com/NousResearch/hermes-agent/blob/b7200efef01dce2097c3c5556843ff3cd2764789/hermes_cli/auth_constants.py)、[device flow](https://github.com/NousResearch/hermes-agent/blob/b7200efef01dce2097c3c5556843ff3cd2764789/hermes_cli/auth_device_flow.py)、[refresh](https://github.com/NousResearch/hermes-agent/blob/b7200efef01dce2097c3c5556843ff3cd2764789/hermes_cli/auth_nous.py)、[account](https://github.com/NousResearch/hermes-agent/blob/b7200efef01dce2097c3c5556843ff3cd2764789/hermes_cli/nous_account.py)。[官方Portal集成说明](https://hermes-agent.nousresearch.com/docs/integrations/nous-portal)2026-10-03读取，说明OAuth/刷新/工具使用及third-party工具，不能将其同机token文件共享建议用于两台独立设备。旧Pulse397c8fc4只借用本机Hermes短期token，本票没有该路径。

ProviderNousPortal图标已存在：Lobe Icons `03fa842d9a4aae31437b6ebd5aa7ca8de7180acc`，packages/static-svg/icons/nousresearch.svg，Copyright(c)2023 LobeHub，MIT；来源/完整许可记录于ProviderIconNotices，24x24黑色template vector imageset。App/Watch/widget/demo和所有注册/PBX路径已实现。worker仅parser/PBX/diff/资产静态检查，不运行Xcode或模拟器；root统一编译、执行测试。真实Portal授权、多grant共存、当前账户单位和硬件刷新没有实测，明确保留事实，用户实现+图标标准不以此阻挡关票。
