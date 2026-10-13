# Notion AI 工作区额度

用户在账号专用临时 WK 容器登录 Notion，只捕获 notion.com/app.notion.com/www.notion.com 的 token_v2，并检查 API 路径与有效期。旧 notion.so Cookie 不跨域转发。getSpaces 只读取当前会话可见工作区的 ID、名称、套餐和用户身份；不读取文档内容、Custom Agents 或 Workers。多个候选工作区（含免费）全部显示给用户选择，不自动选第一个付费工作区。凭证包含 workspaceID 和 remote user ID，参与提供商/账号 UUID/origin/实际 Cookie 指纹；工作区 ID 同时进入缓存窗口 ID，同步/替换会话不混用工作区。

每次设备刷新先验证 getSpaces 中仍存在所选工作区及同一用户，再 POST app.notion.com/api/v3/getCreditRateLimitStatus，仅传该 spaceId。Cookie、Origin 和 Referer 固定，无自动 Cookie jar、无重定向；Watch 获得同一配置/凭证后直接请求。不适用套餐 status=not_applicable 是成功的明确空额度状态，不标作登录失败/网络失败；未提供指标保持缺失，已知计数用 exactCounts 保存，不补零或强求百分比。

滚动窗口长度仅从响应 window token 解析，当前6h显示6小时，不改成5小时；resetsInSeconds 相对采集时间、billingPeriodWindow.periodEndMs 按明确毫秒读取。官方说明账期窗口为monthly，使用monthly身份但不合成30天时间。计数是基础AI额度内部单位，不当USD钱包或Premium/Custom Agents购买的Notion credits；per-user计数不宣称是整个工作区所有成员的共享用量。

[官方 usage allowance](https://www.notion.com/help/manage-your-usage-allowance-for-notion-ai) 证实Business/Enterprise的6小时和monthly allowance、与购买Notion credits及Custom Agents/Workers的区分。[固定Pulse契约](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/notion-ai.md) 提供私有getSpaces/getCreditRateLimitStatus和token_v2线索；官方产品文档不保证内部API的未来兼容。官方SDK仓库未发现合适SVG，使用固定Lobe Icons notion.svg（MIT），图标在asset catalog并映射到所有设备。

6个NotionAIProviderTests验证完整workspace choices/独立指纹、指定查询与Header、同周期Decimal/部分计数/日期、不适用套餐状态、异常用户/已移除工作区、旧域cookie和元数据篡改。当前用户调整的“实现且图标存在”验收已完成。parse/PBX与小模块语义检查已做，root统一执行运行测试及资源构建；未取得真实账号/设备/iCloud证据，不作真实验证声明。
