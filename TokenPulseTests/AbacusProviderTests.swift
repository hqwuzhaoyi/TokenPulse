import Foundation
import XCTest
@testable import TokenPulse

final class AbacusProviderTests: XCTestCase {
    private let points = #"{"success":true,"result":{"totalComputePoints":1000,"computePointsLeft":750}}"#
    private let billing = #"{"success":true,"result":{"nextBillingDate":"2026-11-01T00:00:00Z","currentTier":"Pro"}}"#
    func testReportedPointsAndOptionalBillingKeepUnitsCycleAndExactCounts() throws {
        let snapshot = try AbacusProviderClient.snapshot(Data(points.utf8), billing: Data(billing.utf8), accountID: UUID(), collectedAt: Date())
        let window = try XCTUnwrap(snapshot.windows.first)
        XCTAssertEqual(window.exactCounts?.total, 1000)
        XCTAssertEqual(window.exactCounts?.used, 250)
        XCTAssertEqual(window.exactCounts?.remaining, 750)
        XCTAssertEqual(window.usedPercentage, 25)
        XCTAssertEqual(window.unit, "compute points")
        XCTAssertEqual(window.period, .other)
        XCTAssertNil(window.wallet)
        XCTAssertEqual(window.resetsAt, ProviderHTTP.isoDate("2026-11-01T00:00:00Z"))
        XCTAssertEqual(snapshot.providerPlanName, "Pro")
        let withoutBilling = try AbacusProviderClient.snapshot(Data(points.utf8), billing: Data("bad JSON".utf8), accountID: snapshot.accountID, collectedAt: snapshot.collectedAt)
        XCTAssertEqual(withoutBilling.windows.first?.exactCounts, window.exactCounts)
        XCTAssertNil(withoutBilling.windows.first?.resetsAt)
        XCTAssertNil(withoutBilling.providerPlanName)
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }
    func testMissingTotalMalformedFiguresAndSessionErrorsAreDistinct() {
        for (body, expected) in [
            (#"{"success":true,"result":{"totalComputePoints":0,"computePointsLeft":0}}"#, RefreshFailure.noQuotaWindows),
            (#"{"success":true,"result":{"computePointsLeft":0}}"#, .noQuotaWindows),
            (#"{"success":true,"result":{"totalComputePoints":true,"computePointsLeft":0}}"#, .unreadableResponse),
            (#"{"success":false,"error":"session expired"}"#, .invalidCredential),
            (#"{"success":false,"error":"billing service unavailable"}"#, .server),
        ] {
            XCTAssertThrowsError(try AbacusProviderClient.snapshot(Data(body.utf8), billing: nil, accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, expected)
            }
        }
    }
    func testExactZeroLeftAndExtraPointsNeverBecomeMoney() throws {
        for (left, used, exhausted) in [(0, 1000, true), (1200, 0, false)] {
            let data = Data("{\"success\":true,\"result\":{\"totalComputePoints\":1000,\"computePointsLeft\":\(left)}}".utf8)
            let window = try XCTUnwrap(AbacusProviderClient.snapshot(data, billing: nil, accountID: UUID(), collectedAt: Date()).windows.first)
            XCTAssertEqual(window.exactCounts?.used, Decimal(used))
            XCTAssertEqual(window.isExhausted, exhausted)
            XCTAssertNil(window.wallet)
        }
    }
    func testCookieCaptureIsScopedAndQueryUsesOnlySameAccountCredentialsWithOptionalBillingFailure() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let choices = try await AbacusProviderClient.loginProfile.makeCredentials([
            sessionQuotaCookie("sessionid", domain: ".abacus.ai"), sessionQuotaCookie("analytics", domain: ".abacus.ai")
        ], [:], id, now)
        let envelope = try ProviderCredentialEnvelope.decode(choices[0].credential, expectedProvider: .abacus)
        XCTAssertEqual(envelope.accessToken, "sessionid=fixture-value")
        let transport = SessionQuotaTransport([(200, points), (503, "{}")])
        let result = try await AbacusProviderClient(transport: transport, now: { now }).quota(accountID: id, credential: envelope)
        XCTAssertEqual(result.snapshot.windows.first?.usedPercentage, 25)
        XCTAssertNil(result.snapshot.windows.first?.resetsAt)
        XCTAssertEqual(result.snapshot.sourceCredentialFingerprint, envelope.metadata["sourceCredentialFingerprint"])
        let requests = await transport.requests()
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "POST"])
        XCTAssertEqual(requests.map(\.url?.host), ["apps.abacus.ai", "apps.abacus.ai"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == "sessionid=fixture-value" && !$0.httpShouldHandleCookies })
        XCTAssertEqual(requests.last?.httpBody, Data("{}".utf8))
        let unused = SessionQuotaTransport([])
        do { _ = try await AbacusProviderClient(transport: unused, now: { now }).quota(accountID: UUID(), credential: envelope); XCTFail() }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let noRequests = await unused.requests()
        XCTAssertTrue(noRequests.isEmpty)
    }
    func testExpiredAndForeignCookiesNeverProduceLoginCredentials() async {
        for cookie in [sessionQuotaCookie("sessionid", domain: "evil.example"),
                       sessionQuotaCookie("sessionid", domain: "abacus.ai", expires: Date(timeIntervalSince1970: 1))] {
            do { _ = try await AbacusProviderClient.loginProfile.makeCredentials([cookie], [:], UUID(), Date(timeIntervalSince1970: 100)); XCTFail() }
            catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        }
    }
}
