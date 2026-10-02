import Foundation
import XCTest
@testable import TokenPulse

final class OpenAIAPIProviderTests: XCTestCase {
    // Synthetic pinned Pulse/CodexBar legacy shape; not a captured live reply.
    private let fixture = #"{"object":"credit_summary","total_granted":18,"total_used":5.7,"total_available":12.3,"grants":{"data":[{"grant_amount":18,"used_amount":5.7,"expires_at":1798761600}]}}"#

    func testExactBalanceDoesNotTurnLifetimeSpendOrGrantExpiryIntoQuota() throws {
        for amount in ["0", "-0.01", "12.300000000000000001"] {
            let id = UUID(), time = Date(timeIntervalSince1970: 100)
            let snapshot = try OpenAIAPIProviderClient.snapshot(Data(fixture.replacingOccurrences(of: "12.3", with: amount).utf8),
                                                               accountID: id, collectedAt: time)
            let window = try XCTUnwrap(snapshot.windows.first)
            XCTAssertEqual(snapshot.accountID, id)
            XCTAssertEqual(snapshot.collectedAt, time)
            XCTAssertEqual(window.wallet?.total, Decimal(string: amount))
            XCTAssertEqual(window.wallet?.currency, "USD")
            XCTAssertEqual(window.wallet?.isMonetary, true)
            XCTAssertNil(window.wallet?.granted)
            XCTAssertNil(window.wallet?.toppedUp)
            XCTAssertNil(window.usedPercentage)
            XCTAssertNil(window.exactCounts)
            XCTAssertNil(window.totalCount)
            XCTAssertNil(window.remainingCount)
            XCTAssertNil(window.resetsAt)
            XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        }
    }

    func testMissingMalformedOrCostsReplyNeverInventsBalance() {
        for body in ["{}", #"{"total_available":null}"#, #"{"total_available":true}"#,
                     #"{"total_available":"12.3"}"#, #"{"total_available":"NaN"}"#,
                     #"{"total_available":1e999}"#, #"{"total_granted":18,"total_used":5.7}"#,
                     #"{"data":[{"object":"bucket","results":[{"object":"organization.costs.result","amount":{"value":12.3,"currency":"usd"}}]}]}"#] {
            XCTAssertThrowsError(try OpenAIAPIProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
    }

    func testFixedBearerGETAndPermissionFailuresNeverProbeCosts() async throws {
        let id = UUID(), time = Date(timeIntervalSince1970: 100)
        let key = try ProviderAuthenticationController().credential(provider: .openAIAPI, apiKey: " fixture-a ")
        let transport = WalletExpansionTransport(body: fixture)
        let result = try await ProviderQuotaClient(provider: .openAIAPI, transport: transport, now: { time })
            .quotaResult(for: id, credential: key)
        XCTAssertEqual(result.snapshot.collectedAt, time)
        XCTAssertNil(result.updatedCredential)
        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url, OpenAIAPIProviderClient.endpoint)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-a")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertFalse(request.url!.absoluteString.contains("fixture-a"))
        for (status, failure) in [(401, RefreshFailure.invalidCredential), (403, .insufficientPermissions),
                                  (404, .server), (429, .rateLimited), (503, .server)] {
            let failing = WalletExpansionTransport(status: status, body: "{}")
            do {
                _ = try await ProviderQuotaClient(provider: .openAIAPI, transport: failing).quota(for: id, credential: key)
                XCTFail("Expected failure for \(status)")
            } catch { XCTAssertEqual(error as? RefreshFailure, failure) }
            let attempts = await failing.requests()
            XCTAssertEqual(attempts.count, 1)
            XCTAssertEqual(attempts.first?.url, OpenAIAPIProviderClient.endpoint)
        }
    }

    func testOtherProviderSessionOrEmptyCredentialDoesNotLeaveDevice() async {
        let transport = WalletExpansionTransport(body: fixture)
        let client = OpenAIAPIProviderClient(transport: transport, now: Date.init)
        for envelope in [ProviderCredentialEnvelope(provider: .codex, kind: .apiKey, accessToken: "fixture"),
                         .init(provider: .openAIAPI, kind: .session, accessToken: "fixture"),
                         .init(provider: .openAIAPI, kind: .apiKey, accessToken: " ")] {
            do { _ = try await client.quota(accountID: UUID(), credential: envelope); XCTFail("Expected failure") }
            catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        }
        let requests = await transport.requests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testForeignOriginResponseCannotBecomeWallet() async throws {
        let client = OpenAIAPIProviderClient(transport: ForeignOpenAIAPIBalanceTransport(), now: Date.init)
        do {
            _ = try await client.quota(accountID: UUID(), credential: .init(provider: .openAIAPI, kind: .apiKey, accessToken: "fixture"))
            XCTFail("Foreign origin must not be trusted")
        } catch { XCTAssertEqual(error as? RefreshFailure, .server) }
    }

    @MainActor func testAccountIsolationCachedFailureRestartAndDeletion() async throws {
        try await assertWalletExpansionLifecycle(provider: .openAIAPI, body: fixture,
                                                secondBody: fixture.replacingOccurrences(of: "12.3", with: "9.25"))
    }

    func testWidgetDemoAndLowBalanceHaveMoneyWithoutQuotaAlerts() throws {
        let account = SubscriptionAccount(name: "Legacy", provider: .openAIAPI)
        let snapshot = try OpenAIAPIProviderClient.snapshot(Data(#"{"total_available":0}"#.utf8),
                                                           accountID: account.id, collectedAt: Date())
        let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows,
                                           collectedAt: snapshot.collectedAt, lastFailure: nil)
        let metric = try XCTUnwrap(widget.displayMetrics.first)
        XCTAssertTrue(metric.valueText.contains("USD"))
        XCTAssertNil(metric.ringFraction)
        let plan = NotificationPlanner().planSuccessfulRefresh(accountID: account.id, accountName: account.name,
            previousSnapshot: nil, newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: Date())
        let kinds = plan.operations.compactMap { operation -> ReminderNotificationKind? in
            if case .deliver(let notification) = operation { return notification.kind }
            return nil
        }
        XCTAssertEqual(kinds, [.walletAlert])
        XCTAssertTrue(DemoMode.accounts().contains { $0.provider == .openAIAPI })
        let demo = DemoMode.snapshot(accountID: account.id, provider: .openAIAPI)
        XCTAssertEqual(demo.windows.first?.wallet?.currency, "USD")
        XCTAssertNil(demo.windows.first?.usedPercentage)
        XCTAssertEqual(Provider.openAIAPI.iconAssetName, "ProviderCodex")
        XCTAssertEqual(Provider.openAIAPI.balancePresentation, .walletOnly)
        let login = ProviderAuthenticationController().loginConfiguration(for: .openAIAPI)
        XCTAssertEqual(login.method, .apiKey)
        XCTAssertTrue(login.credentialLabel?.contains("旧余额接口") == true)
    }
}

private struct ForeignOpenAIAPIBalanceTransport: ProviderTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        (Data(#"{"total_available":100}"#.utf8), HTTPURLResponse(url: URL(string: "https://example.invalid/balance")!,
                                                               statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
