# 第四批 Pi 回归

新增接入按冻结代码快照独立运行，provider `cch`、model `glm-5.3`；不访问真实账号/凭证，不运行 Xcode/模拟器。实际运行目录 `/tmp/tokenpulse-wave4-pi`。报告只代表其中列明的实际检查和静态审查。

- [01 OpenAI Legacy](01-openai-legacy.md)：已完成。普通有效金额/类型/请求/缓存范围未发现问题；报告指出 41 位有效数字的合成余额超出 Foundation Decimal 尾数精度会舍入。本轮保留既有数值模型，记录限制，不宣称已修复。详细处理见 [triage.json](triage.json)。
- [02 Alibaba Token Plan](02-alibaba-token-plan.md)：已完成，无可复现问题；root 另行发现并修复 Widget 共享类型遗漏。
- [03 Google 原生 OAuth](03-google-oauth.md)：已完成；有限 userinfo 重试与活动请求取消提示已修复（5c3e5e6），12 项实际 XCTest 通过。未采纳未文档化的 client ID 前缀约束。
- [04 Gemini](04-gemini.md)：已完成，无可复现问题。
- 05 Antigravity、06 Kiro：运行中。

各任务原始状态以运行目录 status.json 和 JSON events 为准，CLI exit 0 不单独作为成功依据。完整 XCTest 由 root 串行运行，Pi 没有代为执行。
