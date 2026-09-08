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

    static func count(_ value: Double?) -> String {
        guard let value else { return "未提供" }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func limitDescription(_ window: QuotaWindow) -> String? {
        window.isUnlimited ? "无限" : nil
    }

    static func refreshFailure(_ failure: RefreshFailure, hasSnapshot: Bool) -> String {
        let message = "刷新失败：\(failure.displayName)。"
        return hasSnapshot ? message + "已保留上次成功数据。" : message
    }
}
