# 40: StepFun 套餐与网页登录

**Status:** implemented-awaiting-real-validation

**Type:** integration

**What to build:** 在 iPhone 完成 StepFun 网页登录，将账户会话同步后由 Watch 独立查询套餐。

**Blocked by:** None (can start immediately)

## Acceptance criteria

- [ ] 以本票建立最小可复用的按提供商和账号隔离的网页登录、Cookie 提取及重新登录路径；保留现有 Claude 行为。
- [ ] 区分国内与国际站；会话与设备标识相匹配，Token Plan 和 Coding Plan 分别解析；到期时间不当成重置。
- [ ] 网页登录使用按服务账号隔离的会话容器，只提取已核实的必要凭证；明确有效域名、过期处理、重新登录及删除清理，并验证双端使用会话的兼容性。
- [ ] 从添加入口到安全凭证保存、账号管理、同步和删除完整可用；同一提供商多个账号隔离，iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别向服务端查询；Watch 获得配置和凭证后不依赖手机、Mac 或新增代查服务在线。
- [ ] 卡片、详情、iPhone 小组件、Watch 和演示数据覆盖新增计量方式；金额、积分、token、时长和预算单位不混淆。
- [ ] 适用的额度告警、重置或低余额提醒接入既有规则；不适用的设置不开放；失败保留旧数据与采集时间，缺失值不补零。
- [x] 覆盖请求契约、字段边界、账号与站点隔离、成功与失败及适用提醒行为的测试；运行相关测试和 unsigned TokenPulse target 完整构建。
- [ ] 新增图标优先官方资源或既有 Lobe Icons，固定来源版本、记录版权许可，并验证矢量与模板渲染覆盖 App、Widgets 和 Watch。
- [ ] 保存真实登录、查询及 Watch 独立刷新验收结论；无账号凭证或设备时保留未验收项，不将合成响应测试当作真实接入证明。
- [ ] 更新支持范围、登录方式、字段含义和验证边界；研究来源固定版本，发现契约不可用时记录具体阻塞。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/stepfun.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。

## 集成验证（2026-10-02，root）

本轮完整 238 项 XCTest 全部通过，unsigned TokenPulse target 构建成功，覆盖 App、两端 Widgets 和 Watch；iPhone 模拟器演示卡片完成查看。分组提交时记录的“待中央构建/测试”已由本次结果补齐，详见[统一验证记录](../validation-record.md)。真实提供商登录/查询、物理 Watch 独立刷新和跨设备 iCloud 到达尚未验收，因此未标完成。
