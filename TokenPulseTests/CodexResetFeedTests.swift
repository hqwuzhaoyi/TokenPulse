import Foundation
import Testing
@testable import TokenPulse

struct CodexResetFeedTests {
    private let now = Date(timeIntervalSince1970: 1_791_720_000)

    private func fixture(latest: String = "null", scheduled: String = "null", watch: String = "null") -> Data {
        Data("""
        {"data":{"latest_reset":\(latest),"scheduled_reset":\(scheduled),"active_watch":\(watch)},
         "meta":{"generated_at":"2026-10-11T12:00:00.000Z"}}
        """.utf8)
    }

    private var scheduled: String {
        """
        {"id":"event-1","reset_type":"banked","announced_at":"2026-10-11T11:00:00Z",
         "scheduled_for":"2026-10-11T11:30:00.000Z","text":"Reset coming"}
        """
    }

    private func watch(expires: String) -> String {
        """
        {"level":"strong","reset_chance_percent":80,"forecast_window":"Today",
         "observed_at":"2026-10-11T11:00:00Z","expires_at":"\(expires)","text":"Possible reset"}
        """
    }

    @Test(arguments: ["zh-Hans", "en"]) func nullStatusHasNoPreview(language: String) throws {
        let status = try CodexResetStatus.decode(fixture())
        L10n.withLanguage(language) {
            #expect(!status.hasVisiblePreview(at: now))
            #expect(status.previewNotification(at: now) == nil)
        }
    }

    @Test(arguments: ["zh-Hans", "en"]) func passedScheduleIsStillAnAnnouncementNotAConfirmedReset(language: String) throws {
        let status = try CodexResetStatus.decode(fixture(scheduled: scheduled))
        let notification = try #require(status.previewNotification(at: now, language: language))
        #expect(status.hasVisiblePreview(at: now))
        #expect(notification.kind == .codexResetPreview)
        #expect(notification.title == (language == "en" ? "Codex Reset Preview · Awaiting confirmation" : "Codex 重置预告 · 待确认"))
        #expect(notification.body.contains(language == "en" ? "Local time" : "本地时间"))
        #expect(!notification.body.contains("Reset coming"))
        #expect(!notification.body.contains("https://codex-resets.com"))
    }

    @Test(arguments: ["zh-Hans", "en"]) func upcomingNotificationHighlightsTimeAndKeepsExactLocalDate(language: String) throws {
        let future = scheduled.replacingOccurrences(of: "11:30:00.000Z", with: "14:00:00.000Z")
        let status = try CodexResetStatus.decode(fixture(scheduled: future))
        let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let locale = Locale(identifier: "en_GB")
        let localNotice = try #require(status.previewNotification(at: now, language: language, locale: locale, timeZone: shanghai))
        let utcNotice = try #require(status.previewNotification(at: now, language: language, locale: locale, timeZone: utc))
        #expect(localNotice.title == (language == "en" ? "Codex Reset Preview · in 2 hours" : "Codex 重置预告 · 2小时后"))
        #expect(localNotice.title == utcNotice.title)
        #expect(localNotice.body.contains("22:00"))
        #expect(utcNotice.body.contains("14:00"))
        #expect(localNotice.body.hasSuffix(language == "en" ? "Local time" : "本地时间"))
        #expect(localNotice.identifier == "codex.preview.scheduled.event-1")
        #expect(!localNotice.body.contains("Reset coming"))
    }

    @Test func headlineRoundsDurationAndUsesAppLanguageRatherThanRegion() {
        let date = now.addingTimeInterval(7_199)
        #expect(CodexResetStatus.scheduledPreviewHeadline(for: date, at: now, language: "en", locale: Locale(identifier: "zh_CN")) == "in 2 hours")
        #expect(CodexResetStatus.scheduledPreviewHeadline(for: date, at: now, language: "zh-Hans", locale: Locale(identifier: "en_US")) == "2小时后")
        #expect(CodexResetStatus.scheduledPreviewHeadline(for: now, at: now, language: "en") == "Awaiting confirmation")
        #expect(CodexResetStatus.scheduledPreviewHeadline(for: nil, at: now, language: "en") == "Time to be determined")
    }

