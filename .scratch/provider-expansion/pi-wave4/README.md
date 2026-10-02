# 第四批 Pi 回归

新增接入按冻结代码快照独立运行，provider `cch`、model `glm-5.3`；不访问真实账号/凭证，不运行 Xcode/模拟器。实际运行目录 `/tmp/tokenpulse-wave4-pi`。报告只代表其中列明的实际检查和静态审查。

- [01 OpenAI Legacy](01-openai-legacy.md)：已完成。普通有效金额/类型/请求/缓存范围未发现问题；报告指出 41 位有效数字的合成余额超出 Foundation Decimal 尾数精度会舍入。本轮保留既有数值模型，记录限制，不宣称已修复。详细处理见 [triage.json](triage.json)。
- [02 Alibaba Token Plan](02-alibaba-token-plan.md)：已完成，无可复现问题；root 另行发现并修复 Widget 共享类型遗漏。
- [03 Google 原生 OAuth](03-google-oauth.md)：已完成；有限 userinfo 重试与活动请求取消提示已修复（5c3e5e6），12 项实际 XCTest 通过。未采纳未文档化的 client ID 前缀约束。
- [04 Gemini](04-gemini.md)：已完成，无可复现问题。
- [05 Antigravity](05-antigravity.md)：已完成；项目输入校验与空标题处理已修复（1a7716f），实际回归通过。
- [06 Kiro](06-kiro.md)：已完成；Widget 编译问题已独立修复，credits 同到期处理及未知到期文案已修复，29 项实际 XCTest 通过；官方 ARN 映射保持。
- [07 Nous vault](07-nous-vault.md)：已完成，安全不变量复现通过；不可再续期秘密清理已补，23 项 Nous 实际 XCTest 通过。
- [08 Nous quota/login](08-nous-quota-login.md)：已完成；风控分类、身份 GET 有限重试及已消费授权码防重放均已修复并通过实际 XCTest。Watch 漂移静态推断漏掉查询前的账号绑定校验，未按缺陷采纳。

- [09 JetBrains protocol](09-jetbrains-protocol.md)：已完成；报告的续期期限问题已由统一mint处理修复，保留官方非正sentinel默认行为。
- [10 JetBrains lifecycle](10-jetbrains-lifecycle.md)：已完成；生产代码独立场景未发现可复现缺陷。

日期更正：05 原报告误写 2026-10-05、06 误写 2025-10-03；两组真实冻结/运行日期均为 2026-10-03，以各任务 snapshot-info.json/status.json 为准。报告原文保留，不能采用其错误日期。

各任务原始状态以运行目录 status.json 和 JSON events 为准，CLI exit 0 不单独作为成功依据。完整 XCTest 由 root 串行运行，Pi 没有代为执行。

## 最终验证

10组均完成，真实运行元数据见[reports.json](reports.json)。源码379d5dd通过773项完整XCTest（0失败）和unsigned App/Watch/两端Widgets构建；这两个完整验证由root运行，Pi没有运行Xcode。采用项已修复；未采纳建议、误报、更正和Decimal表示范围限制保留于[triage.json](triage.json)。上一批10组回归另存pi-regression，不重复计成本批。
