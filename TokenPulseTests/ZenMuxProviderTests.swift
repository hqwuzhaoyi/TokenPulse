import Foundation
import XCTest
@testable import TokenPulse

final class ZenMuxProviderTests: XCTestCase {
    private let quotas = #"{"success":true,"data":{"plan":{"tier":"ultra"},"quota_5_hour":{"usage_percentage":0.0715,"resets_at":"2026-03-24T08:35:09.000Z"},"quota_7_day":{"usage_percentage":0.0673,"resets_at":"2026-03-26T02:15:05.000Z"},"quota_monthly":{"max_flows":34560,"max_value_usd":1134.33}}}"#
    private let balance = #"{"success":true,"data":{"currency":"usd","total_credits":482.74,"top_up_credits":35,"bonus_credits":447.74}}"#

    func testFractionsHaveTheirOwnWindowsAndMonthlyCapDoesNotInventUsedMetric() throws {
        let result = try ZenMuxProviderClient.subscription(Data(quotas.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(result.windows.map(\.id), ["zenmux.five_hour", "zenmux.seven_day"])
        XCTAssertEqual(result.windows.map(\.period), [.fiveHour, .weekly])
        XCTAssertEqual(try XCTUnwrap(result.windows[0].usedPercentage), 7.15, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(result.windows[1].usedPercentage), 6.73, accuracy: 0.000001)
        XCTAssertTrue(result.windows.allSatisfy { $0.totalCount == nil && $0.remainingCount == nil && $0.wallet == nil && $0.resetsAt != nil })
        XCTAssertEqual(result.providerPlanName, "Ultra")
        let over = try ZenMuxProviderClient.subscription(Data(#"{"success":true,"data":{"quota_5_hour":{"usage_percentage":1.25}}}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(over.windows[0].usedPercentage, 125)
        XCTAssertEqual(over.windows[0].isExhausted, true)
    }

    func testWalletPreservesCurrencyDecimalAndNegativeBalanceWithoutInventingBreakdown() throws {
        let wallet = try ZenMuxProviderClient.wallet(Data(balance.utf8))
        XCTAssertEqual(wallet.wallet?.total, Decimal(string: "482.74"))
        XCTAssertEqual(wallet.wallet?.currency, "USD")
        XCTAssertNil(wallet.wallet?.granted)
        XCTAssertNil(wallet.wallet?.toppedUp)
        XCTAssertNil(wallet.usedPercentage)
        let negative = try ZenMuxProviderClient.wallet(Data(#"{"success":true,"data":{"currency":"eur","total_credits":"-0.000356"}}"#.utf8))
        XCTAssertEqual(negative.wallet?.currency, "EUR")
        XCTAssertEqual(negative.wallet?.total, Decimal(string: "-0.000356"))
        XCTAssertNil(negative.resetsAt)
    }

    func testRequestContractUsesOnlyManagementRoutesAndScopedKey() async throws {
        let key = try ProviderAuthenticationController().credential(provider: .zenMux, apiKey: "fixture-management")
        let date = Date(timeIntervalSince1970: 100)
        let transport = ZenMuxTransport([.response(200, quotas), .response(200, balance)])
        let snapshot = try await ProviderQuotaClient(provider: .zenMux, transport: transport, now: { date })
            .quota(for: UUID(), credential: key)
        XCTAssertEqual(snapshot.windows.count, 3)
        XCTAssertEqual(snapshot.walletCollectedAt, date)
        XCTAssertNil(snapshot.walletFailure)
        XCTAssertEqual(snapshot.sourceCredentialFingerprint, try ProviderCredentialEnvelope.decode(key, expectedProvider: .zenMux).sourceCredentialIdentity)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, ["https://zenmux.ai/api/v1/management/subscription/detail", "https://zenmux.ai/api/v1/management/payg/balance"])
        for request in requests {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-management")
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        }
        XCTAssertTrue(ProviderAuthenticationController().loginConfiguration(for: .zenMux).credentialLabel?.contains("Management") == true)
        XCTAssertEqual(Provider.zenMux.balancePresentation, .mixed)
    }

    func testOrdinaryInferenceKeyIsExplainedAndDoesNotMakeASecondRequest() async throws {
        let key = try ProviderAuthenticationController().credential(provider: .zenMux, apiKey: "fixture-inference")
        for status in [401, 403] {
            let transport = ZenMuxTransport([.response(status, "{}")])
            do { _ = try await ProviderQuotaClient(provider: .zenMux, transport: transport).quota(for: UUID(), credential: key); XCTFail("Expected management-key failure") }
            catch { XCTAssertEqual(error as? RefreshFailure, .managementKeyRequired) }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testBalanceFailuresLeaveSuccessfulQuotaStandingWithIndependentFailureState() async throws {
        let key = try ProviderAuthenticationController().credential(provider: .zenMux, apiKey: "fixture-management")
        for (status, text, expected) in [(403, "{}", RefreshFailure.managementKeyRequired), (429, "{}", .rateLimited),
                                         (500, "{}", .server), (200, "bad-json", .unreadableResponse),
                                         (200, #"{"success":false}"#, .unreadableResponse),
                                         (200, #"{"success":true,"data":{"currency":"usd","total_credits":true}}"#, .unreadableResponse)] {
            let result = try await ProviderQuotaClient(provider: .zenMux, transport: ZenMuxTransport([.response(200, quotas), .response(status, text)]))
                .quota(for: UUID(), credential: key)
            XCTAssertEqual(result.windows.count, 2)
            XCTAssertEqual(result.walletFailure, expected)
            XCTAssertNil(result.walletCollectedAt)
            XCTAssertFalse(result.windows.contains { $0.wallet != nil })
        }
        let network = try await ProviderQuotaClient(provider: .zenMux, transport: ZenMuxTransport([.response(200, quotas), .failure]))
            .quota(for: UUID(), credential: key)
        XCTAssertEqual(network.walletFailure, .network)
    }

    @MainActor
    func testPartialClientResultRetainsOldWalletTimeThroughMonitorAndKeyReplacementDropsIt() async throws {
        let id = UUID()
        let key = try ProviderAuthenticationController().credential(provider: .zenMux, apiKey: "fixture-management")
        let firstDate = Date(timeIntervalSince1970: 100)
        let secondDate = Date(timeIntervalSince1970: 200)
        let transport = ZenMuxTransport([.response(200, quotas), .response(200, balance), .response(200, quotas), .response(500, "{}")])
        let first = try await ProviderQuotaClient(provider: .zenMux, transport: transport, now: { firstDate }).quota(for: id, credential: key)
        let second = try await ProviderQuotaClient(provider: .zenMux, transport: transport, now: { secondDate }).quota(for: id, credential: key)
        let store = ZenMuxMemoryStore()
        let query = ZenMuxSnapshots([first, second])
        let monitor = QuotaMonitor(accountStore: store, credentialStore: store, quotaClient: query)
        await monitor.start(refresh: false)
        await monitor.addAccount(name: "ZenMux", credential: key, provider: .zenMux, accountID: id)
        await monitor.refresh(accountID: id)
        let partial = try XCTUnwrap(monitor.states[0].snapshot)
        XCTAssertEqual(partial.collectedAt, secondDate)
        XCTAssertEqual(partial.walletCollectedAt, firstDate)
        XCTAssertEqual(partial.windows.last?.wallet?.total, Decimal(string: "482.74"))
        XCTAssertEqual(partial.walletFailure, .server)
        XCTAssertNil(monitor.states[0].lastFailure)
        let newKey = try ProviderAuthenticationController().credential(provider: .zenMux, apiKey: "another-management")
        await monitor.replaceCredential(newKey, accountID: id)
        XCTAssertNil(monitor.states[0].snapshot)
        XCTAssertEqual(monitor.states[0].lastFailure, .network)
    }

    func testMalformedQuotaCannotTurnIntoAValidZeroAndCancellationIsNotPartialSuccess() async throws {
        for text in [#"{"success":true,"data":{"quota_5_hour":{"usage_percentage":true}}}"#,
                     #"{"success":true,"data":{"quota_5_hour":{"usage_percentage":-1}}}"#,
                     #"{"success":true,"data":{"quota_5_hour":{"usage_percentage":0.1,"resets_at":"bad"}}}"#] {
            XCTAssertThrowsError(try ZenMuxProviderClient.subscription(Data(text.utf8), accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
        let key = try ProviderAuthenticationController().credential(provider: .zenMux, apiKey: "fixture-management")
        do {
            _ = try await ProviderQuotaClient(provider: .zenMux, transport: ZenMuxTransport([.response(200, quotas), .cancelled]))
                .quota(for: UUID(), credential: key)
            XCTFail("Cancellation must not publish partial data")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testUnsafeOrUnboundCredentialDoesNotStartARequest() async throws {
        for key in ["fixture\r\nInjected: value", "fixture key", ""] {
            XCTAssertThrowsError(try ProviderAuthenticationController().credential(provider: .zenMux, apiKey: key))
        }
        let transport = ZenMuxTransport([])
        let encoded = try ProviderCredentialEnvelope(provider: .zenMux, kind: .apiKey, accessToken: "fixture").encoded()
        do { _ = try await ProviderQuotaClient(provider: .zenMux, transport: transport).quota(for: UUID(), credential: encoded); XCTFail("Unbound key must be rejected") }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testWalletOnlyAccountAndMixedDemoWidgetRemainMeaningful() async throws {
        let key = try ProviderAuthenticationController().credential(provider: .zenMux, apiKey: "fixture-management")
        let result = try await ProviderQuotaClient(provider: .zenMux, transport: ZenMuxTransport([.response(200, #"{"success":true,"data":{"quota_monthly":{"max_flows":1000}}}"#), .response(200, balance)]))
            .quota(for: UUID(), credential: key)
        XCTAssertEqual(result.windows.count, 1)
        XCTAssertNotNil(result.windows[0].wallet)
        let account = try XCTUnwrap(DemoMode.accounts().first { $0.provider == .zenMux })
        let demo = DemoMode.snapshot(accountID: account.id, provider: .zenMux)
        let widget = WidgetAccountSnapshot(account: account, windows: demo.windows, collectedAt: demo.collectedAt, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 3)
        XCTAssertTrue(widget.displayMetrics.contains { $0.window?.wallet != nil })
        XCTAssertEqual(Provider.zenMux.iconAssetName, "ProviderZenMux")
    }
}

private actor ZenMuxTransport: ProviderTransport {
    enum Reply: Sendable { case response(Int, String), failure, cancelled }
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        switch replies.removeFirst() {
        case .failure: throw URLError(.timedOut)
        case .cancelled: throw CancellationError()
        case .response(let status, let body):
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}
private actor ZenMuxMemoryStore: AccountStateStoring, CredentialStoring {
    private var states: [AccountQuotaState] = []
    private var keys: [UUID: String] = [:]
    func load() -> [AccountQuotaState] { states }
    func save(_ states: [AccountQuotaState]) { self.states = states }
    func credential(for accountID: UUID) -> String? { keys[accountID] }
    func save(_ credential: String, for accountID: UUID) { keys[accountID] = credential }
    func deleteCredential(for accountID: UUID) { keys[accountID] = nil }
}
private actor ZenMuxSnapshots: QuotaQuerying {
    private var snapshots: [QuotaSnapshot]
    init(_ snapshots: [QuotaSnapshot]) { self.snapshots = snapshots }
    func quota(for accountID: UUID, credential: String) throws -> QuotaSnapshot {
        guard !snapshots.isEmpty else { throw RefreshFailure.network }
        return snapshots.removeFirst()
    }
}
