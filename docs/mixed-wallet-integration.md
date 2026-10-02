# 混合额度与余额接口

`Provider.balancePresentation` 明确选择 `.none`、`.walletOnly` 或 `.mixed`。纯余额服务仍按选定货币展示钱包，混合服务在卡片与小组件保留全部套餐、预算和余额窗口，不从余额推导套餐百分比。`hasMonetaryWallet` 只表示提供商是否具有货币余额能力；非货币积分与混合展示是独立属性。

钱包使用既有 `WalletBalance`，金额为 `Decimal`，明细缺失为 nil，`isMonetary=false` 表示 points、HC、DIEM 等服务单位。低余额 controls 以当前快照是否有货币钱包决定；混合账户没有配额窗口时不提供配额提醒，没有实际重置时间时不提供重置设置。详情中非货币单位按钱包实际单位命名。

`AccountReminderSettings.walletAlertsEnabled: Bool?` 默认 nil，`effectiveWalletAlertsEnabled` 取显式值或回退既有 `quotaAlertsEnabled`，因此旧存档和旧余额开关兼容。混合账户可以分别开启额度与货币低余额提醒。全局关闭通知同时覆盖两种开关，保留账号偏好。非货币钱包不会触发金额阈值；预算、货币余额和服务积分不互相换算。

测试覆盖旧提醒存档、开关独立组合、非货币钱包排除，以及全局关闭优先于显式钱包启用。Swift 6 静态 typecheck 与 parse 已验证；XCTest 执行和 App/Watch/widget 完整构建留待统一集成验证。
