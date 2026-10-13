import Foundation
import XCTest
@testable import TokenPulse

final class ClawRouterProviderTests: XCTestCase {
    func testIntegerMicroDollarsAndReportedCycleNeverBecomeGuessedResetDate() async throws {
        let body = #"{"budget":{"configured":true,"limitMicros":300000,"spentMicros":100000,"windowKey":"fixture/2026-10"}}"#
        let transport = HostedQuotaTransport(body)
        let credential = try ProviderAuthenticationController().credential(provider: .clawRouter, apiKey: "fixture")
        let snapshot = try await ProviderQuotaClient(provider: .clawRouter, transport: transport).quota(for: UUID(), credential: credential)
        let window = try XCTUnwrap(snapshot.windows.first)
        XCTAssertEqual(window.exactCounts?.used, Decimal(string: "0.1"))
        XCTAssertEqual(window.exactCounts?.remaining, Decimal(string: "0.2"))
        XCTAssertEqual(window.exactCounts?.total, Decimal(string: "0.3"))
        XCTAssertEqual(window.cycleID, "fixture/2026-10")
        XCTAssertNil(window.resetsAt)
        XCTAssertNil(window.wallet)
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://clawrouter.openclaw.ai/v1/usage")
    }

    func testMissingBudgetIsNotSpentAndFractionsCannotMasqueradeAsMicroIntegers() throws {
        for body in [#"{"budget":{"configured":false}}"#,
                     #"{"budget":{"configured":true,"limitMicros":0,"spentMicros":0}}"#] {
            XCTAssertTrue(try ClawRouterProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date()).windows.isEmpty)
        }
        for body in [#"{"budget":{"configured":1,"limitMicros":100,"spentMicros":0}}"#,
                     #"{"budget":{"configured":true,"limitMicros":100,"spentMicros":0.1}}"#,
                     #"{"budget":{"configured":true,"limitMicros":9223372036854775808,"spentMicros":0}}"#] {
            XCTAssertThrowsError(try ClawRouterProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date()))
        }
    }

    func testExactBoundaryRetainsOneMicroDollarAndWidgetKeepsBudgetSeparate() throws {
        let account = SubscriptionAccount(name: "Budget", provider: .clawRouter)
        let now = Date()
        let snapshot = try ClawRouterProviderClient.snapshot(Data(#"{"budget":{"configured":true,"limitMicros":10000000000000000,"spentMicros":9999999999999999}}"#.utf8), accountID: account.id, collectedAt: now)
        let window = try XCTUnwrap(snapshot.windows.first)
        XCTAssertEqual(window.exactCounts?.remaining, Decimal(string: "0.000001"))
        XCTAssertLessThan(try XCTUnwrap(window.usedPercentage), 100)
        let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows, collectedAt: now, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 1)
        XCTAssertNotEqual(widget.displayMetrics.first?.displayTitle, "钱包余额")
    }
}
