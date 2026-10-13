import Foundation
import XCTest
@testable import TokenPulse

final class MistralProviderTests: XCTestCase {
    private let money = #"{"wallet_amount":"10.123456789012345678","credit_notes_amount":2,"ongoing_usage_balance":1,"currency":"EUR"}"#
    private let time = Date(timeIntervalSince1970: 1_000)

    private func page(_ stream: String) throws -> String {
        let bytes = try JSONSerialization.data(withJSONObject: [1, stream])
        return "<script>self.__next_f.push(\(String(decoding: bytes, as: UTF8.self)))</script>"
    }
    private func session(_ id: UUID, csrf: Bool = true) throws -> String {
        try WebProviderSession.credential(provider: .mistral, origin: MistralProviderClient.origin, accountID: id,
            accessToken: csrf ? "ory_session_fixture=token; csrftoken=csrf" : "ory_session_fixture=token").encoded()
    }

    func testCurrencyAndAllThreeReportedComponentsAreRequiredForExactNetWallet() throws {
        let wallet = try XCTUnwrap(MistralProviderParser.wallet(Data(money.utf8)))
        XCTAssertEqual(wallet.total, Decimal(string: "11.123456789012345678"))
        XCTAssertEqual(wallet.currency, "EUR")
        for text in [#"{"wallet_amount":10,"currency":"USD"}"#, #"{"wallet_amount":10,"credit_notes_amount":0,"ongoing_usage_balance":0}"#,
                     #"{"wallet_amount":10,"credit_notes_amount":0,"ongoing_usage_balance":0,"currency":"$"}"#] {
            XCTAssertNil(try MistralProviderParser.wallet(Data(text.utf8)))
        }
        XCTAssertThrowsError(try MistralProviderParser.wallet(Data(#"{"wallet_amount":true,"credit_notes_amount":0,"ongoing_usage_balance":0,"currency":"USD"}"#.utf8)))
        let debt = try MistralProviderParser.wallet(Data(#"{"wallet_amount":0,"credit_notes_amount":0,"ongoing_usage_balance":2,"currency":"USD"}"#.utf8))
        XCTAssertEqual(debt?.total, -2)
    }

    func testFlightParsingNamesAPIAndVibeOnlyAndConflictingObjectsDoNotChooseAnAccount() throws {
        let stream = #"{"api_budget":{"usage_percentage":25,"reset_at":"$D2026-10-03T00:00:00Z"},"vibe_budget":{"usage_percentage":120},"monthly_price":"$99"}"#
        let budgets = try MistralProviderParser.subscription(page(stream))
        XCTAssertEqual(budgets["api_budget"]?.usage_percentage, 25)
        XCTAssertEqual(budgets["vibe_budget"]?.usage_percentage, 120)
        XCTAssertNotNil(budgets["api_budget"]?.windowReset)
        let duplicate = try MistralProviderParser.subscription(page(stream + #"{"api_budget":{"usage_percentage":50}}"#))
        XCTAssertNil(duplicate["api_budget"])
        XCTAssertNotNil(duplicate["vibe_budget"])
        let bad = try MistralProviderParser.subscription(page(#"{"api_budget":{"usage_percentage":true}}"#))
        XCTAssertTrue(bad.isEmpty)
        let snapshot = try MistralProviderParser.snapshot(wallet: MistralProviderParser.wallet(Data(money.utf8)), budgets: budgets, accountID: UUID(), collectedAt: time)
        XCTAssertEqual(snapshot.windows.map(\.id), ["mistral.api", "mistral.vibe", "mistral.wallet.EUR"])
        XCTAssertEqual(snapshot.windows[1].isExhausted, true)
        XCTAssertNil(snapshot.windows.last?.resetsAt)
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }

    func testNetWalletRejectsOverflowAndSilentAbsorptionOfTinyAmount() {
        let huge = Decimal.greatestFiniteMagnitude.description
        for payload in [
            "{\"wallet_amount\":\(huge),\"credit_notes_amount\":\(huge),\"ongoing_usage_balance\":0,\"currency\":\"USD\"}",
            #"{"wallet_amount":"100000000000000000","credit_notes_amount":0,"ongoing_usage_balance":"0.0000000000000000000001","currency":"USD"}"#,
            #"{"wallet_amount":"100000000000000000","credit_notes_amount":"0.0000000000000000000001","ongoing_usage_balance":0,"currency":"USD"}"#
        ] {
            XCTAssertThrowsError(try MistralProviderParser.wallet(Data(payload.utf8))) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
    }

    func testOfflineMultiArgumentPushReadsAllJSONChunksButNeverJavaScriptExpressions() throws {
        func argument(_ text: String) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: [1, text]), as: UTF8.self)
        }
        let price = try argument(#"{"monthly_price":"$99"}"#)
        let api = try argument(#"{"api_budget":{"usage_percentage":25}}"#)
        let vibe = try argument(#"{"vibe_budget":{"usage_percentage":35}}"#)
        let result = try MistralProviderParser.subscription("<script>self.__next_f.push(\(price), \(api),\n\(vibe))</script>")
        XCTAssertEqual(result["api_budget"]?.usage_percentage, 25)
        XCTAssertEqual(result["vibe_budget"]?.usage_percentage, 35)
        XCTAssertTrue(try MistralProviderParser.subscription("self.__next_f.push(\(api), computeOtherChunk())").isEmpty)
        XCTAssertTrue(try MistralProviderParser.subscription("self.__next_f.push(\(api),)").isEmpty)
        XCTAssertTrue(try MistralProviderParser.subscription("self.__next_f.push(\(api)").isEmpty)
        XCTAssertTrue(try MistralProviderParser.subscription("self.__next_f.push(" + Array(repeating: api, count: 65).joined(separator: ",") + ")").isEmpty)
        let conflict = try argument(#"{"api_budget":{"usage_percentage":50}}"#)
        XCTAssertNil(try MistralProviderParser.subscription("self.__next_f.push(\(api),\(conflict))")["api_budget"])
    }

    func testFallbackVibeUsesOnlyConsoleCSRFAndAuxiliaryFailureKeepsValidWallet() async throws {
        let id = UUID(), transport = MistralTransport(credits: money, subscription: "<html>No subscription payload</html>", vibe: #"[{"result":{"data":{"json":{"usage_percentage":35,"reset_at":"$D2026-10-04T00:00:00Z"}}}}]"#)
        let snapshot = try await ProviderQuotaClient(provider: .mistral, transport: transport).quota(for: id, credential: session(id))
        XCTAssertEqual(snapshot.windows.map(\.id), ["mistral.vibe", "mistral.wallet.EUR"])
        let captured = await transport.requests()
        XCTAssertEqual(captured.count, 3)
        XCTAssertNil(captured[0].value(forHTTPHeaderField: "X-CSRFToken"))
        XCTAssertEqual(captured[2].url?.host, "console.mistral.ai")
        XCTAssertEqual(captured[2].value(forHTTPHeaderField: "X-CSRFToken"), "csrf")
        XCTAssertTrue(captured.allSatisfy { !$0.httpShouldHandleCookies && $0.value(forHTTPHeaderField: "Authorization") == nil })
        let failedAux = MistralTransport(credits: money, subscription: "bad", vibe: "bad", auxiliaryStatus: 500)
        let preserved = try await ProviderQuotaClient(provider: .mistral, transport: failedAux).quota(for: id, credential: session(id))
        XCTAssertEqual(preserved.windows.count, 1)
        XCTAssertEqual(preserved.windows.first?.wallet?.total, Decimal(string: "11.123456789012345678"))
    }

    func testPrimaryWalletFailureKeepsFreshAPIAndMarksOldWalletRatherThanForgingZero() async throws {
        let id = UUID(), html = try page(#"{"api_budget":{"usage_percentage":15}}"#)
        let transport = MistralTransport(credits: "bad", subscription: html, vibe: "bad", creditStatus: 500)
        let snapshot = try await ProviderQuotaClient(provider: .mistral, transport: transport).quota(for: id, credential: session(id, csrf: false))
        XCTAssertEqual(snapshot.windows.map(\.id), ["mistral.api"])
        XCTAssertEqual(snapshot.walletFailure, .server)
        XCTAssertFalse(snapshot.windows.contains { $0.wallet != nil })
        for status in [302, 401, 403] {
            let denied = MistralTransport(credits: "{}", subscription: html, vibe: "{}", creditStatus: status)
            do { _ = try await ProviderQuotaClient(provider: .mistral, transport: denied).quota(for: id, credential: session(id)); XCTFail("Primary session expired") }
            catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
            let requests = await denied.requests()
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testOryScopeLocalAccountBindingMixedWidgetAndIndependentReminders() throws {
        func cookie(_ domain: String, _ name: String) -> HTTPCookie {
            HTTPCookie(properties: [.domain: domain, .path: "/", .name: name, .value: "fixture", .secure: "TRUE"])!
        }
        let selected = try MistralProviderClient.cookiePolicy.select([cookie(".mistral.ai", "ory_session_fixture"), cookie("console.mistral.ai", "ory_session_other"), cookie(".mistral.ai", "analytics")], now: time)
        XCTAssertTrue(selected.header.contains("ory_session_fixture"))
        XCTAssertFalse(selected.header.contains("ory_session_other"))
        XCTAssertThrowsError(try MistralProviderClient.validateCookies("csrftoken=only"))
        let id = UUID(), budgets = try MistralProviderParser.subscription(page(#"{"api_budget":{"usage_percentage":90}}"#))
        let snapshot = try MistralProviderParser.snapshot(wallet: WalletBalance(currency: "USD", total: 1), budgets: budgets, accountID: id, collectedAt: time)
        let widget = WidgetAccountSnapshot(account: .init(id: id, name: "Fixture", provider: .mistral), windows: snapshot.windows, collectedAt: time, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 2)
        XCTAssertNotNil(widget.displayMetrics.first?.ringFraction)
        XCTAssertNil(widget.displayMetrics.last?.ringFraction)
        let planned = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "Mistral", previousSnapshot: nil,
            newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: time)
        let notices = planned.operations.compactMap { if case .deliver(let value) = $0 { return value.kind }; return nil }
        XCTAssertTrue(notices.contains(.quotaAlert)); XCTAssertTrue(notices.contains(.walletAlert))
        XCTAssertNotNil(Provider.mistral.webLoginProfile); XCTAssertNotNil(Provider.mistral.iconAssetName)
    }
}

private actor MistralTransport: ProviderTransport {
    let credits: String, subscription: String, vibe: String, creditStatus: Int, auxiliaryStatus: Int
    private var captured: [URLRequest] = []
    init(credits: String, subscription: String, vibe: String, creditStatus: Int = 200, auxiliaryStatus: Int = 200) {
        self.credits = credits; self.subscription = subscription; self.vibe = vibe; self.creditStatus = creditStatus; self.auxiliaryStatus = auxiliaryStatus
    }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        captured.append(request)
        let isCredit = request.url?.path == "/api/billing/credits"
        let body = isCredit ? credits : request.url?.path == "/subscription" ? subscription : vibe
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: isCredit ? creditStatus : auxiliaryStatus, httpVersion: nil, headerFields: nil)!)
    }
    func requests() -> [URLRequest] { captured }
}
