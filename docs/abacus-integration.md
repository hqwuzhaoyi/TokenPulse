# Abacus AI compute points

iPhone 通过账号专用临时 WK 会话登录 Abacus，捕获候选 sessionid/session_id/session_token/auth_token/access_token，仅匹配 abacus.ai/apps.abacus.ai 与 API 路径、有效期。候选名来自固定二手契约，尚未实账号核验。不会读取 Safari、其他账号、第三方应用的会话。登录完成后先实际验证 points 查询再保存；会话绑定提供商、账号 UUID、origin 与指纹，凭证沿用 Keychain/同步/删除，Watch 获得配置及凭证后直接请求。

GET apps.abacus.ai/api/_getOrganizationComputePoints 是必需读数；POST /api/_getBillingInfo {} 仅用于账期日期与套餐名，失败不抹去 points。Cookie 放在 header；无自动 cookie jar、无重定向。401/403/3xx 或明确 session/login 错误为凭证失效，其余错误保留对应失败语义。

同一响应提供 totalComputePoints 和 computePointsLeft 才形成额度。金额/积分不经 Double 中转，exactCounts 保存原计数，推导用量检查逆运算避免静默精度丢失。compute points 非货币；更多剩余积分按零用量，零/负剩余明确耗尽，不构造美元钱包。只使用 nextBillingDate 的实际日期，不把账期猜成30天；缺少 billing 则无重置/套餐名。

来源：[Pulse 固定版本](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/abacus.md) 提供私有接口/候选 Cookie 线索；[官方 Billing](https://abacus.ai/help/chatllm-ai-super-assistant/faqs/billing) 证明平台按 compute credits 计量，但不证明这些内部接口及 Cookie 名。原生 SF Symbol square.grid.3x3.fill 为通用标识，存在于 App/Watch/widget 的提供商图标映射，不冒充官方 logo。

5个 AbacusProviderTests 覆盖单位/精确计数/零/缺失/业务错误、可选 billing、Cookie domain/expiry、账号绑定及请求。用户2026-10-02调整的“实现且图标存在”验收已满足；真实登录、Watch/iCloud设备验证未执行，不当作已取得证据。XCTest与完整资源构建由root统一运行。
