import Foundation
import XCTest
@testable import TokenPulse

final class V0ProviderTests: XCTestCase {
    private let billing = #"{"billingType":"token","data":{"balance":{"total":1000,"remaining":750},"billingCycle":{"end":1800003600},"onDemand":{"balance":120}}}"#
    private let rate = #"{"limit":100,"remaining":80,"reset":1800001800000}"#

    func testTokenBillingAndMessagesHaveSeparateUnitsAndKeyRequests() async throws {
        let transport = V0Transport([(200, billing), (200, rate)])
        let id = UUID(), date = Date(timeIntervalSince1970: 100)
        let key = try ProviderAuthenticationController().credential(provider: .v0, apiKey: " fixture ")
        let snapshot = try await ProviderQuotaClient(provider: .v0, transport: transport, now: { date }).quota(for: id, credential: key)
        XCTAssertEqual(snapshot.accountID, id)
        XCTAssertEqual(snapshot.collectedAt, date)
        XCTAssertEqual(snapshot.windows.map(\.id), ["v0.billing", "v0.rate_limit"])
        XCTAssertEqual(snapshot.windows.map(\.unit), ["credits", "条消息"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercentage), [25, 20])
        XCTAssertEqual(snapshot.windows.map(\.exactCounts?.remaining), [750, 80])
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.wallet == nil && $0.period == .other })
        XCTAssertEqual(snapshot.windows[1].resetsAt, Date(timeIntervalSince1970: 1800001800))
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, ["https://api.v0.dev/v1/user/billing", "https://api.v0.dev/v1/rate-limits"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture" && $0.cachePolicy == .reloadIgnoringLocalCacheData && !$0.httpShouldHandleCookies })
        XCTAssertEqual(ProviderAuthenticationController().loginConfiguration(for: .v0).method, .apiKey)
    }

    func testAuxiliaryFailureOrMalformedMetricsKeepsBillingAndMarksMissingMetric() async throws {
        for (status, body) in [(429, "{}"), (500, "{}"), (200, "bad"), (200, #"{"limit":true,"remaining":5}"#), (200, #"{"limit":100,"remaining":-1}"#)] {
            let snapshot = try await ProviderQuotaClient(provider: .v0, transport: V0Transport([(200, billing), (status, body)])).quota(for: UUID(), credential: key("fixture"))
            XCTAssertEqual(snapshot.windows.map(\.id), ["v0.billing"])
            let account = SubscriptionAccount(id: snapshot.accountID, name: "v0", provider: .v0)
            let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows, collectedAt: snapshot.collectedAt, lastFailure: nil)
            XCTAssertEqual(widget.displayMetrics.count, 2)
            XCTAssertEqual(widget.displayMetrics[1].valueText, "未提供")
            XCTAssertNil(widget.displayMetrics[1].ringFraction)
        }
    }

    func testMissingRemainderDoesNotInventPercentageAndLegacyUsesReportedReset() throws {
        let missing = Data(#"{"billingType":"legacy","data":{"limit":1000}}"#.utf8)
        XCTAssertTrue(try V0ProviderClient.windows(billing: missing, rate: nil).isEmpty)
        let onlyMessages = try V0ProviderClient.windows(billing: missing, rate: Data(rate.utf8))
        XCTAssertEqual(onlyMessages.map(\.id), ["v0.rate_limit"])
        let legacy = try V0ProviderClient.windows(billing: Data(#"{"billingType":"legacy","data":{"limit":100,"remaining":25,"reset":"1800003600000"}}"#.utf8), rate: nil)
        XCTAssertEqual(legacy.first?.usedPercentage, 75)
        XCTAssertEqual(legacy.first?.resetsAt, Date(timeIntervalSince1970: 1800003600))
        let noReset = try V0ProviderClient.windows(billing: Data(#"{"billingType":"legacy","data":{"limit":100,"remaining":0,"reset":0}}"#.utf8), rate: nil)
        XCTAssertEqual(noReset.first?.isExhausted, true)
        XCTAssertNil(noReset.first?.resetsAt)
    }

    func testUnknownTypeInvalidCountsAndOverflowCannotBecomeValidBilling() throws {
        for body in [#"{"billingType":"future","data":{}}"#, #"{"billingType":"legacy","data":{"limit":true,"remaining":1}}"#, #"{"billingType":"legacy","data":{"limit":100,"remaining":101}}"#, #"{"billingType":"token","data":{"balance":{"total":"nan","remaining":1}}}"#, #"{"billingType":"legacy","data":{"limit":100,"remaining":5,"reset":"1e300"}}"#] {
            XCTAssertThrowsError(try V0ProviderClient.windows(billing: Data(body.utf8), rate: Data(rate.utf8))) { XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse) }
        }
    }

    func testNotificationWindowsDemoAndCodingStayConsistent() throws {
        let now = Date(timeIntervalSince1970: 100), id = UUID()
        let windows = try V0ProviderClient.windows(billing: Data(billing.replacingOccurrences(of: "remaining\":750", with: "remaining\":50").utf8), rate: Data(rate.utf8))
        let snapshot = QuotaSnapshot(accountID: id, windows: windows, collectedAt: now)
        let planned = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "v0", previousSnapshot: nil, newSnapshot: snapshot, settings: .init(), ledger: .init(), now: now)
        XCTAssertEqual(planned.ledger.pendingSchedules(accountID: id).count, 2)
        XCTAssertTrue(planned.operations.contains { if case .deliver(let n) = $0 { return n.kind == .quotaAlert }; return false })
        XCTAssertFalse(planned.operations.contains { if case .deliver(let n) = $0 { return n.kind == .walletAlert }; return false })
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        let demo = try XCTUnwrap(DemoMode.accounts().first { $0.provider == .v0 })
        XCTAssertEqual(DemoMode.snapshot(accountID: demo.id, provider: .v0).windows.map(\.unit), ["credits", "条消息"])
    }

    @MainActor
    func testTwoAccountsRestoreFailureKeepsBillingAndCredentialReplacementIsIsolated() async throws {
        let store = V0Store(), transport = V0Transport([(200, billing),(200, rate),(200, billing),(200, rate),(401,"{}"),(200,billing),(500,"{}")])
        let client = ProviderQuotaClient(provider: .v0, transport: transport)
        let monitor = QuotaMonitor(accountStore: store, credentialStore: store, quotaClient: client)
        await monitor.start(refresh: false)
        await monitor.addAccount(name: "Work", credential: try key("work"), provider: .v0)
        await monitor.addAccount(name: "Personal", credential: try key("personal"), provider: .v0)
        let first = try XCTUnwrap(monitor.states.first), second = try XCTUnwrap(monitor.states.last)
        let restored = QuotaMonitor(accountStore: store, credentialStore: store, quotaClient: client)
        await restored.start(refresh: false)
        XCTAssertEqual(restored.states, monitor.states)
        await restored.refresh(accountID: first.id)
        XCTAssertEqual(restored.states[0].snapshot, first.snapshot)
        XCTAssertEqual(restored.states[0].lastFailure, .invalidCredential)
        await restored.replaceCredential(try key("renewed"), accountID: first.id)
        XCTAssertEqual(restored.states[0].snapshot?.windows.map(\.id), ["v0.billing"])
        XCTAssertEqual(restored.states[1], second)
        let deleted = await restored.deleteAccount(accountID: first.id)
        XCTAssertTrue(deleted)
        let removed = await store.credential(for: first.id), retained = await store.credential(for: second.id)
        XCTAssertNil(removed)
        XCTAssertEqual(retained, try key("personal"))
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer work", "Bearer work", "Bearer personal", "Bearer personal", "Bearer work", "Bearer renewed", "Bearer renewed"])
    }
    func testCancellationDuringAuxiliaryRequestPropagatesRatherThanPublishingPartialSnapshot() async throws {
        let client = ProviderQuotaClient(provider: .v0, transport: V0CancelTransport(billing: billing))
        do { _ = try await client.quota(for: UUID(), credential: key("fixture")); XCTFail("Cancellation must not be a best-effort success") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    private func key(_ token: String) throws -> String { try ProviderCredentialEnvelope(provider: .v0, kind: .apiKey, accessToken: token).encoded() }
}
private actor V0Transport: ProviderTransport {
    private var replies: [(Int,String)]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [(Int,String)]) { self.replies = replies }
    func data(for request: URLRequest) throws -> (Data,URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let (status,body) = replies.removeFirst()
        return (Data(body.utf8),HTTPURLResponse(url: request.url!,statusCode: status,httpVersion: nil,headerFields: nil)!)
    }
}
private actor V0Store: AccountStateStoring,CredentialStoring {
    private var states: [AccountQuotaState] = [], keys: [UUID:String] = [:]
    func load() -> [AccountQuotaState] { states }
    func save(_ states: [AccountQuotaState]) { self.states = states }
    func save(_ key: String,for accountID: UUID) { keys[accountID] = key }
    func credential(for accountID: UUID) -> String? { keys[accountID] }
    func deleteCredential(for accountID: UUID) { keys[accountID] = nil }
}

private actor V0CancelTransport: ProviderTransport {
    let billing: String
    init(billing: String) { self.billing = billing }
    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        if request.url?.path == "/v1/rate-limits" { throw CancellationError() }
        return (Data(billing.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
