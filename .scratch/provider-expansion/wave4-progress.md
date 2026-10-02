# 第四批：剩余研究票推进

2026-10-03，从 `5c0fb99` 开始。起点为 71 个 provider、62 张已完成接入票，638 项测试通过。

用户已将验收明确为实现完成及图标存在。旧研究票中的真实账号、实体 Watch 验证前置条件已撤销；这些未执行观察仍如实保留。未知认证或额度协议仍需证据，不能以图标或猜测接口冒充实现。

| 票 | 负责 | 当前工作 |
| --- | --- | --- |
| 63 Gemini | sol_copilot | `c87507b` 已合入；自配 iOS OAuth，组合测试中 |
| 64 Kiro | sol_research | `4e76e19` 已合入；官方 Portal HTTPS/CBOR，组合测试中 |
| 65 Antigravity | sol_wallet | `1b2e9bb` 已合入；官方 quota summary，组合测试中 |
| 66 Alibaba Token Plan | sol_gateway | 已合入 `c230bc6`，Widget 类型共享修复 `8c6427b`；9 项 XCTest 通过；Pi 运行中 |
| 67 Nous Portal | sol_web | 独立设备 OAuth 链与账户 credits 查询 |
| 68 JetBrains AI | sol_gateway | `bb2cab3` 追加官方发布包静态证据；仍缺完整原生签发/fallback，protocol-gap |
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
