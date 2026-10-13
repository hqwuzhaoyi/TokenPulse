import Foundation
import XCTest
@testable import TokenPulse

final class AtlasCloudProviderTests: XCTestCase {
    private let fixture = #"{"object":"balance","scope":"account","available":{"value":"42.50","currency":"usd"}}"#
    func testExactAccountMoneyKeepsCurrencyZeroAndNegativeWithoutQuota() throws {
        for text in ["0", "-0.001", "42.500000000000000001"] {
            let data = Data("{\"object\":\"balance\",\"scope\":\"account\",\"available\":{\"value\":\"\(text)\",\"currency\":\"eur\"}}".utf8)
            let snapshot = try AtlasCloudProviderClient.snapshot(data, accountID: UUID(), collectedAt: Date())
            let window = try XCTUnwrap(snapshot.windows.first)
            XCTAssertEqual(window.wallet?.total, Decimal(string: text))
            XCTAssertEqual(window.wallet?.currency, "EUR")
            XCTAssertNil(window.wallet?.granted)
            XCTAssertNil(window.usedPercentage)
            XCTAssertNil(window.totalCount)
            XCTAssertNil(window.resetsAt)
            XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        }
    }
    func testWrongScopeCurrencyOrDecimalNeverBecomesZero() {
        for body in [fixture.replacingOccurrences(of: "account", with: "self"), fixture.replacingOccurrences(of: "balance", with: "usage"),
                     fixture.replacingOccurrences(of: "usd", with: "US"), fixture.replacingOccurrences(of: "usd", with: "€UR"),
                     fixture.replacingOccurrences(of: "\"42.50\"", with: "42.5"), fixture.replacingOccurrences(of: "42.50", with: "NaN"), "{}"] {
            XCTAssertThrowsError(try AtlasCloudProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
    }
    func testBearerContractAndErrors() async throws {
        try await assertWalletExpansionRequest(provider: .atlasCloud, body: fixture, endpoint: AtlasCloudProviderClient.endpoint)
    }
    @MainActor func testIsolatedAccountsRestartFailureAndDeletion() async throws {
        try await assertWalletExpansionLifecycle(provider: .atlasCloud, body: fixture,
                                                secondBody: fixture.replacingOccurrences(of: "42.50", with: "9.25"))
    }
}
