import Foundation
import XCTest
@testable import TokenPulse

final class V2EXProviderTests: XCTestCase {
    private let inactive = #"{"success":true,"result":{"active":false,"total_tokens":8020000,"used_tokens":0,"remaining_tokens":8020000,"used_percent":0,"period_start":0,"period_end":0,"extra_usage":{"pack_count":1,"total_tokens":12000000,"used_tokens":34897,"remaining_tokens":11965103}}}"#
    private func snapshot(_ text: String) throws -> QuotaSnapshot {
        try V2EXProviderClient.snapshot(Data(text.utf8), accountID: UUID(), collectedAt: Date(timeIntervalSince1970: 100))
    }

    func testInactiveAllowanceAndPackStaySeparateWithoutResetOrExpiry() throws {
        let result = try snapshot(inactive)
        XCTAssertEqual(result.windows.map(\.id), ["v2ex.five_hour", "v2ex.extra"])
        XCTAssertEqual(result.windows.map(\.remainingCount), [8_020_000, 11_965_103])
        XCTAssertEqual(result.windows.map(\.totalCount), [8_020_000, 12_000_000])
        XCTAssertEqual(result.windows.map(\.unit), ["tokens", "tokens"])
        XCTAssertEqual(result.windows.map(\.resetSemantics), [.nonResettingAllowance, .nonResettingAllowance])
        XCTAssertTrue(result.windows.allSatisfy { $0.resetsAt == nil && $0.expiresAt == nil && $0.wallet == nil })
        XCTAssertTrue(result.windows[0].name.contains("尚未开始"))
        XCTAssertEqual(result.windows[0].usedPercentage, 0)
        XCTAssertEqual(try XCTUnwrap(result.windows[1].usedPercentage), 34897.0 / 12000000 * 100, accuracy: 0.000001)
        let planned = NotificationPlanner().planSuccessfulRefresh(accountID: result.accountID, accountName: "V2EX",
            previousSnapshot: nil, newSnapshot: result, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: result.collectedAt)
        XCTAssertTrue(planned.operations.isEmpty)
    }

