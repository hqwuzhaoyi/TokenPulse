# Synthetic

Synthetic 通过用户输入的 API Key 查询 `GET https://api.synthetic.new/v2/quotas`，使用 Bearer Authorization。iPhone 与 Watch 均直接请求该固定 HTTPS endpoint；查询本身不依赖 Mac、手机代查或新服务。添加、更新凭证、多账号、安全保存、iCloud 关闭下的本机使用、配置与 Keychain 同步、删除沿用现有应用路径。凭证以提供商与 Key 的 SHA-256 identity 绑定快照和提醒，换 Key 清除旧身份读数；不会保存 Key 到额度缓存或日志。

只解析服务命名的三个 lane，支持根对象或 `data` 包装。五小时 lane 用 `max` / `remaining` 算已用比例，保留服务给出的原始数量；此契约没有核实数量单位，界面不称其为 tokens、请求或货币。每周 `percentRemaining` 为 0–100 的剩余百分比，不能使用“<=1 则乘100”的猜测；没有比例时才从美元预算字符串 `maxCredits` / `remainingCredits` 求比例。该预算不产生钱包余额，也不把美元额度当作 token 计数。搜索 `search.hourly` 由 `requests` / `limit` 显示独立 Search 小时额度，单位为次请求。

五小时与每周 lane 使用 `resetSemantics: .continuousReplenishment`，`nextTickAt` / `nextRegenAt` 单独保存在 `nextReplenishmentAt` 并显示“下次补充”，绝不存入 `resetsAt`。只有搜索 `renewsAt` 是小时窗口完整重置时间。持续补充不预排或确认重置；使用率保持最低配置阈值以上时，补充或下降四十个百分点都不会重开告警；确实恢复到最低阈值以下后，下一次上穿才重新允许提醒。内部告警identity不是重置证据。

未知对象不会被当作额度，缺值不补零，错误数字／类型／时间作为刷新失败；失败保留同身份上次快照与采集时间。演示提供三种 lane；卡片、详情、Watch 和小组件沿用同一领域数据。Synthetic 使用系统 SF Symbol `puzzlepiece.extension.fill`，与固定上游通用 extension 图标含义相同，并非 Synthetic 品牌标志。不导入无法核实许可的品牌资源；Apple 系统符号由系统渲染，没有新增第三方 SVG。

固定来源：

- [Pulse Synthetic 文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/synthetic.md) 与 [SyntheticUsageService.swift](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/SyntheticUsageService.swift)。只按契约独立适配，未复制服务实现。
- [上游合成 fixture](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Tests/PulseTests/Fixtures/synthetic-quotas.json)。上游注明契约来自 CodexBar，未查询真实 Synthetic 账号。

验证边界（2026-10-02）：作者未读取真实 Key 或浏览器凭证，未执行 xcodebuild、未启动模拟器。Synthetic tests 覆盖根／data 包装、数量与单位、百分比刻度、美元预算 fallback、缺失／畸形字段、请求契约、双账号identity、失败缓存、本机恢复与删除、演示／widget；持续补充共用测试单独覆盖无重置／恢复后告警。Swift 6 App 模块与 XCTest 类型检查、PBX 和 diff 静态检查记录由本票提交补齐。unsigned 全目标构建及执行测试由 root 串行整合，仍待完成。

仍未真实验收：实际 API Key 登录后的套餐查询、当前套餐及响应边界、真实滚动恢复／小时搜索重置、真机提醒、iCloud 删除与配置／Keychain 到达顺序、关闭其他设备后 iPhone／Watch 各自独立刷新、品牌图标官方许可与视觉验收。合成测试或静态类型检查不表示真实接入完成。
