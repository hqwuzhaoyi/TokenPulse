# DeepSeek 钱包查询与账号卡片

**Status:** `ready-for-agent`

## What to build

用户在 iPhone 添加 DeepSeek 服务账号并输入 API Key 后，直接查询官方 API 钱包余额。按已确认的 A 原型展示账号卡片，支持同一提供商多个账号；选择一个 API 实际返回的主要币种用于概览，展开后查看各币种的总可用、赠送和充值余额，以及 API 可用状态。

统一使用“服务账号”产品术语。设置负责账号配置，卡片负责数据展示与刷新；本票不新增卡片内提醒设置入口。API Key 进入现有安全凭证存储，币种偏好进入现有账号配置。

## Acceptance criteria

- [ ] 添加两个 DeepSeek 账号后可分别查询，凭证和余额互不混用，重启保留配置；验证：账户隔离与持久化 XCTest、真实 API Key 查询。→ 隔离与持久化 XCTest 已通过（`WalletTests.testTwoDeepSeekAccountsKeepCredentialsPreferencesAndBalancesIsolatedAcrossRestart`）；**真实 API Key 查询未执行（无凭证），保持未勾选**。
- [x] 使用官方余额查询接口和 Bearer API Key；正确解析 `balance_infos` 与 `is_available`，金额保持十进制精度，不做币种换算；验证：请求契约测试、官方示例和高精度金额解析测试。
- [x] 主要币种仅可从实际返回项中选择；概览显示该币种，详情按币种分别展示三种余额；币种偏好在重启后保持；验证：币种切换、持久化与界面操作。
- [x] 所选币种未返回时显示“未提供”，不补零或自动替换；空余额数组保留账户级可用状态，格式错误显式失败；验证：缺失、空数组、重复币种和无效金额测试。
- [x] 卡片采用 A 原型的账号结构，不显示钱包已用百分比或周期重置时间，不添加提醒设置入口；验证：正常、低余额、不可用、币种缺失四种界面场景。
- [x] 失败只影响对应卡片：收起有警告图标，展开有具体原因、保留旧数据说明、原更新时间和单账号刷新；首次查询失败不产生零余额，成功后清除错误；验证：网络、凭证失效、限流及恢复测试和界面操作。
- [x] 自动测试与 iPhone 构建通过，既有提供商展示和账号管理无回归；记录验证命令与结果。

## 验证记录（2026-09-15，共享集成者）

- XCTest：`xcodebuild test -scheme TokenPulse -destination 'platform=iOS Simulator,name=iPhone 16e,OS=26.3.1'` → **TEST SUCCEEDED**，Executed **133 tests, 0 failures**。
- 生产 target：`xcodebuild build -target {TokenPulse|TokenPulseWatch|TokenPulseWidgets|TokenPulseWatchWidgets} -configuration Debug CODE_SIGNING_ALLOWED=NO` → 四个 target 全部 **BUILD SUCCEEDED**（清空 `build/` 后重建）。
- 模拟器 smoke（iPhone 16e / iOS 26.3，演示模式）：首页账号卡片与 A 原型一致；DeepSeek 账号详情显示 CNY 110/10/100 与 USD 8/1/7 的总可用/赠送/充值余额，无百分比与重置时间。
- 缺口：未提供 DeepSeek 真实 API Key，AC1 的“真实 API Key 查询”未执行；工单保持 `ready-for-agent`。

## Blocked by

None — can start immediately.
