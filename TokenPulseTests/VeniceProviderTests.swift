import Foundation
import XCTest
@testable import TokenPulse

final class VeniceProviderTests: XCTestCase {
    private let fixture = #"{"canConsume":true,"consumptionCurrency":"USD","balances":{"usd":25.75,"diem":90.5,"bundledCredits":10,"earnedCredits":5},"diemEpochAllocation":100}"#
    func testProviderCurrencyWinsAndUSDDecimalKeepsZeroAndDebtWithoutFakePercent() throws {
        for (body, currency, monetary, total) in [
            (fixture, "USD", true, Decimal(string: "25.75")!),
            (fixture.replacingOccurrences(of: "\"USD\"", with: "\"DIEM\""), "DIEM", false, Decimal(string: "90.5")!),
            (fixture.replacingOccurrences(of: "\"USD\"", with: "\"VCU\""), "VCU", false, Decimal(string: "90.5")!),
            (fixture.replacingOccurrences(of: "\"USD\"", with: "\"BUNDLED_CREDITS\""), "BUNDLED_CREDITS", false, Decimal(10)),
            (fixture.replacingOccurrences(of: "\"USD\"", with: "\"EARNED_CREDITS\""), "EARNED_CREDITS", false, Decimal(5)),
            (#"{"canConsume":false,"balances":{"usd":"-0.001000000000000001","diem":null}}"#, "USD", true, Decimal(string: "-0.001000000000000001")!),
            (#"{"canConsume":false,"consumptionCurrency":"DIEM","balances":{"usd":0,"diem":0}}"#, "DIEM", false, Decimal(0)),
        ] {
            let snapshot = try VeniceProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())
            let window = try XCTUnwrap(snapshot.windows.first)
            XCTAssertEqual(window.wallet?.currency, currency)
            XCTAssertEqual(window.wallet?.isMonetary, monetary)
            XCTAssertEqual(window.wallet?.total, total)
            XCTAssertNil(window.usedPercentage)
            XCTAssertNil(window.totalCount)
            XCTAssertNil(window.resetsAt)
            XCTAssertNil(snapshot.walletAvailable)
            XCTAssertNil(snapshot.quotaExceeded)
        }
    }
    func testNullableEmptyFiguresAndKnownUnitFallbackNeverBecomeZero() throws {
        let snapshot = try VeniceProviderClient.snapshot(Data(#"{"canConsume":true,"consumptionCurrency":null,"balances":{"usd":"","diem":"90.50"}}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(snapshot.windows.first?.wallet?.currency, "DIEM")
        XCTAssertEqual(snapshot.windows.first?.wallet?.total, Decimal(string: "90.5"))
        for specifiedMissing in [
            #"{"canConsume":false,"consumptionCurrency":"DIEM","balances":{"usd":10,"diem":null}}"#,
            #"{"canConsume":false,"consumptionCurrency":"USD","balances":{"usd":null,"diem":90}}"#,
            #"{"canConsume":true,"consumptionCurrency":"BUNDLED_CREDITS","balances":{"usd":1,"diem":90}}"#,
            #"{"canConsume":true,"consumptionCurrency":"EARNED_CREDITS","balances":{"usd":1,"earnedCredits":null}}"#,
        ] {
            XCTAssertThrowsError(try VeniceProviderClient.snapshot(Data(specifiedMissing.utf8), accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .noQuotaWindows)
            }
        }
        let absent = #"{"canConsume":true,"balances":{"usd":null,"diem":""}}"#
        XCTAssertThrowsError(try VeniceProviderClient.snapshot(Data(absent.utf8), accountID: UUID(), collectedAt: Date())) {
            XCTAssertEqual($0 as? RefreshFailure, .noQuotaWindows)
        }
        for body in ["{}", #"{"canConsume":1,"balances":{"usd":1}}"#, #"{"canConsume":true,"balances":{"usd":true}}"#,
                     #"{"canConsume":true,"balances":{"usd":"NaN","diem":90}}"#,
                     #"{"canConsume":true,"consumptionCurrency":3,"balances":{"usd":1}}"#,
                     #"{"canConsume":true,"consumptionCurrency":"EUR","balances":{"usd":1}}"#,
                     #"{"canConsume":true,"consumptionCurrency":"BUNDLED_CREDITS","balances":{"usd":1,"bundledCredits":true}}"#,
                     #"{"canConsume":true,"consumptionCurrency":"EARNED_CREDITS","balances":{"usd":1,"earnedCredits":"NaN"}}"#] {
            XCTAssertThrowsError(try VeniceProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
    }
    func testUnitSwitchDisplaysActualWalletAndNeverTurnsDIEMIntoDollarAlerts() throws {
        let id = UUID(), date = Date(timeIntervalSince1970: 100)
        let lowUSD = #"{"canConsume":true,"consumptionCurrency":"USD","balances":{"usd":1,"diem":0}}"#
        let lowDIEM = lowUSD.replacingOccurrences(of: "\"USD\"", with: "\"DIEM\"")
        var ledger = ReminderLedger()
        for (index, body, expected) in [(0, lowUSD, 1), (1, lowDIEM, 0)] {
            let at = date.addingTimeInterval(Double(index))
            let snapshot = try VeniceProviderClient.snapshot(Data(body.utf8), accountID: id, collectedAt: at)
            let result = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "Venice", previousSnapshot: nil,
                                                                   newSnapshot: snapshot,
                                                                   settings: AccountReminderSettings(walletCurrency: "USD", walletAlertsEnabled: true),
                                                                   ledger: ledger, now: at)
            ledger = result.ledger
            let alerts = result.operations.compactMap { operation -> ReminderNotification? in
                if case .deliver(let notification) = operation { return notification }; return nil
            }
            XCTAssertEqual(alerts.count, expected)
            let widget = WidgetAccountSnapshot(account: SubscriptionAccount(id: id, name: "Venice", provider: .venice),
                                              windows: snapshot.windows, collectedAt: at, lastFailure: nil, walletCurrency: "USD")
            XCTAssertEqual(widget.displayMetrics.first?.valueText, index == 0 ? "1 USD" : "0 DIEM")
            XCTAssertNil(widget.displayMetrics.first?.ringFraction)
        }
        XCTAssertNil(ledger.walletAlertState(accountID: id, currency: "DIEM"))
        for currency in ["VCU", "BUNDLED_CREDITS", "EARNED_CREDITS"] {
            let body = fixture.replacingOccurrences(of: "\"USD\"", with: "\"\(currency)\"")
            let snapshot = try VeniceProviderClient.snapshot(Data(body.utf8), accountID: id, collectedAt: date.addingTimeInterval(10))
            let result = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "Venice", previousSnapshot: nil,
                                                                   newSnapshot: snapshot, settings: AccountReminderSettings(walletAlertsEnabled: true),
                                                                   ledger: ledger, now: snapshot.collectedAt)
            XCTAssertTrue(result.operations.isEmpty)
            XCTAssertEqual(snapshot.windows.first?.wallet?.currency, currency)
            XCTAssertEqual(snapshot.windows.first?.wallet?.isMonetary, false)
        }
    }
    func testBearerGETContractAndHTTPFailureMapping() async throws {
        try await assertWalletExpansionRequest(provider: .venice, body: fixture, endpoint: VeniceProviderClient.endpoint)
    }
    @MainActor func testTwoAccountsKeepCredentialsDataAndFailureIsolatedAfterRestoreDelete() async throws {
        try await assertWalletExpansionLifecycle(provider: .venice, body: fixture,
                                                secondBody: fixture.replacingOccurrences(of: "25.75", with: "9.25"))
    }
}
