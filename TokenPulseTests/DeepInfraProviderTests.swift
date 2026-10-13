import Foundation
import XCTest
@testable import TokenPulse

final class DeepInfraProviderTests: XCTestCase {
    private let fixture = #"{"stripe_balance":-99.75,"recent":3.94,"limit":20,"suspended":false}"#
    func testInvertedLedgerSubtractsPendingSpendExactlyAndKeepsDebtAndZero() throws {
        for (body, expected) in [
            (#"{"stripe_balance":-99.750000000000000001,"recent":3.94,"limit":20}"#, Decimal(string: "95.810000000000000001")!),
            (#"{"stripe_balance":4,"recent":2}"#, Decimal(-6)),
            (#"{"stripe_balance":0,"recent":0}"#, Decimal(0)),
            (#"{"stripe_balance":-9,"recent":-4}"#, Decimal(9)),
        ] {
            let snapshot = try DeepInfraProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())
            XCTAssertEqual(snapshot.windows.first?.wallet?.total, expected)
            XCTAssertEqual(snapshot.windows.first?.wallet?.currency, "USD")
            XCTAssertNil(snapshot.windows.first?.wallet?.granted)
        }
    }
    func testOnlyPositiveLimitsProduceExactBudgetAndNoSuspensionPercentageOrReset() throws {
        let snapshot = try DeepInfraProviderClient.snapshot(Data(fixture.utf8), accountID: UUID(), collectedAt: Date())
        let spend = try XCTUnwrap(snapshot.windows.last)
        XCTAssertEqual(spend.usedPercentage ?? -1, 19.7, accuracy: 0.0000001)
        XCTAssertEqual(spend.exactCounts?.used, Decimal(string: "3.94"))
        XCTAssertEqual(spend.exactCounts?.remaining, Decimal(string: "16.06"))
        XCTAssertEqual(spend.exactCounts?.total, 20)
        XCTAssertEqual(spend.period, .other)
        XCTAssertNil(spend.resetsAt)
        for body in [#"{"stripe_balance":-99,"recent":2,"suspended":true}"#,
                     #"{"stripe_balance":-99,"recent":2,"limit":0}"#,
                     #"{"stripe_balance":-99,"recent":2,"limit":-1}"#] {
            let walletOnly = try DeepInfraProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())
            XCTAssertEqual(walletOnly.windows.count, 1)
            XCTAssertNil(walletOnly.windows.first?.usedPercentage)
            XCTAssertNil(walletOnly.quotaExceeded)
            XCTAssertNil(walletOnly.walletAvailable)
        }
    }
    func testMalformedOrMissingNumericLedgerIsNotZero() {
        for body in ["{}", #"{"stripe_balance":null,"recent":0}"#, #"{"stripe_balance":true,"recent":0}"#,
                     #"{"stripe_balance":"-99","recent":0}"#, #"{"stripe_balance":0,"recent":"NaN"}"#,
                     #"{"stripe_balance":0,"recent":0,"limit":true}"#] {
            XCTAssertThrowsError(try DeepInfraProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
    }
    func testHybridWidgetAndIndependentReminderRulesUseParsedWindows() throws {
        let id = UUID(), date = Date(timeIntervalSince1970: 100)
        let snapshot = try DeepInfraProviderClient.snapshot(Data(#"{"stripe_balance":-1,"recent":1,"limit":1,"suspended":true}"#.utf8), accountID: id, collectedAt: date)
        let widget = WidgetAccountSnapshot(account: SubscriptionAccount(id: id, name: "DeepInfra", provider: .deepInfra),
                                          windows: snapshot.windows, collectedAt: date, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 2)
        XCTAssertEqual(widget.displayMetrics.first?.valueText, "0 USD")
        XCTAssertEqual(widget.displayMetrics.last?.ringFraction, 1)
        let result = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "DeepInfra", previousSnapshot: nil,
                                                               newSnapshot: snapshot, settings: AccountReminderSettings(quotaAlertsEnabled: false, walletAlertsEnabled: true),
                                                               ledger: ReminderLedger(), now: date)
        let delivered = result.operations.compactMap { operation -> ReminderNotificationKind? in
            if case .deliver(let notification) = operation { return notification.kind }; return nil
        }
        XCTAssertEqual(delivered, [.walletAlert])
    }
    func testRequestContractAndMappedFailures() async throws {
        try await assertWalletExpansionRequest(provider: .deepInfra, body: fixture, endpoint: DeepInfraProviderClient.endpoint)
    }
    @MainActor func testAccountsRemainIsolatedAcrossFailureRestartAndDeletion() async throws {
        try await assertWalletExpansionLifecycle(provider: .deepInfra, body: fixture,
                                                secondBody: fixture.replacingOccurrences(of: "-99.75", with: "-9.75"))
    }
}
