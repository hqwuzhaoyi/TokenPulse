import Foundation
import XCTest
@testable import TokenPulse

final class XKiroProviderTests: XCTestCase {
    private let body = #"{"object":"usage","plan":"ultra","windows":[{"kind":"short","window_sec":18000,"spent_usd":"50.000000","cap_usd":"200.000000","remaining_usd":"150.000000","resets_in_sec":5005},{"kind":"long","window_sec":604800,"spent_usd":"330.000000","cap_usd":"1320.000000","remaining_usd":"990.000000","resets_in_sec":199405}],"free_tokens":{"used_today":412030,"limit_per_day":300000000,"remaining":299587970},"wallet":{"balance_usd":"683.950000","held_usd":"20.000000"}}"#

    func testBudgetFreeTokensAndWalletKeepTheirOwnUnitsAndTimes() throws {
        let date = ISO8601DateFormatter().date(from: "2026-10-02T18:30:00Z")!
        let result = try XKiroProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: date)
        XCTAssertEqual(result.windows.map(\.id), ["xkiro.short", "xkiro.long", "xkiro.free_tokens", "xkiro.wallet"])
        XCTAssertEqual(result.windows.map(\.unit), ["USD 预算额度", "USD 预算额度", "tokens", nil])
        XCTAssertEqual(result.windows[0].usedPercentage, 25)
        XCTAssertEqual(result.windows[1].usedPercentage, 25)
        XCTAssertEqual(result.windows[0].exactCounts?.remaining, 150)
        XCTAssertEqual(result.windows[0].exactCounts?.used, 50)
        XCTAssertEqual(result.windows[0].exactCounts?.total, 200)
        XCTAssertNil(result.windows[0].remainingCount)
        XCTAssertNil(result.windows[0].totalCount)
        XCTAssertEqual(result.windows[2].remainingCount, 299_587_970)
        XCTAssertEqual(result.windows[0].resetsAt, date.addingTimeInterval(5005))
        XCTAssertEqual(result.windows[2].resetsAt, ISO8601DateFormatter().date(from: "2026-10-03T00:00:00Z"))
        XCTAssertEqual(result.windows[3].wallet?.total, Decimal(string: "683.95"))
        XCTAssertNil(result.windows[3].usedPercentage)
        XCTAssertNil(result.walletAvailable)
        XCTAssertNil(result.quotaExceeded)
        XCTAssertEqual(result.walletCollectedAt, date)
        XCTAssertEqual(result.providerPlanName, "Ultra")
    }

    func testDecimalMicrounitsSurviveAndReservedFundsAreNotSubtracted() throws {
        let text = #"{"object":"usage","windows":[{"kind":"short","window_sec":18000,"spent_usd":"0.000356","cap_usd":"1.000000","remaining_usd":"0.999644","resets_in_sec":10}],"wallet":{"balance_usd":"0.000356","held_usd":"0.000350"}}"#
        let result = try XKiroProviderClient.snapshot(Data(text.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(result.windows.last?.wallet?.total, Decimal(string: "0.000356"))
        XCTAssertEqual(try XCTUnwrap(result.windows.first?.usedPercentage), 0.0356, accuracy: 0.0000001)
        XCTAssertTrue(QuotaFormatting.usage(result.windows[0]).contains("0.999644"))
        XCTAssertEqual(QuotaFormatting.money(result.windows.last!.wallet!.total, currency: "USD"), "0.000356 USD")
    }

    func testBudgetQuantitiesRemainExactBeyondDoublePrecisionAndAcrossArchive() throws {
        let raw = #"{"object":"usage","windows":[{"kind":"short","window_sec":18000,"spent_usd":"1.000000","cap_usd":"10000000000000000.123456","remaining_usd":"9999999999999999.123456","resets_in_sec":10}]}"#
        let parsed = try XKiroProviderClient.snapshot(Data(raw.utf8), accountID: UUID(), collectedAt: Date())
        let decoded = try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(parsed))
        let window = try XCTUnwrap(decoded.windows.first)
        XCTAssertEqual(window.exactCounts?.used, Decimal(string: "1.000000"))
        XCTAssertEqual(window.exactCounts?.total, Decimal(string: "10000000000000000.123456"))
        XCTAssertEqual(window.exactCounts?.remaining, Decimal(string: "9999999999999999.123456"))
        XCTAssertNil(window.remainingCount)
        XCTAssertNil(window.totalCount)
        XCTAssertTrue(QuotaFormatting.usage(window).contains("123456"))
        let widget = WidgetQuotaMetric(id: window.id, title: window.name, window: window)
        XCTAssertEqual(widget.valueText, QuotaFormatting.usage(window))
    }

    func testMissingBudgetRemainderStaysAbsentInExactCounts() throws {
        let raw = #"{"object":"usage","windows":[{"kind":"short","window_sec":18000,"spent_usd":"0.000356","cap_usd":"1.000000","resets_in_sec":10}]}"#
        let window = try XCTUnwrap(XKiroProviderClient.snapshot(Data(raw.utf8), accountID: UUID(), collectedAt: Date()).windows.first)
        XCTAssertEqual(window.exactCounts?.used, Decimal(string: "0.000356"))
        XCTAssertEqual(window.exactCounts?.total, 1)
        XCTAssertNil(window.exactCounts?.remaining)
        XCTAssertNil(window.remainingCount)
        XCTAssertTrue(QuotaFormatting.usage(window).contains("0.000356"))
    }

    func testOnlyExplicitNullDailyLimitIsUnlimitedAndMissingCountsAreNotZero() throws {
        let unlimited = try XKiroProviderClient.snapshot(Data(#"{"object":"usage","windows":[],"free_tokens":{"used_today":100,"limit_per_day":null,"remaining":null},"wallet":null}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(unlimited.windows.count, 1)
        XCTAssertTrue(unlimited.windows[0].isUnlimited)
        XCTAssertNil(unlimited.windows[0].resetsAt)
        XCTAssertNil(unlimited.windows[0].usedPercentage)
        XCTAssertThrowsError(try XKiroProviderClient.snapshot(Data(#"{"object":"usage","free_tokens":{},"wallet":null}"#.utf8), accountID: UUID(), collectedAt: Date())) {
            XCTAssertEqual($0 as? RefreshFailure, .noQuotaWindows)
        }
        let missing = try XKiroProviderClient.snapshot(Data(#"{"object":"usage","free_tokens":{"limit_per_day":100,"remaining":100}}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertNil(missing.windows[0].usedPercentage)
        XCTAssertEqual(missing.windows[0].remainingCount, 100)
    }

    func testMalformedFieldsAndDuplicateWindowsFailInsteadOfCreatingFalseBalances() {
        for text in [#"{"object":"wrong","wallet":{"balance_usd":"1"}}"#,
                     #"{"object":"usage","wallet":{"balance_usd":"nan"}}"#,
                     #"{"object":"usage","wallet":{"balance_usd":1}}"#,
                     #"{"object":"usage","free_tokens":{"used_today":true,"limit_per_day":100}}"#,
                     #"{"object":"usage","windows":[{"kind":"short","window_sec":18000,"spent_usd":"1","cap_usd":"2","resets_in_sec":-1}]}"#,
                     #"{"object":"usage","windows":[{"kind":"same","window_sec":18000,"spent_usd":"1","cap_usd":"2"},{"kind":"same","window_sec":604800,"spent_usd":"1","cap_usd":"2"}]}"#] {
            XCTAssertThrowsError(try XKiroProviderClient.snapshot(Data(text.utf8), accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
    }

    func testRequestAndFailuresUseAccountBoundAPIKeyWithMixedPresentation() async throws {
        let key = try ProviderAuthenticationController().credential(provider: .xKiro, apiKey: "fixture-key")
        let date = Date(timeIntervalSince1970: 100)
        let id = UUID()
        let transport = XKiroTransport([.response(200, body), .response(401, "{}"), .response(403, "{}"), .response(429, "{}"), .response(500, "{}"), .failure])
        let client = ProviderQuotaClient(provider: .xKiro, transport: transport, now: { date })
        let result = try await client.quota(for: id, credential: key)
        XCTAssertEqual(result.accountID, id)
        XCTAssertEqual(result.sourceCredentialFingerprint, try ProviderCredentialEnvelope.decode(key, expectedProvider: .xKiro).sourceCredentialIdentity)
        XCTAssertEqual(Provider.xKiro.balancePresentation, .mixed)
        for expected in [RefreshFailure.invalidCredential, .invalidCredential, .rateLimited, .server, .network] {
            do { _ = try await client.quota(for: id, credential: key); XCTFail("Expected failure") }
            catch { XCTAssertEqual(error as? RefreshFailure, expected) }
        }
        let requests = await transport.requests
        for request in requests {
            XCTAssertEqual(request.url?.absoluteString, "https://api.xkiro.com/v1/usage")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        }
        let widget = WidgetAccountSnapshot(account: SubscriptionAccount(id: id, name: "xKiro", provider: .xKiro), windows: result.windows, collectedAt: date, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 4)
        XCTAssertTrue(widget.displayMetrics.contains { $0.window?.wallet != nil })
    }

    func testDailyResetIsUTCAndNegativeWalletDoesNotDeclareEveryModelUnavailable() throws {
        let utc = ISO8601DateFormatter().date(from: "2026-10-02T23:59:59Z")!
        XCTAssertEqual(XKiroProviderClient.nextMidnightUTC(after: utc), utc.addingTimeInterval(1))
        let result = try XKiroProviderClient.snapshot(Data(#"{"object":"usage","plan":null,"windows":[],"wallet":{"balance_usd":"-1.000000"}}"#.utf8), accountID: UUID(), collectedAt: utc)
        XCTAssertEqual(result.windows[0].wallet?.total, -1)
        XCTAssertNil(result.walletAvailable)
        let account = try XCTUnwrap(DemoMode.accounts().first { $0.provider == .xKiro })
        XCTAssertEqual(DemoMode.snapshot(accountID: account.id, provider: .xKiro).windows.count, 4)
        XCTAssertEqual(Provider.xKiro.systemIconName, "puzzlepiece.extension.fill")
    }
}

private actor XKiroTransport: ProviderTransport {
    enum Reply: Sendable { case response(Int, String), failure }
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        switch replies.removeFirst() {
        case .failure: throw URLError(.timedOut)
        case .response(let status, let body):
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}
