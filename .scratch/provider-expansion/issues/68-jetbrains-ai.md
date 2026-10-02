# 68: JetBrains AI 个人 license 原生接入

**Status:** done

**Type:** integration（由feasibility在官方发布包补证后转实施）

**What to build:** 用户主动导入官方Central login export，原生HTTPS完成JBA refresh、license签发、额度与refill查询；iPhone/Watch分别持有独立grant。

**Blocked by:** 无当前代码协议阻塞。真实账号观察未进行，不作为用户最新关闭门槛。

## Acceptance criteria

- [x] 固定Pulse XML只作历史线索，不将文件快照当live；官方Central1.11.0 artifact/hash及ELF静态工具建立完整HTTPS auth/query/fallback契约，不运行binary、不读真实凭证。
- [x] TokenTransfer v1 production personal license导入、原发行public client兼容refresh、Register→ProvideAccess→quota/refill、401及过期fallback全链路实现；无CLI常驻、代理或猜云端URL。
- [x] per-device vault/coordinator及真实save边界：新RT先checkpoint，unknown结果不重放；fresh grant先candidate、scope/quota通过后receipt，由用户实际保存做baseline CAS接管active；失败/取消/迟到/新登录不破坏旧Ready。
- [x] 当前设备所有账号共用的spent RT摘要ledger跨account UUID保留，取消/删除不解除重放禁令；resume lease与activationPending封存防旧页cleanup/晚结果覆盖；不声称跨离线设备global同family锁。
- [x] current=used及100000→AIcredits缩放有固定CLI展示运算证据；tariff/top-up分段不叠加aggregate；Decimal精确计数、未知不补0、不作USD钱包、不把until当reset。
- [x] App入口/Watch独立SecureField/本地凭证路由、widget/demo/register/PBX集成及图标存在，来源/许可取舍写入Notices。PBX使用主线程独立A442登记，保留XKiro。
- [x] 当前用户验收gate：实现+图标存在。没有假勾真实账号/Watch对照；未观察事实保留。
- [x] 实际31项macOS小module XCTest 0fail；主线程曾实际跑JetBrains31+Nous23组合54/0fail。iOS真实AccountClient/Monitor用例沿真实Widget构造。
- [ ] 最终TTL/文档版本的全量XCTest、unsigned所有目标与Pi09/10结果由主线程更新最终validation-record；这里不抢写其最终结论。

## Evidence and implementation

[完整研究与认证闭合](../research/68-jetbrains-ai.md)、[只读静态工具](../research/68-static-tools/README.md)、[原生实现说明](../../../docs/jetbrains-provider-integration.md)。固定archive SHA256为34c7e468870fdc57d60261034760f72b85c4a9e3f2dbfb9dec006b413f62ae4c；binary SHA256为07d76becc367762e31f59ecbf744a967ce5ef1cbf395b4fc05835e6fb244a042。没有将dirty源码revision当可重复源码树。

用户需自行登录官方Central并选择license、主动复制export；每设备分别新登录的授权，TokenPulse不替用户运行Central或读取其凭证。手机表单保存前candidate不会成为active，未保存候选一小时内可激活、超期访问清除且spent marker保留。

历史真实验收未执行：未建立真实外部登录、没有与实际credit页面/IDE对照、没有实体Watch跨token expiry/revoke观察。默认24h仅沿用官方CLI客户端策略，不称服务端精确期限。企业workspace/shared pool/Central Server/staging不在本实施范围。

## Root 最终集成验证 — 2026-10-03

源码 `379d5dd` 已通过773项完整XCTest（0失败）及unsigned App/Watch/两端Widgets构建，本票图标映射存在。此前工作者“未跑完整Xcode”的描述是其交付时事实；本段记录root后续实际验证。当前实现+图标验收完成，真实账号/物理设备观察仍未伪勾。详见[第四批结果](../wave4-progress.md)与[Pi处理](../pi-wave4/README.md)。
