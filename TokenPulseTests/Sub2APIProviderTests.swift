import Foundation
import XCTest
@testable import TokenPulse

final class Sub2APIProviderTests: XCTestCase {
    private func snapshot(_ body: String) throws -> QuotaSnapshot { try Sub2APIProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date(timeIntervalSince1970: 100)) }

    func testWalletUsesExactAvailableMoneyWithoutInventedQuotaAndDistinguishesTokens() throws {
        let money = try snapshot(#"{"isValid":true,"balance":"16.335382880000000001","remaining":999,"unit":"USD"}"#)
        XCTAssertEqual(money.windows[0].wallet?.total, Decimal(string: "16.335382880000000001"))
        XCTAssertNil(money.windows[0].usedPercentage)
        XCTAssertNil(money.windows[0].resetsAt)
        for unit in ["points", "tokens", "PTS", "FOO"] {
            let nonmoney = try snapshot("{\"balance\":12,\"unit\":\"\(unit)\"}")
            XCTAssertEqual(nonmoney.windows[0].wallet?.isMonetary, false)
            XCTAssertEqual(nonmoney.windows[0].wallet?.currency, unit)
        }
        XCTAssertEqual(try snapshot(#"{"remaining":12}"#).windows[0].wallet?.currency, "USD")
    }

    func testQuotaSubscriptionAndRateLimitsKeepIndependentScopesUnitsAndActualDates() throws {
        let body = #"{"isValid":true,"remaining":999,"quota":{"limit":50,"used":12.5,"unit":"points"},"rate_limits":[{"window":"5h","limit":100,"used":91,"remaining":9,"reset_at":"2026-10-05T00:00:00Z"},{"window":"7d","limit":700,"used":210}],"subscription":{"daily_usage_usd":3.2,"daily_limit_usd":10,"weekly_usage_usd":21.5,"weekly_limit_usd":60,"monthly_usage_usd":74,"monthly_limit_usd":0}}"#
        let result = try snapshot(body)
        XCTAssertEqual(result.windows.count, 5)
        XCTAssertTrue(result.windows.allSatisfy { $0.wallet == nil })
        let quota = try XCTUnwrap(result.windows.first { $0.id == "sub2api.quota" })
        XCTAssertEqual(quota.usedPercentage, 25)
        XCTAssertEqual(quota.unit, "points")
        XCTAssertNil(quota.isExhausted)
        XCTAssertNil(quota.exactCounts?.remaining)
        XCTAssertEqual(quota.resetSemantics, .nonResettingAllowance)
        let rates = result.windows.filter { $0.scope == "限流" }
        XCTAssertNotNil(rates[0].resetsAt)
        XCTAssertNil(rates[1].resetsAt)
        XCTAssertTrue(result.windows.filter { $0.scope == "分组订阅" }.allSatisfy { $0.resetsAt == nil })
        XCTAssertNil(Sub2APIProviderClient.seconds("1m"))
        XCTAssertNil(Sub2APIProviderClient.seconds("999999999999999999999999h"))
    }

    func testBodyRefusalAndMalformedDataNeverLookLikeAnEmptyOrSpentAccount() throws {
        XCTAssertThrowsError(try snapshot(#"{"isValid":false,"balance":null}"#)) { XCTAssertEqual($0 as? RefreshFailure, .invalidCredential) }
        for body in [#"{"isValid":0,"balance":12}"#, #"{"balance":true}"#, #"{"balance":"NaN"}"#, #"{"quota":{"limit":100,"used":-1}}"#] {
            XCTAssertThrowsError(try snapshot(body))
        }
        XCTAssertThrowsError(try snapshot(#"{"quota":{"limit":0,"used":0},"remaining":999}"#)) { XCTAssertEqual($0 as? RefreshFailure, .noQuotaWindows) }
        XCTAssertThrowsError(try snapshot(#"{"rate_limits":[{"window":"5h","limit":10,"used":1},{"window":"5h","limit":20,"used":2}]}"#))
    }

    func testGatewayAddressKeyProviderScopesAndSafeGETContract() async throws {
        let original = try GatewayCredentials.make(provider: .sub2api, key: "fixture-group", server: "relay.example/prefix/v1/usage/")
        XCTAssertEqual(original.metadata["serverAddress"], "https://relay.example/prefix")
        XCTAssertEqual(GatewayCredentials.fingerprint(original), GatewayCredentials.fingerprint(try GatewayCredentials.make(provider: .sub2api, key: "fixture-group", server: "https://RELAY.example:443/prefix/v1")))
        XCTAssertNotEqual(GatewayCredentials.fingerprint(original), GatewayCredentials.fingerprint(try GatewayCredentials.make(provider: .sub2api, key: "other", server: "https://relay.example/prefix")))
        XCTAssertNotEqual(GatewayCredentials.fingerprint(original), GatewayCredentials.fingerprint(try GatewayCredentials.make(provider: .sub2api, key: "fixture-group", server: "https://other.example/prefix")))
        XCTAssertNotEqual(GatewayCredentials.fingerprint(original), GatewayCredentials.fingerprint(try GatewayCredentials.make(provider: .newAPI, key: "fixture-group", server: "https://relay.example/prefix")))
        XCTAssertThrowsError(try GatewayCredentials.make(provider: .sub2api, key: "fixture", server: "https://u:p@relay.example"))
        XCTAssertThrowsError(try GatewayCredentials.make(provider: .sub2api, key: "fixture", server: "https://relay.example?key=x"))
        let restored = try ProviderCredentialEnvelope.decode(original.encoded(), expectedProvider: .sub2api)
        XCTAssertEqual(GatewayCredentials.fingerprint(original), GatewayCredentials.fingerprint(restored))
        let transport = Sub2Transport(status: 200, body: #"{"balance":12,"unit":"USD"}"#)
        let result = try await Sub2APIProviderClient(transport: transport, now: { Date(timeIntervalSince1970: 100) }).quota(accountID: UUID(), credential: restored)
        let sent = await transport.request
        let request = try XCTUnwrap(sent)
        XCTAssertEqual(request.url?.absoluteString, "https://relay.example/prefix/v1/usage")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-group")
        XCTAssertEqual(result.snapshot.sourceCredentialFingerprint, GatewayCredentials.fingerprint(original))
    }

    func testRemindersUseMoneyOrDeclaredLimitsAndNeverScheduleSubscriptionGuesses() throws {
        let snapshot = try self.snapshot(#"{"balance":1,"unit":"USD","subscription":{"weekly_usage_usd":95,"weekly_limit_usd":100}}"#)
        let result = NotificationPlanner().planSuccessfulRefresh(accountID: snapshot.accountID, accountName: "sub2api", previousSnapshot: nil, newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: snapshot.collectedAt)
        XCTAssertTrue(result.operations.contains { if case .deliver(let value) = $0 { return value.kind == .walletAlert }; return false })
        XCTAssertFalse(result.operations.contains { if case .schedule = $0 { return true }; return false })
        let points = try self.snapshot(#"{"balance":1,"unit":"points"}"#)
        let nonmoney = NotificationPlanner().planSuccessfulRefresh(accountID: points.accountID, accountName: "sub2api", previousSnapshot: nil, newSnapshot: points, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: points.collectedAt)
        XCTAssertTrue(nonmoney.operations.isEmpty)
    }
}

private actor Sub2Transport: ProviderTransport {
    let status: Int; let body: String
    var request: URLRequest?
    init(status: Int, body: String) { self.status = status; self.body = body }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
