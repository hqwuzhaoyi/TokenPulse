import Foundation

enum QuotaFormatting {
    static func remainingResets(_ count: Int?) -> String {
        guard let count else { return "未提供" }
        return "\(count.formatted()) 次"
    }

    static func resetDate(_ date: Date?, locale: Locale = .autoupdatingCurrent,
                          timeZone: TimeZone = .autoupdatingCurrent) -> String {
        guard let date else { return "未提供" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func percentage(_ value: Double?) -> String {
        guard let value else { return "未提供" }
        return value.formatted(.number.precision(.fractionLength(0...1))) + "% 已用"
    }

    static func usage(_ window: QuotaWindow) -> String {
        if window.isUnlimited { return "无限" }
        if window.isExhausted == true { return "已用尽" }
        if window.unit != nil, window.remainingCount != nil || window.totalCount != nil {
            let remaining = count(window.remainingCount)
            let total = count(window.totalCount)
            let values = window.remainingCount == nil ? total : window.totalCount == nil ? remaining : "\(remaining) / \(total)"
            return window.unit.map { "\(values) \($0)" } ?? values
        }
        return percentage(window.usedPercentage)
    }

    static func effectiveUsedPercentage(_ window: QuotaWindow) -> Double? {
        guard window.wallet == nil, !window.isUnlimited else { return nil }
        return window.isExhausted == true ? 100 : window.usedPercentage
    }

    static func count(_ value: Double?) -> String {
        guard let value else { return "未提供" }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func count(_ value: Double?, unit: String?) -> String {
        let value = count(value)
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
