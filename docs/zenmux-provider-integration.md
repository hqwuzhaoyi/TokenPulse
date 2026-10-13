# ZenMux 管理额度与按量钱包

ZenMux 使用用户粘贴的 **Management Key**，普通推理 Key 不具有管理查询权限。添加和更新输入明确标注“非推理 Key”；管理接口401/403显示管理Key无效／权限不足原因。通过既有API Key路径安全保存、本机恢复、多账号配置、更新、删除及iCloud同步。provider/key identity绑定快照和提醒，新Key不继承旧钱包。

iPhone 与Watch各自先查询 `GET https://zenmux.ai/api/v1/management/subscription/detail`，在成功解析套餐后查询 `GET https://zenmux.ai/api/v1/management/payg/balance`。两者都使用同一Bearer管理Key、固定HTTPS源、禁用系统自动Cookie；没有依赖Mac、另一设备在线代查或新增服务。控制字符／空白Key和未绑定凭证在发请求前拒绝。

`quota_5_hour` 与 `quota_7_day` 分别显示五小时和每周窗口，`usage_percentage` 是 **fraction**：0.0715为7.15%，超过1保留为超额使用，不将其当0–100整数刻度。明确 `resets_at` 才是重置；缺日期不猜。`quota_monthly` 只有max_flows，没有本次使用量，因此不展示为0%额度。plan.tier只作为套餐名称。流量计数或USD预算的其他字段不二次转换为token、积分或余额。

钱包只取 `currency` 和 `total_credits`，使用Decimal保存数值并保持服务声明的三字母币种，保留负余额。没有余额明细证据时赠送／充值保持nil，不补零；不从钱包余额推断整个API账号不可用。mixed展示保留套餐和钱包两类数据，额度告警和低余额开关互相独立。演示包含两个quota和一个USD钱包，小组件显示三种metric。

余额查询限流、无权限、网络或畸形响应不会覆盖刚取得的套餐：本轮snapshot携带 `walletFailure`，quota采集时间更新。QuotaMonitor只在同账号／同凭证identity时保留旧wallet及旧walletCollectedAt。App卡片／详情／设置、Watch和widget明确显示余额为旧数据及独立采集时间；该轮**不触发或重新武装**低余额提醒，quota告警仍可处理。第一次钱包失败没有旧余额则显示不可用，不捏造零。套餐查询失败保持整个旧snapshot；取消也不发布部分成功。

图标使用[Lobe Icons固定ZenMux SVG](https://github.com/lobehub/lobe-icons/blob/f555763cdef7074e22f60970ad1a75334bf267e5/packages/static-svg/icons/zenmux.svg)，commit `f555763cdef7074e22f60970ad1a75334bf267e5`，Copyright (c) 2023 LobeHub，MIT。记录仓库／路径／固定版本与完整已有MIT许可于ProviderIconNotices.txt；只改currentColor为black与显式24x24尺寸，路径保留，imageset开启preserves-vector-representation与template-rendering-intent。

来源：[Pulse固定397c8fc4 ZenMux文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/zenmux.md)、[ZenMuxUsageService.swift](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/ZenMuxUsageService.swift)，及同版本zenmux-subscription-detail／zenmux-payg-balance合成fixtures。按契约独立适配，未复制服务实现；上游明确这些形状来自CodexBar且没有真实ZenMux账号捕获。

9个ZenMux测试覆盖fraction刻度与月cap不补使用量、Decimal／声明币种／负余额、管理请求路由和key身份、推理Key授权错误、partial失败的独立状态、monitor保留旧余额时间且换Key删除旧读数、畸形quota／取消、无套餐wallet-only、demo／widget／图标及危险／未绑定Key拒绝。Swift6完整App模块与所有本波XCTest的语义类型检查，PBX与diff检查通过；SVG XML／imageset JSON静态合法。worker没有运行xcodebuild／模拟器／真实Key。Root负责执行测试和unsigned App/Widgets/Watch全目标构建，catalog编译、真机矢量与模板显示仍未验收。

真实验收仍缺：实际Management Key及推理Key拒绝、当前套餐／钱包契约、负余额、故意余额失败时双端旧数据及时间展示、独立quota／wallet通知、iCloud凭证与配置到达／删除、关闭其他设备后的iPhone与Watch独立刷新、widget视觉。所有真实项目保持未验收，合成数据通过不代表真实接入完成。
