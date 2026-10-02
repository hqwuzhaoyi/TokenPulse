import Foundation
import XCTest
@testable import TokenPulse

final class QoderChinaProviderTests:XCTestCase {
    private let body = #"{"nextResetAt":"2026-09-01T00:00:00Z","total_quota":{"quota_summary":{"used_value":14,"limit_value":600,"remaining_value":586,"unit":"credits"},"quota_detail":[{"remaining_value":86,"expires_at":"2026-10-18T00:00:00Z","is_active":true}]},"sharedQuota":{"quotaSummary":{"usedValue":200,"limitValue":1000,"remainingValue":800,"unit":"credits"}}}"#
    private let now=Date(timeIntervalSince1970:1790934400)
    private func cookie(_ name:String,_ value:String="fixture",domain:String="qoder.com.cn")->HTTPCookie {
        HTTPCookie(properties:[.name:name,.value:value,.domain:domain,.path:"/",.secure:"TRUE"])!
    }

    func testDomesticCookiePolicyKeepsProtectionAndNeverInternationalOrAnalytics()throws {
        let id=UUID()
        let encoded=try QoderChinaProviderClient.credential(cookies:[cookie("session"),cookie("cna"),cookie("isg"),cookie("tfstk"),cookie("Hm_lvt_x"),cookie("_ga"),cookie("other",domain:"qoder.com")],accountID:id,now:now)
        let envelope=try ProviderCredentialEnvelope.decode(encoded,expectedProvider:.qoderChina)
        XCTAssertTrue(envelope.accessToken.contains("isg="))
        XCTAssertTrue(envelope.accessToken.contains("cna="))
        XCTAssertTrue(envelope.accessToken.contains("tfstk="))
        XCTAssertFalse(envelope.accessToken.contains("Hm_"))
        XCTAssertFalse(envelope.accessToken.contains("_ga"))
        XCTAssertFalse(envelope.accessToken.contains("other="))
        XCTAssertThrowsError(try WebProviderSession.validate(envelope,provider:.qoderChina,accountID:UUID(),origins:[QoderChinaProviderClient.origin],now:now))
        XCTAssertThrowsError(try ProviderCredentialEnvelope.decode(encoded,expectedProvider:.qoderInternational))
        XCTAssertEqual(Provider.qoderChina.iconAssetName,Provider.qoderInternational.iconAssetName)
        XCTAssertNotNil(Provider.qoderChina.webLoginProfile)
        XCTAssertEqual(ProviderAuthenticationController().loginConfiguration(for:.qoderChina).method,.webSession)
    }

    func testMixedAliasesKeepPoolsSeparateAndExpiryIsOnlyPersonalSubset()throws {
        let snapshot=try QoderChinaProviderClient.snapshot(Data(body.utf8),accountID:UUID(),collectedAt:now)
        XCTAssertEqual(snapshot.windows.map(\.id),["qoderChina.personal","qoderChina.team","qoderChina.expiring"])
        XCTAssertEqual(snapshot.windows[0].exactCounts?.total,600)
        XCTAssertEqual(snapshot.windows[1].exactCounts?.total,1000)
        XCTAssertNil(snapshot.windows[0].resetsAt,"Stale trial reset must not invalidate usable credits")
        XCTAssertNil(snapshot.windows[1].resetsAt)
        XCTAssertNil(snapshot.windows[0].expiresAt,"The whole 600-credit pool must not claim the subset's expiration")
        XCTAssertEqual(snapshot.windows[2].exactCounts?.remaining,86)
        XCTAssertNotNil(snapshot.windows[2].expiresAt)
        XCTAssertNil(snapshot.windows[2].resetsAt)
        XCTAssertNil(snapshot.windows[2].usedPercentage)
    }

    func testZeroIssuedPoolsAreFreshStatusAndMalformedPoolIsFailure()throws {
        let noQuota=#"{"totalQuota":{"quotaSummary":{"usedValue":0,"limitValue":0,"remainingValue":0}},"sharedQuota":{"quotaSummary":{"usedValue":0,"limitValue":0}}}"#
        let snapshot=try QoderChinaProviderClient.snapshot(Data(noQuota.utf8),accountID:UUID(),collectedAt:now)
        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertNotNil(snapshot.quotaStatusText)
        for body in [#"{}"#,#"{"totalQuota":{"quotaSummary":{"limitValue":500}}}"#,#"{"totalQuota":{"quotaSummary":{"usedValue":true,"limitValue":500}}}"#,#"{"totalQuota":{"quotaSummary":{"usedValue":0,"limitValue":500}},"sharedQuota":{}}"#] {
            XCTAssertThrowsError(try QoderChinaProviderClient.snapshot(Data(body.utf8),accountID:UUID(),collectedAt:now))
        }
    }

