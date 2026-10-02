import Foundation
import XCTest
@testable import TokenPulse

final class FactoryProviderTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_700_000_000)
    private let me = #"{"userProfile":{"id":"work & personal"},"organization":{"subscription":{"orbSubscription":{"plan":{"name":"Pro"}}}}}"#
    private let current = #"{"usesTokenRateLimitsBilling":true,"limits":{"standard":{"fiveHour":{"usedPercent":12,"secondsRemaining":3600},"monthly":{"usedPercent":56,"windowEnd":"2026-10-20T00:00:00Z"}},"core":{"weekly":{"usedPercent":8,"secondsRemaining":2800}}},"extraUsageBalanceCents":2500,"extraUsageAllowed":true}"#
    private let legacy = #"{"usage":{"startDate":1700000000000,"endDate":1702592000000,"standard":{"userTokens":100,"totalAllowance":1000,"usedRatio":0},"premium":{"userTokens":20,"totalAllowance":100,"usedRatio":0.2}}}"#

    func testNewBillingSelectsStandardCoreWithoutRequestingLegacyPremium() async throws {
        let transport = FactoryTransport([(200, me), (200, current)])
        let date = reference
        let credential = try ProviderAuthenticationController().credential(provider: .factory, apiKey: " fk-fixture ")
        let id = UUID()
        let snapshot = try await ProviderQuotaClient(provider: .factory, transport: transport, now: { date }).quota(for: id, credential: credential)
        XCTAssertEqual(snapshot.accountID, id)
        XCTAssertEqual(snapshot.providerPlanName, "Pro")
        XCTAssertEqual(snapshot.windows.map(\.scope), ["Standard", "Standard", "Core", nil])
        XCTAssertEqual(snapshot.windows.map(\.usedPercentage), [12, 56, 8, nil])
        XCTAssertEqual(snapshot.windows[0].resetsAt, date.addingTimeInterval(3600))
        XCTAssertEqual(snapshot.windows.last?.remainingCount, 2500)
        XCTAssertNil(snapshot.windows.last?.wallet)
        XCTAssertEqual(snapshot.windows.last?.unit, "cents（币种未提供）")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/app/auth/me", "/api/billing/limits"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fk-fixture" && $0.value(forHTTPHeaderField: "x-factory-client") == "web-app" && $0.value(forHTTPHeaderField: "Origin") == "https://app.factory.ai" && $0.value(forHTTPHeaderField: "Referer") == "https://app.factory.ai/" && $0.cachePolicy == .reloadIgnoringLocalCacheData && !$0.httpShouldHandleCookies })
    }

    func testLegacyFallbackOnFailedLimitsUsesEscapedAccountIDAndCorrectsZeroCacheRatio() async throws {
        let date = reference
        let transport = FactoryTransport([(200, me), (500, "{}"), (200, legacy)])
        let snapshot = try await ProviderQuotaClient(provider: .factory, transport: transport, now: { date }).quota(for: UUID(), credential: key("fixture"))
        XCTAssertEqual(snapshot.windows.map(\.id), ["factory.legacy.standard", "factory.legacy.premium"])
        XCTAssertEqual(snapshot.windows.map(\.scope), ["Standard", "Premium"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercentage), [10, 20])
        XCTAssertEqual(snapshot.windows.map(\.remainingCount), [900, 80])
        let requests = await transport.requests
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(requests.last?.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems, [.init(name: "useCache", value: "true"), .init(name: "userId", value: "work & personal")])
        XCTAssertEqual(requests.count, 3)
    }

    func testNumericFlagsAndMalformedNewPoolsFailWithoutMixingOldUsage() async throws {
        for body in [#"{"usesTokenRateLimitsBilling":1,"limits":{}}"#, #"{"usesTokenRateLimitsBilling":true,"limits":"bad"}"#, #"{"usesTokenRateLimitsBilling":true,"limits":{"standard":{"weekly":{"usedPercent":true}}}}"#, #"{"usesTokenRateLimitsBilling":true,"limits":{},"extraUsageAllowed":1}"#] {
            let transport = FactoryTransport([(200, me), (200, body), (200, legacy)])
            do { _ = try await ProviderQuotaClient(provider: .factory, transport: transport).quota(for: UUID(), credential: key("fixture")); XCTFail("Expected invalid new contract") }
            catch { XCTAssertEqual(error as? RefreshFailure, .unreadableResponse) }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 2)
        }
    }

    func testExpiredRateWindowsAndUnusedCoreAreOmittedWithoutFakeZero() throws {
        let root = try json(#"{"usesTokenRateLimitsBilling":true,"limits":{"standard":{"fiveHour":{"usedPercent":95,"windowEnd":1699999999},"weekly":{"windowEnd":1700001000000},"monthly":{"usedPercent":25,"windowEnd":"1700002000"}},"core":{"weekly":{"usedPercent":0,"windowEnd":0}}}}"#)
        let windows = try XCTUnwrap(FactoryProviderClient.currentWindows(root, now: reference))
        XCTAssertEqual(windows.map(\.id), ["factory.rate.standard.monthly"])
        XCTAssertEqual(windows[0].usedPercentage, 25)
        XCTAssertNil(windows[0].totalCount)
        XCTAssertEqual(windows[0].resetsAt, Date(timeIntervalSince1970: 1700002000))
        for invalid in ["nan", "inf", "1e300"] {
            let body = "{\"usesTokenRateLimitsBilling\":true,\"limits\":{\"standard\":{\"weekly\":{\"usedPercent\":20,\"secondsRemaining\":\"\(invalid)\"}}}}"
            XCTAssertThrowsError(try FactoryProviderClient.currentWindows(json(body), now: reference))
        }
    }

    func testLegacyUnlimitedMissingLimitsAndUnknownRatioScaleRemainDistinct() throws {
        let root = try json(#"{"usage":{"standard":{"userTokens":100,"totalAllowance":1000000000001,"usedRatio":0},"premium":{"usedRatio":50}}}"#)
        let windows = try FactoryProviderClient.legacyWindows(root, now: reference)
        XCTAssertEqual(windows.count, 1)
        XCTAssertTrue(windows[0].isUnlimited)
        XCTAssertNil(windows[0].usedPercentage)
        XCTAssertNil(windows[0].resetsAt)
        let missing = try FactoryProviderClient.legacyWindows(json(#"{"usage":{"standard":{"usedRatio":0},"premium":{"usedRatio":0.25}}}"#), now: reference)
        XCTAssertEqual(missing.count, 1)
        XCTAssertEqual(missing[0].usedPercentage, 25)
        XCTAssertNil(missing[0].remainingCount)
        XCTAssertNil(missing[0].totalCount)
        XCTAssertTrue(try FactoryProviderClient.legacyWindows(json(legacy), now: reference.addingTimeInterval(3_000_000)).isEmpty)
    }

    func testAuthenticationFailureDoesNotProbeBillingAndCrossProviderCredentialIsRejected() async throws {
        let transport = FactoryTransport([(401, "{}")])
        do { _ = try await ProviderQuotaClient(provider: .factory, transport: transport).quota(for: UUID(), credential: key("fixture")); XCTFail("Expected revoked Key") }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        do { _ = try await ProviderQuotaClient(provider: .factory, transport: transport).quota(for: UUID(), credential: ProviderCredentialEnvelope(provider: .copilot, kind: .oauth, accessToken: "fixture").encoded()); XCTFail("Wrong provider") }
        catch { XCTAssertEqual(error as? ProviderIntegrationError, .invalidCredentialData) }
    }

    func testIncludedQuotaAlertsAndResetSchedulesExcludeUnverifiedCurrencyBalance() throws {
        let root = try json(current.replacingOccurrences(of: "usedPercent\":12", with: "usedPercent\":95"))
        let snapshot = QuotaSnapshot(accountID: UUID(), windows: try XCTUnwrap(FactoryProviderClient.currentWindows(root, now: reference)), collectedAt: reference)
        let first = NotificationPlanner().planSuccessfulRefresh(accountID: snapshot.accountID, accountName: "Factory", previousSnapshot: nil, newSnapshot: snapshot, settings: .init(), ledger: .init(), now: reference)
        let deliveries = first.operations.compactMap { if case .deliver(let notification) = $0 { return notification }; return nil }
        XCTAssertEqual(deliveries.map(\.kind), [.quotaAlert])
        XCTAssertFalse(deliveries[0].body.contains("余额"))
        let widget = WidgetAccountSnapshot(account: SubscriptionAccount(id: snapshot.accountID, name: "Factory", provider: .factory), windows: snapshot.windows, collectedAt: reference, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 4)
        XCTAssertNil(widget.displayMetrics.last?.ringFraction)
        XCTAssertEqual(widget.displayMetrics.last?.valueText, QuotaFormatting.count(2500) + " cents（币种未提供）")
        let repeated = NotificationPlanner().planSuccessfulRefresh(accountID: snapshot.accountID, accountName: "Factory", previousSnapshot: snapshot, newSnapshot: snapshot, settings: .init(), ledger: first.ledger, now: reference)
        XCTAssertTrue(repeated.operations.isEmpty)
        XCTAssertEqual(DemoMode.accounts().filter { $0.provider == .factory }.count, 2)
    }

    @MainActor
    func testTwoLocalAccountsRestoreReplaceDeleteAndRetainFailedSnapshot() async throws {
        let store = FactoryMemoryStore()
        let date = reference
        let transport = FactoryTransport([(200, me), (200, current), (200, me), (200, current), (401, "{}"), (200, me), (200, current)])
        let client = ProviderQuotaClient(provider: .factory, transport: transport, now: { date })
        let monitor = QuotaMonitor(accountStore: store, credentialStore: store, quotaClient: client)
        await monitor.start(refresh: false)
        await monitor.addAccount(name: "Work", credential: try key("work"), provider: .factory)
        await monitor.addAccount(name: "Personal", credential: try key("personal"), provider: .factory)
        let first = try XCTUnwrap(monitor.states.first)
        let second = try XCTUnwrap(monitor.states.last)
        let restored = QuotaMonitor(accountStore: store, credentialStore: store, quotaClient: client)
        await restored.start(refresh: false)
        XCTAssertEqual(restored.states, monitor.states)
        await restored.refresh(accountID: first.id)
        XCTAssertEqual(restored.states[0].snapshot, first.snapshot)
        XCTAssertEqual(restored.states[0].lastFailure, .invalidCredential)
        await restored.replaceCredential(try key("renewed"), accountID: first.id)
        XCTAssertNil(restored.states[0].lastFailure)
        XCTAssertEqual(restored.states[1], second)
        let deleted = await restored.deleteAccount(accountID: first.id)
        XCTAssertTrue(deleted)
        let removed = await store.credential(for: first.id)
        let retained = await store.credential(for: second.id)
        XCTAssertNil(removed)
        XCTAssertEqual(retained, try key("personal"))
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer work", "Bearer work", "Bearer personal", "Bearer personal", "Bearer work", "Bearer renewed", "Bearer renewed"])
    }

    private func key(_ value: String) throws -> String { try ProviderCredentialEnvelope(provider: .factory, kind: .apiKey, accessToken: value).encoded() }
    private func json(_ value: String) throws -> [String: Any] { try ProviderHTTP.json(Data(value.utf8)) }
}

private actor FactoryTransport: ProviderTransport {
    private var replies: [(Int, String)]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [(Int, String)]) { self.replies = replies }
    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let (status, body) = replies.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
private actor FactoryMemoryStore: AccountStateStoring, CredentialStoring {
    private var states: [AccountQuotaState] = []
    private var credentials: [UUID: String] = [:]
    func load() -> [AccountQuotaState] { states }
    func save(_ states: [AccountQuotaState]) { self.states = states }
    func save(_ credential: String, for accountID: UUID) { credentials[accountID] = credential }
    func credential(for accountID: UUID) -> String? { credentials[accountID] }
    func deleteCredential(for accountID: UUID) { credentials[accountID] = nil }
}
