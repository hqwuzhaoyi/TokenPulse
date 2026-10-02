# 69: OpenAI API Legacy 钱包余额

**Status:** done

**Type:** integration（范围有限的 legacy 兼容）

**What to build:** 通过用户主动配置的 Key 请求旧 `credit_grants`，只显示实际返回的预付余额，不将组织消费统计当作余额。

**Blocked by:** 无实现阻塞；真实账号与设备行为未实测，不作为当前关票条件。

## 当前验收标准（用户于2026-10-03确认）

- [x] 完成本票接入实现，并确认 provider 图标存在。真实账号/设备验证不再作为关票条件。
- [x] 明确区分未文档化、未实测与已经废弃；本次未找到官方废弃声明，不宣称 legacy 路由通用兼容。

## 实施记录 — 2026-10-03

- [x] `.openAIAPI` 注册、Key envelope、安全保存/更换/删除与既有同步路径；新增与更换凭证页面提示旧接口兼容性因账号与 Key 而异。
- [x] 固定 HTTPS GET/Bearer 查询；请求不含 Key URL 参数，校验响应同源，403 权限不足与401凭证错误区分，404/限流/服务错误保留既有缓存。
- [x] `total_available` 数字直接解码 Decimal，零与负余额保留；缺失、null、Boolean、字符串或非有限数值失败，未提供明细保留 nil。
- [x] USD 语义来自固定 Pulse legacy contract；不由 Costs 推断币种/余额，不做 Costs probe/fallback，不把 total_used/total_granted 或 grant 到期生成比例与 reset。
- [x] 纯钱包 App/详情/Watch/Widget/低余额提醒及独立演示账号；新增 App+Watch 源码与 XCTest PBX 注册。
- [x] 复用已存在 `ProviderCodex` 的 OpenAI SVG 标记，补固定来源、MIT 许可和路径记录。
- [x] 七个合成回归测试覆盖精确金额、缺失/错误/Costs拒绝、请求与失败/no-probe、错误scope/credential、响应origin、账号隔离/失败缓存/重启/删除、Widget/demo/提醒。
- [x] Swift parse、PBX plist lint、git diff --check通过；小型实际 Foundation parser 可执行验证精度/零/负数/缺失/非法边界通过。
- [ ] 本次未执行真实账号、当前 Key 兼容矩阵、iPhone/Watch 真值或撤销实测；没有保存或读取真实 Key。
- [ ] 本分支未跑 Xcode/XCTest/模拟器，交 root 串行集成验证；上述合成测试不宣称真实路由可用。

## 来源与说明

固定 [Pulse source](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/OpenAIPlatformUsageService.swift) 与 [synthetic fixture](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Tests/PulseTests/Fixtures/openai-api-credit-grants.json)。上游明确 shape 为二手，不能用其旧 Key 注释保证所有账号兼容。

官方 [Costs reference](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs) 仅用于证明组织消费 API 的语义边界。完整边界与设备验证步骤见 [research](../research/69-openai-api.md) 和 [接入说明](../../../docs/openai-api-integration.md)。

## Root 最终集成验证 — 2026-10-03

源码 `379d5dd` 已通过773项完整XCTest（0失败）及unsigned App/Watch/两端Widgets构建，本票图标映射存在。此前工作者“未跑完整Xcode”的描述是其交付时事实；本段记录root后续实际验证。当前实现+图标验收完成，真实账号/物理设备观察仍未伪勾。详见[第四批结果](../wave4-progress.md)与[Pi处理](../pi-wave4/README.md)。
