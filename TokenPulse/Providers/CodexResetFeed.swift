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

    func previewNotification(at now: Date, language: String? = nil,
                             locale: Locale = .autoupdatingCurrent,
                             timeZone: TimeZone = .autoupdatingCurrent) -> ReminderNotification? {
        // Do not notify from stale server caches. A scheduled time passing is not execution evidence.
        guard abs(meta.generatedAt.timeIntervalSince(now)) < 24 * 60 * 60 else { return nil }
        if let reset = data.scheduledReset {
            let time = reset.scheduledFor.map { Self.dateText($0, locale: locale, timeZone: timeZone) }
                ?? L10n.text("时间待定", language: language)
            return ReminderNotification(identifier: "codex.preview.scheduled.\(reset.id)",
                title: L10n.text(reset.resetType == "banked" ? "Codex 重置次数发放预告" : "Codex 重置预告", language: language),
                body: L10n.format("%@，等待执行确认。%@ · 来源 %@", time, reset.text, Self.sourceURL.absoluteString, language: language, locale: locale),
                kind: .codexResetPreview)
        }
        if let watch = activeWatch(at: now) {
            let expires = Self.dateText(watch.expiresAt, locale: locale, timeZone: timeZone)
            let body: String
            if let chance = Self.chanceText(watch.resetChancePercent, locale: locale) {
                body = L10n.format("%@；预测概率 %@；有效至 %@。%@ · 来源 %@", watch.forecastWindow, chance,
                                   expires, watch.text, Self.sourceURL.absoluteString, language: language, locale: locale)
            } else {
                body = L10n.format("%@；有效至 %@。%@ · 来源 %@", watch.forecastWindow, expires, watch.text,
                                   Self.sourceURL.absoluteString, language: language, locale: locale)
            }
            return ReminderNotification(identifier: "codex.preview.watch.\(watch.observedAt.timeIntervalSince1970)",
                title: L10n.text("Codex 重置预测（非官方承诺）", language: language),
                body: body, kind: .codexResetPreview)
        }
        return nil
    }

}

actor CodexResetFeed {
    private let transport: any ProviderTransport
    private let now: @Sendable () -> Date
    private var cached: CodexResetStatus?
    private var lastRequestSucceeded = false
    private var etag: String?
    private var nextRequestAt = Date.distantPast
    private var inFlight: Task<CodexResetStatus, Error>?

    init(transport: any ProviderTransport = URLSessionProviderTransport(),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.now = now
    }

    func status() async throws -> CodexResetStatus {
        if let inFlight { return try await inFlight.value }
        guard now() >= nextRequestAt else {
            if lastRequestSucceeded, let cached { return cached }
            throw URLError(.resourceUnavailable)
        }
        var request = URLRequest(url: URL(string: "https://codex-resets.com/api/v1/status")!)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        let task = Task { try await self.fetch(request) }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    private func fetch(_ request: URLRequest) async throws -> CodexResetStatus {
        // One public request per five minutes, shared by all Codex accounts, including on failure.
        lastRequestSucceeded = false
        nextRequestAt = now().addingTimeInterval(300)
        let (data, rawResponse) = try await transport.data(for: request)
        guard let response = rawResponse as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 304, let cached {
            lastRequestSucceeded = true
            return cached
        }
        if response.statusCode == 429 {
            let delay = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 300
            if delay.isFinite { nextRequestAt = now().addingTimeInterval(max(300, delay)) }
        }
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        let status = try CodexResetStatus.decode(data)
        lastRequestSucceeded = true
        cached = status
        etag = response.value(forHTTPHeaderField: "ETag")
        return status
    }
}
