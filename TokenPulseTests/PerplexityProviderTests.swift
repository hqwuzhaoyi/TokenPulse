import Foundation
import XCTest
@testable import TokenPulse

final class PerplexityProviderTests: XCTestCase {
    private let fixture = #"{"balance_cents":320,"credit_grants":[{"type":"recurring","amount_cents":500}],"total_usage_cents":180}"#
    func testCentsAreExactUSDIncludingZeroWithoutInventedGrantPercentageOrReset() throws {
        for (body, expected) in [
            (fixture, Decimal(string: "3.2")!),
            (#"{"balance_cents":0,"credit_grants":[]}"#, Decimal(0)),
            (#"{"balanceCents":"12345.000000000000001","creditGrants":[]}"#, Decimal(string: "123.45000000000000001")!),
        ] {
            let snapshot = try PerplexityProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())
            let window = try XCTUnwrap(snapshot.windows.first)
            XCTAssertEqual(window.wallet?.total, expected)
            XCTAssertEqual(window.wallet?.currency, "USD")
            XCTAssertNil(window.usedPercentage)
            XCTAssertNil(window.totalCount)
            XCTAssertNil(window.resetsAt)
            XCTAssertEqual(snapshot.windows.count, 1)
            XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        }
    }
    func testMissingNegativeAndMalformedAmountsOrGrantSchemaAreNotZero() {
        for (body, expected) in [
            (#"{"credit_grants":[]}"#, RefreshFailure.noQuotaWindows),
            (#"{"balance_cents":-1,"credit_grants":[]}"#, .noQuotaWindows),
            (#"{"balance_cents":true,"credit_grants":[]}"#, .unreadableResponse),
            (#"{"balance_cents":"NaN","credit_grants":[]}"#, .unreadableResponse),
            (#"{"balance_cents":0,"credit_grants":{}}"#, .unreadableResponse),
        ] {
            XCTAssertThrowsError(try PerplexityProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, expected)
            }
        }
    }
    func testContiguousSessionChunksAndSimpleCookieExcludeUnrelatedCookies() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let name = PerplexityProviderClient.cookieName
        let choices = try await PerplexityProviderClient.loginProfile.makeCredentials([
            sessionQuotaCookie(name + ".1", value: "second", domain: ".perplexity.ai"),
            sessionQuotaCookie(name + ".0", value: "first", domain: ".perplexity.ai"),
            sessionQuotaCookie("analytics", domain: ".perplexity.ai"),
        ], [:], id, now)
        let envelope = try ProviderCredentialEnvelope.decode(choices[0].credential, expectedProvider: .perplexity)
        let transport = SessionQuotaTransport([(200, fixture)])
        let result = try await PerplexityProviderClient(transport: transport, now: { now }).quota(accountID: id, credential: envelope)
        XCTAssertEqual(result.snapshot.windows.first?.wallet?.total, Decimal(string: "3.2"))
        let capturedRequests = await transport.requests()
        let request = try XCTUnwrap(capturedRequests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://www.perplexity.ai/rest/billing/credits?version=2.18&source=default")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "\(name).0=first; \(name).1=second")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), PerplexityProviderClient.origin)
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
    func testGapsForeignDomainsAndExpiredCookieCannotCompleteLogin() async {
        let name = PerplexityProviderClient.cookieName
        for cookies in [[sessionQuotaCookie(name + ".1", domain: "perplexity.ai")],
                        [sessionQuotaCookie(name, domain: "evil.example")],
                        [sessionQuotaCookie(name, domain: "perplexity.ai", expires: Date(timeIntervalSince1970: 1))]] {
            do { _ = try await PerplexityProviderClient.loginProfile.makeCredentials(cookies, [:], UUID(), Date(timeIntervalSince1970: 100)); XCTFail() }
            catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        }
    }
    func testWrongAccountAndRedirectDoNotQueryAnotherScopeOrFollowLogin() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let envelope = try WebProviderSession.credential(provider: .perplexity, origin: PerplexityProviderClient.origin, accountID: id,
                                                         accessToken: PerplexityProviderClient.cookieName + "=fixture")
        let unused = SessionQuotaTransport([])
        do { _ = try await PerplexityProviderClient(transport: unused, now: { now }).quota(accountID: UUID(), credential: envelope); XCTFail() }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let noRequests = await unused.requests(); XCTAssertTrue(noRequests.isEmpty)
        let redirect = SessionQuotaTransport([(302, ""), (200, fixture)])
        do { _ = try await PerplexityProviderClient(transport: redirect, now: { now }).quota(accountID: id, credential: envelope); XCTFail() }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let requests = await redirect.requests(); XCTAssertEqual(requests.count, 1)
    }
}
