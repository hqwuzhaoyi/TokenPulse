# TokenPulse 国际化任务索引

用户已在术语修正后以“继续”批准发布此前 10 票拆分。首期：简体中文与英文。中文保留 API Key、Token、OAuth、Provider 等常用英文术语；品牌与模型名不翻译，操作、说明和错误信息按所选语言显示。

沿用项目本地工单惯例，正式票逐张存放，01—10 已完成并保留双语构建/测试/可视证据；04额外覆盖补漏与复验也已完成；09 两语真宿主与最后回归已完成，10最终验收已收口。没有创建远端 Issue，也没有修改或关闭现有父工单。

规格：[国际化规格](spec.md)。测试边界：复用现有展示、格式化、通知规划/runtime 与平台行为入口，检查外部可见结果，配合各入口双语可视验收。

## 用户验收范围更新

2026-10-13 用户明确指示“跳过这个”，豁免本轮 iPhone 与 Watch 的 VoiceOver 实际听辨及语音导航验收。此项记为用户豁免，未执行、未声称测试通过。已完成的辅助功能标签/AX 检查保留；不豁免普通 Watch 触控、Crown、滚动、表盘宿主或最终中文锁屏复验。

## 工单与依赖

- [x] [01 — 语言基础与首页首条完整路径](issues/01-language-and-home.md) — 阻塞：无。
- [x] [02 — 提供商选择与 API Key 添加流程](issues/02-provider-selection-api-key.md) — 阻塞：01。
- [x] [03 — 网页登录与设备授权流程](issues/03-web-and-device-auth.md) — 阻塞：01。
- [x] [04 — 额度、钱包与缓存数据展示](issues/04-quota-wallet-cache.md) — 阻塞：01。
- [x] [05 — 账号设置与同步管理](issues/05-account-settings-sync.md) — 阻塞：01。
- [x] [06 — 通知与语言切换后的待发提醒](issues/06-notifications-language-change.md) — 阻塞：04。
- [x] [07 — Codex 重置预告双语体验](issues/07-codex-reset-previews.md) — 阻塞：06。
- [x] [08 — Apple Watch 完整使用流程](issues/08-watch-experience.md) — 阻塞：03、04。
- [x] [09 — iPhone 与 Watch 小组件](issues/09-widgets-complications.md) — 阻塞：04。
- [x] [10 — 跨入口验收与翻译完整性检查](issues/10-cross-surface-acceptance.md) — 阻塞：02、05、07、08、09。

## 执行顺序

本轮实施和原范围验收已完成；01—10全部complete。以下依赖顺序保留作追溯。01 完成后 02、03、04、05 可分别开始；04 完成后 06、09 可开始；03 与 04 完成后 08 可开始；06 完成后 07 可开始；02、05、07、08、09 完成后执行 10。只领取阻塞票全部完成的工单。资源目录与 pbxproj 由实施负责人独占整合；各代理按已分配文件实施。

设置文案票 05 不阻塞通知逻辑票 06，Watch 票 08 不依赖主应用设置翻译：它们复用已有行为，避免因文案所在位置相近而制造依赖。不同票涉及共享资源时应协调资源键并保持每票构建可用。


## 最终交付状态（2026-10-13）

10/10工单complete。最终证据汇总见 [验收摘要](10-final-acceptance-summary.md) 与 [最新验证](final-rect-validation.md)。VoiceOver用户豁免、水平swipe工具未测等边界如实保留。当前未提交、推送、安装真机或发布。
