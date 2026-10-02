import Foundation
import XCTest
@testable import TokenPulse

final class BifrostProviderTests: XCTestCase {
    private func reading(_ body: String, at: Double = 1000) throws -> QuotaSnapshot { try BifrostProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date(timeIntervalSince1970: at)) }

    func testActiveOverrideAndKeyProviderModelBudgetsRemainSeparateAndExact() throws {
        let body = #"{"is_active":true,"budgets":[{"id":"b","max_limit":"5","current_usage":"1.000000000000000001","reset_duration":"1h","last_reset":"1970-01-01T00:05:00Z","override_amount":5,"override_mode":"cycles","override_cycles_remaining":2}],"provider_configs":[{"provider":"openai","budgets":[{"id":"b","max_limit":20,"current_usage":10,"reset_duration":"1M"}]}],"model_configs":[{"provider":"openai","model_name":"gpt-4o","budgets":[{"id":"b","max_limit":100,"current_usage":25,"reset_duration":"7d"}]}]}"#
        let result = try reading(body)
        XCTAssertEqual(result.windows.count, 3)
        XCTAssertEqual(Set(result.windows.map(\.id)).count, 3)
        XCTAssertEqual(result.windows[0].exactCounts?.total, 10)
        XCTAssertEqual(result.windows[0].exactCounts?.used, Decimal(string: "1.000000000000000001"))
        XCTAssertEqual(result.windows[0].resetsAt, Date(timeIntervalSince1970: 3900))
        XCTAssertNotNil(result.windows[0].cycleID)
        XCTAssertNil(result.windows[1].resetsAt)
        XCTAssertNil(result.windows[2].resetsAt)
        XCTAssertEqual(result.windows.map(\.scope), ["虚拟 Key", "提供商 · openai", "模型 · openai · gpt-4o"])
        XCTAssertTrue(result.windows.allSatisfy { $0.wallet == nil && $0.unit == "USD 预算额度" })
    }

    func testExpiredOrUnknownOverrideNeverInflatesLimitAndOldClockDoesNotProject() throws {
        for (mode, cycles, expected) in [("cycles", 0, 5), ("cycles", 1, 10), ("forever", 0, 10), ("none", 5, 5)] {
            let result = try reading("{\"budgets\":[{\"id\":\"b\",\"max_limit\":5,\"current_usage\":1,\"override_amount\":5,\"override_mode\":\"\(mode)\",\"override_cycles_remaining\":\(cycles),\"reset_duration\":\"1h\",\"last_reset\":\"1970-01-01T00:00:00Z\"}]}", at: 10000)
            XCTAssertEqual(result.windows[0].exactCounts?.total, Decimal(expected))
            XCTAssertNil(result.windows[0].resetsAt)
        }
        XCTAssertEqual(BifrostProviderClient.period("1h30m").fixedSeconds, 5400)
        XCTAssertNil(BifrostProviderClient.period("1M").fixedSeconds)
        for duration in ["1d", "1w", "1M", "24h", "7d"] {
            let result = try reading("{\"budgets\":[{\"id\":\"b\",\"max_limit\":5,\"current_usage\":1,\"reset_duration\":\"\(duration)\",\"last_reset\":\"1970-01-01T00:05:00Z\"}]}")
            XCTAssertNil(result.windows[0].resetsAt)
        }
    }

    func testInactiveAndNoBudgetHaveDifferentExplicitStatesWithoutZeroPercent() throws {
        let inactive = try reading(#"{"is_active":false,"budgets":[{"id":"b","max_limit":100,"current_usage":50}]}"#)
        XCTAssertTrue(inactive.windows.isEmpty)
        XCTAssertEqual(inactive.quotaStatusText, "虚拟 Key 已停用")
        let none = try reading(#"{"is_active":true,"budgets":[]}"#)
        XCTAssertTrue(none.windows.isEmpty)
        XCTAssertEqual(none.quotaStatusText, "未配置可读取预算")
        XCTAssertThrowsError(try reading("{}"))
        XCTAssertThrowsError(try reading(#"{"budgets":[{"id":"b","max_limit":10,"current_usage":true}]}"#))
    }

    func testDecimalOverrideRefusesOverflowAndLossOfPrecision() throws {
        let huge = Decimal(sign: .plus, exponent: 127, significand: 9)
        XCTAssertThrowsError(try GatewayQuotaSupport.checkedAdd(huge, huge))
        XCTAssertThrowsError(try GatewayQuotaSupport.checkedAdd(huge, 1))
        XCTAssertEqual(try GatewayQuotaSupport.checkedAdd(5, 5), 10)
    }

    func testRequestUsesVirtualKeyHeaderAndConfiguredOriginOnly() async throws {
        let credential = try GatewayCredentials.make(provider: .bifrost, key: "fixture-vk", server: "https://gateway.example/prefix/v1")
        let transport = BifrostTransport()
        let result = try await BifrostProviderClient(transport: transport, now: { Date(timeIntervalSince1970: 1000) }).quota(accountID: UUID(), credential: credential)
        let sent = await transport.request
        let request = try XCTUnwrap(sent)
        XCTAssertEqual(request.url?.absoluteString, "https://gateway.example/prefix/api/governance/virtual-keys/quota")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-bf-vk"), "fixture-vk")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(result.snapshot.sourceCredentialFingerprint, GatewayCredentials.fingerprint(credential))
        let restored = try ProviderCredentialEnvelope.decode(credential.encoded(), expectedProvider: .bifrost)
        XCTAssertEqual(GatewayCredentials.fingerprint(restored), GatewayCredentials.fingerprint(credential))
    }
}
private actor BifrostTransport: ProviderTransport {
    var request: URLRequest?
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        return (Data(#"{"is_active":true,"budgets":[]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
