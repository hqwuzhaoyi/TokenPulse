# DevPass / LLM Gateway Key 接入

输入普通 LLM Gateway API Key，经统一安全存储、UUID 隔离账号生命周期及 iCloud 配置/凭证同步使用；不读取其他应用的 Key。iPhone 和取得凭证后的 Watch 分别直连 `GET https://api.llmgateway.io/v1/key`，使用 Bearer、JSON Accept、禁用自动 Cookie、禁用本地响应缓存，沿用跨 origin 重定向防护。平台 publishable Key 和 end-user session 不是此接口的凭证。

固定参考：[Pulse DevPass 源码](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/DevPassUsageService.swift) 与 [说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/devpass.md)。另核对 [LLMGateway 官方 Usage API 文档](https://github.com/theopenco/llmgateway/blob/8e280f73fb38540e0db5e026f8419ce138e05b43/apps/docs/content/(devpass)/developers/devpass-usage.mdx)，固定 `8e280f73fb38540e0db5e026f8419ce138e05b43`：明确普通 gateway Key、三个 USD credit/limit 字段族、ISO 重置和 none 语义，失效/不活跃 Key 返回 401，不适用的凭证返回 403。

Premium 每周额度 (`devpass.premium_weekly`)、账期 credits (`devpass.cycle`) 和 Key 累计限额 (`devpass.key_limit`) 是三个独立窗口，单位为 `USD credits`，不是 API 钱包余额。数量只接受十进制字符串，先用 Foundation Decimal 解析与相减，最大 38 位有效数字；负数、科学计数法、非有限、布尔/数字替代字符串、不可精确表示的差值均拒绝，不能补零。`QuotaWindow.exactCounts` 保留 used/remaining/total 原始十进制精度，iPhone、Watch 和 widget 共用精确显示；只有环形百分比转有限 Double。零额度表示未发放窗口，缺失任一计数不能制造百分比。

计划只接受 none/lite/pro/max，未知计划失败并保留旧数据。none 且没有正 Key 上限是成功的按量计费无上限状态 (`isNoPlan=true`)，清除过往套餐窗口；卡片、Watch、组件明确显示，没有假额度。none 但有 Key 上限仍显示 Key 累计预算窗口。付费计划完全缺少有效额度是 noQuotaWindows，格式错误是 unreadableResponse。

每周 premium reset 使用返回的 ISO 日期。官方说明窗口从首个 premium 请求开始，过期后接口返回真实零用量和 null reset，直到下一次请求重新开始；不将 null 猜成下周时间。账期 credits 没有返回结束时间，Key 累计限额为所有时间预算，两者没有重置或虚构固定周期。只有实际存在的重置能预排预计提醒；按量计费无上限不开放额度提醒，只有 Key/账期额度时不显示无用的重置开关。所有有效额度共用阈值去重，不启用钱包低余额提醒。错误保留同账号的旧采集时间。

演示保留三窗口，使用独立本机演示存储。添加、恢复、凭证替换、删除和多账号沿用公共基础设施；模拟账号隔离与状态恢复测试不代表真实 Keychain/iCloud/物理 Watch 已验证。

图标为明确的非品牌通用接入图形，沿固定 Pulse 的 `Sources/Pulse/Resources/extension.svg`，Apache 2.0，矢量路径不变，黑色模板 24×24。官方 LLMGateway logo 源码位于 AGPLv3 项目，本次没有导入；该替代选择及完整许可记录在 ProviderIconNotices.txt。

七项专项测试覆盖请求契约、精确小数及超过 Double 精度的计数/编码、无套餐与未知计划、错误类型/溢出、独立提醒/组件/演示、多账号恢复替换删除、畸形保留旧数据与 none 清除旧套餐。完整 App 模块与新增测试 Swift 6 iOS Simulator 17.0 typecheck 已通过；完整 unsigned App/Widgets/Watch 构建和 XCTest 执行由 root 串行验证，不在本分支启动模拟器。

仍未真实验收：普通 API Key 的真实查询、套餐实际额度变化/过期、生产无套餐状态、Key 失效和删除、iCloud 到达、物理 Watch 独立查询、真实提醒和组件视觉表现。官方文档与固定参考不能替代当前账号证据；未接触或输出真实凭证。

生产 DevPass 解析代码 macOS 合成 smoke 另通过：超出 Double 整数精度的 Decimal 原值、精确相减、快照编码、已知 no-plan、非有限/负数/溢出/下溢拒绝。此检查不是模拟器 XCTest 或真实 Key 查询。
