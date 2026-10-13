import Foundation
import XCTest
@testable import TokenPulse

final class LongCatProviderTests:XCTestCase {
    private let packs=#"{"code":0,"data":{"currentLot":{"status":"ACTIVE","totalToken":50000000,"consumedToken":1212576,"consumedRatio":0.99}}}"#
    private let usage=#"{"code":0,"data":{"usage":{"totalToken":500000,"usedToken":120000,"availableToken":380000},"extData":{"model":{"totalToken":50000000,"usedToken":0}}}}"#
    private let fuel=#"{"code":0,"data":{"totalQuota":1000,"list":[{"availableToken":600,"expireTime":"2030-01-01T00:00:00Z"},{"availableToken":150,"expireTime":"2031-01-01T00:00:00Z"}]}}"#
    private let now=Date(timeIntervalSince1970:1790934400)
    private func cookie(_ name:String,domain:String="longcat.chat")->HTTPCookie {HTTPCookie(properties:[.name:name,.value:"fixture",.domain:domain,.path:"/",.secure:"TRUE"])!}
    private func envelope(id:UUID)throws->ProviderCredentialEnvelope {
        try ProviderCredentialEnvelope.decode(LongCatProviderClient.credential(cookies:[cookie("passport_token"),cookie("uid")],accountID:id,now:now),expectedProvider:.longCat)
    }
    func testSessionProofRequiredBeforeQuotaAndIdentityResponseIsNeverRetained()async throws {
        let now=self.now,id=UUID(),envelope=try envelope(id:UUID())
        // Use a matching account-bound envelope, then assert the identity's
        // phone/token payload does not enter the result or Keychain object.
        let valid=try self.envelope(id:id)
        let transport=LongCatTransport(replies:["/api/v1/user-current":(200,#"{"code":0,"data":{"phone":"sensitive-fixture-phone","sessionToken":"sensitive-fixture-token"}}"#),"/api/pay/quota/metering/token-packs/summary":(200,packs),"/api/lc-platform/v1/pending-fuel-packages":(200,fuel)])
        let result=try await LongCatProviderClient(transport:transport,now:{now}).quota(accountID:id,credential:valid)
        let encoded=String(decoding:try JSONEncoder().encode(result.snapshot),as:UTF8.self)
        XCTAssertFalse(encoded.contains("sensitive-fixture"))
        XCTAssertFalse(try valid.encoded().contains("sensitive-fixture"))
        XCTAssertEqual(result.snapshot.windows[0].exactCounts?.used,1_212_576)
        let requests=await transport.requests
        XCTAssertEqual(requests.map(\.url?.path),["/api/v1/user-current","/api/pay/quota/metering/token-packs/summary","/api/lc-platform/v1/pending-fuel-packages"])
        XCTAssertEqual(requests[1].httpMethod,"POST")
        XCTAssertEqual(requests[1].httpBody,Data("{}".utf8))
        XCTAssertTrue(requests.allSatisfy{$0.url?.host=="longcat.chat" && !$0.httpShouldHandleCookies})
        let unused=LongCatTransport(replies:[:])
        do {_ = try await LongCatProviderClient(transport:unused,now:{now}).quota(accountID:id,credential:envelope);XCTFail()}
        catch {XCTAssertEqual(error as? RefreshFailure,.invalidCredential)}
        let unusedRequests=await unused.requests
        XCTAssertTrue(unusedRequests.isEmpty)
    }
    func testSummaryFailureHasExactLegacyFallbackAndNeverReadsModelExtData()async throws {
        let now=self.now,id=UUID(),credential=try envelope(id:UUID())
        let valid=try envelope(id:id)
        let transport=LongCatTransport(replies:["/api/v1/user-current":(200,#"{"code":200,"data":{}}"#),"/api/pay/quota/metering/token-packs/summary":(403,"{}"),"/api/lc-platform/v1/tokenUsage":(200,usage),"/api/lc-platform/v1/pending-fuel-packages":(200,fuel)])
        let result=try await LongCatProviderClient(transport:transport,now:{now}).quota(accountID:id,credential:valid)
        XCTAssertEqual(result.snapshot.windows[0].exactCounts?.total,500_000)
        XCTAssertEqual(result.snapshot.windows[0].exactCounts?.used,120_000)
        XCTAssertEqual(result.snapshot.windows[0].usedPercentage,24)
        let requests=await transport.requests
        XCTAssertEqual(requests.map(\.url?.path),["/api/v1/user-current","/api/pay/quota/metering/token-packs/summary","/api/lc-platform/v1/tokenUsage","/api/lc-platform/v1/pending-fuel-packages"])
        XCTAssertThrowsError(try WebProviderSession.validate(credential,provider:.longCat,accountID:id,origins:[LongCatProviderClient.origin],now:now))
    }
    func testCurrentPackMissingConsumedDoesNotBecomeZeroOrCauseUnnecessaryFallback()throws {
        let noConsumed=Data(#"{"code":0,"data":{"currentLot":{"status":"ACTIVE","totalToken":50000000}}}"#.utf8)
        let snapshot=try LongCatProviderClient.snapshot(packs:noConsumed,usage:nil,fuel:Data(fuel.utf8),accountID:UUID(),collectedAt:now)
        XCTAssertNil(snapshot.windows[0].usedPercentage)
        XCTAssertNil(snapshot.windows[0].exactCounts?.used)
        XCTAssertNil(snapshot.windows[0].exactCounts?.remaining)
        XCTAssertEqual(snapshot.windows[0].exactCounts?.total,50_000_000)
        XCTAssertTrue(snapshot.quotaStatusText?.contains("未提供消耗") ?? false)
    }
    func testFuelUnknownMemberDoesNotProduceFabricatedAggregateUsage()throws {
        let incomplete=Data(#"{"code":0,"data":{"totalQuota":1000,"list":[{"availableToken":600},{"expireTime":"2030-01-01T00:00:00Z"}]}}"#.utf8)
        let snapshot=try LongCatProviderClient.snapshot(packs:Data(packs.utf8),usage:nil,fuel:incomplete,accountID:UUID(),collectedAt:now)
        let window=snapshot.windows.first{$0.id=="longcat.fuel"}!
        XCTAssertNil(window.usedPercentage)
        XCTAssertNil(window.exactCounts?.used)
        XCTAssertNil(window.exactCounts?.remaining)
        XCTAssertEqual(window.exactCounts?.total,1000)
        XCTAssertNil(window.isExhausted)
    }
    func testFuelTotalsAndExpiringSubsetNeverImplyFullResetOrWholePoolExpiry()throws {
        let snapshot=try LongCatProviderClient.snapshot(packs:Data(packs.utf8),usage:nil,fuel:Data(fuel.utf8),accountID:UUID(),collectedAt:now)
        XCTAssertEqual(snapshot.windows.map(\.id),["longcat.tokens","longcat.fuel","longcat.fuel.expiring"])
        XCTAssertEqual(snapshot.windows[1].exactCounts?.remaining,750)
        XCTAssertEqual(snapshot.windows[1].usedPercentage,25)
        XCTAssertNil(snapshot.windows[1].expiresAt)
        XCTAssertNil(snapshot.windows[1].resetsAt)
        XCTAssertEqual(snapshot.windows[2].exactCounts?.remaining,600)
        XCTAssertNotNil(snapshot.windows[2].expiresAt)
        XCTAssertNil(snapshot.windows[2].usedPercentage)
        XCTAssertTrue(snapshot.windows.allSatisfy{$0.resetsAt==nil && $0.wallet==nil && $0.unit=="tokens"})
    }
    func testMalformedLegacyUsageFailsAndExplicitNoTokensIsFreshCategory()throws {
        for usage in [#"{"code":0,"data":{"usage":{}}}"#,#"{"code":0,"data":{"usage":{"totalToken":true,"usedToken":0}}}"#,#"{"code":401,"data":{"usage":{"totalToken":100}}}"#] {
            XCTAssertThrowsError(try LongCatProviderClient.snapshot(packs:nil,usage:Data(usage.utf8),fuel:nil,accountID:UUID(),collectedAt:now))
        }
        let none=try LongCatProviderClient.snapshot(packs:nil,usage:Data(#"{"code":0,"data":{"usage":{"totalToken":0}}}"#.utf8),fuel:nil,accountID:UUID(),collectedAt:now)
        XCTAssertTrue(none.windows.isEmpty)
        XCTAssertTrue(none.quotaStatusText?.contains("未取得") ?? false,"A failed optional fuel query cannot prove there are no fuel packs")
    }
    func testCookieWhitelistAndInitialAuthFailureStopBeforeOptionalRoutes()async throws {
        let now=self.now,id=UUID()
        let encoded=try LongCatProviderClient.credential(cookies:[cookie("passport_token"),cookie("uid"),cookie("_ga"),cookie("passport_token",domain:"evil.example")],accountID:id,now:now)
        let credential=try ProviderCredentialEnvelope.decode(encoded,expectedProvider:.longCat)
        XCTAssertFalse(credential.accessToken.contains("_ga"))
        XCTAssertThrowsError(try LongCatProviderClient.credential(cookies:[cookie("uid")],accountID:id,now:now))
        for (status,body,failure)in [(303,"{}",RefreshFailure.invalidCredential),(401,"{}",.invalidCredential),(200,#"{"code":403,"data":{}}"#,.invalidCredential),(429,"{}",.rateLimited)] {
            let transport=LongCatTransport(replies:["/api/v1/user-current":(status,body)])
            do {_ = try await LongCatProviderClient(transport:transport,now:{now}).quota(accountID:id,credential:credential);XCTFail()}
            catch {XCTAssertEqual(error as? RefreshFailure,failure)}
            let requests=await transport.requests
            XCTAssertEqual(requests.count,1)
        }
        XCTAssertNotNil(Provider.longCat.webLoginProfile)
    }
    func testCodingDemoWidgetsAndNonResettingQuotaAlertRules()throws {
        let account=SubscriptionAccount(name:"fixture",provider:.longCat)
        let spent=packs.replacingOccurrences(of:"1212576",with:"49000000")
        let snapshot=try LongCatProviderClient.snapshot(packs:Data(spent.utf8),usage:nil,fuel:Data(fuel.utf8),accountID:account.id,collectedAt:now)
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self,from:JSONEncoder().encode(snapshot)),snapshot)
        let widget=WidgetAccountSnapshot(account:account,windows:snapshot.windows,collectedAt:now,lastFailure:nil)
        XCTAssertEqual(widget.displayMetrics.count,3)
        XCTAssertTrue(widget.displayMetrics[0].valueText.contains("tokens"))
        XCTAssertEqual(DemoMode.snapshot(accountID:account.id,provider:.longCat).windows.count,3)
        XCTAssertEqual(Provider.longCat.iconAssetName,"ProviderLongCat")
        let result=NotificationPlanner().planSuccessfulRefresh(accountID:account.id,accountName:account.name,previousSnapshot:nil,newSnapshot:snapshot,settings:AccountReminderSettings(),ledger:ReminderLedger(),now:now)
        XCTAssertTrue(result.operations.contains{if case .deliver(let value)=$0{return value.kind == .quotaAlert};return false})
        XCTAssertFalse(result.operations.contains{if case .schedule=$0{return true};return false})
        XCTAssertFalse(result.operations.contains{if case .deliver(let value)=$0{return value.kind == .walletAlert};return false})
    }
}
private actor LongCatTransport:ProviderTransport {
    let replies:[String:(Int,String)];private(set)var requests:[URLRequest]=[]
    init(replies:[String:(Int,String)]){self.replies=replies}
    func data(for request:URLRequest)throws->(Data,URLResponse){requests.append(request);let reply=replies[request.url!.path] ?? (500,"{}");return(Data(reply.1.utf8),HTTPURLResponse(url:request.url!,statusCode:reply.0,httpVersion:nil,headerFields:nil)!)}
}
