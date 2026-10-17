import Foundation

/// Public announcements are independent of an account's actual quota/reset boundaries.
struct CodexResetStatus: Codable, Equatable, Sendable {
    struct Announcement: Codable, Equatable, Sendable {
        let id: String
        let resetType: String
        let announcedAt: Date
        let scheduledFor: Date?
        let text: String
    }

    struct Watch: Codable, Equatable, Sendable {
        let level: String
        let resetChancePercent: Int?
        let forecastWindow: String
        let observedAt: Date
        let expiresAt: Date
        let text: String
    }

    struct Payload: Codable, Equatable, Sendable {
        let latestReset: Announcement?
        let scheduledReset: Announcement?
        let activeWatch: Watch?
    }

    struct Metadata: Codable, Equatable, Sendable {
        let generatedAt: Date
    }

    let data: Payload
    let meta: Metadata

    static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid ISO8601 date"))
            }
            return date
        }
        return try decoder.decode(Self.self, from: data)
    }

    func activeWatch(at now: Date) -> Watch? {
        guard let watch = data.activeWatch, watch.expiresAt > now else { return nil }
        return watch
    }

    /// The home section has no title, footer or placeholder without a current preview.
    /// A scheduled announcement remains pending even after its advertised time passes.
    func hasVisiblePreview(at now: Date) -> Bool {
        data.scheduledReset != nil || activeWatch(at: now) != nil
    }

    static let sourceURL = URL(string: "https://codex-resets.com")!

    static func dateText(_ date: Date, locale: Locale = .autoupdatingCurrent,
                         timeZone: TimeZone = .autoupdatingCurrent) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened,
                                       locale: locale, timeZone: timeZone))
    }

    static func chanceText(_ chance: Int?, locale: Locale = .autoupdatingCurrent) -> String? {
        guard let chance, (0...100).contains(chance) else { return nil }
        return (Double(chance) / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// Shared by the app card and notification title. The exact local date accompanies this headline.
    static func scheduledPreviewHeadline(for date: Date?, at now: Date, language: String? = nil,
                                         locale: Locale = .autoupdatingCurrent) -> String {
        guard let date else { return L10n.text("时间待定", language: language) }
        guard date > now else { return L10n.text("待确认", language: language) }
        let effectiveLanguage = language ?? L10n.languageOverride ?? Bundle.main.preferredLocalizations.first ?? "en"
        let isChinese = effectiveLanguage.hasPrefix("zh-Hans") || effectiveLanguage.hasPrefix("zh-CN")
        var localeComponents = Locale.Components(locale: locale)
        localeComponents.languageComponents.languageCode = Locale.LanguageCode(isChinese ? "zh" : "en")
        localeComponents.languageComponents.script = isChinese ? Locale.Script("Hans") : nil
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(components: localeComponents)
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .full
        // Round so 1h 59m does not read as "1 hour".
        let remaining = date.timeIntervalSince(now)
        let components: DateComponents
        if remaining >= 86_400 {
            components = DateComponents(day: Int((remaining / 86_400).rounded()))
        } else if remaining >= 3_600 {
            components = DateComponents(hour: Int((remaining / 3_600).rounded()))
        } else if remaining >= 60 {
            components = DateComponents(minute: Int((remaining / 60).rounded()))
        } else {
            components = DateComponents(second: max(1, Int(remaining.rounded())))
        }
        return formatter.localizedString(from: components)
    }

    func previewNotification(at now: Date, language: String? = nil,
                             locale: Locale = .autoupdatingCurrent,
                             timeZone: TimeZone = .autoupdatingCurrent) -> ReminderNotification? {
        // Do not notify from stale server caches. A scheduled time passing is not execution evidence.
        guard abs(meta.generatedAt.timeIntervalSince(now)) < 24 * 60 * 60 else { return nil }
        if let reset = data.scheduledReset {
            let headline = Self.scheduledPreviewHeadline(for: reset.scheduledFor, at: now, language: language, locale: locale)
            let body = reset.scheduledFor.map {
                L10n.format("%@ · 本地时间", Self.dateText($0, locale: locale, timeZone: timeZone), language: language, locale: locale)
            } ?? L10n.text("第三方预告 · Codex Resets", language: language)
            return ReminderNotification(identifier: "codex.preview.scheduled.\(reset.id)",
                title: L10n.format("Codex 重置预告 · %@", headline, language: language, locale: locale),
                body: body,
                kind: .codexResetPreview)
        }
        if let watch = activeWatch(at: now) {
            let title: String
            if let chance = Self.chanceText(watch.resetChancePercent, locale: locale) {
                title = L10n.format("Codex 重置预测 · %@", chance, language: language, locale: locale)
            } else {
                title = L10n.text("Codex 重置预测", language: language)
            }
            return ReminderNotification(identifier: "codex.preview.watch.\(watch.observedAt.timeIntervalSince1970)",
                title: title,
                body: L10n.format("%@ · AI 预测 · 非官方", watch.forecastWindow, language: language, locale: locale),
                kind: .codexResetPreview)
        }
        return nil
    }

}
