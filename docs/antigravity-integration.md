# Antigravity 原生模型组额度

TokenPulse直接向Google Cloud Code quota summary查询模型组额度，不启动Antigravity CLI/IDE或本机语言服务器，也不依赖Mac常驻、loopback转发或外部代理。

## 登录与权限

在账号登录页输入用户自己注册的Google iOS OAuth Client ID（Bundle ID `com.tokenpulse.app`）及可选Cloud项目ID。TokenPulse通过ASWebAuthenticationSession完成Google公共原生OAuth、reverse-client回调、PKCE/state和offline refresh，userinfo subject用于身份绑定；没有Google-owned CLI client/secret或浏览器token收集。客户端必须允许本次授权，账号必须已获得Antigravity访问权限。

官方CLI 1.2.15个人consumer登录实际scope集合为：

- `https://www.googleapis.com/auth/cloud-platform`
- `https://www.googleapis.com/auth/userinfo.email`
- `https://www.googleapis.com/auth/userinfo.profile`
- `https://www.googleapis.com/auth/cclog`
- `https://www.googleapis.com/auth/experimentsandconfigs`
- `https://www.googleapis.com/auth/aicode`
- `openid`

本实现保留这一已核实集合，未擅猜Gemini三scope已足够。官方CLI使用这些scope不代表每个都必需，也不保证Google向任意自有iOS client授予内部scope或Antigravity entitlement。实际被拒绝时显示授权/权限错误；不会伪装为Google客户端、开通服务或绕过访问限制。

用户填写的项目 ID 在打开授权浏览器前通过提供商校验器检查；直接调用授权接口也先校验，非法输入显示项目 ID 提示，不发 token/userinfo 请求。额度组与 bucket 名称去除首尾空白，空组名视为缺失，空 bucket 名回退稳定 bucket ID。

授权完成后只POST `loadCodeAssist`，metadata的IDE/platform/plugin为UNSPECIFIED、ideName为TokenPulse。仅currentTier/paidTier的已激活身份与实际managed/用户配置项目可继续；allowedTiers只是可选资格，不能用来自动onboard。项目验证错误会失败。随后POST `retrieveUserQuotaSummary`并成功解码真实额度才保存凭证。

凭证身份包含provider、本地account UUID、Google subject、clientID和resolved项目；轮换access/refresh token不改变身份。敏感凭证走现有系统安全存储、同步与删除机制，手机/Watch分别直连刷新。没有密码或token进入URL参数、quota缓存或日志。撤销/过期刷新失败保留旧缓存并请求重新登录，不删除别的账号。403表示查询权限不足，401为凭证错误，429限流；quota响应URL必须等于请求固定端点，transport拒绝重定向。

## 数值与展示

`groups[].buckets[]`是模型组窗口，bucketId构成稳定window ID。remainingFraction只接受有限0...1，并反转为已用百分比；仍有极小正剩余时百分比向下夹到100以下，避免误发100%告警。remainingAmount是protobuf int64（JSON可为整数字符串或整数），用Decimal精确保存，无总量时不造比例，无类型时显示“单位（类型未提供）”。不将数量称token/美元、不换汇。

这两个remaining字段是oneof，冲突、超界/溢出或非法reset失败。缺失数值保持未知，disabled窗口标明未启用并不告警/排reset；没有数量字段不补0或100%。resetTime只解析实际protobuf时间戳；已知5h/weekly映射时段，未知window不猜时长。根buckets仅用于groups缺失的deprecated兼容；groups存在时不叠加。空groups显示未返回模型组额度，不生成虚构额度。独立AI Premium credits不在本65实现范围。

模型组卡片/详情、Watch、Widget和demo接入既有quota展示，百分比窗口适用额度/真实reset提醒，没有钱包或低余额设置。图标为固定Lobe MIT SVG，ProviderIconNotices记录路径/版本，vector/template图像集存在。

## 证据与验证

主要证据是官方CLI manifest与hash匹配的1.2.15归档内静态FileDescriptor/Go调用，摘要、offset、官方网页及SDK的边界见[研究报告](../.scratch/provider-expansion/research/65-antigravity.md)。下载/静态解析没有运行官方程序、读取用户keyring或凭证。固定Pulse397c8fc4的本机RPC仅佐证已有bucket语义，不用于猜远程URL。

七项合成回归覆盖整数精度、fraction/oneof/disabled/unknown边界、native授权与不onboard、身份/项目隔离、过期轮换、失败缓存/重启/删除和Widget/demo/提醒；共享OAuth另有独立测试。实际小Foundation parser运行及provider/OAuth/五个parser-auth测试Swift6语义检查通过，parse/PBX lint通过。完整Xcode/XCTest由root串行；没有真实账号、scope授予、手机/Watch真值或撤销实测。用户当前关票标准为完整实现加图标存在，不以这些未实测事实伪装成功或判定接口不可行。
