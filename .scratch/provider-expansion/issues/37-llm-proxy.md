# 37: LLM API Key Proxy 分组额度

**Status:** done

**Type:** integration

**What to build:** 配置服务器地址和 Key 后查看每个上游的各配额组。

**Blocked by:** 12 — New API 自定义地址与余额查询

## 当前验收标准（用户于2026-10-02调整）

- [x] 完成本票接入实现，并确认provider图标存在。真实账号/设备验证不再作为关票条件。

下方保留原实现要求与历史验证清单；未勾选不代表当前额外关票门槛。

## 原 Acceptance criteria（历史）

- [ ] 复用按账号绑定的自定义地址；缓存、凭证与提醒不得在服务器或 Key 间复用。
- [ ] 逐组展示剩余比例与实际重置时间，不将所有上游的最小剩余值合成为总额度。
- [ ] 从添加入口到安全凭证保存、账号管理、同步和删除完整可用；同一提供商多个账号隔离，iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别向服务端查询；Watch 获得配置和凭证后不依赖手机、Mac 或新增代查服务在线。
- [ ] 卡片、详情、iPhone 小组件、Watch 和演示数据覆盖新增计量方式；金额、积分、token、时长和预算单位不混淆。
- [ ] 适用的额度告警、重置或低余额提醒接入既有规则；不适用的设置不开放；失败保留旧数据与采集时间，缺失值不补零。
- [ ] 覆盖请求契约、字段边界、账号与站点隔离、成功与失败及适用提醒行为的测试；运行相关测试和 unsigned TokenPulse target 完整构建。
- [ ] 新增图标优先官方资源或既有 Lobe Icons，固定来源版本、记录版权许可，并验证矢量与模板渲染覆盖 App、Widgets 和 Watch。
- [ ] 保存真实登录、查询及 Watch 独立刷新验收结论；无账号凭证或设备时保留未验收项，不将合成响应测试当作真实接入证明。
- [ ] 更新支持范围、登录方式、字段含义和验证边界；研究来源固定版本，发现契约不可用时记录具体阻塞。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/llm-proxy.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。


## 2026-10-02 wave3 evidence

`.llmProxy` 完整gateway账号地址/Key/scope生命周期、GET quota-stats只读、逐上游配额组对象/列表解析、实际reset/局部畸形/不取全局min、App/Watch/widget/demo及适用提醒注册已实现。SF Symbols puzzlepiece.extension.fill图标存在，来源许可在Notices；[专属docs](../../../docs/llm-proxy-provider-integration.md)固定主源和缓存观察边界。新增有效回归、小模块Swift6语义、parse/PBX/diff检查通过。root统一实际target测试/构建，无真实Key/部署/设备/iCloud验证，按当前AC不阻塞done，旧清单未验证项不伪称通过。
