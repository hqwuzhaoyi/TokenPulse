import Foundation
import XCTest
@testable import TokenPulse

final class DevPassProviderTests: XCTestCase {
    private let fixture = #"{"data":{"usage":"0.09","limit":"0.10","devPlan":"pro","devPlanCreditsUsed":"0.20","devPlanCreditsLimit":"0.30","devPlanPremiumCreditsUsed":"0.10","devPlanPremiumWeeklyLimit":"0.20","devPlanPremiumWeekResetsAt":"2026-10-05T12:00:00.000Z"}}"#
    private let payg = #"{"data":{"devPlan":"none","usage":"0","limit":null,"devPlanCreditsUsed":"0","devPlanCreditsLimit":"0"}}"#

    func testDirectKeyContractAndThreeExactBudgetWindows() async throws {
        let transport = DevPassTransport([(200, fixture)])
        let id = UUID(), date = Date(timeIntervalSince1970: 100)
        let credential = try ProviderAuthenticationController().credential(provider: .devPass, apiKey: " gateway-fixture ")
        let snapshot = try await ProviderQuotaClient(provider: .devPass, transport: transport, now: { date }).quota(for: id, credential: credential)
        XCTAssertEqual(snapshot.accountID, id)
        XCTAssertEqual(snapshot.collectedAt, date)
        XCTAssertEqual(snapshot.providerPlanName, "Pro")
        XCTAssertEqual(snapshot.windows.map(\.id), ["devpass.premium_weekly", "devpass.cycle", "devpass.key_limit"])
        XCTAssertEqual(snapshot.windows.map(\.period), [.weekly, .other, .other])
        XCTAssertEqual(snapshot.windows.map(\.exactCounts?.remaining), [decimal("0.10"), decimal("0.10"), decimal("0.01")])
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.remainingCount == nil && $0.totalCount == nil && $0.wallet == nil && $0.unit == "USD credits" })
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
        XCTAssertNil(snapshot.windows[1].resetsAt)
        XCTAssertNil(snapshot.windows[2].resetsAt)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://api.llmgateway.io/v1/key")
        XCTAssertEqual(requests[0].httpMethod, "GET")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer gateway-fixture")
        XCTAssertEqual(requests[0].cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(ProviderAuthenticationController().loginConfiguration(for: .devPass).method, .apiKey)
    }

    func testDecimalCountsPreserveDigitsBeyondDoubleAndOldCachesDecode() throws {
        let exact = decimal("9007199254740993.01")
        XCTAssertEqual(try DevPassProviderClient.amount("9007199254740993.01"), exact)
        let snapshot = try DevPassProviderClient.snapshot(Data(#"{"data":{"devPlan":"max","devPlanCreditsUsed":"9007199254740993.01","devPlanCreditsLimit":"9007199254740994.03"}}"#.utf8), accountID: UUID(), collectedAt: Date())
        let window = try XCTUnwrap(snapshot.windows.first)
        XCTAssertEqual(window.exactCounts?.used, exact)
        XCTAssertEqual(window.exactCounts?.remaining, decimal("1.02"))
        let restored = try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored, snapshot)
        let old = try JSONDecoder().decode(QuotaWindow.self, from: Data(#"{"id":"old","name":"Old","isUnlimited":false,"remainingCount":2,"totalCount":3}"#.utf8))
        XCTAssertNil(old.exactCounts)
        XCTAssertEqual(old.remainingCount, 2)
        XCTAssertTrue(try XCTUnwrap(QuotaFormatting.exactCountSummary(window)).contains(QuotaFormatting.count(decimal("1.02"))))
    }

    func testPayAsYouGoNoLimitAndUnknownPlanAreExplicitlyDifferent() throws {
        let empty = try DevPassProviderClient.snapshot(Data(payg.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(empty.isNoPlan, true)
        XCTAssertTrue(empty.windows.isEmpty)
        let account = SubscriptionAccount(id: empty.accountID, name: "PAYG", provider: .devPass)
        let widget = WidgetAccountSnapshot(account: account, windows: [], collectedAt: empty.collectedAt, lastFailure: nil, isNoPlan: true)
        XCTAssertEqual(widget.displayMetrics.first?.valueText, "按量计费，无上限")
        XCTAssertNil(widget.displayMetrics.first?.ringFraction)
        let bounded = payg.replacingOccurrences(of: "\"limit\":null", with: "\"limit\":\"10.00\"")
        let budget = try DevPassProviderClient.snapshot(Data(bounded.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertNil(budget.isNoPlan)
        XCTAssertEqual(budget.windows.map(\.id), ["devpass.key_limit"])
        XCTAssertThrowsError(try DevPassProviderClient.snapshot(Data(fixture.replacingOccurrences(of: "\"pro\"", with: "\"future\"").utf8), accountID: UUID(), collectedAt: Date()))
    }

    func testInvalidDecimalShapesBooleanAndOverflowDoNotBecomeZero() throws {
        for invalid in ["nan", "inf", "1e300", "-1", "1.2.3", String(repeating: "9", count: 39), "0." + String(repeating: "0", count: 200) + "1"] {
            XCTAssertThrowsError(try DevPassProviderClient.amount(invalid), invalid)
        }
        for body in [#"{"data":{"devPlan":"pro","devPlanCreditsUsed":true,"devPlanCreditsLimit":"1"}}"#, #"{"data":{"devPlan":"pro","devPlanCreditsUsed":1,"devPlanCreditsLimit":"1"}}"#, #"{"data":{"devPlan":"pro","devPlanPremiumCreditsUsed":"1","devPlanPremiumWeeklyLimit":"2","devPlanPremiumWeekResetsAt":"bad"}}"#] {
            XCTAssertThrowsError(try DevPassProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
        let zero = try DevPassProviderClient.snapshot(Data(#"{"data":{"devPlan":"pro","devPlanCreditsUsed":"0.00","devPlanCreditsLimit":"1.00"}}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(zero.windows.first?.usedPercentage, 0)
        XCTAssertEqual(zero.windows.first?.exactCounts?.remaining, 1)
    }

    func testOnlyPremiumHasResetNotificationAndBudgetsAreNotWallets() throws {
        let now = Date(timeIntervalSince1970: 100)
        let snapshot = try DevPassProviderClient.snapshot(Data(fixture.utf8), accountID: UUID(), collectedAt: now)
        let settings = AccountReminderSettings(thresholds: [40, 80])
        let result = NotificationPlanner().planSuccessfulRefresh(accountID: snapshot.accountID, accountName: "DevPass", previousSnapshot: nil, newSnapshot: snapshot, settings: settings, ledger: .init(), now: now)
        let schedules = result.ledger.pendingSchedules(accountID: snapshot.accountID)
        XCTAssertEqual(schedules.count, 1)
        XCTAssertEqual(schedules[0].windowIDs, Set(["devpass.premium_weekly"]))
        let deliveries = result.operations.compactMap { if case .deliver(let notification) = $0 { return notification }; return nil }
        XCTAssertEqual(deliveries.map(\.kind), [.quotaAlert])
        XCTAssertTrue(deliveries[0].body.contains("Key 累计限额"))
        let repeated = NotificationPlanner().planSuccessfulRefresh(accountID: snapshot.accountID, accountName: "DevPass", previousSnapshot: snapshot, newSnapshot: snapshot, settings: settings, ledger: result.ledger, now: now)
        XCTAssertTrue(repeated.operations.isEmpty)
        let account = SubscriptionAccount(id: snapshot.accountID, name: "DevPass", provider: .devPass)
        let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows, collectedAt: now, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 3)
        XCTAssertEqual(widget.displayMetrics[0].valueText, QuotaFormatting.exactCountSummary(snapshot.windows[0]))
        let demo = try XCTUnwrap(DemoMode.accounts().first { $0.provider == .devPass })
        XCTAssertEqual(DemoMode.snapshot(accountID: demo.id, provider: .devPass).windows.count, 3)
    }

    @MainActor
    func testAccountIsolationRestoreDeletionAndNoPlanClearsPreviousQuota() async throws {
        let store = DevPassStore()
        let transport = DevPassTransport([(200, fixture), (200, fixture), (200, "bad"), (200, payg), (200, fixture)])
        let client = ProviderQuotaClient(provider: .devPass, transport: transport)
        let monitor = QuotaMonitor(accountStore: store, credentialStore: store, quotaClient: client)
        await monitor.start(refresh: false)
        await monitor.addAccount(name: "Work", credential: try key("work"), provider: .devPass)
        await monitor.addAccount(name: "Personal", credential: try key("personal"), provider: .devPass)
        let first = try XCTUnwrap(monitor.states.first), second = try XCTUnwrap(monitor.states.last)
        let restored = QuotaMonitor(accountStore: store, credentialStore: store, quotaClient: client)
        await restored.start(refresh: false)
        XCTAssertEqual(restored.states, monitor.states)
        await restored.refresh(accountID: first.id)
        XCTAssertEqual(restored.states[0].snapshot, first.snapshot)
        XCTAssertEqual(restored.states[0].lastFailure, .unreadableResponse)
        await restored.refresh(accountID: first.id)
        XCTAssertEqual(restored.states[0].snapshot?.isNoPlan, true)
        XCTAssertTrue(restored.states[0].snapshot?.windows.isEmpty == true)
        XCTAssertEqual(restored.states[1], second)
        await restored.replaceCredential(try key("renewed"), accountID: first.id)
        XCTAssertNil(restored.states[0].snapshot?.isNoPlan)
        let deleted = await restored.deleteAccount(accountID: first.id)
        XCTAssertTrue(deleted)
        let removed = await store.credential(for: first.id), retained = await store.credential(for: second.id)
        XCTAssertNil(removed)
        XCTAssertEqual(retained, try key("personal"))
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer work", "Bearer personal", "Bearer work", "Bearer work", "Bearer renewed"])
    }

    func testRequestErrorsAndCrossProviderTokensAreRejected() async throws {
        for status in [401, 403, 429, 500] {
            do { _ = try await ProviderQuotaClient(provider: .devPass, transport: DevPassTransport([(status, "{}")])).quota(for: UUID(), credential: key("fixture")); XCTFail("Expected failure") }
            catch { XCTAssertEqual(error as? RefreshFailure, status == 429 ? .rateLimited : status == 500 ? .server : .invalidCredential) }
        }
        do { _ = try await ProviderQuotaClient(provider: .devPass, transport: DevPassTransport([])).quota(for: UUID(), credential: ProviderCredentialEnvelope(provider: .factory, kind: .apiKey, accessToken: "fixture").encoded()); XCTFail("Wrong provider") }
        catch { XCTAssertEqual(error as? ProviderIntegrationError, .invalidCredentialData) }
    }

    private func decimal(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }
    private func key(_ token: String) throws -> String { try ProviderCredentialEnvelope(provider: .devPass, kind: .apiKey, accessToken: token).encoded() }
}
private actor DevPassTransport: ProviderTransport {
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
private actor DevPassStore: AccountStateStoring, CredentialStoring {
    private var states: [AccountQuotaState] = []
    private var keys: [UUID: String] = [:]
    func load() -> [AccountQuotaState] { states }
    func save(_ states: [AccountQuotaState]) { self.states = states }
    func save(_ key: String, for accountID: UUID) { keys[accountID] = key }
    func credential(for accountID: UUID) -> String? { keys[accountID] }
    func deleteCredential(for accountID: UUID) { keys[accountID] = nil }
}
