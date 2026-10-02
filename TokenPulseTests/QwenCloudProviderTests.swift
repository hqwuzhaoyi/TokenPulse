import Foundation
import XCTest
@testable import TokenPulse

final class QwenCloudProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100)
    private let usage = #"{"code":"200","data":{"DataV2":{"data":"{\"success\":true,\"code\":0,\"data\":{\"per5HourPercentage\":0.03,\"per5HourResetTime\":200000,\"per1WeekPercentage\":1.2,\"per1WeekResetTime\":300000}}","success":true,"httpStatus":200}},"successResponse":true}"#

    func testExplicitEnvelopeAndRatiosKeepPeriodsAndDropPastWindows() throws {
        let snapshot = try QwenCloudProviderClient.snapshot(Data(usage.utf8), accountID: UUID(), collectedAt: now)
        XCTAssertEqual(snapshot.windows.map(\.usedPercentage), [3,120])
        XCTAssertEqual(snapshot.windows.map(\.period), [.fiveHour,.weekly])
        XCTAssertEqual(snapshot.windows.last?.isExhausted, true)
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.wallet == nil && $0.exactCounts == nil })
        let stale = try QwenCloudProviderClient.snapshot(Data(usage.utf8), accountID: UUID(), collectedAt: Date(timeIntervalSince1970: 250))
        XCTAssertEqual(stale.windows.map(\.period), [.weekly])
        XCTAssertThrowsError(try QwenCloudProviderClient.snapshot(Data(usage.utf8), accountID: UUID(), collectedAt: Date(timeIntervalSince1970: 400)))
        XCTAssertThrowsError(try QwenCloudProviderClient.snapshot(Data(#"{"unrelated":{"per5HourPercentage":0.2}}"#.utf8), accountID: UUID(), collectedAt: now))
    }
    func testNoSubscriptionIsFreshCategoricalStatusWithoutFakeUnlimitedAllowance() throws {
        let noPlan = #"{"code":"200","data":{"Data":{"TotalCount":0,"ProductCode":"sfm_tokenplansolo_public_intl"},"Code":"Success","Success":true},"successResponse":true}"#
        let id = UUID()
        let snapshot = try QwenCloudProviderClient.snapshot(Data(noPlan.utf8), accountID: id, collectedAt: now)
        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertNil(snapshot.isNoPlan)
        XCTAssertEqual(snapshot.quotaStatusText, "当前账号没有 Qwen Cloud 套餐")
        let widget = WidgetAccountSnapshot(account: .init(id: id, name: "Qwen", provider: .qwenCloud), windows: [], collectedAt: now,
                                          lastFailure: nil, quotaStatusText: snapshot.quotaStatusText)
        XCTAssertEqual(widget.displayMetrics.first?.valueText, snapshot.quotaStatusText)
    }
    func testBooleanNumbersAndNestedRefusalsNeverBecomeQuota() throws {
        for data in [#"{"success":1,"data":{"per5HourPercentage":0}}"#,
                     #"{"data":{"per5HourPercentage":true}}"#, #"{"data":{"per5HourPercentage":-1}}"#] {
            XCTAssertThrowsError(try QwenCloudProviderClient.snapshot(Data(data.utf8), accountID: UUID(), collectedAt: now))
        }
        for (code, failure) in [("Workspace.NotAuthorised",RefreshFailure.server),("ConsoleNeedLogin",.invalidCredential),("TokenError",.invalidCredential)] {
            let body = "{\"data\":{\"DataV2\":{\"success\":false,\"code\":\"\(code)\"}}}"
            XCTAssertThrowsError(try QwenCloudProviderClient.payload(Data(body.utf8))) { XCTAssertEqual($0 as? RefreshFailure, failure) }
        }
    }
    func testFormEscapesTokensAndSeparatelyScopesSubscriptionMetadata() throws {
        let request = try QwenCloudProviderClient.request(api: QwenCloudProviderClient.subscriptionAPI, token: "a+b&c=d",
            cookie: "login_qwencloud_ticket=fixture", cookies: ["csrf":"x+y=z", "cna":"browser+&="])
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertTrue(body.contains("sec_token=a%2Bb%26c%3Dd"))
        var components = URLComponents(string: "https://fixture.test/")!; components.percentEncodedQuery = body
        let fields = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name,$0.value!) })
        XCTAssertEqual(fields["sec_token"], "a+b&c=d")
        let params = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(fields["params"]!.utf8)) as? [String: Any])
        let data = try XCTUnwrap(params["Data"] as? [String: Any])
        XCTAssertEqual(data["commodityCode"] as? String,"sfm_tokenplansolo_public_intl")
        XCTAssertEqual((data["cornerstoneParam"] as? [String:String])?["X-Anonymous-Id"],"browser+&=")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-xsrf-token"), "x+y=z")
        XCTAssertEqual(request.url?.host,"cs-data.qwencloud.com")
        XCTAssertFalse(request.httpShouldHandleCookies)
    }
    func testPageTokenThenQuotaSurvivesOptionalTierFailureAndAccountMismatchStopsRequests() async throws {
        let id = UUID(), date = now
        let credential = try WebProviderSession.credential(provider: .qwenCloud, origin: QwenCloudSession.origin, accountID: id,
            accessToken: "login_qwencloud_ticket=fixture; csrf=csrf-fixture; cna=browser-fixture")
        let transport = QwenTestTransport(replies: [(200,#"<html><script>window.env={"secToken":"a+b&c=d"}</script></html>"#), (200,usage), (503,"{}")])
        let result = try await ProviderQuotaClient(provider: .qwenCloud, transport: transport, now: { date }).quotaResult(for: id, credential: credential.encoded())
        XCTAssertEqual(result.snapshot.windows.count,2); XCTAssertNil(result.snapshot.providerPlanName)
        XCTAssertEqual(result.snapshot.sourceCredentialFingerprint,credential.sourceCredentialIdentity)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.host },["home.qwencloud.com","cs-data.qwencloud.com","cs-data.qwencloud.com"])
        XCTAssertEqual(requests.map(\.httpMethod),["GET","POST","POST"])
        XCTAssertTrue(String(decoding: requests[1].httpBody!,as:UTF8.self).contains("a%2Bb%26c%3Dd"))
        do { _ = try await ProviderQuotaClient(provider: .qwenCloud, transport: transport).quota(for: UUID(), credential: credential.encoded()); XCTFail("wrong local account") } catch { XCTAssertEqual(error as? RefreshFailure,.invalidCredential) }
        let after = await transport.requests; XCTAssertEqual(after.count,3)
    }
    func testConfirmedNoPlanDoesNotFetchOrDisplayPossiblyHistoricalTier() async throws {
        let id = UUID(), date = now
        let credential = try WebProviderSession.credential(provider: .qwenCloud, origin: QwenCloudSession.origin, accountID: id,
            accessToken: "qwen_sso_ticket=fixture; sec_token=cookie-token")
        let transport = QwenTestTransport(replies: [(200, "<html>console</html>"), (200, #"{"data":{"TotalCount":0}}"#),
            (200, #"{"data":{"specCode":"lite"}}"#)])
        let snapshot = try await ProviderQuotaClient(provider: .qwenCloud, transport: transport, now: { date }).quota(for: id, credential: credential.encoded())
        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertNotNil(snapshot.quotaStatusText)
        XCTAssertNil(snapshot.providerPlanName)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testCookieTokenFallbackAndRedirectRejection() async throws {
        let id = UUID(), date = now
        let credential = try WebProviderSession.credential(provider: .qwenCloud, origin: QwenCloudSession.origin, accountID: id,
            accessToken: "qwen_sso_ticket=fixture; sec_token=cookie-token")
        let transport = QwenTestTransport(replies: [(200,"<html>console</html>"),(200,usage),(200,#"{"data":{"specCode":"pro"}}"#)])
        let snapshot = try await ProviderQuotaClient(provider:.qwenCloud,transport:transport,now:{date}).quota(for:id,credential:credential.encoded())
        XCTAssertEqual(snapshot.providerPlanName,"Pro")
        let denied = QwenTestTransport(replies:[(302,"{}")])
        do { _ = try await ProviderQuotaClient(provider:.qwenCloud,transport:denied).quota(for:id,credential:credential.encoded()); XCTFail("redirect") } catch { XCTAssertEqual(error as? RefreshFailure,.invalidCredential) }
        let requests = await denied.requests; XCTAssertEqual(requests.count,1)
    }
}
private actor QwenTestTransport: ProviderTransport {
    var replies: [(Int,String)]
    private(set) var requests: [URLRequest] = []
    init(replies: [(Int,String)]) { self.replies = replies }
    func data(for request: URLRequest) async throws -> (Data,URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw RefreshFailure.server }
        let (status,body) = replies.removeFirst()
        return (Data(body.utf8),HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!)
    }
}
