import Foundation
import XCTest
@testable import TokenPulse

final class AugmentCodeProviderTests: XCTestCase {
    private let credits = #"{"usageUnitsRemaining":15,"usageUnitsConsumedThisBillingCycle":10,"usageUnitsAvailable":100,"usageBalanceStatus":"active"}"#
    private let subscription = #"{"planName":"Pro","billingPeriodEnd":"2026-11-01T00:00:00Z"}"#

    func testProfileExtractsOnlyOwnSessionAndBindsAccountExpiryOrigin() async throws {
        let id = UUID(), date = Date(timeIntervalSince1970: 100)
        let choices = try await AugmentCodeProviderClient.loginProfile.makeCredentials([
            cookie("_session", "fake", domain: "app.augmentcode.com", expiry: date.addingTimeInterval(300)),
            cookie("web_rpc_proxy_session", "proxy", domain: ".augmentcode.com"),
            cookie("tracking", "ignored", domain: "app.augmentcode.com"),
            cookie("_session", "other", domain: "evil.example"),
        ], [:], id, date)
        XCTAssertEqual(choices.count, 1)
        let value = try ProviderCredentialEnvelope.decode(choices[0].credential, expectedProvider: .augmentCode)
        XCTAssertTrue(value.accessToken.contains("_session=fake"))
        XCTAssertTrue(value.accessToken.contains("web_rpc_proxy_session=proxy"))
        XCTAssertFalse(value.accessToken.contains("tracking"))
        XCTAssertEqual(value.expiresAt, date.addingTimeInterval(300))
        try WebProviderSession.validate(value, provider: .augmentCode, accountID: id, origins: [AugmentCodeProviderClient.origin], now: date)
        XCTAssertThrowsError(try WebProviderSession.validate(value, provider: .augmentCode, accountID: UUID(), origins: [AugmentCodeProviderClient.origin], now: date))
        XCTAssertThrowsError(try WebProviderSession.validate(value, provider: .augmentCode, accountID: id, origins: [AugmentCodeProviderClient.origin], now: date.addingTimeInterval(301)))
        XCTAssertFalse(AugmentCodeProviderClient.loginProfile.permits(URL(string: "https://evil.example")))
        XCTAssertNotNil(Provider.augmentCode.webLoginProfile)
        XCTAssertEqual(ProviderAuthenticationController().loginConfiguration(for: .augmentCode).method, .webSession)
    }

    func testTwoReadOnlyRoutesUseCookieAndOptionalSubscriptionFailureKeepsCredits() async throws {
        let id = UUID(), date = Date(timeIntervalSince1970: 100)
        let transport = AugmentTransport([(200, credits), (500, "{}")])
        let client = ProviderQuotaClient(provider: .augmentCode, transport: transport, now: { date })
        let snapshot = try await client.quota(for: id, credential: credential(id: id, value: "first", date: date))
        XCTAssertEqual(snapshot.accountID, id)
        XCTAssertEqual(snapshot.collectedAt, date)
        XCTAssertEqual(snapshot.windows[0].exactCounts?.used, 10)
        XCTAssertEqual(snapshot.windows[0].exactCounts?.remaining, 15)
        XCTAssertNil(snapshot.windows[0].resetsAt)
        XCTAssertNil(snapshot.providerPlanName)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/credits", "/api/subscription"])
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Cookie") == "_session=first" && $0.value(forHTTPHeaderField: "Authorization") == nil && !$0.httpShouldHandleCookies && $0.cachePolicy == .reloadIgnoringLocalCacheData })
    }

