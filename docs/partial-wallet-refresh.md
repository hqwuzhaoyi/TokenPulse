# 独立钱包采集状态

支持单次额度刷新中套餐成功、钱包失败的提供商可使用以下可选快照字段：`walletFailure: RefreshFailure?` 与 `walletCollectedAt: Date?`。旧快照解码保持兼容。套餐窗口与本轮 `collectedAt` 正常更新；客户端钱包成功时带其本次时间，失败时带失败原因而不补零余额。

QuotaMonitor 只从同账号、同 `sourceCredentialFingerprint` 的前一份快照保留旧 wallet 窗口和旧钱包采集时间。缺少身份或已换凭证不继承钱包。第一次钱包采集就失败时仍可展示新套餐，但余额不可用。客户端失败响应中的钱包值会被剔除，不可伪装成成功余额。

NotificationRuntime 将两个字段复制到提醒快照。钱包失败的本轮不触发、不重新武装低余额或 API 可用状态提醒，旧钱包状态保持不动；套餐告警继续使用新额度。App 卡片／详情／设置、Watch 和 widget 独立显示“钱包为旧数据”和原采集时间，套餐更新文字不代表钱包也是新数据。widget 缓存也编码两个字段。

4个 PartialWalletTests 覆盖同身份保留及不同身份拒绝、独立时间、低余额不触发／不重武装且新套餐可告警、NotificationRuntime复制metadata、widget持久化及旧格式解码。Swift 6完整 App模块与完整测试语义类型检查、PBX lint和diff检查已通过；没有运行xcodebuild／模拟器／测试执行，整合验收由root串行完成。