    @Test(arguments: ["zh-Hans", "en"]) func expiredWatchCannotNotify(language: String) throws {
        let status = try CodexResetStatus.decode(fixture(watch: watch(expires: "2026-10-11T11:59:59Z")))
        #expect(status.activeWatch(at: now) == nil)
        #expect(!status.hasVisiblePreview(at: now))
        #expect(status.previewNotification(at: now, language: language) == nil)
    }

    @Test(arguments: ["zh-Hans", "en"]) func watchIsExplicitlyUnconfirmedAndScheduledAnnouncementTakesPriority(language: String) throws {
        let rawWatch = watch(expires: "2026-10-12T12:00:00Z")
        let forecast = try CodexResetStatus.decode(fixture(watch: rawWatch))
        let notification = try #require(forecast.previewNotification(at: now, language: language, locale: Locale(identifier: "en_US")))
        #expect(notification.body.contains(language == "en" ? "Unofficial" : "非官方"))
        #expect(notification.body.contains("Today"))
        #expect(notification.title == (language == "en" ? "Codex Reset Forecast · 80%" : "Codex 重置预测 · 80%"))
        #expect(!notification.body.contains("80%"))
        #expect(!notification.body.contains(language == "en" ? "valid until" : "有效至"))
        #expect(!notification.body.contains("Possible reset"))
        let both = try CodexResetStatus.decode(fixture(scheduled: scheduled, watch: rawWatch))
        #expect(both.previewNotification(at: now, language: language)?.identifier == "codex.preview.scheduled.event-1")
        #expect(both.previewNotification(at: now.addingTimeInterval(86_401), language: language) == nil)
    }

    @Test(arguments: ["zh-Hans", "en"]) func historyOnlyAndExpiredOrCancelledForecastHaveNoSection(language: String) throws {
        let history = try CodexResetStatus.decode(fixture(latest: scheduled))
        let valid = try CodexResetStatus.decode(fixture(watch: watch(expires: "2026-10-11T12:00:01Z")))
        let cancelled = try CodexResetStatus.decode(fixture())
        L10n.withLanguage(language) {
            #expect(history.data.latestReset != nil)
            #expect(!history.hasVisiblePreview(at: now))
            #expect(history.previewNotification(at: now) == nil)
            #expect(valid.hasVisiblePreview(at: now))
            #expect(!valid.hasVisiblePreview(at: now.addingTimeInterval(1)))
            #expect(!cancelled.hasVisiblePreview(at: now))
            #expect(cancelled.previewNotification(at: now) == nil)
        }
    }

    @Test func rawSourceTextWindowAndIdentifiersSurviveLanguageChanges() throws {
        let rawText = "设置 · 80% · %@ (original source)"
        let rawAnnouncement = scheduled.replacingOccurrences(of: "Reset coming", with: rawText)
        let status = try CodexResetStatus.decode(fixture(scheduled: rawAnnouncement))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let original = try encoder.encode(status)
        let zh = try #require(status.previewNotification(at: now, language: "zh-Hans"))
        let en = try #require(status.previewNotification(at: now, language: "en"))
        let fallback = try #require(status.previewNotification(at: now, language: "fr"))
        #expect(!zh.body.contains(rawText))
        #expect(!en.body.contains(rawText))
        #expect(en.title != zh.title)
        #expect(fallback == en)
        #expect(en.identifier == zh.identifier)
        #expect(en.kind == zh.kind)
        #expect(status.data.scheduledReset?.text == rawText)
        #expect(try encoder.encode(status) == original)
        let rawForecast = watch(expires: "2026-10-12T12:00:00Z")
            .replacingOccurrences(of: "Today", with: "设置")
            .replacingOccurrences(of: "Possible reset", with: "取消 · 80% · %@ 原文")
        let forecast = try CodexResetStatus.decode(fixture(watch: rawForecast))
        for language in ["zh-Hans", "en"] {
            let notice = try #require(forecast.previewNotification(at: now, language: language))
            #expect(notice.body.contains("设置"))
            #expect(!notice.body.contains("取消 · 80% · %@ 原文"))
        }
        #expect(forecast.data.activeWatch?.forecastWindow == "设置")
        #expect(forecast.data.activeWatch?.text == "取消 · 80% · %@ 原文")
        #expect(CodexResetStatus.sourceURL.absoluteString == "https://codex-resets.com")
    }

