import Foundation
import XCTest
@testable import TokenPulse

final class SakanaProviderTests: XCTestCase {
    private let billing = #"<main><div data-slot="card-title"><span>Standard</span><span>$20/mo</span></div><div data-slot="card-title">Usage limit</div><p>5-hour</p><p>Resets on June 23, 2026 at 2:53 PM</p><p>92% used</p><p>Weekly</p><p>32% used</p></main>"#
    private let credits = #"<main><h2>Credit balance</h2><p class="tabular-nums">$1,212.34</p><h2>Usage</h2><p>$999</p></main>"#
    private let time = Date(timeIntervalSince1970: 1_000)

    private func session(_ id: UUID, cookie: String = "__Secure-authjs.session-token.0=first; __Secure-authjs.session-token.1=second") throws -> String {
        try WebProviderSession.credential(provider: .sakana, origin: SakanaProviderClient.origin, accountID: id, accessToken: cookie).encoded()
    }

    func testKnownUsageCardLimitsPlanAndUTCResetWithNonCurrencyCredits() throws {
        let snapshot = try SakanaProviderParser.snapshot(page: Data(billing.utf8), balancePage: Data(credits.utf8), accountID: UUID(), collectedAt: time)
        XCTAssertEqual(snapshot.providerPlanName, "Standard")
        XCTAssertEqual(snapshot.windows.map(\.usedPercentage), [92, 32, nil])
        XCTAssertEqual(snapshot.windows[0].resetsAt, ISO8601DateFormatter().date(from: "2026-06-23T14:53:00Z"))
        XCTAssertEqual(snapshot.windows[0].period, .fiveHour)
        XCTAssertEqual(snapshot.windows[1].period, .weekly)
        XCTAssertEqual(snapshot.windows.last?.wallet?.total, Decimal(string: "1212.34"))
        XCTAssertEqual(snapshot.windows.last?.wallet?.currency, "$ credits")
        XCTAssertEqual(snapshot.windows.last?.wallet?.isMonetary, false)
        XCTAssertNil(snapshot.windows.last?.resetsAt)
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }

    func testOnlyExplicitUSDCurrencyEnablesMoneyAndUnrelatedScriptPricesAreIgnored() throws {
        let usd = credits.replacingOccurrences(of: "$1,212.34", with: "USD $1,212.34000000000001")
        let snapshot = try SakanaProviderParser.snapshot(page: Data(billing.utf8), balancePage: Data(usd.utf8), accountID: UUID(), collectedAt: time)
        XCTAssertEqual(snapshot.windows.last?.wallet?.currency, "USD")
        XCTAssertEqual(snapshot.windows.last?.wallet?.isMonetary, true)
        XCTAssertEqual(snapshot.windows.last?.wallet?.total, Decimal(string: "1212.34000000000001"))
        let bare = try SakanaProviderParser.snapshot(page: Data(billing.utf8), balancePage: Data(credits.replacingOccurrences(of: "$1,212.34", with: "1212.34").utf8), accountID: UUID(), collectedAt: time)
        XCTAssertEqual(bare.windows.count, 2)
        let script = "<script>\(billing)</script><div data-slot=\"card-title\">Pricing</div><p>5-hour</p><p>99% used</p>"
        XCTAssertThrowsError(try SakanaProviderParser.snapshot(page: Data(script.utf8), balancePage: nil, accountID: UUID(), collectedAt: time))
        let changedCard = billing + #"<div data-slot="card-title">Pricing</div><p>5-hour</p><p>99% used</p>"#
        let scoped = try SakanaProviderParser.snapshot(page: Data(changedCard.utf8), balancePage: nil, accountID: UUID(), collectedAt: time)
        XCTAssertEqual(scoped.windows.map(\.usedPercentage), [92, 32])
    }

