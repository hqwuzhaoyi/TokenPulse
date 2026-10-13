import Foundation
import XCTest
@testable import TokenPulse

final class SyntheticProviderTests: XCTestCase {
    private let body = #"{"plan":"Starter","weeklyTokenLimit":{"nextRegenAt":"2026-04-17T05:19:30.000Z","percentRemaining":98,"maxCredits":"$36.00","remainingCredits":"$35.30","nextRegenCredits":"$0.72"},"rollingFiveHourLimit":{"nextTickAt":"2026-04-17T03:44:11.000Z","tickPercent":0.05,"remaining":600,"max":750,"limited":false},"search":{"hourly":{"limit":250,"requests":2,"renewsAt":"2026-04-17T04:30:01.494Z"}}}"#

    func testNamedLanesPreserveCountsPercentScaleAndPartialReplenishment() throws {
        let date = Date(timeIntervalSince1970: 100)
        for text in [body, "{\"data\":\(body)}"] {
            let snapshot = try SyntheticProviderClient.snapshot(Data(text.utf8), accountID: UUID(), collectedAt: date)
            XCTAssertEqual(snapshot.windows.map(\.id), ["synthetic.five_hour", "synthetic.weekly", "synthetic.search_hourly"])
            XCTAssertEqual(snapshot.windows.map(\.usedPercentage), [20, 2, 0.8])
            XCTAssertEqual(snapshot.windows.map(\.remainingCount), [600, nil, 248])
            XCTAssertEqual(snapshot.windows.map(\.unit), [nil, nil, "次请求"])
            XCTAssertEqual(snapshot.windows.map(\.resetSemantics), [.continuousReplenishment, .continuousReplenishment, nil])
            XCTAssertNil(snapshot.windows[0].resetsAt)
            XCTAssertNil(snapshot.windows[1].resetsAt)
            XCTAssertNotNil(snapshot.windows[0].nextReplenishmentAt)
            XCTAssertNotNil(snapshot.windows[1].nextReplenishmentAt)
            XCTAssertNotNil(snapshot.windows[2].resetsAt)
            XCTAssertNil(snapshot.windows[2].nextReplenishmentAt)
            XCTAssertEqual(snapshot.providerPlanName, "Starter")
            XCTAssertTrue(snapshot.windows.allSatisfy { $0.wallet == nil })
        }
    }

