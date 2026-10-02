import Foundation
import XCTest
@testable import TokenPulse

final class LiteLLMProviderTests: XCTestCase {
    private let identity = LiteLLMProviderClient.Identity(user: "user-1", team: "team-1")
    private let userReply = #"{"user_id":"user-1","user_info":{"user_id":"user-1","spend":"12.000000000000000001","max_budget":100,"budget_duration":"1mo","budget_reset_at":"2026-11-01T00:00:00Z"},"teams":[{"team_id":"other","spend":999,"max_budget":1},{"team_id":"team-1","spend":20,"max_budget":50,"budget_duration":"7d","budget_reset_at":"2026-10-05T00:00:00Z"}]}"#

    func testReturnedIdentitiesMustMatchAndOnlyBoundTeamIsIncluded() throws {
        let snapshot = try LiteLLMProviderClient.userSnapshot(Data(userReply.utf8), identity: identity, accountID: UUID(), at: Date())
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.windows[0].scope, "团队 · team-1")
        XCTAssertEqual(snapshot.windows[0].usedPercentage, 40)
        XCTAssertEqual(snapshot.windows[1].scope, "用户 · user-1")
        XCTAssertEqual(snapshot.windows[1].exactCounts?.used, Decimal(string: "12.000000000000000001"))
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.wallet == nil })
        XCTAssertThrowsError(try LiteLLMProviderClient.userSnapshot(Data(userReply.replacingOccurrences(of: #""user_id":"user-1""#, with: #""user_id":"foreign""#).utf8), identity: identity, accountID: UUID(), at: Date()))
        let contradictory = userReply.replacingOccurrences(of: #"{"user_id":"user-1","user_info""#, with: #"{"user_id":"foreign","user_info""#)
        XCTAssertThrowsError(try LiteLLMProviderClient.userSnapshot(Data(contradictory.utf8), identity: identity, accountID: UUID(), at: Date()))
        XCTAssertThrowsError(try LiteLLMProviderClient.teamSnapshot(Data(#"{"team_id":"other","team_info":{"team_id":"team-1","spend":1,"max_budget":10}}"#.utf8), identity: .init(user: nil, team: "team-1"), accountID: UUID(), at: Date()))
    }

    func testMissingLimitKeepsKnownSpendButNeverInfersZeroExhaustionOrPercent() throws {
        let reply = #"{"team_id":"team-1","team_info":{"team_id":"team-1","spend":"2.000000000000000001","max_budget":null}}"#
        let snapshot = try LiteLLMProviderClient.teamSnapshot(Data(reply.utf8), identity: .init(user: nil, team: "team-1"), accountID: UUID(), at: Date())
        XCTAssertEqual(snapshot.windows[0].exactCounts?.used, Decimal(string: "2.000000000000000001"))
        XCTAssertNil(snapshot.windows[0].exactCounts?.total)
        XCTAssertNil(snapshot.windows[0].usedPercentage)
        XCTAssertNil(snapshot.windows[0].isExhausted)
        XCTAssertNotNil(snapshot.quotaStatusText)
        XCTAssertEqual(LiteLLMProviderClient.period("1mo"), .monthly)
        XCTAssertEqual(LiteLLMProviderClient.period("7d"), .weekly)
        XCTAssertEqual(LiteLLMProviderClient.period("999999999999999999999h"), .other)
        XCTAssertThrowsError(try LiteLLMProviderClient.identity(Data(#"{"info":{"user_id":"u","status":"revoked"}}"#.utf8)))
        XCTAssertThrowsError(try LiteLLMProviderClient.identity(Data(#"{"info":{"user_id":"u","blocked":true}}"#.utf8)))
    }

    func testPermissionDeniedIsOneReadableStatusWithoutSpendFallbackOrFakeBudget() async throws {
        let credential = try GatewayCredentials.make(provider: .liteLLM, key: "fixture-vk", server: "https://proxy.example/v1")
        for status in [403, 404] {
            let transport = LiteTransport(status: status, bodies: ["{}"])
            let result = try await LiteLLMProviderClient(transport: transport, now: { Date() }).quota(accountID: UUID(), credential: credential)
            XCTAssertTrue(result.snapshot.windows.isEmpty)
            XCTAssertTrue(result.snapshot.quotaStatusText?.contains("无权") == true)
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests[0].url?.path, "/key/info")
        }
    }

    func testDirectQueryKeepsIdentityInEncodedParameterNotURLHostOrAnotherTeam() async throws {
        let credential = try GatewayCredentials.make(provider: .liteLLM, key: "fixture-vk", server: "https://proxy.example/base/v1")
        let user = "user+1&team_id=other"
        let response = try JSONSerialization.data(withJSONObject: ["user_id": user, "user_info": ["user_id": user, "spend": 1, "max_budget": 10]])
        let keyBody = try JSONSerialization.data(withJSONObject: ["info": ["user_id": user]])
        let transport = LiteTransport(status: 200, bodies: [String(decoding: keyBody, as: UTF8.self), String(decoding: response, as: UTF8.self)])
        let result = try await LiteLLMProviderClient(transport: transport, now: { Date() }).quota(accountID: UUID(), credential: credential)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].url?.host, "proxy.example")
        XCTAssertEqual(requests[1].url?.path, "/base/user/info")
        let items = URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.count, 1)
        XCTAssertEqual(items?.first?.name, "user_id")
        XCTAssertEqual(items?.first?.value, user)
        XCTAssertTrue(requests[1].url?.absoluteString.contains("%2B") == true)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer fixture-vk")
        XCTAssertEqual(result.snapshot.sourceCredentialFingerprint, GatewayCredentials.fingerprint(credential))
    }
}
private actor LiteTransport: ProviderTransport {
    let status: Int; var bodies: [String]; var requests: [URLRequest] = []
    init(status: Int, bodies: [String]) { self.status = status; self.bodies = bodies }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return (Data(bodies.removeFirst().utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
