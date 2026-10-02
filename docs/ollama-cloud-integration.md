# Ollama Cloud 账户页额度

`.ollamaCloud` 注册通用账号隔离 WK 登录，入口 `https://ollama.com/settings`。只从临时容器的 ollama.com 域保留已知 wos-session、__Secure-session、__Secure-next-auth.session-token、next-auth.session-token 及数字分片后缀；分析 Cookie、其它 origin、伪分片和裸推理 API Key 均不作为凭证。root WebProviderSession 绑定 provider/账号 UUID/origin/会话/expiry/来源指纹。过期或3xx/401/403要求重新登录，删除与重登沿用安全存储和会话清理。

iPhone 与 Watch 独立 GET /settings，关闭自动 Cookie、禁缓存、Accept=text/html、Accept-Language=en-US,en;q=0.9；生产传输拒绝所有重定向。只有目标 HTTPS host/path 和 text/html 响应进入解析。官方 [Cloud 文档](https://docs.ollama.com/cloud) 描述账户用量，官方 [usage API](https://docs.ollama.com/api/usage) 是推理响应 token/耗时，不是这里的账号额度。2026-10-02 未登录公开探测 /settings 返回303→/signin，说明签入保护结构；文档中 /settings/usage 链接匿名返回404，因此本实现继续使用固定参考实际 /settings 路径，不据此声称真实账号验证。

解析使用 iOS/watchOS 可运行的有限 HTML token/tree parser，不依赖 macOS 专属 XMLDocument，不执行 JS，不加载外部实体。最大2MiB、128层和50,000节点；拒绝 ENTITY 声明，剔除 script/style/template 与注释。必须有唯一可见“Session usage”“Weekly usage”标签；分别沿本窗口容器读唯一明确“数字% used”文本，不读取 CSS width、模型图段或任意搜索数字。两窗口都必须能解析，局部或变更页面失败保留旧数值，缺失时间保持 nil，重复/非法时间拒绝。signin/login表单映射凭证无效；其它失配为无法读取响应，首次没取得可识别会话会在查询前拒绝。

会话额度的5小时、每周周期身份来自固定 Pulse provider 契约；真正重置时刻只用页面 data-time ISO 字段，不算下次日期，不把推理指标当使用量。已知使用率0–100直接传入；没有计数、钱币、余额、假无限或缺失变0。独立 card/detail/widget/Watch/演示与适用额度/预计重置提醒已注册。图标 ProviderOllama 固定 Lobe SVG 提交2e76c487…、原路径、MIT/版权、黑色模板与矢量属性在 notices 与 image set。

新增七项测试覆盖正常/missing reset、丢窗口/重复/歧义/超范围、脚本/template/CSS/实体/大小、非法多时间与登录页、Cookie数字分片/源隔离/API Key拒绝、请求/content-type/失效以及Widget/编码/演示/提醒。真实 Swift6 必要 client/session/parser 小模块类型检查、parse、PBX plist/diff 已通过；未执行 xcodebuild 或模拟器，root统一合并全测/资源构建。

按当前完整实现+图标存在验收已 done。真实 Cookie/账户页布局、SSO/验证码、iCloud/Keychain、物理 Watch 和实际通知未声称通过，不阻塞当前关票。固定依据：[Pulse client/page parser](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/OllamaCloudClient.swift)、[窗口映射](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/OllamaCloudUsageService.swift) 与 ollama-page-* fixtures。未来页面/文字结构改变会明确失败，需要适配，不能用猜测补齐。
