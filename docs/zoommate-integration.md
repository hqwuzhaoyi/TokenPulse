# ZoomMate 接入

每次刷新在ai.zoom.us交换nak，再请求credits/status；仅网络或5xx可在zoommate.zoom.us重试，拒绝跳转和认证失败不重试。短期nak仅存在于当前刷新、不写入凭证。只复用zoom.us父域Cookie到两个子域。credits精确计数、无限、停用和允许超额付费分别表达，毫秒日期校验溢出，服务明确不可用优先于超额付费显示。

登录采用按本地账号UUID隔离的临时WK容器，完成登录后读取限定域名/路径的必要会话，查询成功才保存。WebProviderSession将provider、origin、实际凭证、本地UUID及工作区元数据绑定为指纹，错误账号、过期、篡改scope会拒绝。直连查询同时用于iPhone和Watch，失败保留旧快照；App、Widget及演示已注册。读取账号的普通浏览器Cookie、桌面凭证数据库不属于实现。

契约来源：[固定Pulse说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/zoommate.md)及其中指向的固定源码/合成fixture。它们属于二手契约证据，没有伪称本次获取了真实账号响应。当前网页兼容性、实际认证、iCloud和物理Watch未实测；按用户最新标准，这些不作为ticket关票条件。

图标为系统通用符号，非官方品牌logo。固定Lobe目录未找到对应static-SVG条目，出处判断见ProviderIconNotices.txt。实现及图标存在满足本轮验收。

验证：root实际执行HostedWebProviderTests与WebProviderSessionTests共8项，全部通过。覆盖受限Cookie、身份变更、部分计数、定向tRPC解析、日期/布尔边界、Zoom短期token和有限主机重试。完整最终多目标构建由root整合后执行。
