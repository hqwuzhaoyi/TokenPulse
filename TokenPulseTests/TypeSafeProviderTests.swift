import Foundation
import XCTest
@testable import TokenPulse

final class TypeSafeProviderTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 100)
    private let action = String(repeating: "a", count: 40)
    private let page = #"<html><script src="/_next/static/chunks/app.js"></script></html>"#
    private func stream(_ body: String) -> String { "0:{\"a\":\"$@1\"}\n1:" + body }
    private func chunk(_ id: String) -> String { "x(\"" + id + "\",c.callServer,void 0,c.findSourceMapURL,\"getBillingOverviewResult\")" }
    private func credential(id: UUID) throws -> ProviderCredentialEnvelope {
        try WebProviderSession.credential(provider: .typeSafe, origin: TypeSafeSession.origin, accountID: id, accessToken: "site-session=fixture")
    }
    func testReferencedResultOnlyAndExactBalanceWithoutAssumedCurrency() throws {
        let payload = #"{"ok":true,"data":{"billing":{"balance":4.980000000000000001,"spent":100,"plan":"free_plan"}}}"#
        let body = stream(payload) + "\n2:{\"ok\":true,\"data\":{\"billing\":{\"balance\":999}}}"
        let snapshot = try TypeSafeProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: date)
        let wallet = try XCTUnwrap(snapshot.windows.first?.wallet)
        XCTAssertEqual(wallet.total, Decimal(string: "4.980000000000000001"))
        XCTAssertFalse(wallet.isMonetary); XCTAssertEqual(snapshot.providerPlanName,"Free")
        XCTAssertNil(snapshot.windows.first?.usedPercentage)
        XCTAssertNil(snapshot.windows.first?.resetsAt)
        let usd = stream(#"{"ok":true,"data":{"billing":{"balance":0,"currency":"USD","plan":"pro_monthly"}}}"#)
        let known = try TypeSafeProviderClient.snapshot(Data(usd.utf8),accountID:UUID(),collectedAt:date)
        XCTAssertEqual(known.windows.first?.wallet?.isMonetary,true)
        XCTAssertEqual(known.windows.first?.wallet?.total,0)
        XCTAssertEqual(known.providerPlanName,"Pro Monthly")
    }
    func testMalformedUnknownAndLoginResponsesDoNotBecomeFreshZero() {
        for payload in [#"{"ok":1,"data":{"billing":{"balance":0}}}"#, #"{"ok":true,"data":{}}"#,
                        #"{"ok":true,"data":{"billing":{"balance":true}}}"#, #"{"ok":true,"data":{"billing":{"balance":"4.98"}}}"#] {
            XCTAssertThrowsError(try TypeSafeProviderClient.snapshot(Data(stream(payload).utf8),accountID:UUID(),collectedAt:date))
        }
        XCTAssertThrowsError(try TypeSafeProviderClient.snapshot(Data(stream(#"{"ok":false}"#).utf8),accountID:UUID(),collectedAt:date)) { XCTAssertEqual($0 as? RefreshFailure,.server) }
        XCTAssertThrowsError(try TypeSafeProviderClient.snapshot(Data(#"2:{"ok":true,"data":{"billing":{"balance":0}}}"#.utf8),accountID:UUID(),collectedAt:date))
        XCTAssertTrue(TypeSafeProviderClient.isLoginLanding(#"["(auth)",{"children":["login""#))
        XCTAssertThrowsError(try TypeSafeProviderClient.snapshot(Data(#"<html>["(auth)",{"children":["login""#.utf8),accountID:UUID(),collectedAt:date)) { XCTAssertEqual($0 as? RefreshFailure,.invalidCredential) }
    }
    func testScriptDiscoveryRejectsForeignOriginsAndConflictingActionIdentifiers() {
        let html = page + #"<script src="https://console.typesafe.ai.evil.test/evil.js"></script><script src="https://user@console.typesafe.ai/evil.js"></script><script src="https://console.typesafe.ai:444/wrong.js"></script><script src="/_next/static/chunks/app.js"></script><script src="/style.css"></script>"#
        XCTAssertEqual(TypeSafeProviderClient.chunkURLs(html).map(\.path),["/_next/static/chunks/app.js"])
        let many = (0..<100).map { "<script src=\"/\($0).js\"></script>" }.joined()
        XCTAssertEqual(TypeSafeProviderClient.chunkURLs(many).count,60)
        XCTAssertEqual(TypeSafeProviderClient.actionID(chunk(action)),action)
        XCTAssertNil(TypeSafeProviderClient.actionID(chunk(action)+chunk(String(repeating:"b",count:40))))
        XCTAssertNil(TypeSafeProviderClient.actionID("\""+action+"\");unrelated(\"getBillingOverviewResult\")"))
    }
    func testDiscoveryCachesOnlyPublicActionAndNeverSendsSessionOnScripts() async throws {
        let id = UUID(), now = date, credential = try credential(id:id), cache = TypeSafeActionCache()
        let result = stream(#"{"ok":true,"data":{"billing":{"balance":4.98}}}"#)
        let transport = TypeSafeTestTransport(replies:[.init(200,page),.init(200,chunk(action)),.init(200,result),.init(200,result)])
        let client = TypeSafeProviderClient(transport:transport,now:{now},cache:cache)
        let first = try await client.quota(accountID:id,credential:credential)
        _ = try await client.quota(accountID:id,credential:credential)
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.httpMethod),["GET","GET","POST","POST"])
        XCTAssertNil(requests[1].value(forHTTPHeaderField:"Cookie"))
        XCTAssertFalse(requests[1].httpShouldHandleCookies)
        XCTAssertEqual(requests[2].value(forHTTPHeaderField:"Cookie"),"site-session=fixture")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField:"Next-Action"),action)
        XCTAssertEqual(requests[2].httpBody,Data("[]".utf8))
        XCTAssertNil(first.updatedCredential)
        XCTAssertEqual(first.snapshot.sourceCredentialFingerprint,credential.sourceCredentialIdentity)
        let expired = await cache.current(at:now.addingTimeInterval(12*3600)); XCTAssertNil(expired)
    }
    func testOnlyExplicitActionNotFoundRediscoveryIsRetriedOnce() async throws {
        let id=UUID(),now=date,credential=try credential(id:id),cache=TypeSafeActionCache()
        await cache.remember(action,at:now)
        let newAction=String(repeating:"b",count:40)
        let result=stream(#"{"ok":true,"data":{"billing":{"balance":1}}}"#)
        let transport=TypeSafeTestTransport(replies:[.init(404,"",headers:["x-nextjs-action-not-found":"1"]),.init(200,page),.init(200,chunk(newAction)),.init(200,result)])
        _ = try await TypeSafeProviderClient(transport:transport,now:{now},cache:cache).quota(accountID:id,credential:credential)
        let requests=await transport.requests
        XCTAssertEqual(requests.map(\.httpMethod),["POST","GET","GET","POST"])
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField:"Next-Action"),newAction)
        let denied=TypeSafeTestTransport(replies:[.init(404,"")])
        do { _ = try await TypeSafeProviderClient(transport:denied,now:{now},cache:cache).quota(accountID:id,credential:credential); XCTFail("ordinary404") } catch {}
        let deniedCount=await denied.requests.count; XCTAssertEqual(deniedCount,1)
    }
    func testAuthenticationRedirectAndAccountMismatchStopRequests() async throws {
        let id=UUID(),now=date,credential=try credential(id:id)
        for code in [302,401,403] {
            let transport=TypeSafeTestTransport(replies:[.init(code,"")])
            do { _ = try await TypeSafeProviderClient(transport:transport,now:{now},cache:TypeSafeActionCache()).quota(accountID:id,credential:credential); XCTFail("auth") }
            catch { XCTAssertEqual(error as? RefreshFailure,.invalidCredential) }
            let requests=await transport.requests;XCTAssertEqual(requests.count,1)
        }
        let transport=TypeSafeTestTransport(replies:[])
        do { _ = try await TypeSafeProviderClient(transport:transport,now:{now},cache:TypeSafeActionCache()).quota(accountID:UUID(),credential:credential);XCTFail("scope") }
        catch { XCTAssertEqual(error as? RefreshFailure,.invalidCredential) }
        let requests=await transport.requests;XCTAssertTrue(requests.isEmpty)
    }
}
private actor TypeSafeTestTransport: ProviderTransport {
    struct Reply: Sendable { let status:Int;let body:String;let headers:[String:String];init(_ status:Int,_ body:String,headers:[String:String]=[:]) {self.status=status;self.body=body;self.headers=headers} }
    var replies:[Reply]
    private(set) var requests:[URLRequest]=[]
    init(replies:[Reply]) {self.replies=replies}
    func data(for request:URLRequest) async throws -> (Data,URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else {throw RefreshFailure.server}
        let reply=replies.removeFirst()
        return (Data(reply.body.utf8),HTTPURLResponse(url:request.url!,statusCode:reply.status,httpVersion:nil,headerFields:reply.headers)!)
    }
}
