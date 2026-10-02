import Foundation
import XCTest
@testable import TokenPulse

final class WebProviderSessionTests: XCTestCase {
    func testScopeChangesCannotReuseIdentityAndCookiesRespectPathAndExpiry() throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let credential = try WebProviderSession.credential(provider: .raycastAI, origin: "https://www.raycast.com", accountID: id,
            accessToken: "__raycast_session=fixture", metadata: ["workspaceID": "one"])
        try WebProviderSession.validate(credential, provider: .raycastAI, accountID: id, origins: ["https://www.raycast.com"], now: now)
        XCTAssertThrowsError(try WebProviderSession.validate(credential, provider: .raycastAI, accountID: UUID(), origins: ["https://www.raycast.com"], now: now))
        var changed = credential; changed.metadata["workspaceID"] = "two"
        XCTAssertNotEqual(changed.sourceCredentialIdentity, credential.sourceCredentialIdentity)
        XCTAssertThrowsError(try WebProviderSession.validate(changed, provider: .raycastAI, accountID: id, origins: ["https://www.raycast.com"], now: now))
        let policy = CookieWebSessionPolicy(domains: ["example.com"], path: "/api/usage", prefixes: ["session."], requiredAnyNames: ["session.0"])
        func cookie(_ name: String, domain: String = "example.com", path: String = "/", expires: Date? = nil) -> HTTPCookie {
            var props: [HTTPCookiePropertyKey: Any] = [.name: name, .value: "fixture", .domain: domain, .path: path]
            if let expires { props[.expires] = expires }
            return HTTPCookie(properties: props)!
        }
        let selection = try policy.select([cookie("session.0"), cookie("session.1"), cookie("analytics"),
            cookie("session.bad", domain: "other.com"), cookie("session.private", path: "/settings"),
            cookie("session.old", expires: Date(timeIntervalSince1970: 90))], now: now)
        XCTAssertEqual(selection.header, "session.0=fixture; session.1=fixture")
        XCTAssertThrowsError(try policy.values(in: "session.0=fixture; unknown=other"))
        XCTAssertThrowsError(try policy.values(in: "session.0=fixture; session.0=other"))
    }
    func testOriginAndHeaderRestrictionsRejectInvalidSessions() throws {
        let profile = try XCTUnwrap(Provider.raycastAI.webLoginProfile)
        XCTAssertTrue(profile.permits(URL(string: "https://www.raycast.com/settings")))
        for url in ["http://www.raycast.com", "https://www.raycast.com.evil.test", "https://www.raycast.com:444", "https://user@www.raycast.com"] {
            XCTAssertFalse(profile.permits(URL(string: url)))
        }
        XCTAssertThrowsError(try WebProviderSession.credential(provider: .raycastAI, origin: "https://www.raycast.com/path", accountID: UUID(), accessToken: "a"))
        XCTAssertThrowsError(try WebProviderSession.credential(provider: .raycastAI, origin: "https://www.raycast.com", accountID: UUID(), accessToken: "a\r\nInjected: x"))
        let expired = try WebProviderSession.credential(provider: .raycastAI, origin: "https://www.raycast.com", accountID: UUID(), accessToken: "a", expiresAt: .distantPast)
        XCTAssertThrowsError(try WebProviderSession.validate(expired, provider: .raycastAI,
            accountID: UUID(uuidString: expired.metadata["localAccountID"]!)!, origins: ["https://www.raycast.com"], now: Date()))
    }
}

