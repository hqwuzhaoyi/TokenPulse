import Foundation
import XCTest
@testable import TokenPulse

final class ManusProviderTests: XCTestCase {
    private let body = #"{"totalCredits":"1200","periodicCredits":"300","proMonthlyCredits":1000,"refreshCredits":75,"maxRefreshCredits":300,"nextRefreshTime":"2026-04-13T00:00:00Z","refreshInterval":"daily"}"#
    private func cookie(domain: String = "manus.im", expires: Date? = nil) -> HTTPCookie {
        var fields: [HTTPCookiePropertyKey: Any] = [.name: "session_id", .value: "fixture-session-token", .domain: domain, .path: "/", .secure: "TRUE"]
        if let expires { fields[.expires] = expires }
        return HTTPCookie(properties: fields)!
    }

    func testOnlyNamedManusCookieBecomesBearerCredentialAndExpiryOrWrongDomainFails() throws {
        let id = UUID(), date = Date(timeIntervalSince1970: 100)
        let envelope = try ManusWebSession.credential(cookies: [cookie(domain: ".manus.im")], accountID: id, now: date)
        XCTAssertEqual(envelope.accessToken, "fixture-session-token")
        XCTAssertEqual(envelope.metadata["origin"], "https://manus.im")
        XCTAssertEqual(envelope.metadata["localAccountID"], id.uuidString)
        XCTAssertEqual(envelope.metadata["cookieName"], "session_id")
        XCTAssertThrowsError(try ManusWebSession.credential(cookies: [cookie(domain: "evil.manus.im")], accountID: id, now: date))
        XCTAssertThrowsError(try ManusWebSession.credential(cookies: [cookie(expires: date)], accountID: id, now: date))
        XCTAssertNotNil(Provider.manus.webLoginProfile)
        XCTAssertTrue(Provider.manus.webLoginProfile!.storageKeys.isEmpty)
    }

    func testSeparateDailyMonthlyAndTotalCreditsNeverMakeMoneyOrCombinedPercentage() throws {
        for text in [body, "{\"data\":\(body)}", "{\"result\":\(body)}", "{\"response\":\(body)}", "{\"availableCredits\":\(body)}"] {
            let snapshot = try ManusProviderClient.snapshot(Data(text.utf8), accountID: UUID(), collectedAt: Date())
            XCTAssertEqual(snapshot.windows.map(\.id), ["manus.refresh", "manus.monthly", "manus.total"])
            XCTAssertEqual(snapshot.windows.map(\.usedPercentage), [75, 70, nil])
            XCTAssertEqual(snapshot.windows[0].exactCounts?.remaining, 75)
            XCTAssertEqual(snapshot.windows[1].exactCounts?.total, 1000)
            XCTAssertEqual(snapshot.windows[0].name, "每日恢复额度")
            XCTAssertEqual(snapshot.windows[0].resetsAt, ISO8601DateFormatter().date(from: "2026-04-13T00:00:00Z"))
            XCTAssertNil(snapshot.windows[1].resetsAt)
            XCTAssertEqual(snapshot.windows[1].resetSemantics, .nonResettingAllowance)
            XCTAssertEqual(snapshot.windows[2].wallet?.total, 1200)
            XCTAssertEqual(snapshot.windows[2].wallet?.currency, "credits")
            XCTAssertEqual(snapshot.windows[2].wallet?.isMonetary, false)
        }
    }

    func testNumericRefreshTimestampHasNoGuessedEpochAndIntervalMustStateDaily() throws {
        for timestamp in ["123456789", "\"123456789\""] {
            let raw = "{\"refreshCredits\":75,\"maxRefreshCredits\":300,\"nextRefreshTime\":\(timestamp),\"refreshInterval\":\"weekly\"}"
            let window = try XCTUnwrap(ManusProviderClient.snapshot(Data(raw.utf8), accountID: UUID(), collectedAt: Date()).windows.first)
            XCTAssertNil(window.resetsAt)
            XCTAssertEqual(window.name, "恢复额度")
            XCTAssertEqual(window.period, .other)
        }
    }

