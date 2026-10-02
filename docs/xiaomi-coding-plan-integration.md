# 小米 Coding Plan 与 MiMo 余额

已实现 `.xiaomiCodingPlan` 全链路：添加/更新入口采用 root 通用 WebProviderSessionLoginView 的账号专用 nonPersistent WK 容器，固定入口 `https://platform.xiaomimimo.com/#/console/balance`；仅保留 `api-platform_serviceToken` 和 `userId` 必需 Cookie，以及可选 `api-platform_ph`、`api-platform_slh`。普通推理 API Key 不能用于这里的查询。来源绑定 provider、origin、账号 UUID、实际 Cookie 和可选到期；重登、不同账号和同步分开到达沿用来源身份防护。Cookie 从应用临时容器提取，不读真实用户浏览器、桌面文件或编辑器凭证。

唯一控制台为 `platform.xiaomimimo.com`，没有猜测海外账号站点，也不向 cn/sgp 推理域名发送会话。iPhone 与 Watch 都自行 GET `/api/v1/tokenPlan/usage`、`tokenPlan/detail` 和 `balance`，Cookie 禁自动处理、GET 禁缓存、生产传输拒绝所有重定向。三个独立请求共同检查 HTTP 与 JSON code；任一鉴权拒绝提示重新登录。usage 必须成功；detail 非鉴权失败可暂时缺失套餐名/重置；balance 非鉴权失败独立标注 walletFailure，经共享保持规则只保留同来源旧钱包及原 walletCollectedAt，并且不拿旧余额触发或重置低余额去重。

`data.monthUsage.items[]` 的实际 used/limit 成为各自月度 Token 窗口，数值缺失/类型错误不能伪装零使用或无套餐。空列表、零发放或明确 expired=true 作为当前无 Coding Plan 的静态 quotaStatusText，能保留同时返回的钱包；不复用“按量无上限”文案。余额、现金与赠送使用 Decimal，零/负数原样保留，币种只取服务实际字段，不兑换或默认海外币种。当前月结束时间采用服务给出的 UTC `yyyy-MM-dd HH:mm:ss` 或 ISO，未知不推算30天周期。所有返回月度桶分别显示，避免依赖上游未确认的“仅首桶就是套餐”假设。

注册包括 ProviderQuotaClient、网页登录 profile、图标、混合额度/钱包展示、Widget、Watch、演示与独立额度/低余额提醒开关。图标 `ProviderXiaomiMiMo` 使用 Lobe Icons 固定提交 `2e76c48721e91b9aaa40803a0fa2eb8aca7399c4` 的 `packages/static-svg/icons/xiaomimimo.svg`，MIT、Copyright 2023 LobeHub、模板黑色/矢量保留在 notices 与 image set 中记录。

新增七项 XCTest 覆盖 Cookie 白名单/账号源、三条请求契约、Token/Decimal 钱包单位、部分余额失败/旧采集时间、任一路 envelope401、无套餐/过期套餐仍保留余额、字段缺失、编码/演示/提醒。已运行实际 Swift6 必要小模块 typecheck（领域模型、真实会话/协议类型、session/helper 与本 client）、Swift parse、PBX plist 和 diff 检查；脚本 `/tmp/tokenpulse-wave3-regional-static/prepare.py`。没有运行 xcodebuild 或模拟器，root 合并后统一执行测试/资源构建。

当前用户验收门槛为完整实现与图标存在，已完成。真实账号、SSO/验证码、物理设备、Keychain/iCloud 到达与通知结果未声称验证，也不作为本票关闭阻塞。来源：[固定 Pulse Xiaomi 文档](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Docs/providers/xiaomi-coding-plan.md)、[实际控制台 client](https://github.com/qunqin24/Pulse/blob/397c8fc4f1bd52180a452d2f3f0c099def97cf69/Sources/Pulse/Providers/XiaomiMiMoUsageService.swift) 与其无秘密 fixtures。额度/余额契约来自第二手捕获与源码，API 布局或会话要求变化仍可造成明确刷新失败。
