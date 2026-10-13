# GitKraken AI 会话与组织额度

新增 `.gitKraken`，用户明确输入账户会话 Token，允许粘贴完整 Bearer header 值，只接受一个无内部空白的 token。界面称“账户会话 Token”，提醒会过期及重新配置入口，不称永久 API Key、不自动登录或读取浏览器/CLI。envelope kind 为 `.session`；可解析的 JWT exp 只作为本地过期提示，不验证签名、不证明登录成功，opaque token 到期未知，401/403要求重新配置。没有来源支持的刷新协议则不发明 refresh。

可选组织 ID 对应已知 `gk-org-id` 请求 header；留空查 token 默认组织。请求固定 GET `https://api.gitkraken.dev/v1/ai-tasks/usage`、Bearer、Accept JSON、Client-Name TokenPulse/Client-Version。组织 ID 限制为安全单行标识符并保存在账号配置及凭证元数据。SHA-256(provider,token,organization) 绑定使同 token 换组织也清旧快照/协调提醒；iCloud配置与Keychain未一致时不借旧会话查询新组织。

只解析 `data.used/limit/resetsOn/organization.used/limit`，个人与组织池为两个稳定窗口。数量为 credits，不是美元；resetsOn保留真实ISO偏移时间，没有据名称推断七天周期。组织窗口标明配置ID；接口不返回名称时显示“默认组织（接口未提供名称）”。`sharedUsed`只是个人对池的贡献，没自己的分母，不另画额度。缺失/非法数值不补零，limit=0不画百分比，limit=-1表示明确无限，无百分比/提醒/reset；只剩无有界窗口时保留真实无限状态或noQuotaWindows，不伪造完整配额。

进入既有账号添加、安全保存、可选同步、本机/双端直连和删除流程；Widget/卡片/详情/Watch按credits分两池，演示包含个人与指定组织。适用quota告警与已报告reset沿既有规则，失败保留同身份旧观测与时间；换身份先清旧观测。没有货币钱包或低余额提醒能力。

协议来源：[Pulse文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/gitkraken.md)及[固定parser](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/GitKrakenUsageService.swift)，上游标明二手GitLens/CodexBar契约。组织header是上游文档列出的候选能力，尚未实账号确认。图标使用官方GitKraken/vscode-gitlens commit `a3ab1179ac86a0d83cb35c63a0af9114a6003f99` 的GitLens符号 `images/dark/icon-gitlens-filled-orange.svg`（不在plus目录，适用仓库MIT），改为黑色模板fill，路径/尺寸保持，版权/完整许可见ProviderIconNotices。它是官方客户端符号，不冒充未有许可的GitKraken网站logo。

2026-10-02：完整App所有Swift source的Swift6 iOS module emit通过；新增6个GitKraken XCTest方法、CommandCode/Amp全测试文件一同semantic typecheck通过（包括凭证身份修正），PBX lint/diff/矢量模板metadata检查通过。合成测试覆盖会话kind/清Bearer/JWT过期前零请求、HTTP错误、个人/组织/credits/时间/Widget、无限/零/缺失/Bool边界、组织header、切组织身份清缓存、本机配置持久化与删除。

没有执行XCTest、xcodebuild或模拟器；root集中完整测试和unsigned App/Widgets/Watch构建。没有真实Token/组织授权/设备实验，尚未验证当前API/header权限、实际pool/reset、expiry/reconfiguration、多账号真实隔离、iCloud到达、物理Watch在手机离线下读取、提醒及视觉。票保持implemented-awaiting-validation。
