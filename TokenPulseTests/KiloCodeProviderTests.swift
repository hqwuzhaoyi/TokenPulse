import Foundation
import XCTest
@testable import TokenPulse

final class KiloCodeProviderTests: XCTestCase {
    private let fixture = #"[{"result":{"data":{"creditBlocks":[{"balance_mUsd":12500000,"expiry_date":"2026-05-10T00:00:00Z"}],"totalBalance_mUsd":12750000}}},{"result":{"data":{"subscription":{"tier":"tier_19","currentPeriodUsageUsd":7.125,"currentPeriodBaseCreditsUsd":19.0,"currentPeriodBonusCreditsUsd":9.5,"nextBillingAt":"2026-03-28T04:00:00.000Z"}}}}]"#
    func testWalletAndPassRemainSeparateWithExactMicroDollarsAndReportedReset() throws {
        let snapshot = try KiloCodeProviderClient.snapshot(Data(fixture.utf8), accountID: UUID(), collectedAt: Date())
        let wallet = try XCTUnwrap(snapshot.windows.first?.wallet)
        XCTAssertEqual(wallet.total, Decimal(string: "12.75"))
        let pass = try XCTUnwrap(snapshot.windows.first { $0.wallet == nil })
        XCTAssertEqual(pass.usedPercentage, 25)
        XCTAssertEqual(pass.exactCounts?.used, Decimal(string: "7.125"))
        XCTAssertEqual(pass.exactCounts?.total, Decimal(string: "28.5"))
        XCTAssertEqual(pass.exactCounts?.remaining, Decimal(string: "21.375"))
        XCTAssertEqual(pass.period, .other)
        XCTAssertEqual(pass.resetsAt, ProviderHTTP.isoDate("2026-03-28T04:00:00.000Z"))
        XCTAssertNil(snapshot.windows.first?.resetsAt, "Block expiry does not reset a wallet or the Pass")
        let account = SubscriptionAccount(id: snapshot.accountID, name: "Kilo", provider: .kiloCode)
        let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows, collectedAt: snapshot.collectedAt, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.map(\.window?.id), snapshot.windows.map { Optional($0.id) })
        XCTAssertEqual(widget.displayMetrics.first?.valueText, "12.75 USD")
        XCTAssertEqual(widget.displayMetrics.last?.ringFraction, 0.25)
        XCTAssertEqual(Provider.kiloCode.balancePresentation, .mixed)
    }
    func testArrayIndexedObjectWrappedPayloadFallbackSumAndMissingBonus() throws {
        let fallback = #"{"0":{"result":{"data":{"json":{"creditBlocks":[{"balance_mUsd":"0.1"},{"balance_mUsd":"0.2"}]}}}},"1":{"result":{"data":{"json":{"subscription":{"currentPeriodUsageUsd":"2.5","currentPeriodBaseCreditsUsd":"10"}}}}}}"#
        let snapshot = try KiloCodeProviderClient.snapshot(Data(fallback.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(snapshot.windows.first?.wallet?.total, Decimal(string: "0.0000003"))
        XCTAssertEqual(snapshot.windows.last?.usedPercentage, 25)
        XCTAssertEqual(snapshot.windows.last?.exactCounts?.total, 10)
        let exact = #"[{"result":{"data":{"totalBalance_mUsd":123456789012345678}}},{"result":{"data":{"subscription":null}}}]"#
        XCTAssertEqual(try KiloCodeProviderClient.snapshot(Data(exact.utf8), accountID: UUID(), collectedAt: Date()).windows.first?.wallet?.total,
                       Decimal(string: "123456789012.345678"))
    }
    func testAbsentPassAndZeroBalanceDoNotCreateAllowanceOrBlockExpiryReset() throws {
        let body = #"[{"result":{"data":{"totalBalance_mUsd":0,"creditBlocks":[{"balance_mUsd":0,"amount_mUsd":19000000,"expiry_date":"2027-01-01T00:00:00Z"}]}}},{"result":{"data":{"subscription":null}}}]"#
        let snapshot = try KiloCodeProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows.first?.wallet?.total, 0)
        XCTAssertNil(snapshot.windows.first?.usedPercentage)
        XCTAssertNil(snapshot.windows.first?.resetsAt)
    }
    func testSubrequestFailuresMissingProceduresAndBadNumbersAreRejected() {
        for (body, expected) in [
            (#"[{"error":{"json":{"data":{"code":"UNAUTHORIZED"}}}},{"result":{"data":{"subscription":null}}}]"#, RefreshFailure.invalidCredential),
            (#"[{"result":{"data":{"totalBalance_mUsd":1}}},{"error":{"data":{"code":"FORBIDDEN"}}}]"#, .invalidCredential),
            (#"[{"result":{"data":{"totalBalance_mUsd":1}}},{"error":{"message":"provider failed"}}]"#, .unreadableResponse),
            (#"[{"result":{"data":{"totalBalance_mUsd":true}}},{"result":{"data":{"subscription":null}}}]"#, .unreadableResponse),
            (#"[{"result":{"data":{"totalBalance_mUsd":"NaN"}}},{"result":{"data":{"subscription":null}}}]"#, .unreadableResponse),
            (#"[{"result":{"data":{"totalBalance_mUsd":1}}}]"#, .unreadableResponse),
            (#"[{"result":{"data":{"totalBalance_mUsd":-1}}},{"result":{"data":{"subscription":null}}}]"#, .noQuotaWindows),
        ] {
            XCTAssertThrowsError(try KiloCodeProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, expected)
            }
        }
    }
    func testParsedWalletAndPassAlertIndependently() throws {
        let date = Date(timeIntervalSince1970: 100)
        let accountID = UUID()
        let body = fixture.replacingOccurrences(of: "12750000", with: "1000000").replacingOccurrences(of: "7.125", with: "28.0")
        let snapshot = try KiloCodeProviderClient.snapshot(Data(body.utf8), accountID: accountID, collectedAt: date)
        let result = NotificationPlanner().planSuccessfulRefresh(accountID: accountID, accountName: "Kilo", previousSnapshot: nil,
                                                               newSnapshot: snapshot, settings: AccountReminderSettings(walletAlertsEnabled: true),
                                                               ledger: ReminderLedger(), now: date)
        let delivered = result.operations.compactMap { operation -> ReminderNotificationKind? in
            if case .deliver(let notification) = operation { return notification.kind }; return nil
        }
        XCTAssertEqual(Set(delivered), Set([.walletAlert, .quotaAlert]))
    }
    func testBatchedRequestAndHTTPFailures() async throws {
        try await assertWalletExpansionRequest(provider: .kiloCode, body: fixture, endpoint: KiloCodeProviderClient.endpoint)
        let query = URLComponents(url: KiloCodeProviderClient.endpoint, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first { $0.name == "batch" }?.value, "1")
        XCTAssertEqual(query?.first { $0.name == "input" }?.value, #"{"0":{"json":null},"1":{"json":null}}"#)
    }
    @MainActor func testIndependentAccountsFailureRestartAndDeletion() async throws {
        try await assertWalletExpansionLifecycle(provider: .kiloCode, body: fixture,
                                                secondBody: fixture.replacingOccurrences(of: "12750000", with: "1000000"))
    }
}
