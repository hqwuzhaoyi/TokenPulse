# Qwen Cloud 套餐接入

独立于百炼 Coding Plan。登录入口为 home.qwencloud.com 的个人Token Plan页，临时WK仅选择qwencloud.com父域的已知ticket、CSRF、cna及sec_token。至少一个登录ticket必需；会话按本地UUID/provider/origin绑定，正常浏览器Cookie和CLI凭证不参与。

每次刷新先读取控制台页的安全token，再回退到同会话sec_token Cookie、固定user/info.json；认证拒绝和跳转直接失败，不绕过登录。额度调用固定cs-data.qwencloud.com网关，POST form的每个值仅保留ASCII unreserved字符，+、&、=均编码。cornerstone记录固定QWENCLOUD和ap-southeast-1，cna保持原值；CSRF作为两个明确header传递，不访问任意host。查询成功后订阅名称只是best-effort，名称失败不抹掉额度，取消不会吞掉。

解析只展开已知data/DataV2/Data控制台包装，包含包装内JSON字符串；不递归搜索任意对象。比例per5Hour/1Week/1MonthPercentage乘100，没有使用率尺度猜测；窗口reset是毫秒，过去窗口丢弃。真实布尔与数字分开，明确TotalCount=0显示“当前账号没有Qwen Cloud套餐”并清旧窗口，不声称无上限。Workspace.NotAuthorised表示服务权限错误，ConsoleNeedLogin/TokenError等为会话失效。错误保留旧数据。

来源：[Pulse固定说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/qwen-cloud.md)、同commit的QwenCloudUsageService.swift及三个合成fixtures。这是已公开的二手接口契约，不是本次真实账号录制。接口当前兼容性、iCloud及物理Watch未实测；用户已明确不将这些作为关票门槛。

图标沿用Lobe Icons commit79b551cf26aab9ea4ac701fb807160950a5b860f的qwen.svg，MIT出处和版权位于ProviderIconNotices.txt，24px黑色矢量模板包为ProviderQwenCloud。

root实际运行6项QwenCloudProviderTests及3项公共WebProviderSessionTests，9项全部通过，日志/tmp/tokenpulse-wave3-qwen.log。最终全量构建随第三批整合执行。
