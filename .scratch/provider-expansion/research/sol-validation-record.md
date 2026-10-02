# 63–69 研究验证记录

日期：2026-10-02。仅验证公开证据与报告一致性，不是实际 provider 接入验收。

- agent-reach doctor 已运行，GitHub CLI、公开网页读取可用；Exa 一次成功后出现 429，后续只查官方文档，没有配置新 key 或平台登录。
- 固定 Pulse commit `397c8fc4f1bd52180a452d2f3f0c099def97cf69` 的 8 个客户端文件已逐个读取，包括 Kiro transport 与 parser。
- Gemini、Bailian、Hermes 的官方源码分别固定为报告中列出的 commits。`public-source-lock.json` 共 20 个文件，SHA-256 均已实际复取匹配。首轮 18 成功、Hermes 两个 raw CDN 请求被限流；使用 GitHub contents API 验证存在，脚本补充 429 fallback 后单独复取 Hermes 4 个文件，全部匹配。没有将网络失败报成内容不存在。
- JetBrains 公开 Account OpenAPI 实际 GET 成功，SHA-256 与 68 报告相同；检查 13 个 paths 与 schema，没有 AI quota/credits 契约。这个结论仅针对该公开 spec。
- 7 份报告的 ADR 相对链接及 7 票的报告链接已检查。第 3 项真实纵向验收、第 6 项通过后实施票均保留未勾选；63 和 67 的独立授权验证条件也保留未勾选。
- `git diff --check` 通过。没有修改 app/source/asset/target、中央 manifest 或 README 索引，未运行 app build；本次改动为研究与票据，不用构建成功冒充账号接入证明。
- 没有读取 Gemini/Kiro/Hermes/JetBrains/Antigravity 用户凭证、IDE 额度文件或系统 Keychain，没有发起外部登录、token grant、推理、套餐修改、充值或账号操作。没有真实账号、iPhone/Watch 设备验收证据。

可重复的公开源码审计：

```sh
python3 .scratch/provider-expansion/research/verify-public-evidence.py
# 单独复核某仓库
python3 .scratch/provider-expansion/research/verify-public-evidence.py --repo NousResearch/hermes-agent
```

脚本仅 GET 锁定 public paths，raw CDN 限流时调用 `gh api` 读取相同固定版本的 public content；只输出文件名/哈希是否一致和异常类别，不打印源码常量或 credential。它不调用账户 API、不读取 provider credential、不发起登录。各报告中的真实账号验证步骤均为**未执行的后续步骤**；不得以本脚本通过声称 provider 或双端授权验证通过。
