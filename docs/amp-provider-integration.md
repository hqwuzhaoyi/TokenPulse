# Amp 额度与个人美元余额

`.amp` 使用用户从 Amp settings 明确配置的 Access Token，经既有安全 envelope/按账号 Keychain/可选 iCloud 同步、本机配置与删除流程查询；不读取 CLI 文件。iPhone/Watch 同一原生查询客户端直接 POST `https://ampcode.com/api/internal?userDisplayBalanceInfo`，Bearer，JSON body `{"method":"userDisplayBalanceInfo","params":{}}`。这是只读 RPC，不运行 CLI/代理。

响应只能是严格 Bool `ok` + `result.displayText`；`ok:false/error.code=auth-required` 或登录提示表示凭证失效，其他业务拒绝为服务错误，HTTP 拒绝/限流分开处理。没有公开刷新协议时不发明续期请求，失效从账号设置重新配置。

已知文本形态取固定 Pulse commit `397c8fc4f1bd52180a452d2f3f0c099def97cf69` 的[Amp provider文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/amp.md)和[parser](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/AmpUsageService.swift)：小时Free `Amp Free: $R/$L remaining (replenishes +$x/hour)`、每日Free的明确 today/resets daily 百分比、`Amp <Plan> Tier: agent usage $R of $L remaining` 与其 `a1.small orb hours`、两个旧 Subscription 百分比表述及 `Individual credits: $N remaining`。只清 ANSI 与 Markdown bold，不改变数字；千位分组必须合法，未知text/缺失/错误类型不生成零。Workspace balance与其他Orb单位不混入个人钱包/小时额度。

所有金额用 Decimal 解析及算比率，个人 USD 钱包保持 Decimal。小时Free优先于同一响应的每日百分比，使用 `.continuousReplenishment`、无reset/no next-time估算，不拿40百分点恢复当周期翻转。共享 planner 只在恢复到最小有效阈值以下后重新武装quota提醒，不发送reset提醒。每日Free有明确每日语义，但文本没有重置时刻，不推算纽约8点。

Agent用实际美元而非旁边四舍五入百分比；Orb用小时，两者稳定ID为amp.agent/amp.orb。旧Subscription只有百分比，不补金额或小时数量。`period YYYY-MM-DD to YYYY-MM-DD` 是UTC日锚点+`.day`精度，跨时区显示源YYYY-MM-DD，不按午夜误判needsUpdate、不预排精确reset；只读真实刷新仍可根据observations判断周期。rounded renewal countdown不当reset，非法日期丢弃边界。零cap不产生环。

`.mixed` 显式能力让额度与钱包在卡片/详情/Widgets/Watch分别展示，独立额度和USD低余额提醒沿共享规则。演示含continuous Free、Orb小时和个人钱包。图标为Lobe Icons commit `79b551cf26aab9ea4ac701fb807160950a5b860f` `packages/static-svg/icons/amp.svg`，版权/完整MIT记录在ProviderIconNotices；vector/template包装保持路径与明确尺寸。

2026-10-02静态验证：全部App Swift6 iOS module emit与新增7个完整XCTest方法semantic typecheck通过，PBX lint/diff通过。合成测试覆盖清理/精确金额、小时与每日区别、日期精度、known/unknown文本与零cap、strict flags、RPC请求与凭证身份/HTTP失败、continuous提醒重武装、Widget与归档。未执行XCTest、xcodebuild或模拟器；root集中执行完整测试与unsigned App/Widgets/Watch构建。

没有真实Access Token或实际设备实验，上游text fixtures也是二手契约线索；尚需真实RPC兼容、当前plan/text、token失效/重配、两账号隔离、iCloud凭证到Watch、手机离线直连、实际通知和组件视觉验收。整票保持implemented-awaiting-validation。
