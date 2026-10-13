# 阿里百炼 Coding Plan

`.alibabaCodingPlan` 提供显式地区选择和 Coding Plan Key 路线，复用 Moonshot 接入的共享 `ProviderRegion`、账号安全存储和地区来源身份。添加与更新必须先选择国内/国际，再输入对应 Key；更改地区清除输入框 Key，提交后清除旧来源缓存和提醒身份。不自动跨地区尝试 Key，不复用 New API 的 `serverAddress`。

| 地区 | Console host | currentRegionId | commodityCode |
| --- | --- | --- | --- |
| 国内 | `bailian.console.aliyun.com` | `cn-beijing` | `sfm_codingplan_public_cn` |
| 国际 | `modelstudio.console.alibabacloud.com` | `ap-southeast-1` | `sfm_codingplan_public_intl` |

唯一请求为 `POST {console}/data/api.json`，参数 `action=zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2`、`product=broadscope-bailian`、`api=queryCodingPlanInstanceInfoV2` 和地区 ID。请求体为 `queryCodingPlanInstanceInfoRequest.commodityCode`；按固定参考发送 Bearer、`x-api-key`、`X-DashScope-API-Key`、同地区 Origin/Referer。提供商传输仅允许同源重定向，不向另一地区发送凭证。iPhone 和 Watch 都通过本机 AppRuntime 的 ProviderQuotaClient 路由执行请求。

## Key 查询边界

2026-10-02 在实施前向两个固定站点执行了只读契约探测，只发送明确无效的合成 `tokenpulse-invalid-contract-probe`，没有使用或读取真实 Key。两站均 HTTP 200：国内返回 `code=ConsoleNeedLogin`、`message=请登录`、`successResponse=false`，国际返回同一 code、`message=You need to log in.`、`successResponse=false`。

这些响应仅验证失败结构与提示。它们不能推断有效 Coding Plan Key 一定失败，也不能证明有效 Key 可用。本版本未扩展控制台会话登录；真实 Key 若同样遇到 `ConsoleNeedLogin`，Key 路线将明确受阻。`RefreshFailure.consoleSessionRequired` 直接说明接口要求控制台会话，添加/更新 UI 明确显示 Key 兼容性尚待验证。不能把这类失败解释为零额度、无套餐或普通凭证过期。有效 Key 的成功查询仍是未解决验收边界。

## 解析与展示

解析只展开已知 `data`/`result` envelope（最多四层，允许 JSON 字符串包装），只读取 `codingPlanInstanceInfos[].codingPlanQuotaInfo`，不递归搜索其它对象或从过期套餐捞取看似有效的数字。显式 EXPIRED/INVALID/INACTIVE/DISABLED/TERMINATED/STOPPED、active=false 或已过去的 endTime 均排除；VALID/ACTIVE 或明确未来 endTime 才可选。空列表/全已失效列表是无有效套餐；有效套餐没有可解析额度是未返回额度，二者不同。数字及成功/active 旗标均拒绝布尔/数字相互桥接。

固定字段分别构成 5 小时、每周、账期窗口。每个窗口必须同时返回非负 used 和正 total，字符串或数字均可；用量按 used/total，剩余按 total-used（耗尽时归零）。缺失/非法指标不补零，未知形状失败保留旧成功快照。NextRefreshTime 只读 epoch 毫秒；过去、不合法或不可表示的时间留空，不前移五小时。账期归为 monthly 展示身份，不用 30 天推算真实重置。日期格式化的非 ISO `yyyy-MM-dd HH:mm[:ss]` 结束时间沿 console 地区的 UTC+8 解释，仍需真实响应确认。

所有返回窗口都进入卡片、详情、小组件和 Watch；没有钱包、假余额或低余额提醒。共享额度告警、重置提醒、采集时间与失败保留沿用既有规则。演示包含三个额度周期，保持与真实账号隔离。图标固定 Lobe Icons 的 alibabacloud SVG，来源、版权、MIT 和模板矢量处理记录在 notices。

## 验证状态

已验证：9 项新 `AlibabaCodingPlanProviderTests` 和 7 项 Moonshot 测试均通过真实 Swift 6 iOS SDK `-typecheck`；完整生产 module、完整 App UI、PBX plist 与 diff 检查通过。静态命令脚本 `/tmp/tokenpulse-wave2-regional-static/check.py` 使用 Simulator26.5 SDK 和 `arm64-apple-ios17.0-simulator`，并非只 parse。测试覆盖选区地址/参数/三个认证头、无跨区重试、ConsoleNeedLogin、限定 JSON 包装、套餐筛选、缺失/过期时间/类型边界、HTTP 业务错误/取消、widget/提醒，以及多账号恢复/删除、失败旧数据保留与换区清旧缓存。

待 root：运行 `TokenPulseTests/AlibabaCodingPlanProviderTests` 和完整 unsigned TokenPulse target build（App/Widgets/Watch）。本 worker 没有启动 xcodebuild 或模拟器。真实 Key 查询、是否需要会话、失效/撤销 Key、真实套餐单位/周期/字段兼容、Keychain/iCloud 到达、关闭 iCloud 的设备生命周期、物理 Watch 独立刷新和真实通知/widget 仍待验收。模拟数据及无效 Key 的登录要求响应不替代成功账号证据。

固定契约来源：[Pulse 文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/alibaba-coding-plan.md)、[实现](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/AlibabaCodingPlanUsageService.swift) 与无秘密 fixture `Tests/PulseTests/Fixtures/alibaba-coding-plan-instances.json`。该未公开接口的额度形状是第二手契约，生产成功路径没有真实账号确认。
