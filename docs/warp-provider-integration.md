# Warp 套餐和按来源区分的附加 credits

用户在 Warp 设置取得 API Key 后，在 TokenPulse 添加或替换凭证。统一账号生命周期负责安全保存、UUID 隔离、恢复、删除和 iCloud 配置/凭证同步；不读取 Warp.app、`.warp`、浏览器或环境变量。代码路径中手机与取得凭证的 Watch 分别直连提供商，不使用 Mac/手机代查服务。

只读请求固定为 `POST https://app.warp.dev/graphql/v2?op=GetRequestLimitInfo`，operationName 和 GraphQL 文本均为 `query GetRequestLimitInfo`，没有 mutation。Bearer、JSON Accept/Content-Type、`x-warp-client-id: warp-app`、`User-Agent: Warp/1.0`、`x-warp-os-category/-name: macOS` 及版本/对应 requestContext 沿参考客户端；禁自动 Cookie、禁本地缓存，沿通用跨 origin 重定向保护。

**移动端兼容性仍未真实验证。** 这些是桌面客户端兼容请求头，OS category/name 使用参考的 macOS，version 取当前运行设备的 ProcessInfo。不能由静态请求断言推导服务接受 iOS/watchOS Key 或该上下文。没有实际账号/设备，本票的平台约束验收保持未完成；如果后端拒绝，应给出真实状态/响应证据再更改契约，不能猜一个移动平台头或声称已可用。

额度形状和客户端头依据 [固定 Pulse Warp 实现](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/Profiled/WarpUsageService.swift) 与 [说明](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/warp.md)，二手来源来自 CodexBar；不是生产账号捕获。本次另核对 [Warp 官方查询定义](https://github.com/warpdotdev/Warp/blob/3f37d69ff3e87818d24f803c16b2e045fa4bd95e/crates/graphql/src/api/queries/get_request_limit_info.rs)，固定 `3f37d69ff3e87818d24f803c16b2e045fa4bd95e`，确认 `workspaces.uid` 和 grant `createdAt` 可以查询。官方 RequestContext 的 OS 字段是可选字符串；这只能证明输入形状，不能证明服务端移动兼容策略。

套餐单独为 `warp.plan`，`requestsUsedSinceLastRefresh / requestLimit`，单位是 credits（接口旧称 requests），不是 token 或美元。`isUnlimited` 必须为真正 Bool；无限计划显示“无限”，没有假额度、百分比或重置提醒。有限计划保留精确 Decimal used/remaining/total，唯一 reset 来自 `nextRefreshTime`，未声明周期长度，不捏造每月长度。

每一个个人 grant 与每一个工作区 grant 保留自己的分母、剩余量、创建时间和到期时间，**不合并成一个套餐百分比或总余额**。名称注明“个人”或“工作区 N”；工作区 uid 用于内部来源身份而非钱包账户。grant ID 由来源 uid、创建时间、初始额度与到期的哈希组成，排除 remaining/used，因此消耗变化不改 ID、工作区重新排序不串额度。同一来源的完全相同条目用出现次数区分，后端没有返回唯一 grant ID 的部分仍不声称拥有不可变服务端身份。

grants 永不填 reset；到期仅为到期，已过去的 grant 从活跃额度中省略，不伪装为零用量。缺少总量但有剩余只显示准确剩余，不制造使用率或耗尽结论。字段缺失不补零；显式负数、非有限、Bool冒充数量、剩余超过发放量、错误类型、工作区发放 grant 却没有 uid 均失败保留旧数据。ISO/秒/毫秒/数字字符串时间受有限与 Int64 毫秒界限保护。GraphQL 非空 errors（即便 HTTP200）为失败；401/403 为失效凭证，429 为限流。

通知对可信套餐/单个 grant 的使用阈值分别去重，不使用钱包低余额提醒；只有套餐可按实际 reset 预排预计通知，grant 到期不代表重置。未知分母、无限、没有 reset 时相应提醒不生成。重置设置仅在收到 reset 后开放。非周期 grants 的统一 resetSemantics 补丁及 Key 身份范围修正在独立后续提交中复用，避免旧 Key/one-off 数据被当成确认重置。

Widget、Watch、手机都使用同一份窗口与 exactCounts，没有合并 grant；演示包含有限套餐、个人 grant 和工作区 grant，维持本机隔离。七项 XCTest 覆盖请求/Headers/body只读、个人/工作区分离/到期、消费与工作区排序稳定身份、无限/缺失分母/过期/重复 grant、GraphQL错误/Bool/溢出/计数矛盾、通知/编码/demo及多账号恢复替换删除/失败保留。App 全源和新测试已 Swift6 typecheck；完整构建/模拟器测试由 root 串行执行。

图标使用明确非品牌的通用接入图形，固定 Pulse397c8fc4 的 `Sources/Pulse/Resources/extension.svg`，Apache2，24×24 黑色矢量模板；出处和完整许可已记录。官方 Warp logo 位于 `app/assets`，其 README 明确这些部分为 AGPLv3（MIT 仅适用于 UI 框架 crates），本次未引入。

未真实验收：Warp Key 查询、桌面上下文在移动端的服务端约束、生产字段与 workspaces.uid、grants 真实发放/花费/到期、Key失效与删除、iCloud 到达、物理 Watch 独立刷新、真实提醒与组件外观。固定源码、合成样例和静态检查不等于这些验收。

生产 Warp 解析代码 macOS 合成 smoke 通过套餐/个人/工作区分离、独立到期、消费变化稳定ID、无限、缺少分母、真实Bool及计数矛盾拒绝。不是移动端/真实Key验证或模拟器XCTest。
