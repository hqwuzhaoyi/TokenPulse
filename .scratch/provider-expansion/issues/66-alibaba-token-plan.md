# 66: Alibaba Token Plan 原生 HTTPS 接入

**Status:** done

**Type:** integration

**What to build:** 无 bl CLI 的 AK/SK console token 生成、明确地区/站点绑定和 Personal Token Plan 查询。

**Blocked by:** 无。本票按用户最新“实际实现+图标存在”验收；真实账号/实体设备观察不作关票门槛。

## Acceptance criteria

- [x] Token Plan 单独注册，与 Coding Plan 及 sk-sp 推理 Key 区分；App/Watch 本设备直接 HTTPS，不运行 CLI/代查服务。
- [x] 固定官方 modelstudioai/cli 证据：ACS3 空 body 签名生成 cliAccessToken，随后个人 usage gateway；NotLogined 最多重取/重读一次。
- [x] AK:SK secure composite、北京/新加坡与国内/国际站均显式选择；四组固定 host/action，拒绝重定向。凭证和目标进入实际 identity，账号配置/缓存/提醒隔离。
- [x] 正确解析官方 DataV2/data envelope、已用比例 [0,1] 和毫秒 reset，仅 5h/week；缺失未知、无月窗/Team预算/钱包假值。
- [x] 认证 UI、展示、Watch/widget 注册、PBX、演示、独立窗口提醒及相关回归源码完成。
- [x] 图标存在：复用 ProviderAlibabaCloud vector/template SVG；固定源/许可 Notices 保留并注明复用。
- [x] 实际 Swift6 Foundation 语义检查及 synthetic 离线请求链通过；签名 golden 由固定官方 Node 源码独立生成。完整 XCTest/unsigned build 由 root 统一执行。
- [x] 未读取真实凭证、未创建外部真实登录、不保存 synthetic 以外的测试凭证。

## Evidence — 2026-10-03

[专属实现说明](../../../docs/alibaba-token-plan-integration.md)记录生产接口、四地区/站点组合、数据语义、签名 golden 来源及验证边界。[固定官方研究](../research/66-alibaba-token-plan.md)保留原调查证据并更新当前验收。

生产实现 AlibabaTokenPlanProvider.swift；回归 AlibabaTokenPlanProviderTests.swift 覆盖签名、form 请求、DataV2/ratio/reset、retry/permission、scope与失败换绑、配置兼容、演示/widget/图标与提醒。本次 isolated Swift6 typecheck 和合成离线 probe 实际通过，未启动 Xcode/模拟器；完整 XCTest及多 target build 由 root 集中验证。

未进行真实账号 RAM 权限/TTL、双端 token 互不撤销、真实面板数值、iCloud 和实体 Watch 观察。不宣称这些观察已通过；它们按当前用户验收标准不阻塞本票 done。长期 AK/SK 被撤销需用户重新配置；STS自动续期、switchAgent团队身份和月额度不在本实现范围。
