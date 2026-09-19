# DeepSeek Watch 与小组件

**Status:** `ready-for-agent`

## What to build

iPhone 配置的 DeepSeek 服务账号、主要币种及安全凭证同步后，Watch 能独立查询并显示钱包。iPhone 与 Watch 小组件展示所选币种的金额与数据状态，沿用现有账号选择、排序及关注设置，不把钱包画成已用百分比。

## Acceptance criteria

- [ ] 账号、币种偏好与凭证通过既有同步机制到达 Watch；未取得凭证时明确提示，已有凭证时手机离线仍能查询；验证：同步契约测试及真实手机离线、Watch 联网刷新。→ 同步与凭证机制沿用既有 XCTest；**真实手机离线 + 实体 Watch 联网刷新未执行，保持未勾选**。
- [ ] Watch 每页一个服务账号，显示所选币种的余额和可用状态，支持查看赠送与充值余额；账号顺序和关注选择与配置一致；验证：两账号界面操作及配置恢复。→ 配置恢复与关注选择由 `AccountConfigurationTests` 覆盖；**实体 Watch 界面操作未执行，保持未勾选**。
- [ ] iPhone 小组件与 Watch 表盘/智能叠放入口使用同一主要币种，设置改变后发布更新；验证：小组件快照数据与币种切换测试，以及各入口实际显示。→ 快照与币种切换由 `WalletPresentationTests` 覆盖；**各入口在实体设备上的实际显示未执行，保持未勾选**。
- [x] 钱包展示金额和币种，不显示假的百分比进度或重置时间；所选币种缺失显示未提供，API 不可用状态保留；验证：正常、零余额、空数组、缺失币种场景。
- [x] 刷新失败保留对应账号的旧余额和原采集时间，明确标记失败，不影响其他账号；验证：网络失败测试与 Watch/小组件界面操作。
- [ ] 长账号名、较大金额、系统字号和深浅外观下关键金额与币种可读，辅助功能能读出余额及状态；验证：目标尺寸预览及设备检查。→ **未做实体设备字号/外观/读屏检查，保持未勾选**。
- [x] iOS、watchOS 与两端 Widget 构建通过，既有提供商小组件选择和深链不回归；运行相关 XCTest 并保存结果。

## 验证记录（2026-09-15，共享集成者）

- XCTest：`xcodebuild test -scheme TokenPulse -destination 'platform=iOS Simulator,name=iPhone 16e,OS=26.3.1'` → **TEST SUCCEEDED**，Executed **133 tests, 0 failures**。
- 生产 target：`TokenPulse`、`TokenPulseWatch`、`TokenPulseWidgets`、`TokenPulseWatchWidgets` 四个 target 均 **BUILD SUCCEEDED**（`CODE_SIGNING_ALLOWED=NO`，清空 `build/` 后重建）。
- 钱包小组件展示统一走 `WidgetAccountSnapshot.displayMetrics`（iPhone 与 Watch 共用），币种偏好由 `WidgetSnapshotStore.save(states:configurations:)` 发布，`WalletPresentationTests` 覆盖币种切换与缺失币种“未提供”。
- 缺口：实体 Apple Watch 独立刷新、表盘/智能叠放入口、设备字号与辅助功能均未验收；工单保持 `ready-for-agent`。

## Blocked by

- [01 — DeepSeek 钱包查询与账号卡片](01-deepseek-wallet-card.md)
