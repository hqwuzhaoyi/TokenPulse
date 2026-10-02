# Command Code 余额与真实限额

新增 `.commandCode` 提供商，可在 iPhone/Watch 添加自己的 API Key。使用既有按账号 Keychain envelope、配置持久化、可选 iCloud 同步、重新配置和删除流程；不开启同步时本机可查询，客户端不运行 CLI、不读取本机 Command Code 凭证、不依赖 Mac 代查。

直接凭证保存 SHA-256(provider,key) 单向身份元数据，沿用既有 scoped credential 绑定。换 Key、配置/Keychain 分批同步或正在查询时更换凭证，不允许旧用户额度冒充新账号；身份变化清旧快照，提醒账本按同一配置身份协调。

请求固定为 Bearer GET `https://api.commandcode.ai/alpha/whoami?limits=1`，成功后以该响应 `org.id` 为 URL query `orgId` 读取 `/alpha/billing/credits`。组织缺失时参数省略，查询 token 默认身份。认证失败先停止后续请求；HTTP 401/403、429、服务器错误和不可读 JSON 分开报错，既有 QuotaMonitor 保留旧快照与采集时间。

`credits.monthlyCredits/purchasedCredits/freeCredits` 都表示当前美元余额池，不是月度 allowance。全部三个实际返回时才用 Decimal 相加成 USD 钱包；缺任意池就不计算未知总额，仍可显示已给出的有界限额。没有凭套餐名称/价格表推算月度总额，没有用剩余+历史消费构造假限额，不请求 subscriptions/summary。服务给出的 `planId` 仅作为名称。

`windowLimits.limited` 必须是真正 JSON Bool true 才显示 `fiveHour/weekly` 的 used/cap；resetAt 是毫秒 epoch。组织 `orgLimits` 的 spent/limit 和严格 Bool exceeded 则分开显示，非正或缺失 limit 不产生百分比。id 取 scope/model/resetInterval 及仅完全重复时的后缀，不取数组位置或重置时间；组织 ISO reset 保留，monthly/total 不推断固定周期。所有金额先按 Decimal 解码和算比率，额度展示标量最后转换为现有 Double 字段，钱包总额保持 Decimal。字段类型错误明确不可读，不把 Bool、NaN、缺失值补成数字。

余额与额度采用显式 `.mixed` 能力，卡片/详情/Widget/Watch 使用共享混合展示，独立的额度与低余额提醒设置分别控制已报告的真实限额和 USD 钱包。钱包没有百分比或重置；全局关闭通知停用两类提醒。演示包含实际有界 USD 限额与 Decimal 钱包。

来源：[固定 Pulse 文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/command-code.md)及[客户端](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/CommandCodeUsageService.swift)，其协议依据 `command-code@1.51.3` shipping client，未公开稳定账单 API 保证。TokenPulse 刻意不采用上游估算 plan/pool 两个窗口。官方仓库资产有 logo 但未找到再分发许可，使用已许可 Lobe Icons `79b551cf26aab9ea4ac701fb807160950a5b860f` 的 `packages/static-svg/icons/commandcode.svg`，版权/完整 MIT 见 ProviderIconNotices。

2026-10-02 验证：完整 TokenPulse app 的所有 Swift source 用 Swift6、arm64 iOS Simulator SDK 执行 emit-module/语义检查通过；新增7个 XCTest 方法完整 semantic typecheck通过；PBX `plutil -lint`、资产 vector/template metadata、`git diff --check`通过。测试覆盖 exact Decimal、缺失池、严格 Bool/畸形金额、无界/零cap、组织重排稳定ID、请求与错误类别、两账号凭证隔离/本机持久化/失败保留/删除、Widget 度量和归档。

本工作者未执行 XCTest、xcodebuild 或启动模拟器；完整 App/Widgets/Watch unsigned 构建与测试执行由 root 串行验证。没有真实 Key/账号/手机/Watch 实验，尚未验证当前接口兼容、真实数值/组织身份、凭证撤销、iCloud 凭证到达、物理 Watch 在手机离线下直连及实际通知。整票仍为 implemented-awaiting-validation。
