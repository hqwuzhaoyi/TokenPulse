# Hugging Face ZeroGPU 时间额度

新增 `.huggingFace`，用户明确配置自己的 User Token，经既有 Keychain envelope、SHA-256(provider,token)身份绑定、账号配置/可选iCloud同步、本机保存/删除，iPhone/Watch分别直连 GET `https://huggingface.co/api/spaces/zero-gpu/quota`。只发Bearer/Accept JSON，无CLI、Mac、代理；不查询whoami、Inference Providers usage或钱包。

官方 huggingface/huggingface_hub commit `c31df8646537edfdb8a561a11c87551b83d6d53b` 的[HfApi.get_zero_gpu_quota](https://github.com/huggingface/huggingface_hub/blob/c31df8646537edfdb8a561a11c87551b83d6d53b/src/huggingface_hub/hf_api.py)确认此只读endpoint及权限：fine-grained Token需要 `Billing > Read billing usage and payment method status`，OAuth需 `read-billing` scope。[ZeroGpuQuota类型](https://github.com/huggingface/huggingface_hub/blob/c31df8646537edfdb8a561a11c87551b83d6d53b/src/huggingface_hub/_space_api.py)明确 base是总GPU秒、current是剩余GPU秒、resetsAt可为null（未使用），overquotaUsed是另一付费GPU消耗。界面凭证标签提示账单读取权限，但这次功能仍只查询ZeroGPU，权限名不等于包含推理账单功能。

兼容固定[Pulse文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/hugging-face.md)记录的ISO或epoch秒reset；当前官方SDK仅展示ISO日期路线，numeric兼容仍需实际账号确认。base>0和非负current都实际提供才产生稳定huggingFace.zeroGPU窗口，used=max(0,base-current)/base。零/缺失分母、缺失剩余不补零或画假日窗口；JSON Bool/string不冒充数字。只有服务返回reset才保存边界，null/缺失无推断时间，不强制24小时周期、无余额/货币提醒、无计划价格或token映射。overquotaUsed不当钱包或擅自启用超额付费能力。

Widget、卡片、详情、Watch与演示均以GPU秒或GPU s标明数量，不称模型token。余额能力为none，适用quota告警与已报告reset沿既有规则；无reset不预排，失败保留同身份旧观测与时间，换token清旧缓存/提醒绑定。

图标为Lobe Icons commit `79b551cf26aab9ea4ac701fb807160950a5b860f` 的 `packages/static-svg/icons/huggingface.svg`（官方Hub SDK仓库未提供可重用SVG标记），MIT/版权/固定路径记录在ProviderIconNotices，black template+vector preservation+明确尺寸。

2026-10-02静态验证：全部App Swift6 iOS module emit与四个新增provider的完整XCTest文件semantic typecheck通过（共26个测试方法，另有3个day precision测试），PBX lint/diff与四套资产metadata检查通过。HF六个合成方法覆盖GPU秒/reset/null/秒尺度、非正/缺失/Bool边界、单一只读请求/权限标签/失败、quota提醒与不误触发钱包/假reset、Widget/归档、本机两账号隔离/失败保留/持久化/删除。没有执行XCTest、xcodebuild或启动模拟器，完整unsigned App/Widgets/Watch构建和测试执行由root串行验证。

没有实际Token或账号/设备验收，当前权限、服务响应数值/reset、真实ZeroGPU使用与恢复、撤销/换Token、iCloud凭证到达、物理Watch手机离线直连、实际提醒与视觉仍未验证。整票保持implemented-awaiting-validation，源代码与合成测试不是实际接入证明。
