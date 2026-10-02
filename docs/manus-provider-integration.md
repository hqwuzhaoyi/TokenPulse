# Manus 网页会话与 credits

添加／重新登录通过共用临时WKWebView，限定 `https://manus.im`。只提取有效域 `manus.im`／`.manus.im`、根路径、未过期的 `session_id` Cookie，包含HttpOnly；不会读正常浏览器或其它站点资料，也不保留tracking Cookie。保存的是此Cookie值作为bearer token，绝不把Cookie header整串当token。通用WebProviderSession绑定provider、local account UUID、origin和实际session token重算fingerprint；查询时再校验scope和expiry，401/403/redirect要求重新登录，关闭／重试清除临时容器。

iPhone／Watch取得同一账号配置和安全凭证后各自 `POST https://api.manus.im/user.v1.UserService/GetAvailableCredits`，空JSON body、Bearer token、Connect-Protocol-Version 1、固定Origin/Referer/User-Agent，无Cookie转发、无手机／Mac代查。添加、更新会话、本机保存／恢复、多账号、iCloud关闭本机使用、配置与Keychain同步、删除沿用已有流程。错误保留同身份上次snapshot和采集时间。

接受固定的bare／data／result／response／availableCredits credits结构，数字或严格numeric字符串以Decimal保存。每日恢复额度maxRefreshCredits／refreshCredits、月度proMonthlyCredits／periodicCredits分别作为exactCounts和各自百分比；totalCredits独立显示为非货币credits总量，不能把它与分项相加，也没有总百分比。只有refreshInterval明确daily才标“每日”，不从额度数量猜日周期。nextRefreshTime只读明确ISO日期；数值或数字字符串没有已核实epoch，保留未知而不猜1970／2001。月度未给reset则nil，不预排月度重置；月度恢复只重武装阈值告警，不能确认完整重置。totalCredits不是USD／钱包现金，低余额提醒不开放。

[Manus官方每日刷新credits说明](https://help.manus.im/en/articles/11711121-will-my-daily-refresh-credits-accumulate-or-reset)在2026-10-02读取，说明登录获每日额度、UTC每日刷新且不积累到主余额；此政策不用于补造响应缺失的max/reset。接口、Cookie和响应shape来自[Pulse固定397c8fc4 Manus文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/manus.md)、同版本ManusUsageService及manus-credits合成fixture。没有把second-hand内部Connect接口当公开管理API文档。

ProviderManus图标已存在：Lobe Icons commit `2df73b8899ec387eb94b96ecb6b87b151c4770dc`，`packages/static-svg/icons/manus.svg`，Copyright (c) 2023 LobeHub，MIT；notice保留来源、版权与完整MIT，24x24、黑色template、vector preservation均已配置。App详情、Watch、widget和demo包含每日／每月／总credits三类独立值。

7个Manus测试覆盖Cookie域名/expiry/token-value、wrapper形状、计数和单位、numeric时间不猜epoch、missing/bad字段不补零、Connect请求头、账号scope和错误、non-money无低余额、demo/widget/icon。parser、PBX、diff和图标存在/XML/JSON静态检查通过；root统一编译／执行测试。按用户新标准，接入全链路与图标存在已实现，ticket done。

未读取真实session_id、未运行Xcode或模拟器，未执行真实Manus账号／设备刷新；这些真实验证仍明确未做，依据用户2026-10-02标准不阻塞关票。
