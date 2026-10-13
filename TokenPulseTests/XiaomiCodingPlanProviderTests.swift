import Foundation
import XCTest
@testable import TokenPulse

final class XiaomiCodingPlanProviderTests: XCTestCase {
    private let usage = #"{"code":0,"data":{"monthUsage":{"items":[{"name":"Coding Plan","used":3750000,"limit":10000000}]}}}"#
    private let detail = #"{"code":0,"data":{"planCode":"coding-pro","currentPeriodEnd":"2026-10-01 00:00:00","expired":false}}"#
    private let balance = #"{"code":0,"data":{"balance":"42.750000000000001","currency":"CNY","cashBalance":"40","giftBalance":"2.750000000000001"}}"#
    private func cookie(_ name: String, _ value: String = "fixture", domain: String = "platform.xiaomimimo.com") -> HTTPCookie {
        HTTPCookie(properties: [.name:name, .value:value, .domain:domain, .path:"/", .secure:"TRUE"])!
    }

    func testCookieAllowlistAccountOriginAndFingerprintBeforeNetwork() throws {
        let now = Date(timeIntervalSince1970: 100), id = UUID()
        let encoded = try XiaomiCodingPlanProviderClient.credential(cookies: [cookie("api-platform_serviceToken"), cookie("userId"), cookie("api-platform_ph"), cookie("_ga"), cookie("api-platform_slh", domain:"evil.example")], accountID: id, now: now)
        let envelope = try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .xiaomiCodingPlan)
        XCTAssertTrue(envelope.accessToken.contains("api-platform_serviceToken="))
        XCTAssertTrue(envelope.accessToken.contains("userId="))
        XCTAssertFalse(envelope.accessToken.contains("_ga"))
        XCTAssertFalse(envelope.accessToken.contains("api-platform_slh"))
        try WebProviderSession.validate(envelope, provider: .xiaomiCodingPlan, accountID: id, origins: [XiaomiCodingPlanProviderClient.origin], now: now)
        XCTAssertThrowsError(try WebProviderSession.validate(envelope, provider: .xiaomiCodingPlan, accountID: UUID(), origins: [XiaomiCodingPlanProviderClient.origin], now: now))
        XCTAssertThrowsError(try XiaomiCodingPlanProviderClient.credential(cookies: [cookie("userId")], accountID: id, now: now))
        XCTAssertNotNil(Provider.xiaomiCodingPlan.webLoginProfile)
        XCTAssertEqual(ProviderAuthenticationController().loginConfiguration(for: .xiaomiCodingPlan).method, .webSession)
    }

    func testAllRoutesUseSameRestrictedSessionAndSeparatePlanFromExactMoney() async throws {
        let now = Date(timeIntervalSince1970: 100), id = UUID()
        let transport = XiaomiRouteTransport(["tokenPlan/usage":(200,usage), "tokenPlan/detail":(200,detail), "balance":(200,balance)])
        let envelope = try ProviderCredentialEnvelope.decode(XiaomiCodingPlanProviderClient.credential(cookies: [cookie("api-platform_serviceToken"), cookie("userId")], accountID: id, now: now), expectedProvider: .xiaomiCodingPlan)
        let result = try await XiaomiCodingPlanProviderClient(transport: transport, now: { now }).quota(accountID: id, credential: envelope)
        XCTAssertEqual(result.snapshot.windows.count, 2)
        XCTAssertEqual(result.snapshot.windows[0].usedPercentage, 37.5)
        XCTAssertEqual(result.snapshot.windows[0].exactCounts?.remaining, 6_250_000)
        XCTAssertEqual(result.snapshot.windows[0].unit, "tokens")
        XCTAssertEqual(result.snapshot.windows[1].wallet?.total, Decimal(string:"42.750000000000001"))
        XCTAssertEqual(result.snapshot.windows[1].wallet?.granted, Decimal(string:"2.750000000000001"))
        XCTAssertNil(result.snapshot.windows[1].usedPercentage)
        XCTAssertEqual(result.snapshot.walletCollectedAt, now)
        XCTAssertNil(result.snapshot.quotaStatusText)
        let requests = await transport.requests
        XCTAssertEqual(Set(requests.map(\.url?.path)), ["/api/v1/tokenPlan/usage","/api/v1/tokenPlan/detail","/api/v1/balance"])
        XCTAssertTrue(requests.allSatisfy { $0.url?.host == "platform.xiaomimimo.com" && $0.value(forHTTPHeaderField:"Cookie") == envelope.accessToken && !$0.httpShouldHandleCookies })
    }

    func testPartialWalletFailureIsTaggedAndNeverRelabelsOldMoneyAsFresh() async throws {
        let now = Date(timeIntervalSince1970: 100), id = UUID()
        let envelope = try ProviderCredentialEnvelope.decode(XiaomiCodingPlanProviderClient.credential(cookies: [cookie("api-platform_serviceToken"), cookie("userId")], accountID: id, now: now), expectedProvider: .xiaomiCodingPlan)
        let transport = XiaomiRouteTransport(["tokenPlan/usage":(200,usage),"tokenPlan/detail":(500,"{}"),"balance":(500,"{}")])
        let result = try await XiaomiCodingPlanProviderClient(transport:transport,now:{now}).quota(accountID:id,credential:envelope)
        XCTAssertEqual(result.snapshot.windows.count, 1)
        XCTAssertEqual(result.snapshot.walletFailure, .server)
        XCTAssertNil(result.snapshot.walletCollectedAt)
        XCTAssertNil(result.snapshot.windows[0].resetsAt)
        var old = try XiaomiCodingPlanProviderClient.snapshot(usage:Data(usage.utf8),detail:nil,balance:Data(balance.utf8),accountID:id,collectedAt:Date(timeIntervalSince1970:50))
        old.sourceCredentialFingerprint = result.snapshot.sourceCredentialFingerprint
        let merged = result.snapshot.retainingWalletAfterPartialFailure(from:old)
        XCTAssertEqual(merged.walletCollectedAt,old.collectedAt)
        let plan = NotificationPlanner().planSuccessfulRefresh(accountID:id,accountName:"fixture",previousSnapshot:old,newSnapshot:merged,settings:AccountReminderSettings(walletThresholds:["CNY":100]),ledger:ReminderLedger(),now:now)
        XCTAssertFalse(plan.operations.contains { if case .deliver(let value)=$0 { return value.kind == .walletAlert }; return false })
    }

    func testEnvelopeRefusalOnAnyRouteIsCredentialFailureNotNoPlan() async throws {
        let now = Date(timeIntervalSince1970:100),id=UUID()
        let credential = try ProviderCredentialEnvelope.decode(XiaomiCodingPlanProviderClient.credential(cookies:[cookie("api-platform_serviceToken"),cookie("userId")],accountID:id,now:now),expectedProvider:.xiaomiCodingPlan)
        for route in ["tokenPlan/usage","tokenPlan/detail","balance"] {
            var replies:[String:(Int,String)] = ["tokenPlan/usage":(200,usage),"tokenPlan/detail":(200,detail),"balance":(200,balance)]
            replies[route]=(200,#"{"code":401,"data":{}}"#)
            do { _ = try await XiaomiCodingPlanProviderClient(transport:XiaomiRouteTransport(replies),now:{now}).quota(accountID:id,credential:credential); XCTFail() }
            catch { XCTAssertEqual(error as? RefreshFailure,.invalidCredential) }
        }
    }

    func testNoPlanAndExpiredPlanStillShowMoneyWithoutClaimingUnlimited() throws {
        for (usage, detail) in [(#"{"code":0,"data":{"monthUsage":{"items":[]}}}"#,self.detail),(self.usage,#"{"code":0,"data":{"expired":true}}"#)] {
            let account = SubscriptionAccount(name:"fixture",provider:.xiaomiCodingPlan)
            let snapshot = try XiaomiCodingPlanProviderClient.snapshot(usage:Data(usage.utf8),detail:Data(detail.utf8),balance:Data(balance.utf8),accountID:account.id,collectedAt:Date())
            XCTAssertNotNil(snapshot.quotaStatusText)
            XCTAssertEqual(snapshot.windows.count,1)
            XCTAssertNotNil(snapshot.windows[0].wallet)
            let widget=WidgetAccountSnapshot(account:account,windows:snapshot.windows,collectedAt:snapshot.collectedAt,lastFailure:nil,quotaStatusText:snapshot.quotaStatusText)
            XCTAssertEqual(widget.displayMetrics.count,1)
            XCTAssertFalse(widget.displayMetrics[0].valueText.contains("无上限"))
            XCTAssertTrue(widget.displayMetrics[0].valueText.contains("CNY"))
        }
    }

    func testMissingMalformedUsageNeverBecomesZeroOrNoPlan() {
        for data in [#"{"code":0,"data":{}}"#,#"{"code":0,"data":{"monthUsage":{"items":[{"limit":10}]}}}"#,#"{"code":true,"data":{"monthUsage":{"items":[]}}}"#,#"{"code":500,"data":{"monthUsage":{"items":[]}}}"#] {
            XCTAssertThrowsError(try XiaomiCodingPlanProviderClient.snapshot(usage:Data(data.utf8),detail:nil,balance:nil,accountID:UUID(),collectedAt:Date()))
        }
        XCTAssertThrowsError(try XiaomiCodingPlanProviderClient.balanceWindow(Data(#"{"code":0,"data":{"currency":"CNY"}}"#.utf8)))
    }

    func testParserCodingDemoAndApplicableNotificationUnits() throws {
        let account=SubscriptionAccount(name:"fixture",provider:.xiaomiCodingPlan)
        let snapshot=try XiaomiCodingPlanProviderClient.snapshot(usage:Data(usage.utf8),detail:Data(detail.utf8),balance:Data(balance.utf8),accountID:account.id,collectedAt:Date(timeIntervalSince1970:100))
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self,from:JSONEncoder().encode(snapshot)),snapshot)
        XCTAssertEqual(DemoMode.snapshot(accountID:account.id,provider:.xiaomiCodingPlan).windows.count,2)
        XCTAssertEqual(Provider.xiaomiCodingPlan.iconAssetName,"ProviderXiaomiMiMo")
        let plan=NotificationPlanner().planSuccessfulRefresh(accountID:account.id,accountName:account.name,previousSnapshot:nil,newSnapshot:snapshot,settings:AccountReminderSettings(walletThresholds:["CNY":100]),ledger:ReminderLedger(),now:snapshot.collectedAt)
        XCTAssertTrue(plan.operations.contains { if case .deliver(let value)=$0 { return value.kind == .walletAlert }; return false })
    }
}

private actor XiaomiRouteTransport:ProviderTransport {
    let replies:[String:(Int,String)]
    private(set) var requests:[URLRequest]=[]
    init(_ replies:[String:(Int,String)]) { self.replies=replies }
    func data(for request:URLRequest)throws->(Data,URLResponse) {
        requests.append(request)
        let key=String(request.url!.path.dropFirst("/api/v1/".count))
        let reply=replies[key] ?? (500,"{}")
        return (Data(reply.1.utf8),HTTPURLResponse(url:request.url!,statusCode:reply.0,httpVersion:nil,headerFields:nil)!)
    }
}
