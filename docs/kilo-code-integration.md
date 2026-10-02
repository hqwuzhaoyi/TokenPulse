# Kilo Code 钱包与 Pass

添加 Kilo Code 账号时粘贴个人 API Key。TokenPulse 不读取 Mac/CLI 登录文件，不设置组织 header，也不提供未经实现的组织切换。凭证安全存储、多个账号 UUID 隔离、iCloud/本地恢复、删除和双端独立刷新沿用既有流程。

单次 Bearer GET 请求 `https://app.kilo.ai/api/trpc/user.getCreditBlocks,kiloPass.getState`，query 为 `batch=1` 与两项 null input；Key 不进入 URL。支持索引数组/对象和 `result.data.json` 包装。任何子请求错误都使本次刷新失败：UNAUTHORIZED/FORBIDDEN 为凭证无效，其余错误为不可读响应，旧数据与采集时间保留；缺少子回复不静默视为未订阅。

钱包读取 `totalBalance_mUsd`，缺失时在所有 block 均提供余额的前提下精确求和，除以一百万转成 USD。不以 block 起始金额计算套餐额度，不将 block expiry 当重置。负余额不当可用钱包；明确零有效。

Pass 使用已报告的 `currentPeriodUsageUsd`、基础和奖励 USD；缺失奖励为零，显式无效奖励报错。正总额度才产生百分比，Decimal 精确用量/剩余/总额保存于 exactCounts。`nextBillingAt` 是 Pass 重置，周期长度未给出时保持 other。subscription=null 时仅显示钱包。卡片、小组件、详情与 Watch 同时显示钱包和 Pass，两个提醒开关独立；钱包低余额与 Pass 额度/实际重置各用相应规则。

契约参考 [Pulse 固定版本](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/kilo-code.md) 与 [Kilo Pass 官方介绍](https://kilo.ai/pricing/kilo-pass)。tRPC 私有响应仍属参考线索，真实账号待验收。图标采用固定官方 Kilo-Org/kilocode 的 `packages/kilo-docs/public/img/kilo-v1.svg`，黑色模板填充/明确尺寸，完整 MIT 许可与版权见 ProviderIconNotices.txt。

KiloCodeProviderTests 覆盖微美元精确转换、Pass 合并/缺失 bonus、无订阅/零余额、tRPC 两种形状/包装/子错误、不可读数值、请求参数、App/widget 两类窗口和多账号失败恢复/删除。完整 iOS Swift6 App module 与相关 XCTest 静态 typecheck、PBX 与 diff 检查通过。真实 Key、失效、iCloud/Watch独立刷新和 unsigned 全目标资源构建、XCTest 执行均未验收；没有使用真实凭证。