    func testActiveWindowUsesProviderStartAndExactCountsRatherThanRoundedPercent() throws {
        let result = try snapshot(#"{"success":true,"result":{"active":true,"total_tokens":1000,"used_tokens":799,"remaining_tokens":201,"used_percent":80,"period_start":10000,"period_end":28000,"extra_usage":{"pack_count":0,"total_tokens":0,"used_tokens":0,"remaining_tokens":0}}}"#)
        XCTAssertEqual(result.windows.count, 1)
        XCTAssertEqual(result.windows[0].usedPercentage, 79.9)
        XCTAssertEqual(result.windows[0].resetsAt, Date(timeIntervalSince1970: 28000))
        XCTAssertEqual(result.windows[0].cycleID, "v2ex.start.10000.0")
        XCTAssertNil(result.windows[0].resetSemantics)
        XCTAssertEqual(result.windows[0].isExhausted, false)
    }

    func testMissingMetricsRemainUnknownAndZeroAllowanceDoesNotBecomeSpent() throws {
        let missing = try snapshot(#"{"success":true,"result":{"active":false,"total_tokens":1000,"remaining_tokens":1000,"period_start":0,"period_end":0}}"#)
        XCTAssertNil(missing.windows[0].usedPercentage)
        XCTAssertEqual(missing.windows[0].remainingCount, 1000)
        let missingRemainder = try snapshot(#"{"success":true,"result":{"active":false,"total_tokens":1000,"used_tokens":1000,"period_start":0,"period_end":0}}"#)
        XCTAssertNil(missingRemainder.windows[0].isExhausted)
        XCTAssertNil(missingRemainder.windows[0].remainingCount)
        XCTAssertThrowsError(try snapshot(#"{"success":true,"result":{"active":false,"total_tokens":0,"used_tokens":0,"remaining_tokens":0}}"#)) {
            XCTAssertEqual($0 as? RefreshFailure, .noQuotaWindows)
        }
    }

    func testPurchaseOrCurrentWindowTopUpDoesNotConfirmAReset() throws {
        let id = UUID()
        let time = Date(timeIntervalSince1970: 100)
        let planner = NotificationPlanner()
        func reading(total: Int, used: Int, collected: Date) throws -> QuotaSnapshot {
            try V2EXProviderClient.snapshot(Data("{\"success\":true,\"result\":{\"active\":true,\"total_tokens\":\(total),\"used_tokens\":\(used),\"remaining_tokens\":\(total-used),\"period_start\":10000,\"period_end\":28000}}".utf8), accountID: id, collectedAt: collected)
        }
        let old = try reading(total: 100, used: 95, collected: time)
        let first = planner.planSuccessfulRefresh(accountID: id, accountName: "V2EX", previousSnapshot: nil,
            newSnapshot: old, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: time)
        let expanded = try reading(total: 1000, used: 95, collected: time.addingTimeInterval(100))
        let second = planner.planSuccessfulRefresh(accountID: id, accountName: "V2EX", previousSnapshot: old,
            newSnapshot: expanded, settings: AccountReminderSettings(), ledger: first.ledger, now: time.addingTimeInterval(100))
        XCTAssertTrue(second.operations.isEmpty)
        XCTAssertEqual(first.ledger.cycleState(accountID: id, windowID: old.windows[0].id)?.identity,
                       second.ledger.cycleState(accountID: id, windowID: expanded.windows[0].id)?.identity)
    }

    func testMalformedContractCannotClearValidDataAndSuccessFalseMeansRejectedToken() {
        for body in [#"{"success":true,"result":{"active":true,"total_tokens":1000,"used_tokens":100}}"#,
                     #"{"success":true,"result":{"active":false,"total_tokens":true,"used_tokens":100}}"#,
                     #"{"success":true,"result":{"active":false,"total_tokens":1000,"used_tokens":-1}}"#,
                     #"{"success":true,"result":{"active":false,"total_tokens":1000,"used_tokens":100,"extra_usage":{"pack_count":-1}}}"#,
                     #"{"success":true,"result":{"active":false,"total_tokens":1000,"used_tokens":100,"period_end":-1}}"#,
                     #"{"success":true,"result":{"total_tokens":1000,"used_tokens":100}}"#] {
            XCTAssertThrowsError(try snapshot(body)) { XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse) }
        }
        XCTAssertThrowsError(try snapshot(#"{"success":false}"#)) { XCTAssertEqual($0 as? RefreshFailure, .invalidCredential) }
    }

    @MainActor
    func testRequestScopeFailurePreservationAndLocalDeletion() async throws {
        let id = UUID()
        let key = try ProviderAuthenticationController().credential(provider: .v2ex, apiKey: "fixture-personal-token")
        let envelope = try ProviderCredentialEnvelope.decode(key, expectedProvider: .v2ex)
        XCTAssertEqual(ProviderAuthenticationController().loginConfiguration(for: .v2ex).credentialLabel, "V2EX Personal Access Token")
        let changed = try ProviderAuthenticationController().credential(provider: .v2ex, apiKey: "other-token")
        XCTAssertNotEqual(envelope.sourceCredentialIdentity, try ProviderCredentialEnvelope.decode(changed, expectedProvider: .v2ex).sourceCredentialIdentity)
        let transport = V2EXTransport([.response(200, inactive), .response(401, "{}"), .response(403, "{}"), .response(429, "{}"),
                                     .response(500, "{}"), .failure, .response(200, #"{"success":true,"result":"bad"}"#)])
        let store = V2EXMemoryStore()
        let now = Date(timeIntervalSince1970: 100)
        let monitor = QuotaMonitor(accountStore: store, credentialStore: store,
            quotaClient: ProviderQuotaClient(provider: .v2ex, transport: transport, now: { now }))
        await monitor.start(refresh: false)
        await monitor.addAccount(name: "V2EX", credential: key, provider: .v2ex, accountID: id)
        let initial = try XCTUnwrap(monitor.states.first?.snapshot)
        for failure in [RefreshFailure.invalidCredential, .invalidCredential, .rateLimited, .server, .network, .unreadableResponse] {
            await monitor.refresh(accountID: id)
            XCTAssertEqual(monitor.states[0].snapshot, initial)
            XCTAssertEqual(monitor.states[0].lastFailure, failure)
        }
        let requests = await transport.requests
        for request in requests {
            XCTAssertEqual(request.url?.absoluteString, "https://edge.v2ex.com/api/v2/chat/quota")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-personal-token")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertFalse(request.httpShouldHandleCookies)
        }
        let deleted = await monitor.deleteAccount(accountID: id)
        XCTAssertTrue(deleted)
        let credential = await store.credential(for: id)
        XCTAssertNil(credential)
    }

    func testDemoAndWidgetKeepWindowAndPackMetrics() throws {
        let account = try XCTUnwrap(DemoMode.accounts().first { $0.provider == .v2ex })
        let snapshot = DemoMode.snapshot(accountID: account.id, provider: .v2ex)
        let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows, collectedAt: snapshot.collectedAt, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 2)
        XCTAssertEqual(widget.ringMetrics.count, 2)
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
        XCTAssertNil(snapshot.windows[1].resetsAt)
        XCTAssertNil(snapshot.windows[1].expiresAt)
        XCTAssertEqual(Provider.v2ex.systemIconName, "bubble.left.and.bubble.right.fill")
    }
}

private actor V2EXTransport: ProviderTransport {
    enum Reply: Sendable { case response(Int, String), failure }
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        switch replies.removeFirst() {
        case .failure: throw URLError(.timedOut)
        case .response(let status, let body):
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}
private actor V2EXMemoryStore: AccountStateStoring, CredentialStoring {
    private var states: [AccountQuotaState] = []
    private var credentials: [UUID: String] = [:]
    func load() -> [AccountQuotaState] { states }
    func save(_ states: [AccountQuotaState]) { self.states = states }
    func save(_ credential: String, for accountID: UUID) { credentials[accountID] = credential }
    func credential(for accountID: UUID) -> String? { credentials[accountID] }
    func deleteCredential(for accountID: UUID) { credentials[accountID] = nil }
}
