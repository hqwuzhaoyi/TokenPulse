import Foundation
import XCTest
@testable import TokenPulse

actor HostedQuotaTransport: ProviderTransport {
    let body: String
    let status: Int
    private(set) var requests: [URLRequest] = []
    init(_ body: String, status: Int = 200) { self.body = body; self.status = status }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

final class CodebuffProviderTests: XCTestCase {
    func testCreditsAreExactNonMoneyAndAPIKeyDoesNotQueryCLISubscription() async throws {
        let body = #"{"usage":"0.10","quota":"0.30","remainingBalance":"0.20","next_quota_reset":"2026-11-01T00:00:00Z"}"#
        let transport = HostedQuotaTransport(body)
        let controller = ProviderAuthenticationController()
        let id = UUID()
        let snapshot = try await ProviderQuotaClient(provider: .codebuff, transport: transport).quota(
            for: id, credential: controller.credential(provider: .codebuff, apiKey: "fixture"))
        XCTAssertEqual(snapshot.accountID, id)
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.windows[0].exactCounts?.used, Decimal(string: "0.10"))
        XCTAssertEqual(snapshot.windows[0].exactCounts?.remaining, Decimal(string: "0.20"))
        XCTAssertNil(snapshot.windows[0].period)
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
        XCTAssertEqual(snapshot.windows[1].wallet?.total, Decimal(string: "0.20"))
        XCTAssertEqual(snapshot.windows[1].wallet?.isMonetary, false)
        XCTAssertNil(snapshot.windows[1].resetsAt)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://www.codebuff.com/api/v1/usage")
        XCTAssertEqual(requests.first?.httpMethod, "POST")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
        XCTAssertNotNil(requests.first?.httpBody)
    }

    func testBalanceOnlyDoesNotInventQuotaAndMalformedCountsFail() throws {
        let id = UUID(), now = Date()
        let wallet = try CodebuffProviderClient.snapshot(Data(#"{"remainingBalance":0}"#.utf8), accountID: id, collectedAt: now)
        XCTAssertEqual(wallet.windows.count, 1)
        XCTAssertEqual(wallet.windows.first?.wallet?.total, 0)
        XCTAssertNil(wallet.windows.first?.usedPercentage)
        for body in [#"{"remainingBalance":true}"#, #"{"usage":"NaN","quota":10}"#, "[]"] {
            XCTAssertThrowsError(try CodebuffProviderClient.snapshot(Data(body.utf8), accountID: id, collectedAt: now))
        }
        let missing = try CodebuffProviderClient.snapshot(Data(#"{"usage":0}"#.utf8), accountID: id, collectedAt: now)
        XCTAssertTrue(missing.windows.isEmpty)
        let hugeDate = try CodebuffProviderClient.snapshot(Data(#"{"usage":1,"quota":2,"next_quota_reset":1e30}"#.utf8), accountID: id, collectedAt: now)
        XCTAssertNil(hugeDate.windows.first?.resetsAt)
    }

    func testMixedCreditsWidgetAndNotificationsKeepNonMoneyOutOfWalletAlerts() throws {
        let account = SubscriptionAccount(name: "Credits", provider: .codebuff)
        let now = Date()
        let snapshot = try CodebuffProviderClient.snapshot(Data(#"{"usage":95,"quota":100,"remainingBalance":1}"#.utf8), accountID: account.id, collectedAt: now)
        let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows, collectedAt: now, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 2)
        XCTAssertEqual(widget.displayMetrics.last?.displayTitle, "剩余 credits")
        XCTAssertNil(widget.displayMetrics.last?.ringFraction)
        let result = NotificationPlanner().planSuccessfulRefresh(accountID: account.id, accountName: account.name,
            previousSnapshot: nil, newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: now)
        let kinds = result.operations.compactMap { operation -> ReminderNotificationKind? in
            if case .deliver(let notification) = operation { return notification.kind }; return nil
        }
        XCTAssertEqual(kinds, [.quotaAlert])
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }
}
