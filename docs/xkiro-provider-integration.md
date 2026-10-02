# xKiro 配额与钱包

xKiro 是 `xkiro.com` 提供的服务，与 AWS Kiro 不同。用户输入 API Key，iPhone 与 Watch 均直接以 Bearer 请求 `GET https://api.xkiro.com/v1/usage`，不依赖 Mac、其他设备代查或新增服务。官方说明该查询免费、不消耗 tokens、不占用额度或速率限制，统计范围是 Key 所属账号。添加、多个账号、安全保存、更新 Key、本机恢复与删除、iCloud 配置／Keychain 同步使用现有 API Key 流程；快照和提醒通过 provider/key 指纹隔离旧身份。

响应 `object` 必须为 `usage`。套餐 spend windows 以 `window_sec` 明确周期，以 `spent_usd / cap_usd` 求比例，并显示各自 USD 预算上限与剩余预算。预算与钱包都以 USD 计量，但预算不是可用现金，名称和单位明确为“USD 预算额度”，窗口可额度告警，钱包可低余额提醒，两种提醒开关独立。金额按官方的定点字符串解析为 Decimal；预算展示保留六位小数，钱包保持 Decimal，不把微额舍成假零。窗口重置只取当前采集时间加明确 `resets_in_sec`，不推测缺少的重置。

每日 free_tokens 是独立的免费模型 tokens 额度，以官方声明的 UTC 00:00 为边界；与付费模型预算和钱包互不替代。只有明确 `limit_per_day: null` 才是无限免费额度，缺失值不是无限或零。计数缺失保持 nil；无限 lane 不告警、不预排重置。窗口 cap 为零／不支持的非整小时长度不提供假额度；重复窗口身份、畸形金额、错误计数或重置字段不能成为成功的假读数。

钱包只取 `wallet.balance_usd`，保留服务给出的负值。`held_usd` 是进行中请求预留金额，官方说明不是余额扣减，本接入不二次扣除。`wallet: null` 表示钱包尚未创建，不捏造零余额。余额不足、免费额度耗尽和套餐额度耗尽均各自展示，不从一个数推断整个账号／所有模型的 API 可用状态。没有服务端显式 availability 字段时保持未知。

Provider.balancePresentation 为 mixed，因此 App 卡片／详情、Watch 和 widget保留所有套餐、免费token与钱包窗口；演示包含四种数据。xKiro 使用系统 SF Symbol `puzzlepiece.extension.fill` 通用扩展符号，不称为品牌标志；未核实独立品牌 vector 许可，没有新增第三方 SVG。

来源：

- [xKiro 官方 Usage 文档](https://docs.xkiro.com/api/usage)，2026-10-02通过agent-reach网页后端读取，页面发布时间2026-09-22。核对账号范围、免费查询、定点字符串、UTC免费额度边界、wallet null与held资金语义。
- [Pulse 固定397c8fc4文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/xkiro.md) 和 [XKiroUsageService.swift](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/XKiroUsageService.swift)。按契约独立适配，未复制服务实现；上游注明fixture为合成且没有真实账号查询。

6个XKiro tests覆盖四种单位／时间、Decimal微额／held不扣减、显式null无限与缺值、畸形／重复lane、请求／错误／identity／mixed展示、UTC边界与负余额。Swift 6完整App模块与完整测试语义类型检查、PBX lint和diff check通过；没有执行xcodebuild、启动模拟器或真实Key查询。整合测试执行和unsigned全目标App/Widgets/Watch构建由root串行负责，当前仍未验收。

真实账号响应、Key有效／失效、PAYG及每日免费无限账户、余额／quota提醒、iCloud配置与凭证到达／删除、关闭另一台设备后的独立刷新、实际widget视觉和品牌许可均未真实验证。文档契约与合成测试不等价于双端真实成功。
