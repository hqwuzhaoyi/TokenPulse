import Foundation
import XCTest
@testable import TokenPulse

final class ReplicateProviderTests: XCTestCase {
    private let page = #"<script type="application/json" id="react-component-props-billing">{"billing":{"account":{"kind":"user","username":"alice"}},"team":{"account":{"kind":"organization","username":"team-one"}}}</script>"#
    private let time = Date(timeIntervalSince1970: 1_000)

    private func session(_ id: UUID, kind: String = "user", username: String = "alice", expiry: Date? = nil) throws -> String {
        try WebProviderSession.credential(provider: .replicate, origin: ReplicateProviderClient.origin, accountID: id,
            accessToken: "sessionid=fixture; csrftoken=csrf", expiresAt: expiry, remoteAccountID: "\(kind):\(username)",
            metadata: ["accountKind": kind, "accountUsername": username]).encoded()
    }

    func testBillingPropsExposeExplicitUserAndOrganizationCandidatesAndBoundedSafePaths() throws {
        let accounts = try ReplicateProviderParser.accounts(in: page)
        XCTAssertEqual(accounts.map(\.id), ["organization:team-one", "user:alice"])
        XCTAssertEqual(accounts[0].balanceURL.absoluteString, "https://replicate.com/api/organizations/team-one/unused-credit")
        let falseProps = page.replacingOccurrences(of: "react-component-props-billing", with: "other-script")
        XCTAssertThrowsError(try ReplicateProviderParser.accounts(in: falseProps))
        for username in ["../other", "name/other", "a?admin=true", "a\nname"] {
            let payload = try JSONSerialization.data(withJSONObject: ["account": ["kind": "user", "username": username]])
            let html = "<script type=\"application/json\" id=\"react-component-props\">\(String(decoding: payload, as: UTF8.self))</script>"
            XCTAssertThrowsError(try ReplicateProviderParser.accounts(in: html))
        }
        XCTAssertThrowsError(try ReplicateProviderParser.accounts(in: "<title>Sign in | Replicate</title><a href=\"/login/github/\">Sign in</a>")) {
            XCTAssertEqual($0 as? RefreshFailure, .invalidCredential)
        }
    }