    func testMalformedDetailCannotCostValidPersonalSummary()throws {
        let body=#"{"totalQuota":{"quotaSummary":{"usedValue":0,"limitValue":500},"quotaDetail":"not-a-list"}}"#
        let snapshot=try QoderChinaProviderClient.snapshot(Data(body.utf8),accountID:UUID(),collectedAt:now)
        XCTAssertEqual(snapshot.windows.count,1)
        XCTAssertEqual(snapshot.windows[0].usedPercentage,0)
        XCTAssertEqual(snapshot.windows[0].exactCounts?.remaining,500)
    }

    func testRequestHasFixedOriginProtectionHeadersAndMapsRedirectAsExpired()async throws {
        let now=self.now,id=UUID()
        let encoded=try QoderChinaProviderClient.credential(cookies:[cookie("session"),cookie("isg")],accountID:id,now:now)
        let envelope=try ProviderCredentialEnvelope.decode(encoded,expectedProvider:.qoderChina)
        let transport=QoderChinaTransport(status:200,body:body)
        _ = try await QoderChinaProviderClient(transport:transport,now:{now}).quota(accountID:id,credential:envelope)
        let requests=await transport.requests
        XCTAssertEqual(requests[0].url?.absoluteString,"https://qoder.com.cn/api/v2/me/usages/big_model_credits")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField:"Bx-V"),"2.5.35")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField:"X-Requested-With"),"XMLHttpRequest")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField:"Cookie"),envelope.accessToken)
        XCTAssertFalse(requests[0].httpShouldHandleCookies)
        for (status,failure) in [(302,RefreshFailure.invalidCredential),(401,.invalidCredential),(403,.invalidCredential),(429,.rateLimited),(500,.server)] {
            do {_ = try await QoderChinaProviderClient(transport:QoderChinaTransport(status:status,body:"{}"),now:{now}).quota(accountID:id,credential:envelope);XCTFail()}
            catch {XCTAssertEqual(error as? RefreshFailure,failure)}
        }
    }

    func testBuyingCreditsDoesNotLookLikeAResetAndExpiryNeverSchedules()throws {
        let account=UUID()
        func snapshot(_ limit:Int)throws->QuotaSnapshot {
            try QoderChinaProviderClient.snapshot(Data("{\"nextResetAt\":\"2026-11-01T00:00:00Z\",\"totalQuota\":{\"quotaSummary\":{\"usedValue\":400,\"limitValue\":\(limit)}}}".utf8),accountID:account,collectedAt:now)
        }
        let before=try snapshot(500),after=try snapshot(1000)
        let planner=NotificationPlanner()
        let initial=planner.planSuccessfulRefresh(accountID:account,accountName:"fixture",previousSnapshot:nil,newSnapshot:before,settings:AccountReminderSettings(),ledger:ReminderLedger(),now:now)
        let purchase=planner.planSuccessfulRefresh(accountID:account,accountName:"fixture",previousSnapshot:before,newSnapshot:after,settings:AccountReminderSettings(),ledger:initial.ledger,now:now)
        XCTAssertFalse(initial.operations.contains {if case .schedule=$0{return true};return false})
        XCTAssertFalse(purchase.operations.contains {if case .deliver(let value)=$0{return value.kind == .confirmedReset};return false})
    }

    func testCodingWidgetAndDemoUseCreditsNoCurrencyOrSummedPool()throws {
        let account=SubscriptionAccount(name:"fixture",provider:.qoderChina)
        let snapshot=try QoderChinaProviderClient.snapshot(Data(body.utf8),accountID:account.id,collectedAt:now)
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self,from:JSONEncoder().encode(snapshot)),snapshot)
        let widget=WidgetAccountSnapshot(account:account,windows:snapshot.windows,collectedAt:now,lastFailure:nil)
        XCTAssertEqual(widget.displayMetrics.count,3)
        XCTAssertTrue(widget.displayMetrics[0].valueText.contains("credits"))
        XCTAssertFalse(snapshot.windows.contains {$0.wallet != nil})
        XCTAssertEqual(DemoMode.snapshot(accountID:account.id,provider:.qoderChina).windows.count,2)
    }
}
private actor QoderChinaTransport:ProviderTransport {
    let status:Int;let body:String;private(set)var requests:[URLRequest]=[]
    init(status:Int,body:String){self.status=status;self.body=body}
    func data(for request:URLRequest)throws->(Data,URLResponse){requests.append(request);return(Data(body.utf8),HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!)}
}
