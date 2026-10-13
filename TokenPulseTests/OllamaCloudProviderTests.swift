import Foundation
import XCTest
@testable import TokenPulse

final class OllamaCloudProviderTests:XCTestCase {
    private let normal=#"<html><body><div><section data-usage-meter='session'><h3>Session usage</h3><p>12% used</p><span data-time='2026-11-01T00:00:00Z'>Next</span></section><section data-usage-meter='week'><h3>Weekly usage</h3><p>34.5% used</p></section></div></body></html>"#
    private func cookie(_ name:String,domain:String="ollama.com")->HTTPCookie {
        HTTPCookie(properties:[.name:name,.value:"fixture",.domain:domain,.path:"/",.secure:"TRUE"])!
    }
    func testVisibleMetersHaveOriginalScaleAndMissingResetIsUnknown()throws {
        let windows=try OllamaUsagePage.windows(Data(normal.utf8))
        XCTAssertEqual(windows.map(\.usedPercentage),[12,34.5])
        XCTAssertEqual(windows.map(\.period),[.fiveHour,.weekly])
        XCTAssertNotNil(windows[0].resetsAt)
        XCTAssertNil(windows[1].resetsAt)
        XCTAssertTrue(windows.allSatisfy{$0.totalCount==nil && $0.wallet==nil})
    }
    func testMissingDuplicateAmbiguousAndOutOfRangeMetersAreLayoutFailure() {
        for html in [normal.replacingOccurrences(of:"Weekly usage",with:"Other usage"),normal.replacingOccurrences(of:"<p>12% used</p>",with:"<p>12% used</p><p>3% used</p>"),normal.replacingOccurrences(of:"12% used",with:"101% used"),normal.replacingOccurrences(of:"<h3>Session usage</h3>",with:"<h3>Session usage</h3><h3>Session usage</h3>"),normal.replacingOccurrences(of:"12% used",with:"Coming soon") ] {
            XCTAssertThrowsError(try OllamaUsagePage.windows(Data(html.utf8))) {XCTAssertEqual($0 as? RefreshFailure,.unreadableResponse)}
        }
    }
    func testScriptTemplateCSSAndEntitiesCannotSupplyFakeMeters()throws {
        let injection=#"<script>const html='</div><h3>Session usage</h3><p>99% used</p>';</script><template><h3>Weekly usage</h3><p>99% used</p></template>"#
        let html=normal.replacingOccurrences(of:"<body>",with:"<body>"+injection)
        XCTAssertEqual(try OllamaUsagePage.windows(Data(html.utf8)).map(\.usedPercentage),[12,34.5])
        let css=normal.replacingOccurrences(of:"<p>12% used</p>",with:"<div style='width:12%'></div>")
        XCTAssertThrowsError(try OllamaUsagePage.windows(Data(css.utf8)))
        XCTAssertThrowsError(try OllamaUsagePage.windows(Data(("<!DOCTYPE html [<!ENTITY xxe SYSTEM 'file:///not-read'>]>"+normal).utf8)))
        XCTAssertThrowsError(try OllamaUsagePage.windows(Data(repeating:65,count:OllamaUsagePage.maximumBytes+1)))
    }
    func testMultipleOrMalformedTimesNeverCreateResetGuesses() {
        for html in [normal.replacingOccurrences(of:"2026-11-01T00:00:00Z",with:"tomorrow"),normal.replacingOccurrences(of:"Next</span>",with:"Next</span><time data-time='2026-11-02T00:00:00Z'></time>")] {
            XCTAssertThrowsError(try OllamaUsagePage.windows(Data(html.utf8)))
        }
        XCTAssertThrowsError(try OllamaUsagePage.windows(Data(#"<html><body><form action='/signin'><input name='email'></form></body></html>"#.utf8))) {XCTAssertEqual($0 as? RefreshFailure,.invalidCredential)}
    }
    func testRecognizedChunksAreScopedAndAPIKeysAreNotSessions()throws {
        let id=UUID(),now=Date(timeIntervalSince1970:100)
        let encoded=try OllamaCloudProviderClient.credential(cookies:[cookie("wos-session.0"),cookie("wos-session.1"),cookie("wos-session.bad"),cookie("_ga"),cookie("wos-session",domain:"evil.example")],accountID:id,now:now)
        let envelope=try ProviderCredentialEnvelope.decode(encoded,expectedProvider:.ollamaCloud)
        XCTAssertTrue(envelope.accessToken.contains("wos-session.0="))
        XCTAssertTrue(envelope.accessToken.contains("wos-session.1="))
        XCTAssertFalse(envelope.accessToken.contains(".bad"))
        XCTAssertFalse(envelope.accessToken.contains("_ga"))
        XCTAssertThrowsError(try OllamaCloudProviderClient.credential(cookies:[cookie("api-key")],accountID:id,now:now))
        XCTAssertThrowsError(try WebProviderSession.validate(envelope,provider:.ollamaCloud,accountID:UUID(),origins:[OllamaCloudProviderClient.origin],now:now))
        XCTAssertNotNil(Provider.ollamaCloud.webLoginProfile)
    }
    func testRequestAndExpiredSessionOrWrongContentTypeRemainDistinct()async throws {
        let now=Date(timeIntervalSince1970:100),id=UUID()
        let envelope=try ProviderCredentialEnvelope.decode(OllamaCloudProviderClient.credential(cookies:[cookie("wos-session")],accountID:id,now:now),expectedProvider:.ollamaCloud)
        let transport=OllamaTransport(status:200,body:normal,mime:"text/html")
        let result=try await OllamaCloudProviderClient(transport:transport,now:{now}).quota(accountID:id,credential:envelope)
        XCTAssertEqual(result.snapshot.windows.count,2)
        let requests=await transport.requests
        XCTAssertEqual(requests[0].url?.absoluteString,"https://ollama.com/settings")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField:"Accept-Language"),"en-US,en;q=0.9")
        XCTAssertFalse(requests[0].httpShouldHandleCookies)
        for(status,mime,failure)in [(303,"text/html",RefreshFailure.invalidCredential),(401,"text/html",.invalidCredential),(429,"text/html",.rateLimited),(200,"application/json",.unreadableResponse)] {
            do {_ = try await OllamaCloudProviderClient(transport:OllamaTransport(status:status,body:normal,mime:mime),now:{now}).quota(accountID:id,credential:envelope);XCTFail()}
            catch {XCTAssertEqual(error as? RefreshFailure,failure)}
        }
    }
    func testWidgetDemoCodingAndQuotaAlertsHaveNoWalletInterpretation()throws {
        let account=SubscriptionAccount(name:"fixture",provider:.ollamaCloud)
        let windows=try OllamaUsagePage.windows(Data(normal.replacingOccurrences(of:"12% used",with:"95% used").utf8))
        let snapshot=QuotaSnapshot(accountID:account.id,windows:windows,collectedAt:Date(timeIntervalSince1970:100))
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self,from:JSONEncoder().encode(snapshot)),snapshot)
        let widget=WidgetAccountSnapshot(account:account,windows:windows,collectedAt:snapshot.collectedAt,lastFailure:nil)
        XCTAssertEqual(widget.displayMetrics.count,2)
        XCTAssertEqual(DemoMode.snapshot(accountID:account.id,provider:.ollamaCloud).windows.count,2)
        XCTAssertEqual(Provider.ollamaCloud.iconAssetName,"ProviderOllama")
        let plan=NotificationPlanner().planSuccessfulRefresh(accountID:account.id,accountName:account.name,previousSnapshot:nil,newSnapshot:snapshot,settings:AccountReminderSettings(),ledger:ReminderLedger(),now:snapshot.collectedAt)
        XCTAssertTrue(plan.operations.contains {if case .deliver(let value)=$0{return value.kind == .quotaAlert};return false})
        XCTAssertFalse(plan.operations.contains {if case .deliver(let value)=$0{return value.kind == .walletAlert};return false})
    }
}
private actor OllamaTransport:ProviderTransport {
    let status:Int;let body:String;let mime:String;private(set)var requests:[URLRequest]=[]
    init(status:Int,body:String,mime:String){self.status=status;self.body=body;self.mime=mime}
    func data(for request:URLRequest)throws->(Data,URLResponse){requests.append(request);return(Data(body.utf8),HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:["Content-Type":mime])!)}
}
