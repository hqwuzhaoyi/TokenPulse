# Bifrost 虚拟 Key 预算

配置账号自己的网关地址和虚拟 Key；沿共享gateway规范化、Keychain同步、地址/Key/provider身份隔离、失败旧快照和删除路径。App和Watch各自GET `/api/governance/virtual-keys/quota`，认证使用 `x-bf-vk`，不是管理Key或模型推理；跨origin重定向拒绝。入口、设置更新、Watch详情、widget和隔离演示均已注册。

每个Key自身、provider_configs提供商及model_configs提供商+模型预算各一窗口，不求和也不以数组顺序作为身份。金额保留Decimal USD预算额度，正effective limit才绘制比例；它不是钱包。override_amount只在forever或cycles且remaining>0时增加上限；过期/未知override不提升预算。缺current_usage保留未知，不补0。停用Key显示“虚拟Key已停用”，正常Key没有正预算显示“未配置可读取预算”，均无虚构0%或钱包提示。

预算持续期保留原始名称，1M只归月度；日/周/季度/年不假装固定天数。主源证明sub-day Go duration无法calendar aligned，只有这些周期的last_reset+duration仍在未来时用于预计reset，过旧last_reset不投射到未来，24h及更长周期因响应缺owner alignment不推算。last_reset本身作为实际预算周期边界身份，可查询确认其变化；预计时间不是服务端确认恢复。百分比/实际周期和明确日期沿既有告警规则，所有池独立。rate_limits/per-model花费不混入美元预算，缺少对应真实分母不造额度。

主源：[maximhq/bifrost 8ffa1fbd handlers/governance.go](https://github.com/maximhq/bifrost/blob/8ffa1fbd27d1a33a55a05109b96fc2d2aab8805b/transports/bifrost-http/handlers/governance.go)确认只读self-service路由、x-bf-vk、is_active和多层预算；[tables/budget.go](https://github.com/maximhq/bifrost/blob/8ffa1fbd27d1a33a55a05109b96fc2d2aab8805b/framework/configstore/tables/budget.go)确认USD和HasActiveOverride/EffectiveMaxLimit、calendar semantics。参考[Pulse397c8fc4](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/bifrost.md)。新测试覆盖分层隔离、override有效/失效、过去时钟/日历不推算、停用与无预算、缺值和x-bf-vk请求契约；小模块Swift6语义与parse/PBX/diff检查通过，target测试/build由root统一。

图标使用已存在的SF Symbols `puzzlepiece.extension.fill`，Apple SDK通用网关图形。官方固定树仅有Bifrost raster品牌图，既有Lobe无适合的vector mark，未把位图当模板或假造商标；来源/许可说明在ProviderIconNotices.txt。没有真实凭证、部署、设备或iCloud验证，按当前“实现+图标存在”标准完成并保留历史未验证项。本分支不运行xcodebuild或模拟器。
