import Foundation
import XCTest
@testable import TokenPulse

final class AixyProviderTests: XCTestCase {
    private func envelope(_ budgets: [String]) -> String {
        #"{"object":"key.usage","currency":"USD","key":{"id":"key-a","project_id":"project-a"},"budgets":["#
            + budgets.joined(separator: ",") + "]}"
    }
    private func budget(_ id: String, enforcement: String = "hard", interval: String = "monthly",
                        key: String = "key-a", spent: String = "40", reserved: String = "20") -> String {
        """
        {"id":"\(id)","scope":"team","target_name":"Team","shared":true,
         "interval":"\(interval)","enforcement":"\(enforcement)","limit_usd":"100",
         "applies_to":[{"api_key_id":"\(key)","project_id":"project-a"}],
         "availability":{"status":"available","spent_usd":"\(spent)","reserved_usd":"\(reserved)"},
         "spend_status":"available","spend_usd":"99","resets_at":"2026-11-01T00:00:00Z"}
        """
    }

    func testKeepsOverlappingScopesAndReservesOnlyForHardBudgets() async throws {
        let body = envelope([budget("first"), budget("second", spent: "60"),
                             budget("monitor", enforcement: "monitor"), budget("other", key: "key-b")])
        let transport = HostedQuotaTransport(body)
        let credential = try ProviderAuthenticationController().credential(provider: .aixy, apiKey: "fixture")
        let snapshot = try await ProviderQuotaClient(provider: .aixy, transport: transport).quota(for: UUID(), credential: credential)
        XCTAssertEqual(snapshot.windows.map(\.id), ["aixy.second", "aixy.first", "aixy.monitor"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercentage), [80, 60, 99])
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.scope == "团队 · Team · 共享" && $0.wallet == nil })
        XCTAssertEqual(snapshot.windows[0].exactCounts?.used, 80)
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://api.aixy-gateway.com/v1/usage")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
    }

    func testUnknownUsageRetainsLimitWithoutZeroAndLifetimeNeverResets() throws {
        let unknown = budget("unknown").replacingOccurrences(of: #""status":"available""#, with: #""status":"unavailable""#)
        let snapshot = try AixyProviderClient.snapshot(Data(envelope([unknown, budget("life", interval: "lifetime")]).utf8),
                                                        accountID: UUID(), collectedAt: Date())
        XCTAssertNil(snapshot.windows[0].usedPercentage)
        XCTAssertNil(snapshot.windows[0].exactCounts?.used)
        XCTAssertEqual(snapshot.windows[0].exactCounts?.total, 100)
        XCTAssertTrue(snapshot.windows[0].name.contains("未提供"))
        XCTAssertNil(snapshot.windows[1].resetsAt)
        XCTAssertEqual(snapshot.windows[1].resetSemantics, .nonResettingAllowance)
    }

    func testDuplicateIDsWrongCurrencyAndMalformedAmountsFail() throws {
        let cases = [envelope([budget("same"), budget("same")]),
                     envelope([budget("a")]).replacingOccurrences(of: #""currency":"USD""#, with: #""currency":"EUR""#),
                     envelope([budget("a")]).replacingOccurrences(of: #""limit_usd":"100""#, with: #""limit_usd":true"#)]
        for body in cases {
            XCTAssertThrowsError(try AixyProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date()))
        }
    }
}