final class HostedWebProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100)
    private let raycast = #"{"remaining_balance_credits":"75.125","total_balance_credits":"100","next_credits_at":"2026-11-02T10:00:00Z","funding_subscription":{"tier":"pro_plus"}}"#
    private let zoom = #"{"data":{"credit_status":{"budget_cap":1000,"used_credit":1100,"remaining_credit":0,"overage_credit":100,"allow_overage":true,"is_quota_available":true,"cycle_end_date":1793613600000}}}"#
    private let t3 = """
    {"json":{"0":[[0],[null,0,0]]}}
    {"json":[0,0,[[{"result":0}],["result",0,1]]]}
    {"json":[1,0,[[{"data":0}],["data",0,2]]]}
    {"json":[2,0,[[{"subTier":"pro","subscription":{"productName":"pro","currentPeriodEnd":1780763009000},"usageFourHourPercentage":12.5,"usageMonthPercentage":34.25,"usageFourHourNextResetAt":1779366216920,"usagePeriodPercentage":44}]]]}
    """
    private func envelope(_ provider: Provider, id: UUID) throws -> ProviderCredentialEnvelope {
        try WebProviderSession.credential(provider: provider, origin: HostedWebProfiles.origin(provider), accountID: id,
            accessToken: provider == .raycastAI ? "__raycast_session=fixture" : "fixture-session=fixture")
    }
    func testRaycastExactCountsPartialMissingAndNoInventedPeriod() throws {
        let snapshot = try RaycastAIProviderClient.snapshot(Data(raycast.utf8), accountID: UUID(), collectedAt: now)
        XCTAssertEqual(snapshot.providerPlanName, "Pro+")
        XCTAssertEqual(snapshot.windows[0].exactCounts?.used, Decimal(string: "24.875"))
        XCTAssertEqual(snapshot.windows[0].period, .other)
        let partial = try RaycastAIProviderClient.snapshot(Data(#"{"remaining_balance_credits":"0.00000000000000000000001"}"#.utf8), accountID: UUID(), collectedAt: now)
        XCTAssertNil(partial.windows[0].usedPercentage)
        XCTAssertNil(partial.windows[0].isExhausted)
        XCTAssertNotEqual(QuotaFormatting.usage(partial.windows[0]), "未提供")
        XCTAssertThrowsError(try RaycastAIProviderClient.snapshot(Data(#"{"remaining_balance_credits":true}"#.utf8), accountID: UUID(), collectedAt: now))
        XCTAssertThrowsError(try RaycastAIProviderClient.snapshot(Data("{}".utf8), accountID: UUID(), collectedAt: now))
    }
    func testT3ResolvesRequestedStreamOnlyAndKeepsSeparateResetDates() throws {
        let decoy = "\n{\"json\":[99,0,[[{\"usageFourHourPercentage\":99}]]]}"
        let snapshot = try T3ChatProviderClient.snapshot(Data((t3 + decoy).utf8), accountID: UUID(), collectedAt: now)
        XCTAssertEqual(snapshot.windows.map(\.usedPercentage), [12.5,34.25])
        XCTAssertEqual(snapshot.windows[1].resetsAt, Date(timeIntervalSince1970: 1780763009))
        XCTAssertNotEqual(snapshot.windows[0].resetsAt, snapshot.windows[1].resetsAt)
        let nested = #"{"unrelated":{"usageFourHourPercentage":99}}"#
        XCTAssertThrowsError(try T3ChatProviderClient.snapshot(Data(nested.utf8), accountID: UUID(), collectedAt: now))
        let unknownPeriod = #"{"result":{"data":{"json":{"usagePeriodPercentage":40}}}}"#
        XCTAssertThrowsError(try T3ChatProviderClient.snapshot(Data(unknownPeriod.utf8), accountID: UUID(), collectedAt: now))
        XCTAssertThrowsError(try T3ChatProviderClient.snapshot(Data(t3.replacingOccurrences(of: "34.25", with: "true").utf8), accountID: UUID(), collectedAt: now))
        XCTAssertThrowsError(try T3ChatProviderClient.snapshot(Data((t3 + "\n" + t3.split(separator: "\n")[3]).utf8), accountID: UUID(), collectedAt: now))
    }
    func testZoomUnlimitedOverageDisabledAndSafeDates() throws {
        let overage = try ZoomMateProviderClient.snapshot(Data(zoom.utf8), accountID: UUID(), collectedAt: now).windows[0]
        XCTAssertEqual(overage.isExhausted, false)
        XCTAssertEqual(QuotaFormatting.usage(overage), "超额付费 100 credits")
        let disabled = try ZoomMateProviderClient.snapshot(Data(zoom.replacingOccurrences(of: "\"is_quota_available\":true", with: "\"is_quota_available\":false").utf8), accountID: UUID(), collectedAt: now).windows[0]
        XCTAssertEqual(disabled.isExhausted, true)
        XCTAssertEqual(QuotaFormatting.usage(disabled), "已用尽")
        let unlimited = try ZoomMateProviderClient.snapshot(Data(#"{"data":{"credit_status":{"is_unlimited":true}}}"#.utf8), accountID: UUID(), collectedAt: now).windows[0]
        XCTAssertTrue(unlimited.isUnlimited); XCTAssertNil(unlimited.usedPercentage)
        XCTAssertNil(HostedWebHTTP.epoch(1e30, millisecondsOnly: true))
        XCTAssertThrowsError(try ZoomMateProviderClient.token(Data(#"{"success":false,"data":{"nak":"still-rejected"}}"#.utf8)))
        XCTAssertThrowsError(try ZoomMateProviderClient.snapshot(Data(#"{"data":{"credit_status":{"is_unlimited":1}}}"#.utf8), accountID: UUID(), collectedAt: now))
    }
    func testRequestsValidateAccountAndPreserveCookieOnlyOnExpectedHost() async throws {
        let date = now
        for (provider, body) in [(Provider.raycastAI, raycast), (.t3Chat, t3)] {
            let id = UUID(), transport = HostedWebTestTransport(replies: [(200, body)])
            let credential = try envelope(provider, id: id)
            let result = try await ProviderQuotaClient(provider: provider, transport: transport, now: { date }).quotaResult(for: id, credential: credential.encoded())
            XCTAssertEqual(result.snapshot.sourceCredentialFingerprint, credential.sourceCredentialIdentity)
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1); XCTAssertEqual(requests[0].httpMethod, "GET")
            XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Cookie"), credential.accessToken)
            XCTAssertFalse(requests[0].httpShouldHandleCookies)
            XCTAssertEqual(requests[0].url?.host, URL(string: HostedWebProfiles.origin(provider))?.host)
            do { _ = try await ProviderQuotaClient(provider: provider, transport: transport).quota(for: UUID(), credential: credential.encoded()); XCTFail("Account mismatch") }
            catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
            let after = await transport.requests; XCTAssertEqual(after.count, 1)
        }
    }
    func testZoomRefreshExchangesNewTokenWithoutPersistenceAndOnlyRetriesUnavailableHosts() async throws {
        let id = UUID(), credential = try envelope(.zoomMate, id: id), date = now
        let transport = HostedWebTestTransport(replies: [(503,"{}"), (200,#"{"success":true,"data":{"nak":"temporary-one"}}"#), (200,zoom)])
        let result = try await ProviderQuotaClient(provider: .zoomMate, transport: transport, now: { date }).quotaResult(for: id, credential: credential.encoded())
        XCTAssertNil(result.updatedCredential)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.host }, ["ai.zoom.us","zoommate.zoom.us","zoommate.zoom.us"])
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer temporary-one")
        for status in [302,401,403,429] {
            let denied = HostedWebTestTransport(replies: [(status,"{}")])
            do { _ = try await ProviderQuotaClient(provider: .zoomMate, transport: denied).quota(for: id, credential: credential.encoded()); XCTFail("Refusal") } catch {}
            let count = await denied.requests.count; XCTAssertEqual(count, 1)
        }
    }
    func testHostedWebProviderWidgetsAndDemoHaveDefinedUnitsAndNoWalletAlerts() throws {
        for provider in [Provider.raycastAI, .t3Chat, .zoomMate] {
            let account = SubscriptionAccount(name: "fixture", provider: provider)
            let demo = DemoMode.snapshot(accountID: account.id, provider: provider, now: now)
            let widget = WidgetAccountSnapshot(account: account, windows: demo.windows, collectedAt: now, lastFailure: nil)
            XCTAssertFalse(widget.displayMetrics.isEmpty)
            XCTAssertTrue(demo.windows.allSatisfy { $0.wallet == nil })
            XCTAssertEqual(ProviderAuthenticationController().loginConfiguration(for: provider).method, .webSession)
            XCTAssertNotNil(provider.systemIconName)
        }
    }
}

private actor HostedWebTestTransport: ProviderTransport {
    private var replies: [(Int,String)]
    private(set) var requests: [URLRequest] = []
    init(replies: [(Int,String)]) { self.replies = replies }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw RefreshFailure.server }
        let (status, body) = replies.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
