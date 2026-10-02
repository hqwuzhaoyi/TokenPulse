import Foundation
import XCTest
@testable import TokenPulse

final class NeuralwattProviderTests: XCTestCase {
    private let body = #"{"balance":{"credits_remaining_usd":"1.000000001"},"subscription":{"plan":"energy","billing_interval":"monthly","current_period_end":"2026-11-01T00:00:00Z","kwh_used":"0.2","kwh_included":"1.0"},"key":{"allowance":{"spent_usd":"9.50","limit_usd":"10.00","period":"weekly"}}}"#

    func testEnergyBudgetAndPrepaidMoneyStaySeparateAndExact() async throws {
        let transport = HostedQuotaTransport(body)
        let id = UUID()
        let credential = try ProviderAuthenticationController().credential(provider: .neuralwatt, apiKey: "fixture")
        let snapshot = try await ProviderQuotaClient(provider: .neuralwatt, transport: transport).quota(for: id, credential: credential)
        XCTAssertEqual(snapshot.windows.map(\.unit), ["kWh", "USD", nil])
        XCTAssertEqual(snapshot.windows[0].exactCounts?.used, Decimal(string: "0.2"))
        XCTAssertEqual(snapshot.windows[1].exactCounts?.remaining, Decimal(string: "0.50"))
        XCTAssertEqual(snapshot.windows[2].wallet?.total, Decimal(string: "1.000000001"))
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
        XCTAssertNil(snapshot.windows[1].resetsAt)
        XCTAssertNil(snapshot.windows[2].resetsAt)
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://api.neuralwatt.com/v1/quota")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
    }

    func testMissingAllowanceDoesNotTurnRemainingEnergyIntoATotal() throws {
        let snapshot = try NeuralwattProviderClient.snapshot(Data(#"{"balance":{"total_credits_usd":"0.3","credits_used_usd":"0.1"},"subscription":{"kwh_used":1,"kwh_remaining":5}}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows.first?.wallet?.total, Decimal(string: "0.2"))
        let deficit = try NeuralwattProviderClient.snapshot(Data(#"{"balance":{"credits_remaining_usd":"-0.5"}}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(deficit.windows.first?.wallet?.total, Decimal(string: "-0.5"))
        XCTAssertThrowsError(try NeuralwattProviderClient.snapshot(Data(#"{"balance":{"credits_remaining_usd":true}}"#.utf8), accountID: UUID(), collectedAt: Date()))
        XCTAssertThrowsError(try NeuralwattProviderClient.snapshot(Data("{}".utf8), accountID: UUID(), collectedAt: Date()))
    }

    func testWalletAndBudgetAlertsCanBeSelectedIndependently() throws {
        let account = SubscriptionAccount(name: "Energy", provider: .neuralwatt)
        let now = Date()
        let snapshot = try NeuralwattProviderClient.snapshot(Data(body.utf8), accountID: account.id, collectedAt: now)
        let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows, collectedAt: now, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 3)
        for (quota, money, expected) in [(true, false, ReminderNotificationKind.quotaAlert), (false, true, .walletAlert)] {
            let result = NotificationPlanner().planSuccessfulRefresh(accountID: account.id, accountName: account.name,
                previousSnapshot: nil, newSnapshot: snapshot,
                settings: AccountReminderSettings(quotaAlertsEnabled: quota, walletAlertsEnabled: money),
                ledger: ReminderLedger(), now: now)
            let kinds = result.operations.compactMap { operation -> ReminderNotificationKind? in
                if case .deliver(let notification) = operation { return notification.kind }; return nil
            }
            XCTAssertEqual(kinds, [expected])
        }
    }
}