    @Test func unspecifiedScheduleTimeAndProbabilityStayUnknown() throws {
        let unspecified = scheduled.replacingOccurrences(of: "\"2026-10-11T11:30:00.000Z\"", with: "null")
        let status = try CodexResetStatus.decode(fixture(scheduled: unspecified))
        #expect(status.data.scheduledReset?.scheduledFor == nil)
        #expect(status.previewNotification(at: now, language: "en")?.title == "Codex Reset Preview · Time to be determined")
        #expect(status.previewNotification(at: now, language: "zh-Hans")?.title == "Codex 重置预告 · 时间待定")
        for chance in [nil, -1, 101] as [Int?] { #expect(CodexResetStatus.chanceText(chance) == nil) }
        let unknownChance = try CodexResetStatus.decode(fixture(watch: watch(expires: "2026-10-12T12:00:00Z").replacingOccurrences(of: "80", with: "null")))
        let notice = try #require(unknownChance.previewNotification(at: now, language: "en"))
        #expect(!notice.body.contains("probability"))
        #expect(notice.title == "Codex Reset Forecast")
        #expect(notice.body == "Today · AI forecast · Unofficial")
    }

    @Test(arguments: ["zh-Hans", "en"]) func widgetPreviewPrioritizesAnnouncementsAndExpiresForecasts(language: String) throws {
        let expiry = now.addingTimeInterval(1)
        let forecast = try CodexResetStatus.decode(fixture(watch: watch(expires: "2026-10-11T12:00:01Z")))
        var account = WidgetAccountSnapshot(account: SubscriptionAccount(name: "Codex", provider: .codex),
                                           windows: [], collectedAt: now, lastFailure: nil, codexResetStatus: forecast)
        L10n.withLanguage(language) {
            #expect(WidgetContentPresentation.resetPreview(account, at: now)?.contains("80") == true)
            #expect(WidgetContentPresentation.resetPreview(account, at: expiry) == nil)
        }
        let entry = QuotaWidgetEntry(date: now, accounts: [account], selectionRequired: false,
                                    accountSelectionMissing: false, hasAvailableAccounts: true)
        #expect(entry.timelineDates == [expiry])
        account.codexResetStatus = try CodexResetStatus.decode(fixture(scheduled: scheduled, watch: watch(expires: "2026-10-11T12:00:01Z")))
        account.codexResetUnavailable = true
        L10n.withLanguage(language) {
            let summary = WidgetContentPresentation.resetPreview(account, at: expiry)
            #expect(summary?.contains(language == "en" ? "Reset preview" : "重置预告") == true)
            #expect(summary?.contains(language == "en" ? "Awaiting confirmation" : "待确认") == true)
            #expect(summary?.contains(language == "en" ? "Cached" : "旧数据") == true)
            #expect(summary?.contains("80") == false)
        }
        account.codexResetStatus = try CodexResetStatus.decode(fixture(latest: scheduled))
        #expect(WidgetContentPresentation.resetPreview(account, at: now) == nil)
    }

    @Test func widgetTimelineChangesAtScheduledTimeWithoutClaimingAReset() throws {
        let future = scheduled.replacingOccurrences(of: "11:30:00.000Z", with: "12:30:00.000Z")
        let status = try CodexResetStatus.decode(fixture(scheduled: future))
        let account = WidgetAccountSnapshot(account: SubscriptionAccount(name: "Codex", provider: .codex),
                                           windows: [], collectedAt: now, lastFailure: nil, codexResetStatus: status)
        let entry = QuotaWidgetEntry(date: now, accounts: [account], selectionRequired: false,
                                    accountSelectionMissing: false, hasAvailableAccounts: true)
        #expect(entry.timelineDates == [now.addingTimeInterval(1_800)])
        L10n.withLanguage("en") {
            #expect(WidgetContentPresentation.resetPreview(account, at: now)?.contains("Awaiting confirmation") == false)
            #expect(WidgetContentPresentation.resetPreview(account, at: now.addingTimeInterval(1_800))?.contains("Awaiting confirmation") == true)
        }
    }

    @Test func widgetStorageCarriesPreviewOnlyForCodexAndClearsCancelledPreview() async throws {
        let suite = "CodexResetFeedTests.widget.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = WidgetSnapshotStore(defaults: UserDefaults(suiteName: suite))
        let status = try CodexResetStatus.decode(fixture(scheduled: scheduled))
        let states = [Provider.codex, .superGrok].map {
            AccountQuotaState(account: SubscriptionAccount(name: "Account", provider: $0))
        }
        try await store.save(states: states, codexResetStatus: status, codexResetUnavailable: true)
        let saved = await store.load()
        #expect(saved[0].codexResetStatus == status)
        #expect(saved[0].codexResetUnavailable == true)
        #expect(saved[1].codexResetStatus == nil)
        #expect(WidgetContentPresentation.resetPreview(saved[1], at: now) == nil)
        let cancelled = try CodexResetStatus.decode(fixture())
        try await store.save(states: states, codexResetStatus: cancelled)
        let cleared = await store.load()
        #expect(cleared[0].codexResetUnavailable == false)
        #expect(WidgetContentPresentation.resetPreview(cleared[0], at: now) == nil)
        try await store.save(states: states, isDemoMode: true, codexResetStatus: status)
        #expect(await store.load() == cleared)
        await store.setDemoMode(true)
        #expect(await store.load().first?.codexResetStatus == status)
    }

    @Test func legacyWidgetSnapshotDecodesWithoutPreviewFields() throws {
        let account = WidgetAccountSnapshot(account: SubscriptionAccount(name: "Legacy", provider: .codex),
                                           windows: [], collectedAt: now, lastFailure: nil)
        let encoded = try JSONEncoder().encode(account)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["codexResetStatus"] == nil)
        #expect(object["codexResetUnavailable"] == nil)
        let decoded = try JSONDecoder().decode(WidgetAccountSnapshot.self, from: encoded)
        #expect(decoded == account)
        #expect(WidgetContentPresentation.resetPreview(decoded, at: now) == nil)
    }