    func testAvailableNeverBecomesDenominatorOrMoneyAndMissingFieldsStayUnknown() throws {
        let id = UUID(), date = Date(timeIntervalSince1970: 100)
        let snapshot = try AugmentCodeProviderClient.snapshot(credits: Data(credits.utf8), subscription: Data(subscription.utf8), accountID: id, collectedAt: date)
        let window = snapshot.windows[0]
        XCTAssertNil(window.usedPercentage)
        XCTAssertNil(window.totalCount)
        XCTAssertNil(window.exactCounts?.total)
        XCTAssertNil(window.wallet)
        XCTAssertNil(window.isExhausted)
        XCTAssertNotNil(window.resetsAt)
        XCTAssertEqual(snapshot.providerPlanName, "Pro")
        XCTAssertTrue(QuotaFormatting.usage(window).contains("已用"))
        XCTAssertTrue(QuotaFormatting.usage(window).contains("剩余"))
        let onlyUsed = try AugmentCodeProviderClient.snapshot(credits: Data(#"{"usageUnitsConsumedThisBillingCycle":10}"#.utf8), subscription: nil, accountID: id, collectedAt: date)
        XCTAssertNil(onlyUsed.windows[0].exactCounts?.remaining)
        XCTAssertThrowsError(try AugmentCodeProviderClient.snapshot(credits: Data(#"{"usageUnitsAvailable":100}"#.utf8), subscription: nil, accountID: id, collectedAt: date)) { XCTAssertEqual($0 as? RefreshFailure, .noQuotaWindows) }
    }

    func testInvalidNumbersHtmlAndAbsentSessionCannotBecomeSuccessfulZero() async throws {
        for body in ["<html>Sign in</html>", "[]", #"{"usageUnitsConsumedThisBillingCycle":true}"#, #"{"usageUnitsRemaining":-1}"#, #"{"usageUnitsRemaining":"nan"}"#] {
            XCTAssertThrowsError(try AugmentCodeProviderClient.snapshot(credits: Data(body.utf8), subscription: nil, accountID: UUID(), collectedAt: Date())) { XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse) }
        }
        XCTAssertThrowsError(try AugmentCodeProviderClient.policy.select([cookie("tracking", "ignored", domain: "app.augmentcode.com")], now: Date()))
        let id = UUID(), date = Date(timeIntervalSince1970: 100), transport = AugmentTransport([])
        var envelope = try ProviderCredentialEnvelope.decode(credential(id: id, value: "first", date: date), expectedProvider: .augmentCode)
        envelope.accessToken = "_session=second"
        do { _ = try await ProviderQuotaClient(provider: .augmentCode, transport: transport, now: { date }).quota(for: id, credential: envelope.encoded()); XCTFail("Tampered session") }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testCountersDoNotTriggerPercentageAlertButExplicitCycleEndSchedulesExpectedReset() throws {
        let now = Date(timeIntervalSince1970: 100), id = UUID()
        let snapshot = try AugmentCodeProviderClient.snapshot(credits: Data(credits.utf8), subscription: Data(subscription.utf8), accountID: id, collectedAt: now)
        let result = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "Augment", previousSnapshot: nil, newSnapshot: snapshot, settings: .init(thresholds: [1]), ledger: .init(), now: now)
        XCTAssertFalse(result.operations.contains { if case .deliver(let n) = $0 { return n.kind == .quotaAlert || n.kind == .walletAlert }; return false })
        XCTAssertEqual(result.ledger.pendingSchedules(accountID: id).count, 1)
        let noDate = try AugmentCodeProviderClient.snapshot(credits: Data(credits.utf8), subscription: nil, accountID: id, collectedAt: now)
        XCTAssertTrue(NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "Augment", previousSnapshot: nil, newSnapshot: noDate, settings: .init(), ledger: .init(), now: now).ledger.pendingSchedules(accountID: id).isEmpty)
        let account = SubscriptionAccount(id: id, name: "Augment", provider: .augmentCode)
        let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows, collectedAt: now, lastFailure: nil, quotaStatusText: snapshot.quotaStatusText)
        XCTAssertEqual(widget.displayMetrics.count, 1, "Status must not replace valid counters")
        XCTAssertNotNil(widget.displayMetrics[0].window)
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        XCTAssertNotNil(DemoMode.accounts().first { $0.provider == .augmentCode })
        XCTAssertEqual(Provider.augmentCode.iconAssetName, "ProviderAugmentCode")
    }

    @MainActor
    func testMultipleAccountsRestoreFailureDeleteAndCredentialReplacementRemainIsolated() async throws {
        let store = AugmentStore(), transport = AugmentTransport([(200, credits), (200, subscription), (200, credits), (200, subscription), (401, "{}"), (200, credits), (500, "{}")])
        let client = ProviderQuotaClient(provider: .augmentCode, transport: transport)
        let monitor = QuotaMonitor(accountStore: store, credentialStore: store, quotaClient: client)
        await monitor.start(refresh: false)
        let firstID = UUID(), secondID = UUID(), now = Date()
        await monitor.addAccount(name: "First", credential: try credential(id: firstID, value: "first", date: now), provider: .augmentCode, accountID: firstID)
        await monitor.addAccount(name: "Second", credential: try credential(id: secondID, value: "second", date: now), provider: .augmentCode, accountID: secondID)
        let before = try XCTUnwrap(monitor.states.first?.snapshot), other = try XCTUnwrap(monitor.states.last)
        let restored = QuotaMonitor(accountStore: store, credentialStore: store, quotaClient: client)
        await restored.start(refresh: false)
        XCTAssertEqual(restored.states, monitor.states)
        await restored.refresh(accountID: firstID)
        XCTAssertEqual(restored.states[0].snapshot, before)
        XCTAssertEqual(restored.states[0].lastFailure, .invalidCredential)
        await restored.replaceCredential(try credential(id: firstID, value: "replacement", date: now), accountID: firstID)
        XCTAssertNil(restored.states[0].lastFailure)
        XCTAssertEqual(restored.states[1], other)
        let deleted = await restored.deleteAccount(accountID: firstID)
        XCTAssertTrue(deleted)
        let removed = await store.credential(for: firstID), kept = await store.credential(for: secondID)
        XCTAssertNil(removed)
        XCTAssertNotNil(kept)
    }
    private func credential(id: UUID, value: String, date: Date) throws -> String {
        try WebProviderSession.cookieCredential(cookies: [cookie("_session", value, domain: "app.augmentcode.com")],
            policy: AugmentCodeProviderClient.policy, provider: .augmentCode, origin: AugmentCodeProviderClient.origin, accountID: id, now: date).encoded()
    }
    private func cookie(_ name: String, _ value: String, domain: String, expiry: Date? = nil) -> HTTPCookie {
        var p: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: "/", .secure: "TRUE"]
        if let expiry { p[.expires] = expiry }; return HTTPCookie(properties: p)!
    }
}
private actor AugmentTransport: ProviderTransport {
    private var replies: [(Int, String)]; private(set) var requests: [URLRequest] = []
    init(_ replies: [(Int, String)]) { self.replies = replies }
    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request); guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let (status, body) = replies.removeFirst(); return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
private actor AugmentStore: AccountStateStoring, CredentialStoring {
    private var states: [AccountQuotaState] = [], values: [UUID: String] = [:]
    func load() -> [AccountQuotaState] { states }; func save(_ states: [AccountQuotaState]) { self.states = states }
    func save(_ value: String, for accountID: UUID) { values[accountID] = value }; func credential(for accountID: UUID) -> String? { values[accountID] }
    func deleteCredential(for accountID: UUID) { values[accountID] = nil }
}
