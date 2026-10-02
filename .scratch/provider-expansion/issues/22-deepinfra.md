# 22: DeepInfra 钱包与支出上限

**Status:** implemented-awaiting-real-validation

**Type:** integration

**What to build:** 输入 Key 后查看可用美元余额和服务实际配置的支出上限。

**Blocked by:** None (can start immediately)

## Acceptance criteria

- [ ] 核对账本正负号及待结算支出规则，验证预付余额与欠费场景，使用十进制金额。
- [ ] 余额与支出限额分别展示；没有正上限时只显示余额，不把停用标志转成 100% 用量。
- [ ] 从添加入口到安全凭证保存、账号管理、同步和删除完整可用；同一提供商多个账号隔离，iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别向服务端查询；Watch 获得配置和凭证后不依赖手机、Mac 或新增代查服务在线。
- [ ] 卡片、详情、iPhone 小组件、Watch 和演示数据覆盖新增计量方式；金额、积分、token、时长和预算单位不混淆。
- [ ] 适用的额度告警、重置或低余额提醒接入既有规则；不适用的设置不开放；失败保留旧数据与采集时间，缺失值不补零。
- [ ] 覆盖请求契约、字段边界、账号与站点隔离、成功与失败及适用提醒行为的测试；运行相关测试和 unsigned TokenPulse target 完整构建。
- [ ] 新增图标优先官方资源或既有 Lobe Icons，固定来源版本、记录版权许可，并验证矢量与模板渲染覆盖 App、Widgets 和 Watch。
- [ ] 保存真实登录、查询及 Watch 独立刷新验收结论；无账号凭证或设备时保留未验收项，不将合成响应测试当作真实接入证明。
- [ ] 更新支持范围、登录方式、字段含义和验证边界；研究来源固定版本，发现契约不可用时记录具体阻塞。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/deepinfra.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。

## Implementation record (2026-10-02)

已实现倒置Decimal账本/待支出、纯钱包或正上限混合额度、独立提醒/Widget/Watch/演示/APIKey安全流程和licensed icon。6个DeepInfraProviderTests覆盖请求、类型/零/欠费/限额、恢复隔离及删除。完整App iOS Swift6 module/测试静态typecheck和PBX/diff检查通过。XCTest执行、unsigned资源构建与真实账号/设备/iCloud未验收，清单保持开放。详见 `docs/deepinfra-integration.md`。
