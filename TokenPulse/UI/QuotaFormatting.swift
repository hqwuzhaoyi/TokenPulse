import Foundation

enum QuotaFormatting {
    static func walletCollectionStatus(failure: RefreshFailure?, collectedAt: Date?) -> String? {
        guard failure != nil || collectedAt != nil else { return nil }
        let time = collectedAt.map { "钱包采集于 \(resetDate($0))" } ?? "暂无成功钱包数据"
        if let failure {
            if let collectedAt {
                return "钱包为旧数据（采集于 \(resetDate(collectedAt))）；刷新失败：\(failure.displayName)。"
            }
            return "钱包刷新失败：\(failure.displayName)。\(time)。"
        }
        return time
    }
    static func remainingResets(_ count: Int?) -> String {
        guard let count else { return "未提供" }
        return "\(count.formatted()) 次"
    }

    static func resetDate(_ date: Date?, locale: Locale = .autoupdatingCurrent,
                          timeZone: TimeZone = .autoupdatingCurrent,
                          precision: QuotaDatePrecision? = nil) -> String {
        guard let date else { return "未提供" }
        let formatter = DateFormatter()
        if precision == .day {
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
        } else {
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateStyle = .short
            formatter.timeStyle = .short
        }
        return formatter.string(from: date)
    }

    static func nextEventDate(_ window: QuotaWindow) -> Date? {
        [window.expiresAt, window.resetsAt, window.nextReplenishmentAt].compactMap { $0 }.min()
    }

    static func nextEventValue(_ window: QuotaWindow) -> String {
        let event = nextEventDate(window)
        if event == nil, window.resetSemantics == .continuousReplenishment { return "持续补充" }
        if event == nil, window.resetSemantics == .nonResettingAllowance { return "无周期重置" }
        return resetDate(event, precision: event == window.resetsAt ? window.resetDatePrecision : nil)
    }

    static func nextEventLabel(_ window: QuotaWindow) -> String {
        if nextEventDate(window) == nil, window.resetSemantics == .continuousReplenishment { return "额度补充" }
        if nextEventDate(window) == nil, window.resetSemantics == .nonResettingAllowance { return "额度类型" }
        if let replenishment = window.nextReplenishmentAt,
           nextEventDate(window) == replenishment { return "下次补充" }
        guard let expiry = window.expiresAt else { return "下次重置" }
        return window.resetsAt.map { $0 < expiry } == true ? "下次重置"
            : window.id == "stepfun.credits" ? "最早积分到期" : "到期时间"
    }

    static func percentage(_ value: Double?) -> String {
        guard let value else { return "未提供" }
        return value.formatted(.number.precision(.fractionLength(0...1))) + "% 已用"
    }

    static func usage(_ window: QuotaWindow) -> String {
        if window.isUnlimited { return "无限" }
        if let overage = overageDescription(window) { return overage }
        if window.isExhausted == true { return "已用尽" }
        if let value = exactCountSummary(window) { return value }
        if window.unit != nil, window.remainingCount != nil || window.totalCount != nil {
            let remaining = count(window.remainingCount, maximumFractionDigits: window.unit == "USD 预算额度" ? 6 : 2)
            let total = count(window.totalCount, maximumFractionDigits: window.unit == "USD 预算额度" ? 6 : 2)
            let values = window.remainingCount == nil ? total : window.totalCount == nil ? remaining : "\(remaining) / \(total)"
            return window.unit.map { "\(values) \($0)" } ?? values
        }
        return percentage(window.usedPercentage)
    }

    static func overageDescription(_ window: QuotaWindow) -> String? {
        guard !window.isUnlimited, window.overagePermitted == true,
              (window.usedPercentage ?? 0) >= 100 || (window.overageCount ?? 0) > 0 else { return nil }
        if let count = window.overageCount, count > 0 { return "超额付费 \(Self.count(count)) 次" }
        return "可超额付费"
    }

    static func effectiveUsedPercentage(_ window: QuotaWindow) -> Double? {
        guard window.wallet == nil, !window.isUnlimited else { return nil }
        return window.isExhausted == true ? 100 : window.usedPercentage
    }

    static func exactCountSummary(_ window: QuotaWindow) -> String? {
        guard let counts = window.exactCounts else { return nil }
        let values: String
        if let remaining = counts.remaining, let total = counts.total {
            values = "\(count(remaining)) / \(count(total))"
        } else if let used = counts.used, let total = counts.total {
            values = "已用 \(count(used)) / \(count(total))"
        } else if let used = counts.used, let remaining = counts.remaining {
            values = "已用 \(count(used)) · 剩余 \(count(remaining))"
        } else if let used = counts.used {
            values = "已用 \(count(used))"
        } else if let remaining = counts.remaining {
            values = "剩余 \(count(remaining))"
        } else if let total = counts.total {
            values = "总量 \(count(total))"
        } else { return nil }
        return window.unit.map { "\(values) \($0)" } ?? values
    }

    static func count(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...38)))
    }

    static func count(_ value: Decimal, unit: String?) -> String {
        let formatted = count(value)
        return unit.map { "\(formatted) \($0)" } ?? formatted
    }

    static func count(_ value: Double?, maximumFractionDigits: Int = 2) -> String {
        guard let value else { return "未提供" }
        return value.formatted(.number.precision(.fractionLength(0...maximumFractionDigits)))
    }

    static func count(_ value: Double?, unit: String?) -> String {
        let value = count(value, maximumFractionDigits: unit == "USD 预算额度" ? 6 : 2)
        guard value != "未提供", let unit, !unit.isEmpty else { return value }
        return "\(value) \(unit)"
    }

    static func money(_ value: Decimal?, currency: String) -> String {
        guard let value else { return "未提供" }
        return money(value, currency: currency)
    }

    static func balance(_ value: Decimal?, wallet: WalletBalance) -> String {
        guard let value else { return "未提供" }
        return "\(value.formatted(.number.precision(.fractionLength(0...8)))) \(wallet.currency)"
    }

    static func money(_ value: Decimal, currency: String) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...8)))) \(currency)"
    }

    /// Wallet status wording shared by the account card, Watch pages and widgets.
    /// The badge form is the short inline label; the detail form is the full sentence.
    static let walletUnavailableBadge = "余额不足"
    static let walletUnavailableDetail = "余额不足，无法调用 API"
    static let quotaExceededBadge = "额度已用尽"

    static func limitDescription(_ window: QuotaWindow) -> String? {
        window.isUnlimited ? "无限" : nil
    }

    static func refreshFailure(_ failure: RefreshFailure, hasSnapshot: Bool) -> String {
        let message = "刷新失败：\(failure.displayName)。"
        return hasSnapshot ? message + "已保留上次成功数据。" : message
    }
}
