# V2EX AI Chat

V2EX 使用用户输入的 Personal Access Token，iPhone／Watch 各自 `GET https://edge.v2ex.com/api/v2/chat/quota`，使用 Bearer Authorization，不借用网页 Cookie 或设备外服务。添加、凭证更新、多个账号、本机保存与恢复、iCloud 配置和 Keychain 同步、删除使用现有 API Key 流程。Key 的提供商指纹与缓存和提醒identity绑定，换 Token 不沿用旧身份数据。

五小时窗口与 `extra_usage` 额外用量补充包各自展示 tokens、总量、剩余量及比例，不相加制造总使用率。已用百分比由原始 `used_tokens / total_tokens` 算出，不再次使用整数舍入的 `used_percent`。缺少 used 或 remaining 时保持缺失，不能称为零或已用尽；总量为零不能作分母。只有提供商返回 `remaining_tokens <= 0` 才标记已用尽。

`active: false` 表示窗口尚未开始：不映射零起止时间为1970、不提供倒计时、名称提示“尚未开始”，并使用非重置语义避免未知窗口被使用率下降误判重置。`active: true` 时只使用明确的 `period_end` 作重置，`period_start` 是服务端真实窗口身份。当前窗口充值扩大总量、使用率下降也不会制造新窗口或确认重置。V2EX 官方帮助说明查询不启动窗口；只有下一条消息启动窗口，TokenPulse不发送聊天消息。

额外用量按照官方说明没有到期时间，只在五小时额度消耗完后使用。`pack_count > 0` 时才显示补充包；它没有 reset、expiry 或周期倒计时，购买补充包是恢复可用额度而非套餐重置，使用 `resetSemantics: .nonResettingAllowance`。仅在使用率真实恢复到最低阈值以下后允许未来再次上穿提醒，不将购买造成的下降四十个百分点称作重置。

五小时窗口明确重置时可预排既有重置提醒；未开始窗口／永久补充包不提供重置开关。额度阈值独立判断，钱包与低余额设置不开放。HTTP 401/403 及 `success:false` 是 Token 拒绝，429 是限流，网络／服务端／畸形数据失败保留同身份上次数据和采集时间。演示包含运行中的五小时窗口和补充包，小组件及 Watch 分别展示两种 metric。

图标使用系统 SF Symbol `bubble.left.and.bubble.right.fill` 作为通用聊天符号，不称为 V2EX 品牌标志。不导入无法确认来源许可的站点品牌 SVG，Apple 系统符号由系统渲染；图标替代选择见 ProviderIconNotices.txt。

来源：

- [V2EX 官方配额帮助](https://edge.v2ex.com/help/quota)，2026-10-02读取，页面注明最后更新2026-09-06。确认 Token 计数、消息触发窗口、当前窗口充值不重置已用、额外用量没有到期，以及只读查询不开始窗口。
- [Pulse 397c8fc4 V2EX 文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/v2ex.md) 和 [V2EXUsageService.swift](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/V2EXUsageService.swift)。按契约独立适配，未复制服务实现；上游测试响应也是合成，未查询真实Token。

验证：7个 V2EX XCTest 方法覆盖 inactive／active、原始精度、缺值和零总量、购买与窗口充值不确认重置、畸形响应、Token拒绝、请求及身份、失败保留快照、本机删除、演示和widget。Swift 6完整 App 模块、完整 XCTest 语义类型检查、PBX lint 与 diff check 通过。未运行 xcodebuild 或启动模拟器，测试执行和 unsigned 全目标 App／Widgets／Watch 构建由root统一进行，未完成这些验收。

尚未真实验收：真实Token有效／失效、当前活跃窗口和补充包、是否已用字段能超额及所有边界、账号删除／Keychain配置同步、设备离线后的双端独立刷新、真实通知和widget视觉。官方帮助和合成测试不等价于真实手机／Watch接入成功。所有真实验收保持未勾选；品牌矢量与许可仍未核实，当前只使用通用系统符号。
