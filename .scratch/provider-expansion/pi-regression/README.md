# Pi 批量回归

用户要求批量启动Pi执行回归。2026-10-02启动10个独立任务，限定为冻结代码快照及本任务临时工作目录，禁止真实凭证/账号访问、禁止Xcode/模拟器、禁止修改开发分支。实际XCTest与多目标构建由root串行执行。

最初使用用户默认zcode/glm-5.3-flash，服务返回503（账号不可用/配额/并发原因未能区分）。切换已配置cch/glm-5.3后产出真实运行报告；队列按4个槽位执行。模型路由仍可能发生Cloudflare524，保留错误记录和已生成的复现材料，不能把CLI退出码0当作测试成功，也不因报告后总结调用超时而反复重做已经审阅的报告。

当前原始运行目录：`/tmp/tokenpulse-pi-regression-20261002-222956`；其中有prompts、逐任务快照说明、JSON事件、状态及Swift复现文件。临时材料不属于跨机器永久附件；已审阅报告保存到本目录，来源版本记录于reports.json。

本目录triage.json区分发现、代码修复、运行验证和未完成工作。Pi报告仅代表其中列出的检查，静态发现不冒充UIKit运行测试；报告产出不等于所有建议已接受或所有回归已通过。

## 已审阅报告

10个任务均已交付报告。`completed-reviewed` 表示报告已完整产出且经root采用，停止了上游超时后的重复续跑；不表示所有模型调用都成功。实际修复与验证状态见[triage.json](triage.json)。

- [01-web-session](01-web-session.md)
- [02-decimal-reminders](02-decimal-reminders.md)
- [03-hosted-web](03-hosted-web.md)
- [04-gateways](04-gateways.md)
- [05-regional](05-regional.md)
- [06-org-sessions](06-org-sessions.md)
- [07-billing-sessions](07-billing-sessions.md)
- [08-research-providers](08-research-providers.md)
- [09-coding-sessions](09-coding-sessions.md)
- [10-surfaces-icons](10-surfaces-icons.md)

## 取舍与更正

- 网关、地区、Abacus/Perplexity/Notion、编码工具和跨端图标报告未发现可复现问题；这只代表所列检查范围。
- Pi08 的Replicate枚举上限建议未采纳：部分枚举不能当成完整可选账号集合。
- Pi08 的“未找到图标许可”观察不成立；Notices第41/43/45行已有完整来源，MIT全文也在同一文件。
- Mistral/Sakana的DOM/flight变体修复属于有界离线健壮性改进，没有宣称真实站点已故障。
- 所有建议测试均由root筛选，未把Pi的parse/独立harness或未执行XCTest建议文件计作完整XCTest通过。
