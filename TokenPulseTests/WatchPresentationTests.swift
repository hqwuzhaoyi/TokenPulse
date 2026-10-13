import Foundation
import XCTest
@testable import TokenPulse

/// Watch reads the same cached domain state locally and resolves its own native resources.
final class WatchPresentationTests: XCTestCase {
    func testWatchCacheUsesItsLanguageWithoutRewritingAccountsCountsOrDateOnlyBoundary() async throws {
        let suite = "com.tokenpulse.tests.watch-presentation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LocalAccountStateStore(suiteName: suite)
        let account = SubscriptionAccount(name: "演示 · 我的 Claude workspace Ω", provider: .claude)
        let remaining = try XCTUnwrap(Decimal(string: "0.123456789012345678901234567890"))
        let reset = try XCTUnwrap(ProviderHTTP.isoDate("2026-11-01T00:00:00Z"))
        let window = QuotaWindow(id: "claude.weekly", name: "每周额度", scope: nil, period: .weekly,
            usedPercentage: 25, remainingCount: nil, totalCount: nil, resetsAt: reset,
            unit: "requests", exactCounts: .init(remaining: remaining, total: 1), resetDatePrecision: .day)
        let unknown = QuotaWindow(id: "service.custom", name: "用户模型 Limit Ω", scope: "我的团队 / Team A",
            usedPercentage: nil, remainingCount: 3, totalCount: nil, resetsAt: nil, unit: "unknown-unit Ω")
        let snapshot = QuotaSnapshot(accountID: account.id, windows: [window, unknown], collectedAt: reset)
        let original = AccountQuotaState(account: account, snapshot: snapshot, lastFailure: .network)
        try await store.save([original])
        let archive = defaults.data(forKey: "accountQuotaStates")
        let loaded = try await store.load()
        let cached = try XCTUnwrap(loaded.first)
        for language in ["zh-Hans", "en"] {
            L10n.withLanguage(language) {
                XCTAssertEqual(L10n.demoAccountName(cached.account), account.name)
                XCTAssertEqual(L10n.windowDisplayName(window, provider: account.provider), language == "en" ? "Weekly Quota" : "每周额度")
                XCTAssertEqual(QuotaFormatting.totalLabel(window), language == "en" ? "Total" : "总量")
                XCTAssertTrue(QuotaFormatting.count(remaining, window: window).contains("0.12345678901234567890123456789"))
                XCTAssertEqual(QuotaFormatting.nextEventValue(window), "2026-11-01")
                XCTAssertEqual(L10n.windowDisplayName(unknown, provider: account.provider), "我的团队 / Team A 用户模型 Limit Ω")
                XCTAssertEqual(L10n.windowUnit(unknown), "unknown-unit Ω")
                XCTAssertEqual(QuotaFormatting.quotaStatus("Provider 原文 Ω", provider: .claude), "Provider 原文 Ω")
                XCTAssertEqual(cached.lastFailure?.displayName, language == "en" ? "Network connection failed" : "网络连接失败")
            }
        }
        XCTAssertEqual(cached, original)
        XCTAssertEqual(defaults.data(forKey: "accountQuotaStates"), archive)
        let restored = try await store.load()
        XCTAssertEqual(restored, [original])
    }

    func testDifferentPhoneAndWatchLanguagesPreserveIndependentNousAuthorizationChains() throws {
        let accountID = UUID()
        func chain(device: String) throws -> ProviderCredentialEnvelope {
            var envelope = ProviderCredentialEnvelope(provider: .nousPortal, kind: .oauth,
                accessToken: "fixture-access-\(device)", refreshToken: "fixture-refresh-\(device)",
                expiresAt: Date(timeIntervalSince1970: 2_000_000_000), accountID: "same-service-user",
                metadata: ["nousSessionFormat": "device-v1", "portal": NousPortalCredential.portal,
                           "localAccountID": accountID.uuidString, "ownerDeviceID": device,
                           "clientID": NousPortalCredential.clientID, "credentialDistribution": "deviceLocal",
                           "organizationID": "same-organization"])
            envelope.metadata["sourceCredentialFingerprint"] = try NousPortalCredential.fingerprint(envelope)
            return envelope
        }
        let phone = try chain(device: "phone"), watch = try chain(device: "watch")
        let savedPhone = try phone.encoded(), savedWatch = try watch.encoded()
        try L10n.withLanguage("zh-Hans") { try NousPortalCredential.validateLocal(phone, accountID: accountID, deviceID: "phone") }
        try L10n.withLanguage("en") { try NousPortalCredential.validateLocal(watch, accountID: accountID, deviceID: "watch") }
        XCTAssertEqual(try NousPortalCredential.identity(phone), try NousPortalCredential.identity(watch))
        XCTAssertEqual(phone.sourceCredentialIdentity, watch.sourceCredentialIdentity)
        XCTAssertNotEqual(phone.accessToken, watch.accessToken)
        XCTAssertNotEqual(phone.refreshToken, watch.refreshToken)
        XCTAssertThrowsError(try NousPortalCredential.validateLocal(phone, accountID: accountID, deviceID: "watch"))
        try L10n.withLanguage("zh-Hans") { try NousPortalCredential.validateLocal(watch, accountID: accountID, deviceID: "watch") }
        XCTAssertEqual(try phone.encoded(), savedPhone)
        XCTAssertEqual(try watch.encoded(), savedWatch)
    }

    @MainActor
    func testWatchDemoRefreshAndFavoriteSelectionRemainLocalAcrossLanguages() async throws {
        let suite = "com.tokenpulse.tests.watch-refresh.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let monitor = DemoMode.makeMonitor(suiteName: suite)
        await monitor.start(refresh: false)
        let initial = try XCTUnwrap(monitor.states.first { $0.account.provider == .claude })
        await monitor.updateWatchFavorite(false, accountID: initial.id)
        XCTAssertFalse(monitor.configuration(for: initial.id)?.isWatchFavorite ?? true)
        for language in ["zh-Hans", "en"] {
            await L10n.withLanguage(language) { await monitor.refresh(accountID: initial.id) }
            let current = try XCTUnwrap(monitor.states.first { $0.id == initial.id })
            XCTAssertEqual(current.account, initial.account)
            XCTAssertNil(current.lastFailure)
            XCTAssertNotEqual(current.snapshot?.windows, initial.snapshot?.windows)
            XCTAssertFalse(monitor.configuration(for: initial.id)?.isWatchFavorite ?? true)
            XCTAssertEqual(L10n.demoAccountName(current.account, language: language), language == "en" ? "Demo · Claude" : "演示 · Claude")
        }
        let restored = DemoMode.makeMonitor(suiteName: suite)
        await restored.start(refresh: false)
        XCTAssertEqual(restored.states, monitor.states)
        XCTAssertEqual(restored.configuration(for: initial.id)?.isWatchFavorite, false)
    }
}