    func testWeeklyDollarBudgetFallbackDoesNotBecomeWalletAndOnePercentMeansOnePercentRemaining() throws {
        for (slot, expected) in [(#"{"maxCredits":"$36.00","remainingCredits":"$9.00"}"#, 75.0),
                                 (#"{"percentRemaining":1}"#, 99), (#"{"percentRemaining":0}"#, 100)] {
            let snapshot = try SyntheticProviderClient.snapshot(Data("{\"weeklyTokenLimit\":\(slot)}".utf8), accountID: UUID(), collectedAt: Date())
            XCTAssertEqual(snapshot.windows[0].usedPercentage, expected)
            XCTAssertNil(snapshot.windows[0].wallet)
            XCTAssertNil(snapshot.windows[0].remainingCount)
        }
        let partial = try SyntheticProviderClient.snapshot(Data(#"{"rollingFiveHourLimit":{"max":750},"search":{"hourly":{"limit":250,"requests":0}}}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(partial.windows.map(\.id), ["synthetic.search_hourly"])
        XCTAssertEqual(partial.windows.first?.usedPercentage, 0)
    }

    func testMalformedMetricsDoNotBecomeZeroOrAnInventedFallbackLane() {
        for body in [#"{"rollingFiveHourLimit":{"max":true,"remaining":0}}"#,
                     #"{"weeklyTokenLimit":{"percentRemaining":101}}"#,
                     #"{"weeklyTokenLimit":{"maxCredits":"$nan","remainingCredits":"$1"}}"#,
                     #"{"rollingFiveHourLimit":{"max":750,"remaining":-1}}"#,
                     #"{"search":{"hourly":{"limit":250,"requests":2,"renewsAt":"bad"}}}"#] {
            XCTAssertThrowsError(try SyntheticProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
        for body in ["{}", #"{"unknown":{"limit":100,"used":80}}"#, #"{"rollingFiveHourLimit":{"max":0,"remaining":0}}"#] {
            XCTAssertThrowsError(try SyntheticProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .noQuotaWindows)
            }
        }
    }

    func testCredentialScopeRequestContractAndIndependentAccounts() async throws {
        let controller = ProviderAuthenticationController()
        XCTAssertEqual(controller.loginConfiguration(for: .synthetic).method, .apiKey)
        let key = try controller.credential(provider: .synthetic, apiKey: "fixture-key")
        let first = try ProviderCredentialEnvelope.decode(key, expectedProvider: .synthetic)
        let other = try ProviderCredentialEnvelope.decode(controller.credential(provider: .synthetic, apiKey: "other-fixture"), expectedProvider: .synthetic)
        XCTAssertNotEqual(first.sourceCredentialIdentity, other.sourceCredentialIdentity)
        let transport = SyntheticTransport([.response(200, body), .response(200, body)])
        let date = Date(timeIntervalSince1970: 100)
        let client = ProviderQuotaClient(provider: .synthetic, transport: transport, now: { date })
        for id in [UUID(), UUID()] {
            let snapshot = try await client.quota(for: id, credential: key)
            XCTAssertEqual(snapshot.accountID, id)
            XCTAssertEqual(snapshot.sourceCredentialFingerprint, first.sourceCredentialIdentity)
            XCTAssertEqual(snapshot.collectedAt, date)
        }
        let requests = await transport.requests
        for request in requests {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "https://api.synthetic.new/v2/quotas")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        }
        XCTAssertEqual(requests.count, 2)
    }

    @MainActor
    func testRefreshFailuresPreserveDataAndAccountDeletionWorksWithoutCloud() async throws {
        let suite = "com.tokenpulse.tests.synthetic.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = try ProviderAuthenticationController().credential(provider: .synthetic, apiKey: "fixture-key")
        let transport = SyntheticTransport([.response(200, body), .response(401, "{}"), .response(403, "{}"),
                                           .response(429, "{}"), .response(500, "{}"), .failure,
                                           .response(200, #"{"weeklyTokenLimit":{"percentRemaining":true}}"#)])
        let date = Date(timeIntervalSince1970: 100)
        let store = SyntheticCredentials()
        let monitor = QuotaMonitor(accountStore: LocalAccountStateStore(suiteName: suite), credentialStore: store,
            quotaClient: ProviderQuotaClient(provider: .synthetic, transport: transport, now: { date }),
            configurationStore: LocalAccountConfigurationStore(suiteName: suite))
        await monitor.start(refresh: false)
        await monitor.addAccount(name: "Synthetic", credential: key, provider: .synthetic)
        let state = try XCTUnwrap(monitor.states.first)
        for expected in [RefreshFailure.invalidCredential, .invalidCredential, .rateLimited, .server, .network, .unreadableResponse] {
            await monitor.refresh(accountID: state.id)
            XCTAssertEqual(monitor.states[0].snapshot, state.snapshot)
            XCTAssertEqual(monitor.states[0].lastFailure, expected)
        }
        let restored = QuotaMonitor(accountStore: LocalAccountStateStore(suiteName: suite), credentialStore: store,
            quotaClient: ProviderQuotaClient(provider: .synthetic, transport: transport), configurationStore: LocalAccountConfigurationStore(suiteName: suite))
        await restored.start(refresh: false)
        XCTAssertEqual(restored.states[0].snapshot, state.snapshot)
        let deleted = await restored.deleteAccount(accountID: state.id)
        XCTAssertTrue(deleted)
        let deletedCredential = await store.credential(for: state.id)
        XCTAssertNil(deletedCredential)
    }

    func testDemoAndWidgetExposeAllThreeLanesAndGenericIcon() throws {
        let account = try XCTUnwrap(DemoMode.accounts().first { $0.provider == .synthetic })
        let snapshot = DemoMode.snapshot(accountID: account.id, provider: .synthetic)
        let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows, collectedAt: snapshot.collectedAt, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 3)
        XCTAssertEqual(widget.ringMetrics.count, 3)
        XCTAssertEqual(snapshot.windows.filter { $0.resetSemantics == .continuousReplenishment }.count, 2)
        XCTAssertEqual(Provider.synthetic.systemIconName, "puzzlepiece.extension.fill")
    }
}

private actor SyntheticTransport: ProviderTransport {
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
private actor SyntheticCredentials: CredentialStoring {
    private var keys: [UUID: String] = [:]
    func credential(for accountID: UUID) -> String? { keys[accountID] }
    func save(_ credential: String, for accountID: UUID) { keys[accountID] = credential }
    func deleteCredential(for accountID: UUID) { keys[accountID] = nil }
}
