# Aixy 托管预算

固定 GET https://api.aixy-gateway.com/v1/usage，输入项目 Key。逐条验证 applies_to 中的 Key 与项目身份，不显示其他账户预算；硬预算用 settled+reserved，监控预算用 recorded spend，二者不当成 API 钱包。

一手公开 [OpenAPI](https://docs.aixy-gateway.com/openapi.json) 和 [Usage](https://docs.aixy-gateway.com/observe/usage) 于 2026-10-02 核对，明确多个重叠预算应分别保留，null意味着未提供。本实现保留所有适用预算及服务给出的目标名称/共享标识，修正旧 Pulse 每周期只选一个的丢数据行为；未知用量仍保留已知上限，不造零。lifetime 不产生 reset。金额使用 Decimal，提醒与同源请求沿公共路径。

不查询推理、不推算发票、不把预留额称为已结算费用。服务建议刷新不快于一分钟；应用后台由系统调度，手动刷新需注意提供商限流。官方资料和已固定Lobe tree未找到可用品牌SVG，采用原生network通用图形。

测试覆盖重叠预算、Key范围、预留语义、未知与零、生命周期/重复ID、请求与单位。真实Key、物理Watch/iCloud仍待验收。