    @Test func probabilityKeepsRegionalPercentFormattingAndExactReportedBoundaries() {
        #expect(CodexResetStatus.chanceText(0, locale: Locale(identifier: "en_US")) == "0%")
        #expect(CodexResetStatus.chanceText(80, locale: Locale(identifier: "en_US")) == "80%")
        #expect(CodexResetStatus.chanceText(100, locale: Locale(identifier: "en_US")) == "100%")
        #expect(CodexResetStatus.chanceText(80, locale: Locale(identifier: "de_DE")) == "80\u{00a0}%")
    }

    @Test @MainActor func failedRefreshKeepsPreviewButSuccessfulCancellationHidesIt() async throws {
        let suite = "CodexResetFeedTests.recovery.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let monitor = DemoMode.makeMonitor(suiteName: suite)
        await monitor.start(refresh: false)
        let account = try #require(monitor.states.first { $0.account.provider == .codex })
        let preview = try CodexResetStatus.decode(fixture(watch: watch(expires: "2026-10-12T12:00:00Z")))
        let cancellation = try CodexResetStatus.decode(fixture())
        var requests = 0
        monitor.fetchCodexResets = {
            requests += 1
            if requests == 1 { return preview }
            if requests == 2 { throw URLError(.notConnectedToInternet) }
            return cancellation
        }
        await monitor.refresh(accountID: account.id)
        #expect(monitor.codexResetStatus == preview)
        #expect(!monitor.codexResetUnavailable)
        await monitor.refresh(accountID: account.id)
        #expect(monitor.codexResetStatus == preview)
        #expect(monitor.codexResetUnavailable)
        for language in ["zh-Hans", "en"] {
            L10n.withLanguage(language) { #expect(monitor.codexResetStatus?.hasVisiblePreview(at: now) == true) }
        }
        await monitor.refresh(accountID: account.id)
        #expect(monitor.codexResetStatus == cancellation)
        #expect(!monitor.codexResetUnavailable)
        #expect(monitor.codexResetStatus?.hasVisiblePreview(at: now) == false)
        #expect(requests == 3)
        #expect(monitor.configuration(for: account.id)?.account == account.account)
    }

    @Test func requestsArePublicAndSharedAcrossRefreshes() async throws {
        let transport = ResetFeedTransport(data: fixture(scheduled: scheduled), status: 200)
        let feed = CodexResetFeed(transport: transport)
        async let first = feed.status()
        async let second = feed.status()
        let values = try await (first, second)
        #expect(values.0 == values.1)
        _ = try await feed.status()
        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests.first?.url?.absoluteString == "https://codex-resets.com/api/v1/status")
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(requests.first?.value(forHTTPHeaderField: "ChatGPT-Account-Id") == nil)
    }

