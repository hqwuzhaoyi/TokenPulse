# 64: Kiro 官方 portal 独立额度查询

**Status:** done

**Type:** integration（原 feasibility，经新增官方协议证据转为实现）

**What to build:** iPhone 专属网页登录个人 Kiro 账号，iPhone/Watch 原生 HTTPS 获取与续期额度；不运行 CLI ACP。

**Blocked by:** 无当前实施阻塞。真实账号观察未进行；它不再是用户当前验收的关闭门槛。

## Acceptance criteria

- [x] 固定 Pulse 证据与官方新证据分开：ACP 本地接口不被当成云端 API；新增官方 portal release/hash、认证/额度/续期 wire 与 schema 已建立来源。
- [x] 完成 auth/query、严格有界 CBOR、scope/expiry/401 处理、账号客户端与持久化入口、App/Watch/widget/demo/register/PBX 集成。
- [x] Kiro 独立图标存在、固定来源/许可已记录、模板向量资产与 mapping 已落实。
- [x] 用户最新验收 gate：实现和图标存在。缺少真实账号与实机观察不再是研究硬门槛，也不被伪记为观察成功。
- [x] 非周期试用/bonus/额外 credits 仅作到期 allowance；monthly credits 与返回 reset 精确对应；未知/缺失不补0、不从套餐价格推算额度、不把 credits 当钱包。
- [x] 凭证本地账号+真实服务个人 scope 绑定；Cookie轮换不误判换账号；逐cookie expiry更新后可独立续期。只使用本账号专属WK会话，不读真实用户凭证或其它浏览器。
- [x] 脱敏夹具：23项本地实际 XCTest 0 failures；额外提交真实 AccountQuotaClient/QuotaMonitor 续期/恢复回归供主线程跑。
- [x] 不引入 Mac 常驻进程、CLIProxyAPI 代查或设备外推送；不变更设备直连 ADR。
- [x] root已确认原24项iOS XCTest及77providers unsigned app/widgets/Watch构建通过；Pi06新增小补丁由root重跑，不把小模块通过伪当全目标通过。

## Evidence

[协议和研究报告](../research/64-kiro.md)、[接入实现说明](../../../docs/kiro-provider-integration.md)。官方 portal release `7641e207feab0c25` 的 main/vendor SHA-256 已锁定并实际重取校验；匿名 GetToken 空 map POST 被服务识别为 CBOR并返回缺少CSRF的HTTP400，不证明账号额度读取成功。

## Validation facts

生产小 module Swift6 语义检查通过，macOS命令行实际23 tests/0 failures，日志 `/tmp/tokenpulse-kiro-small/test.log`。第24项 iOS完整账号客户端/Monitor链路、unsigned全目标由主线程统一执行。

未完成历史真实验收：没有登录外部真实账号，没有与官方实际额度页对照，没有iPhone/Watch实机跨到期或撤销观察；这些事实保留，但按用户最新验收口径不作为关闭阻塞。当前支持默认production portal的Google/GitHub/BuilderID个人会话，企业/其它区域不偷偷兜底。

## Pi06后续 — 2026-10-03

root已确认原24项iOS XCTest与77providers unsigned全目标构建通过。F2接受并修复为同resource/expiry无计数cohort，不冒单packID、不相加；F3保留ACTIVE quota并补未知到期文案；F4与锁定官方Md/profile常量一致，不采纳盲改。5项新回归已加入，生产小module真实macOS XCTest28项0fail（含cohort实际NotificationPlanner不告警），iOS新补丁留root统一执行。详见研究报告末尾。F1已有ca87270修复，未重复改widget。

## Root 最终集成验证 — 2026-10-03

源码 `379d5dd` 已通过773项完整XCTest（0失败）及unsigned App/Watch/两端Widgets构建，本票图标映射存在。此前工作者“未跑完整Xcode”的描述是其交付时事实；本段记录root后续实际验证。当前实现+图标验收完成，真实账号/物理设备观察仍未伪勾。详见[第四批结果](../wave4-progress.md)与[Pi处理](../pi-wave4/README.md)。