    func testCompleteCapturedAuthjsChunksRequiredAndNonProviderStatsCannotBeExported() throws {
        try SakanaProviderClient.validateCookies("__Secure-authjs.session-token.0=a; __Secure-authjs.session-token.1=b")
        try SakanaProviderClient.validateCookies("authjs.session-token=single")
        for bad in ["__Secure-authjs.session-token.1=only", "__Secure-authjs.session-token.0=a; __Secure-authjs.session-token.2=b",
                    "__Secure-authjs.session-token=single; __Secure-authjs.session-token.0=chunk", "cf_clearance=only"] {
            XCTAssertThrowsError(try SakanaProviderClient.validateCookies(bad))
        }
        func cookie(_ name: String, _ domain: String) -> HTTPCookie {
            HTTPCookie(properties: [.name: name, .value: "fixture", .domain: domain, .path: "/", .secure: "TRUE"])!
        }
        let selected = try SakanaProviderClient.cookiePolicy.select([cookie("__Secure-authjs.session-token.0", "console.sakana.ai"),
            cookie("__Secure-authjs.session-token.1", "console.sakana.ai"), cookie("_ga", "console.sakana.ai"), cookie("private", "google.com")], now: time)
        XCTAssertFalse(selected.header.contains("_ga")); XCTAssertFalse(selected.header.contains("private"))
        try SakanaProviderClient.validateCookies(selected.header)
    }

    func testRequestsAreDirectAndAuxiliaryWalletFailureDoesNotEraseQuota() async throws {
        let id = UUID(), transport = SakanaTransport(billing: billing, balance: credits)
        let snapshot = try await ProviderQuotaClient(provider: .sakana, transport: transport).quota(for: id, credential: session(id))
        XCTAssertEqual(snapshot.windows.count, 3)
        let requests = await transport.requests()
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, ["https://console.sakana.ai/billing", "https://console.sakana.ai/billing?tab=payAsYouGo"])
        XCTAssertTrue(requests.allSatisfy { !$0.httpShouldHandleCookies && $0.value(forHTTPHeaderField: "Accept-Language") == "en-US,en;q=0.9" })
        let failed = try await ProviderQuotaClient(provider: .sakana, transport: SakanaTransport(billing: billing, balance: "bad", balanceStatus: 500)).quota(for: id, credential: session(id))
        XCTAssertEqual(failed.windows.count, 2)
        XCTAssertEqual(failed.walletFailure, .server)
        for status in [302, 401, 403] {
            do { _ = try await ProviderQuotaClient(provider: .sakana, transport: SakanaTransport(billing: billing, balance: credits, status: status)).quota(for: id, credential: session(id)); XCTFail("Session expired") }
            catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        }
    }

    func testBindingMixedWidgetAndOnlyActuallyMonetaryBalanceTriggersMoneyAlerts() throws {
        let id = UUID(), snapshot = try SakanaProviderParser.snapshot(page: Data(billing.utf8), balancePage: Data(credits.utf8), accountID: id, collectedAt: time)
        let widget = WidgetAccountSnapshot(account: .init(id: id, name: "Fixture", provider: .sakana), windows: snapshot.windows, collectedAt: time, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 3)
        XCTAssertNil(widget.displayMetrics.last?.ringFraction)
        let plan = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "Sakana", previousSnapshot: nil,
            newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: time)
        let notices = plan.operations.compactMap { if case .deliver(let notification) = $0 { return notification.kind }; return nil }
        XCTAssertTrue(notices.contains(.quotaAlert)); XCTAssertFalse(notices.contains(.walletAlert))
        let env = try ProviderCredentialEnvelope.decode(session(id), expectedProvider: .sakana)
        XCTAssertThrowsError(try WebProviderSession.validate(env, provider: .sakana, accountID: UUID(), origins: [SakanaProviderClient.origin], now: time))
        XCTAssertNotNil(Provider.sakana.webLoginProfile); XCTAssertNotNil(Provider.sakana.iconAssetName)
    }
}

private actor SakanaTransport: ProviderTransport {
    let billing: String, balance: String, status: Int, balanceStatus: Int
    private var captured: [URLRequest] = []
    init(billing: String, balance: String, status: Int = 200, balanceStatus: Int = 200) { self.billing = billing; self.balance = balance; self.status = status; self.balanceStatus = balanceStatus }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        captured.append(request)
        let tab = request.url?.query == "tab=payAsYouGo"
        return (Data((tab ? balance : billing).utf8), HTTPURLResponse(url: request.url!, statusCode: tab ? balanceStatus : status, httpVersion: nil, headerFields: nil)!)
    }
    func requests() -> [URLRequest] { captured }
}