    func testMissingCountsRemainMissingAndMalformedCreditsCannotEmptyTheAccount() throws {
        let partial = try ManusProviderClient.snapshot(Data(#"{"totalCredits":12,"proMonthlyCredits":1000}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(partial.windows.map(\.id), ["manus.total"])
        for raw in ["{}", #"{"totalCredits":true}"#, #"{"totalCredits":"nan"}"#, #"{"refreshCredits":-1,"maxRefreshCredits":300}"#,
                    #"{"data":{"totalCredits":"bad"},"totalCredits":10}"#] {
            XCTAssertThrowsError(try ManusProviderClient.snapshot(Data(raw.utf8), accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
    }

    func testRequestIsConnectJSONUsingSIDValueWithoutOtherCookies() async throws {
        let id = UUID(), date = Date(timeIntervalSince1970: 100)
        let envelope = try ManusWebSession.credential(cookies: [cookie()], accountID: id, now: date)
        let transport = ManusTransport([.response(200, body)])
        let snapshot = try await ProviderQuotaClient(provider: .manus, transport: transport, now: { date }).quota(for: id, credential: envelope.encoded())
        XCTAssertEqual(snapshot.sourceCredentialFingerprint, try WebProviderSession.fingerprint(envelope))
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.manus.im/user.v1.UserService/GetAvailableCredits")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.httpBody, Data("{}".utf8))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-session-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Connect-Protocol-Version"), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://manus.im")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    }

    func testScopedCredentialsAndStandardFailuresNeverBorrowAnotherAccount() async throws {
        let id = UUID(), date = Date(timeIntervalSince1970: 100)
        let envelope = try ManusWebSession.credential(cookies: [cookie()], accountID: id, now: date)
        let none = ManusTransport([])
        do { _ = try await ProviderQuotaClient(provider: .manus, transport: none).quota(for: UUID(), credential: envelope.encoded()); XCTFail("Wrong account") }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let empty = await none.requests
        XCTAssertTrue(empty.isEmpty)
        for (status, expected) in [(401, RefreshFailure.invalidCredential), (403, .invalidCredential), (302, .invalidCredential), (429, .rateLimited), (500, .server)] {
            do { _ = try await ProviderQuotaClient(provider: .manus, transport: ManusTransport([.response(status, "{}")])).quota(for: id, credential: envelope.encoded()); XCTFail("Expected failure") }
            catch { XCTAssertEqual(error as? RefreshFailure, expected) }
        }
    }

    func testNonMonetaryTotalDoesNotTriggerLowBalanceAndDemoWidgetIconAreRegistered() throws {
        let id = UUID(), date = Date(timeIntervalSince1970: 100)
        let snapshot = try ManusProviderClient.snapshot(Data(#"{"totalCredits":0}"#.utf8), accountID: id, collectedAt: date)
        let planned = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "Manus", previousSnapshot: nil,
            newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: date)
        XCTAssertTrue(planned.operations.isEmpty)
        let account = try XCTUnwrap(DemoMode.accounts().first { $0.provider == .manus })
        let demo = DemoMode.snapshot(accountID: account.id, provider: .manus)
        let widget = WidgetAccountSnapshot(account: account, windows: demo.windows, collectedAt: demo.collectedAt, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 3)
        XCTAssertEqual(Provider.manus.balancePresentation, .mixed)
        XCTAssertFalse(Provider.manus.hasMonetaryWallet)
        XCTAssertEqual(Provider.manus.iconAssetName, "ProviderManus")
    }

    func testInexactDecimalDifferenceDoesNotInventUsedCountOrOneHundredPercentAlert() throws {
        let id = UUID(), date = Date(timeIntervalSince1970: 100)
        let raw = #"{"refreshCredits":"0.0000000000000000000001","maxRefreshCredits":"100000000000000000","refreshInterval":"daily"}"#
        let snapshot = try ManusProviderClient.snapshot(Data(raw.utf8), accountID: id, collectedAt: date)
        let window = try XCTUnwrap(snapshot.windows.first)
        XCTAssertEqual(window.exactCounts?.remaining, Decimal(string: "0.0000000000000000000001"))
        XCTAssertEqual(window.exactCounts?.total, Decimal(string: "100000000000000000"))
        XCTAssertNil(window.exactCounts?.used)
        XCTAssertNil(window.usedPercentage)
        XCTAssertEqual(window.isExhausted, false)
        let planned = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "Manus", previousSnapshot: nil,
            newSnapshot: snapshot, settings: AccountReminderSettings(thresholds: [100]), ledger: ReminderLedger(), now: date)
        XCTAssertFalse(planned.operations.contains { if case .deliver(let message) = $0 { return message.kind == .quotaAlert }; return false })
    }
}

private actor ManusTransport: ProviderTransport {
    enum Reply: Sendable { case response(Int, String) }
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.timedOut) }
        switch replies.removeFirst() {
        case .response(let status, let body): return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}