    @Test func rateLimitBacksOffWithoutRetryingForEveryAccount() async {
        let transport = ResetFeedTransport(data: Data(), status: 429)
        let feed = CodexResetFeed(transport: transport)
        for _ in 0..<3 {
            do { _ = try await feed.status(); Issue.record("Expected unavailable") }
            catch { }
        }
        #expect(await transport.requests.count == 1)
    }

    @Test @MainActor func notificationsRespectSettingsAndPersistDeduplication() async throws {
        let suite = "CodexResetFeedTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let adapter = ResetPreviewAdapter()
        let status = try CodexResetStatus.decode(fixture(scheduled: scheduled))
        var configuration = AccountConfiguration(account: SubscriptionAccount(name: "Codex", provider: .codex))
        let disabledRuntime = NotificationRuntime(defaults: defaults, adapter: adapter)
        try await disabledRuntime.codexResetPreview(status, configurations: [configuration], now: now)
        #expect(await adapter.operations.isEmpty)
        defaults.set(true, forKey: "notificationsEnabled")
        let runtime = NotificationRuntime(defaults: defaults, adapter: adapter)
        configuration.reminders.resetRemindersEnabled = false
        try await runtime.codexResetPreview(status, configurations: [configuration], now: now)
        #expect(await adapter.operations.isEmpty)
        configuration.reminders.resetRemindersEnabled = true
        try await L10n.withLanguage("zh-Hans") {
            try await runtime.codexResetPreview(status, configurations: [configuration, configuration], now: now)
        }
        let restored = NotificationRuntime(defaults: defaults, adapter: adapter)
        try await L10n.withLanguage("en") {
            try await runtime.codexResetPreview(status, configurations: [configuration], now: now)
        }
        #expect(await adapter.operations.count == 1)
        let operation = try #require(await adapter.operations.first)
        guard case .deliver(let delivered) = operation else { Issue.record("Expected an immediate preview delivery"); return }
        #expect(delivered.title == "Codex 重置预告 · 待确认")
        #expect(delivered.identifier == "codex.preview.scheduled.event-1")
        #expect(defaults.stringArray(forKey: "codexResetPreviewDelivered") == [delivered.identifier])
        #expect(configuration.reminders.resetRemindersEnabled)
    }
}

private actor ResetFeedTransport: ProviderTransport {
    let payload: Data
    let status: Int
    var requests: [URLRequest] = []
    init(data: Data, status: Int) { payload = data; self.status = status }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return (payload, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                        headerFields: ["Retry-After": "600", "ETag": "fixture"])!)
    }
}

private actor ResetPreviewAdapter: NotificationApplying {
    var operations: [NotificationOperation] = []
    @MainActor func configure() {}
    func requestAuthorization() async throws -> Bool { true }
    func authorizationStatus() async -> NotificationAuthorizationStatus { .authorized }
    func apply(_ operations: [NotificationOperation]) async throws { self.operations += operations }
}
