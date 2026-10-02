# 25: Hugging Face ZeroGPU 额度

**Status:** done

**Type:** integration

**What to build:** 输入用户 token 后查看 ZeroGPU 已用与剩余 GPU 时长。

**Blocked by:** None (can start immediately)

## 当前验收标准（用户于2026-10-02调整）

- [x] 图标存在：`ProviderHuggingFace`，映射及资源已核对，见[图标验收记录](../icon-acceptance.md)。本票已关闭。

以下原检查表保留为历史实现/验证记录，不再作为本票关票条件；未勾选项不改写为已实测。

## 原 Acceptance criteria（历史）

- [x] 以秒或可读时长显示 GPU 配额，不称为模型 token 或 API 钱包。
- [x] 使用接口返回的重置时间，额度为零或未提供时不伪造日窗口；不包含 Inference Providers 账单。
- [ ] 从添加入口到安全凭证保存、账号管理、同步和删除完整可用；同一提供商多个账号隔离，iCloud 关闭时本机可用。
- [ ] iPhone 与 Watch 分别向服务端查询；Watch 获得配置和凭证后不依赖手机、Mac 或新增代查服务在线。
- [ ] 卡片、详情、iPhone 小组件、Watch 和演示数据覆盖新增计量方式；金额、积分、token、时长和预算单位不混淆。
- [ ] 适用的额度告警、重置或低余额提醒接入既有规则；不适用的设置不开放；失败保留旧数据与采集时间，缺失值不补零。
- [ ] 覆盖请求契约、字段边界、账号与站点隔离、成功与失败及适用提醒行为的测试；运行相关测试和 unsigned TokenPulse target 完整构建。
- [ ] 新增图标优先官方资源或既有 Lobe Icons，固定来源版本、记录版权许可，并验证矢量与模板渲染覆盖 App、Widgets 和 Watch。
- [ ] 保存真实登录、查询及 Watch 独立刷新验收结论；无账号凭证或设备时保留未验收项，不将合成响应测试当作真实接入证明。
- [x] 更新支持范围、登录方式、字段含义和验证边界；研究来源固定版本，发现契约不可用时记录具体阻塞。

## Evidence

参考 Pulse 固定版本的[接入说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/hugging-face.md)。上游实现与合成响应只作为线索，真实账号验收仍须执行。

## Implementation — 2026-10-02

已实现用户Token入口（提示账单读取权限）、身份绑定、安全保存/同步/删除、双端单一ZeroGPU GET、GPU秒计量与真实reset/null边界、Widget/演示/MIT图标；不请求Inference账单或钱包。官方SDK commit c31df8646537edfdb8a561a11c87551b83d6d53b补充一手schema与权限证据。

[完整范围/验证](../../../docs/hugging-face-provider-integration.md)。新增6个合成XCTest方法和全部App Swift6语义检查、完整四provider测试semantic typecheck、PBX/diff检查通过。无XCTest执行/xcodebuild/模拟器，无实际Token/物理iPhone/Watch/iCloud/提醒和完整目标构建验收，因此其余验收项保持未勾选，整票未完成。
