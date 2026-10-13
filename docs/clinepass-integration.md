# ClinePass 接入

固定查询 api.cline.bot 的 plan/usage-limits，使用用户配置的 Bearer API Key。5 小时、每周与每月窗口采用明确字段，百分比 0.5 保持 0.5%，重复同类窗口视为无法读取，缺失值不补零。凭证存储、多账号、双端独立刷新、演示、额度和重置提醒沿用公共路径。

契约参考 [Pulse 397c8fc4](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/clinepass.md)，该来源也是合成响应，不能替代真实账号验收。生产客户端测试覆盖请求及错误映射、窗口顺序/单位/缺失/重复、Widget 与提醒。

静态与集成验证分别由 root 记录；没有读取真实密钥或执行真实账号请求，物理 Watch 与云端到达仍待验收。
