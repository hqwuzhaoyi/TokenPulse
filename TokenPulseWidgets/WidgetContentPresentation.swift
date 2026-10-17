import Foundation

/// Text used by both widget renderers and their accessible descriptions.
/// Persisted account names, entity identifiers and provider data remain unchanged.
enum WidgetContentPresentation {
    static func emptyMessage(selectionRequired: Bool, accountSelectionMissing: Bool, hasAvailableAccounts: Bool) -> String {
        if accountSelectionMissing { return L10n.text("所选账号尚未同步") }
        if selectionRequired && hasAvailableAccounts { return L10n.text("请选择展示账号") }
        return L10n.text("请先添加账号")
    }

    static func accountName(_ account: SubscriptionAccount) -> String {
        L10n.demoAccountName(account)
    }

    static func entityTitle(name: String, identifier: String) -> String {
        guard let id = UUID(uuidString: identifier) else { return name }
        return accountName(SubscriptionAccount(id: id, name: name))
    }

    static func entitySubtitle(_ providerName: String) -> String {
        // Older saved entity values contain the former displayed brand/region name.
        let provider = Provider.allCases.first {
            $0.displayName(language: "zh-Hans") == providerName || $0.displayName(language: "en") == providerName
        }
        return provider?.displayName ?? providerName
    }

    static func compactInlineDetails(_ account: WidgetAccountSnapshot, at date: Date) -> String {
        var phrases = [account.displayMetrics.first?.valueText ?? L10n.text("额度未提供")]
        if account.supportsManualResetCount {
            phrases.append("↺ " + QuotaFormatting.remainingResets(account.remainingResetCount))
        }
        if account.lastFailure != nil || account.walletFailure != nil {
            phrases.append(L10n.text("刷新失败"))
        } else if account.needsUpdate(at: date) {
            phrases.append(L10n.text("待更新"))
        } else if let availability = availability(account) {
            phrases.append(availability)
        }
        return phrases.joined(separator: " · ")
    }

    static func resetCount(_ account: WidgetAccountSnapshot) -> String? {
        guard account.supportsManualResetCount else { return nil }
        return L10n.format("可重置 %@", QuotaFormatting.remainingResets(account.remainingResetCount))
    }

    static func resetPreview(_ account: WidgetAccountSnapshot, at date: Date) -> String? {
        guard account.account.provider == .codex, let status = account.codexResetStatus else { return nil }
        let summary: String
        if let reset = status.data.scheduledReset {
            let time: String
            if let scheduled = reset.scheduledFor {
                time = scheduled <= date ? L10n.text("待确认")
                    : scheduled.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
            } else {
                time = L10n.text("时间待定")
            }
            summary = L10n.format("重置预告 · %@", time)
        } else if let watch = status.activeWatch(at: date) {
            if let chance = CodexResetStatus.chanceText(watch.resetChancePercent) {
                summary = L10n.format("AI 重置预测 %@ · %@", chance, watch.forecastWindow)
            } else {
                summary = L10n.format("AI 重置预测 · %@", watch.forecastWindow)
            }
        } else {
            return nil
        }
        return account.codexResetUnavailable == true ? L10n.format("%@ · 旧数据", summary) : summary
    }

    static func resetText(_ metric: WidgetQuotaMetric) -> String {
        guard let window = metric.window else { return L10n.text("时间未提供") }
        if let wallet = window.wallet {
            return wallet.isMonetary ? L10n.text("钱包余额") : L10n.text("服务积分余额")
        }
        return L10n.format("%@ %@", QuotaFormatting.nextEventLabel(window), QuotaFormatting.nextEventValue(window))
    }

    static func availability(_ account: WidgetAccountSnapshot) -> String? {
        if account.walletAvailable == false { return QuotaFormatting.walletUnavailableBadge }
        if account.quotaExceeded == true { return QuotaFormatting.quotaExceededBadge }
        return nil
    }

    static func status(_ account: WidgetAccountSnapshot) -> String? {
        if account.lastFailure != nil {
            return L10n.text(account.collectedAt == nil ? "刷新失败" : "刷新失败 · 保留旧数据")
        }
        if account.walletFailure != nil {
            return QuotaFormatting.walletCollectionStatus(failure: account.walletFailure, collectedAt: account.walletCollectedAt)
                ?? L10n.text("余额为旧数据")
        }
        if let availability = availability(account) { return availability }
        return account.collectedAt.map { L10n.format("更新于 %@", $0.formatted(date: .omitted, time: .shortened)) }
    }

    static func metricSummary(_ metric: WidgetQuotaMetric, percentage: String? = nil) -> String {
        let value = L10n.format("%@ %@", metric.displayTitle, metric.valueText)
        guard metric.window?.wallet == nil, metric.window != nil else { return value }
        if let percentage {
            return L10n.format("%@，已用 %@，%@", value, percentage, resetText(metric))
        }
        return L10n.format("%@，%@", value, resetText(metric))
    }

    static func accessibilitySummary(_ account: WidgetAccountSnapshot, at date: Date) -> String {
        var phrases = account.displayMetrics.map { metricSummary($0) }
        if phrases.isEmpty { phrases.append(L10n.text("额度未提供")) }
        if let resetCount = resetCount(account) { phrases.append(resetCount) }
        if let availability = availability(account) { phrases.append(availability) }
        if account.needsUpdate(at: date) { phrases.append(L10n.text("待更新")) }
        if let failure = account.lastFailure {
            phrases.append(QuotaFormatting.refreshFailure(failure, hasSnapshot: account.collectedAt != nil))
        } else if let status = status(account) { phrases.append(status) }
        if let quotaStatus = QuotaFormatting.quotaStatus(account.quotaStatusText, provider: account.account.provider) {
            phrases.append(quotaStatus)
        }
        let details = phrases.joined(separator: L10n.text("；"))
        return L10n.format("%@，%@", accountName(account.account), details)
    }
}
