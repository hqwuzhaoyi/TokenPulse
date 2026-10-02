import Foundation
import XCTest
@testable import TokenPulse

final class ZedProviderTests: XCTestCase {
    private let body = #"{"plan":"zed_pro_trial","current_usage":{"edit_predictions":{"used":12,"limit":{"limited":100}},"token_spend":{"spend_in_cents":250,"limit_in_cents":1000}}}"#

    func testWebProfileUsesOwnCookieAndCloudRequestWithBoundIdentity() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100), transport = ZedTransport([(200, body)])
        let profile = ZedProviderClient.loginProfile
        XCTAssertEqual(profile.loginURL.host, "dashboard.zed.dev")
        let choices = try await profile.makeCredentials([cookie("zed.session", "fake", domain: ".zed.dev"), cookie("tracking", "ignored", domain: "dashboard.zed.dev")], [:], id, now)
        XCTAssertEqual(choices.count, 1)
        let snapshot = try await ProviderQuotaClient(provider: .zed, transport: transport, now: { now }).quota(for: id, credential: choices[0].credential)
        XCTAssertEqual(snapshot.accountID, id)
        XCTAssertEqual(snapshot.providerPlanName, "Zed Pro Trial")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://cloud.zed.dev/frontend/billing/usage")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Cookie"), "zed.session=fake")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertFalse(requests[0].httpShouldHandleCookies)
        XCTAssertEqual(requests[0].cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(ProviderAuthenticationController().loginConfiguration(for: .zed).method, .webSession)
    }

    func testPredictionAndMoneyBudgetHaveDifferentUnitsAndNoInventedReset() throws {
        let snapshot = try ZedProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(snapshot.windows.map(\.id), ["zed.editPredictions", "zed.tokenSpend"])
        XCTAssertEqual(snapshot.windows.map(\.unit), ["次", "USD 预算"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercentage), [12, 25])
        XCTAssertEqual(snapshot.windows[1].exactCounts?.used, Decimal(string: "2.5"))
        XCTAssertEqual(snapshot.windows[1].exactCounts?.total, 10)
        XCTAssertEqual(snapshot.windows[1].exactCounts?.remaining, Decimal(string: "7.5"))
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.resetsAt == nil && $0.wallet == nil })
    }

    func testUnlimitedUnsetBudgetAndZeroBudgetCannotBecomeExhaustedOrFakePercent() throws {
        let unlimited = try ZedProviderClient.snapshot(Data(#"{"plan":"zed_pro","current_usage":{"edit_predictions":{"used":12,"limit":"unlimited"},"token_spend":{"spend_in_cents":125,"limit_in_cents":null}}}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertTrue(unlimited.windows[0].isUnlimited)
        XCTAssertNil(unlimited.windows[0].usedPercentage)
        XCTAssertNil(unlimited.windows[1].usedPercentage)
        XCTAssertNil(unlimited.windows[1].isExhausted)
        XCTAssertNil(unlimited.windows[1].exactCounts?.total)
        XCTAssertEqual(unlimited.windows[1].exactCounts?.used, Decimal(string: "1.25"))
        let zero = try ZedProviderClient.snapshot(Data(#"{"current_usage":{"token_spend":{"spend_in_cents":0,"limit_in_cents":0}}}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertNil(zero.windows[0].usedPercentage)
        XCTAssertFalse(zero.windows[0].isUnlimited)
        XCTAssertEqual(zero.windows[0].exactCounts?.total, 0)
        XCTAssertNotNil(zero.quotaStatusText)
    }

    func testBooleanNegativeHtmlAndUnknownLimitShapeFailWithoutInventingZero() throws {
        for input in ["<html>Sign in</html>", #"{"current_usage":{"edit_predictions":{"used":true,"limit":100}}}"#, #"{"current_usage":{"token_spend":{"spend_in_cents":-1,"limit_in_cents":100}}}"#, #"{"current_usage":{"edit_predictions":{"used":1,"limit":{"wrong":100}}}}"#] {
            XCTAssertThrowsError(try ZedProviderClient.snapshot(Data(input.utf8), accountID: UUID(), collectedAt: Date())) { XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse) }
        }
        XCTAssertThrowsError(try ZedProviderClient.snapshot(Data(#"{"plan":"zed_pro"}"#.utf8), accountID: UUID(), collectedAt: Date()))
        XCTAssertThrowsError(try ZedProviderClient.policy.select([cookie("zed.session", "wrong", domain: "evil.example")], now: Date()))
    }

    func testAlertsWidgetsAndDemoNeverScheduleEditorDerivedDate() throws {
        let now = Date(timeIntervalSince1970: 100), id = UUID()
        let snapshot = try ZedProviderClient.snapshot(Data(body.replacingOccurrences(of: "spend_in_cents\":250", with: "spend_in_cents\":1100").utf8), accountID: id, collectedAt: now)
        XCTAssertEqual(snapshot.windows[1].isExhausted, true)
        XCTAssertEqual(try XCTUnwrap(snapshot.windows[1].usedPercentage), 110, accuracy: 0.000001)
        let result = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "Zed", previousSnapshot: nil, newSnapshot: snapshot, settings: .init(), ledger: .init(), now: now)
        XCTAssertTrue(result.ledger.pendingSchedules(accountID: id).isEmpty)
        XCTAssertTrue(result.operations.contains { if case .deliver(let n) = $0 { return n.kind == .quotaAlert }; return false })
        let widget = WidgetAccountSnapshot(account: SubscriptionAccount(id: id, name: "Zed", provider: .zed), windows: snapshot.windows, collectedAt: now, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 2)
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        XCTAssertNotNil(DemoMode.accounts().first { $0.provider == .zed })
        XCTAssertEqual(Provider.zed.iconAssetName, "ProviderZed")
    }

    @MainActor
    func testTwoAccountsRestoreInvalidCookieFailureReauthorizeAndDelete() async throws {
        let store = ZedStore(), transport = ZedTransport([(200, body), (200, body), (403, "{}"), (200, body)])
        let client = ProviderQuotaClient(provider: .zed, transport: transport), id = UUID(), otherID = UUID()
        let monitor = QuotaMonitor(accountStore: store, credentialStore: store, quotaClient: client)
        await monitor.start(refresh: false)
        await monitor.addAccount(name: "First", credential: try credential(id: id, value: "first"), provider: .zed, accountID: id)
        await monitor.addAccount(name: "Second", credential: try credential(id: otherID, value: "second"), provider: .zed, accountID: otherID)
        let first = try XCTUnwrap(monitor.states.first), second = try XCTUnwrap(monitor.states.last)
        let restored = QuotaMonitor(accountStore: store, credentialStore: store, quotaClient: client)
        await restored.start(refresh: false)
        XCTAssertEqual(restored.states, monitor.states)
        await restored.refresh(accountID: id)
        XCTAssertEqual(restored.states[0].snapshot, first.snapshot)
        XCTAssertEqual(restored.states[0].lastFailure, .invalidCredential)
        await restored.replaceCredential(try credential(id: id, value: "new"), accountID: id)
        XCTAssertNil(restored.states[0].lastFailure)
        XCTAssertEqual(restored.states[1], second)
        let removed = await restored.deleteAccount(accountID: id)
        XCTAssertTrue(removed)
        let key = await store.credential(for: id)
        XCTAssertNil(key)
    }
    private func credential(id: UUID, value: String) throws -> String {
        try WebProviderSession.cookieCredential(cookies: [cookie("zed.session", value, domain: ".zed.dev")], policy: ZedProviderClient.policy,
            provider: .zed, origin: ZedProviderClient.origin, accountID: id, now: Date()).encoded()
    }
    private func cookie(_ name: String, _ value: String, domain: String) -> HTTPCookie {
        HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: "/", .secure: "TRUE"])!
    }
}
private actor ZedTransport: ProviderTransport {
    private var replies: [(Int, String)]; private(set) var requests: [URLRequest] = []
    init(_ replies: [(Int, String)]) { self.replies = replies }
    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request); guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let (status, body) = replies.removeFirst(); return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
private actor ZedStore: AccountStateStoring, CredentialStoring {
    private var states: [AccountQuotaState] = [], values: [UUID: String] = [:]
    func load() -> [AccountQuotaState] { states }; func save(_ states: [AccountQuotaState]) { self.states = states }
    func save(_ value: String, for accountID: UUID) { values[accountID] = value }; func credential(for accountID: UUID) -> String? { values[accountID] }
    func deleteCredential(for accountID: UUID) { values[accountID] = nil }
}
