import Foundation
import XCTest
@testable import TokenPulse

final class HyperProviderTests: XCTestCase {
    private let fixture = #"{"balance":1234.5}"#
    func testNonMoneyHCZeroAndDecimalsNeverInventQuotaOrCurrency() throws {
        for value in ["0", "1234.5", "1234.500000000000000001"] {
            let id = UUID(), date = Date(timeIntervalSince1970: 100)
            let snapshot = try HyperProviderClient.snapshot(Data("{\"balance\":\(value)}".utf8), accountID: id, collectedAt: date)
            let window = try XCTUnwrap(snapshot.windows.first)
            XCTAssertEqual(window.wallet?.total, Decimal(string: value))
            XCTAssertEqual(window.wallet?.currency, "HC")
            XCTAssertEqual(window.wallet?.isMonetary, false)
            XCTAssertNil(window.usedPercentage)
            XCTAssertNil(window.totalCount)
            XCTAssertNil(window.resetsAt)
            let widget = WidgetAccountSnapshot(account: SubscriptionAccount(id: id, name: "Hyper", provider: .hyper),
                                              windows: snapshot.windows, collectedAt: date, lastFailure: nil)
            XCTAssertTrue(widget.displayMetrics.first?.valueText.hasSuffix(" HC") == true)
            XCTAssertNil(widget.displayMetrics.first?.ringFraction)
            let result = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "HC", previousSnapshot: nil,
                                                                   newSnapshot: snapshot, settings: AccountReminderSettings(walletAlertsEnabled: true),
                                                                   ledger: ReminderLedger(), now: date)
            XCTAssertTrue(result.operations.isEmpty)
            XCTAssertFalse(Provider.hyper.hasMonetaryWallet)
            XCTAssertEqual(Provider.hyper.balancePresentation, .walletOnly)
        }
    }
    func testMissingNegativeStringAndBooleanBalanceAreUnreadable() {
        for body in ["{}", #"{"balance":null}"#, #"{"balance":-1}"#, #"{"balance":"1234.5"}"#,
                     #"{"balance":true}"#, #"{"balance":"NaN"}"#] {
            XCTAssertThrowsError(try HyperProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
    }
    func testBearerGETContractAndErrorMapping() async throws {
        try await assertWalletExpansionRequest(provider: .hyper, body: fixture, endpoint: HyperProviderClient.endpoint)
    }
    @MainActor func testMultiAccountLocalRecoveryFailureAndDeletion() async throws {
        try await assertWalletExpansionLifecycle(provider: .hyper, body: fixture, secondBody: #"{"balance":0}"#)
    }
}
