# 第四批：剩余研究票推进

2026-10-03，从 `5c0fb99` 开始。起点为 71 个 provider、62 张已完成接入票，638 项测试通过。

用户已将验收明确为实现完成及图标存在。旧研究票中的真实账号、实体 Watch 验证前置条件已撤销；这些未执行观察仍如实保留。未知认证或额度协议仍需证据，不能以图标或猜测接口冒充实现。

| 票 | 负责 | 当前工作 |
| --- | --- | --- |
| 63 Gemini | sol_copilot | `c87507b` 已合入；自配 iOS OAuth，组合测试中 |
| 64 Kiro | sol_research | `4e76e19` 已合入；官方 Portal HTTPS/CBOR，组合测试中 |
| 65 Antigravity | sol_wallet | `1b2e9bb` 已合入；官方 quota summary，组合测试中 |
| 66 Alibaba Token Plan | sol_gateway | 已合入 `c230bc6`，Widget 类型共享修复 `8c6427b`；9 项 XCTest 通过；Pi 运行中 |
| 67 Nous Portal | sol_web | `b93a367` 已合入，`2b530a3` 续期轮询路由修复；unsigned 构建通过，专项测试/Pi 进行中 |
| 68 JetBrains AI | sol_research | `bb2cab3` 官方发布包证据后继续补齐 TokenTransfer 导入/签发/独立续期方案，进行中 |
| 69 OpenAI API | sol_wallet | 已合入 `444a1ba`；Legacy 余额，7 项 XCTest 通过；Pi 运行中 |

sol_regional 负责 Nous 设备本地凭证与快照同步的架构审查。Root 负责集成、中央清单和串行 Xcode 验证。新增实现稳定后安排针对性的 Pi 回归，前一批 10 组结果保留。

## 已执行验证

- `444a1ba`：新增 OpenAI Legacy 7 项 XCTest，0 失败。日志 `/tmp/tokenpulse-wave4-openai.log`，结果 `/tmp/tokenpulse-wave4-openai.xcresult`。此为定向验证，不替代本轮最终全套测试。
- Pi 新任务 `01-openai-legacy` 使用独立代码快照，运行目录 `/tmp/tokenpulse-wave4-pi`。

- `8c6427b`：Alibaba Token Plan 9 项 XCTest，0 失败。初次编译发现站点枚举未进入 Widget，已移到共享账号配置模型后通过。日志 `/tmp/tokenpulse-wave4-alibaba-fixed.log`，结果 `/tmp/tokenpulse-wave4-alibaba-fixed.xcresult`。

- `d402277`：共享 Google 原生 OAuth 6 项 XCTest，0 失败。日志 `/tmp/tokenpulse-wave4-google-auth.log`，结果 `/tmp/tokenpulse-wave4-google-auth.xcresult`。后续 `ab300b9` 在授权期间禁用 client/project 编辑；待最终统一构建覆盖。
- 第四批 Pi 报告逐项归档至 [pi-wave4](pi-wave4/README.md)，OpenAI 任务已完成，其余按新实现陆续启动。

- `5dd15e5`、`274fbbd` 修正新增测试对实际模型 API 的引用；`ca87270` 补齐 Kiro Widget 分支。独立小模块检查不等于 App XCTest 编译通过，组合回归将验证这些接合点。

- `274fbbd`：Gemini 12 + Google OAuth 12 + Antigravity 7 + Kiro 24，共 55 项 XCTest，0 失败。日志 `/tmp/tokenpulse-wave4-cloud-providers-run.log`，结果 `/tmp/tokenpulse-wave4-cloud-providers-run.xcresult`。包括 Pi 03 后的 bounded userinfo 重试和取消提示修复（`5c3e5e6`）。

- `312b742`（76 provider）：709 项全量 XCTest，0 失败，运行日志 `/tmp/tokenpulse-wave4-pre-nous.log`，结果 `/tmp/tokenpulse-wave4-pre-nous.xcresult`。图标只读检查为 76 映射、61 SVG 映射/56 image sets、15 SF 映射/8 种已知系统符号，缺失 0。Nous 尚未合入，此项不是最终全量结果。

- `2b530a3`（77 provider）：unsigned TokenPulse target App/Watch/Widgets 构建成功，日志 `/tmp/tokenpulse-wave4-nous-unsigned-fixed.log`。首次发现 Nous continueLogin 漏 poll 分支，已补齐；Nous 专项测试仍在补充，不混同为已跑完。

- `1a7716f`（77 provider，Nous专项尚未加入）：713 项全量 XCTest，0 失败，日志 `/tmp/tokenpulse-wave4-77-integration.log`，结果 `/tmp/tokenpulse-wave4-77-integration.xcresult`。涵盖 Antigravity/Google 输入与标签的4项新增回归。

- `f5f4678`：Kiro Pi修复后的29项XCTest，0失败，日志 `/tmp/tokenpulse-wave4-kiro-pi-fix.log`。同刻到期多笔credits保留其他池并显示未知分项cohort，试用到期缺失明确标注；不采纳与官方映射相悖的ARN改动。

- `ac6c429`：Nous专项23项XCTest，0失败，日志 `/tmp/tokenpulse-wave4-nous-tests.log`，结果 `/tmp/tokenpulse-wave4-nous-tests.xcresult`。覆盖Pi07/08采用问题、身份GET耗尽后禁止再次POST已消费device code、手机换绑后旧Watch本地链查询前拒绝、rollover/zero/未知月重置。
