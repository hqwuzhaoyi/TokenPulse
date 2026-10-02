import Foundation
import XCTest
@testable import TokenPulse

final class LLMProxyProviderTests: XCTestCase {
    func testEveryUpstreamGroupKeepsOwnPercentAndResetWithoutGlobalMinimum() throws {
        let data = Data(#"{"providers":{"openai":{"quota_groups":{"default":{"remaining_percent":42,"reset_time":"2026-10-05T00:00:00Z"},"fast":{"remaining_percent":80}}},"gemini_cli":{"quota_groups":[{"remaining_percent":0},{"remaining_percent":90}]}}}"#.utf8)
        let snapshot = try LLMProxyProviderClient.snapshot(data, accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(snapshot.windows.count, 4)
        XCTAssertEqual(Set(snapshot.windows.map(\.id)).count, 4)
        XCTAssertEqual(snapshot.windows.filter { $0.scope == "openai" }.first?.usedPercentage, 58)
        XCTAssertEqual(snapshot.windows.filter { $0.scope == "openai · fast" }.first?.usedPercentage, 20)
        XCTAssertNotNil(snapshot.windows.first { $0.scope == "openai" }?.resetsAt)
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.exactCounts == nil && $0.wallet == nil && $0.totalCount == nil })
    }

    func testMalformedGroupsSkipLocallyWithoutFalseZeroOrResetAndEmptyHasStatus() throws {
        let body = #"{"providers":{"bad":{"quota_groups":"oops"},"good":{"quota_groups":{"valid":{"remaining_percent":50,"reset_time":"not-a-date"},"invalid":{"remaining_percent":-1},"bool":{"remaining_percent":false},"missing":{}}}}}"#
        let snapshot = try LLMProxyProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].usedPercentage, 50)
        XCTAssertNil(snapshot.windows[0].resetsAt)
        let empty = try LLMProxyProviderClient.snapshot(Data(#"{"providers":{}}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertTrue(empty.windows.isEmpty)
        XCTAssertNotNil(empty.quotaStatusText)
        XCTAssertThrowsError(try LLMProxyProviderClient.snapshot(Data("{}".utf8), accountID: UUID(), collectedAt: Date()))
    }

    func testNamedIdentityIsStableAfterObjectReorderingAndDoesNotCollideWithListIndex() throws {
        let first = #"{"providers":{"p":{"quota_groups":{"a":{"remaining_percent":10},"b":{"remaining_percent":20}}}}}"#
        let second = #"{"providers":{"p":{"quota_groups":{"b":{"remaining_percent":20},"a":{"remaining_percent":10}}}}}"#
        let a = try LLMProxyProviderClient.snapshot(Data(first.utf8), accountID: UUID(), collectedAt: Date())
        let b = try LLMProxyProviderClient.snapshot(Data(second.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(a.windows, b.windows)
    }

    func testProxyQueryIsOnlyReadGETAtConfiguredServerWithScopedKey() async throws {
        let key = try GatewayCredentials.make(provider: .llmProxy, key: "fixture-proxy-key", server: "https://proxy.example/base/v1")
        let transport = ProxyTransport()
        let result = try await LLMProxyProviderClient(transport: transport, now: { Date() }).quota(accountID: UUID(), credential: key)
        let sent = await transport.request
        let request = try XCTUnwrap(sent)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://proxy.example/base/v1/quota-stats")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-proxy-key")
        XCTAssertEqual(result.snapshot.sourceCredentialFingerprint, GatewayCredentials.fingerprint(key))
        let changed = try GatewayCredentials.make(provider: .llmProxy, key: "other", server: "https://proxy.example/base")
        XCTAssertNotEqual(GatewayCredentials.fingerprint(key), GatewayCredentials.fingerprint(changed))
    }
}
private actor ProxyTransport: ProviderTransport {
    var request: URLRequest?
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        return (Data(#"{"providers":{"p":{"quota_groups":{"default":{"remaining_percent":50}}}}}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