    func testWalletUsesExactReportedBalanceWithoutRingResetOrGuessedZero() throws {
        let account = ReplicateProviderParser.Account(kind: "user", username: "alice")
        for literal in ["0", "12.123456789012345678", "\"12.123456789012345678\""] {
            let snapshot = try ReplicateProviderParser.snapshot(Data(("{\"unused_credit\":\(literal)}").utf8), accountID: UUID(), collectedAt: time, account: account)
            let window = try XCTUnwrap(snapshot.windows.first)
            XCTAssertEqual(window.wallet?.total, Decimal(string: literal.replacingOccurrences(of: "\"", with: "")))
            XCTAssertEqual(window.wallet?.currency, "USD")
            XCTAssertNil(window.usedPercentage)
            XCTAssertNil(window.resetsAt)
            XCTAssertNil(window.totalCount)
            XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        }
        for bad in [#"{"unused_credit":true}"#, #"{"unused_credit":"NaN"}"#, #"{"unused_credit":"1e2"}"#, #"{"unused_credit":-1}"#] {
            XCTAssertThrowsError(try ReplicateProviderParser.balance(Data(bad.utf8))) { XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse) }
        }
        for absent in ["{}", #"{"unused_credit":null}"#] {
            XCTAssertThrowsError(try ReplicateProviderParser.balance(Data(absent.utf8))) { XCTAssertEqual($0 as? RefreshFailure, .noQuotaWindows) }
        }
    }

    func testRequestsValidateSelectedAccountThenReadOnlyItsBalanceAndCookieScope() async throws {
        let id = UUID(), transport = ReplicateTransport(page: page, balance: #"{"unused_credit":"80.00"}"#)
        let snapshot = try await ProviderQuotaClient(provider: .replicate, transport: transport).quota(for: id, credential: session(id, kind: "organization", username: "team-one"))
        XCTAssertEqual(snapshot.windows.first?.scope, "组织 · team-one")
        let requests = await transport.requests()
        XCTAssertEqual(requests.map { $0.url?.path }, ["/account/billing", "/api/organizations/team-one/unused-credit"])
        for request in requests {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "sessionid=fixture; csrftoken=csrf")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        }
        let a = try ProviderCredentialEnvelope.decode(session(id), expectedProvider: .replicate)
        let b = try ProviderCredentialEnvelope.decode(session(id, kind: "organization", username: "team-one"), expectedProvider: .replicate)
        XCTAssertNotEqual(a.sourceCredentialIdentity, b.sourceCredentialIdentity)
        XCTAssertNotNil(Provider.replicate.webLoginProfile)
    }

    func testWrongLocalAccountExpiredSessionMissingRemoteMembershipAndStatusesFailSafely() async throws {
        let id = UUID(), transport = ReplicateTransport(page: page, balance: #"{"unused_credit":"80.00"}"#)
        for (target, credential) in [(UUID(), try session(id)), (id, try session(id, expiry: time)), (id, try session(id, username: "missing"))] {
            do { _ = try await ProviderQuotaClient(provider: .replicate, transport: transport, now: { Date(timeIntervalSince1970: 1001) }).quota(for: target, credential: credential); XCTFail("Invalid session/scope") }
            catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        }
        for (status, expected) in [(302, RefreshFailure.invalidCredential), (401, .invalidCredential), (403, .invalidCredential), (429, .rateLimited), (500, .server)] {
            do { _ = try await ProviderQuotaClient(provider: .replicate, transport: ReplicateTransport(page: page, balance: "{}", status: status)).quota(for: id, credential: session(id)); XCTFail("Failure expected") }
            catch { XCTAssertEqual(error as? RefreshFailure, expected) }
        }
    }

    func testOnlyProviderRootSessionCookiesCanBeCapturedAndWalletReminderWidgetAreApplicable() throws {
        func cookie(_ name: String, _ domain: String, _ path: String = "/") -> HTTPCookie {
            HTTPCookie(properties: [.name: name, .value: "fixture", .domain: domain, .path: path, .secure: "TRUE"])!
        }
        let policy = ReplicateProviderClient.cookiePolicy
        let selected = try policy.select([cookie("sessionid", ".replicate.com"), cookie("csrftoken", "replicate.com"), cookie("sessionid", "evil.example"), cookie("analytics", "replicate.com")], now: time)
        XCTAssertFalse(selected.header.contains("analytics"))
        XCTAssertThrowsError(try policy.select([cookie("sessionid", "replicate.com", "/account")], now: time))
        XCTAssertThrowsError(try policy.values(in: "sessionid=a; sessionid=b"))
        let id = UUID(), snapshot = try ReplicateProviderParser.snapshot(Data(#"{"unused_credit":"1"}"#.utf8), accountID: id, collectedAt: time,
            account: .init(kind: "user", username: "alice"))
        let result = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "Replicate", previousSnapshot: nil,
            newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: time)
        let notices = result.operations.compactMap { if case .deliver(let value) = $0 { return value }; return nil }
        XCTAssertEqual(notices.map(\.kind), [.walletAlert])
        XCTAssertNil(WidgetQuotaMetric(id: "wallet", title: "wallet", window: snapshot.windows[0]).ringFraction)
        XCTAssertNotNil(Provider.replicate.iconAssetName)
    }
}

private actor ReplicateTransport: ProviderTransport {
    let page: String, balance: String, status: Int
    private var captured: [URLRequest] = []
    init(page: String, balance: String, status: Int = 200) { self.page = page; self.balance = balance; self.status = status }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        captured.append(request)
        return (Data((request.url?.path == "/account/billing" ? page : balance).utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    func requests() -> [URLRequest] { captured }
}
