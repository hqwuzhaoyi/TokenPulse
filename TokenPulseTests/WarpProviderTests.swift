import Foundation
import XCTest
@testable import TokenPulse

final class WarpProviderTests: XCTestCase {
    private let reply = #"{"data":{"user":{"__typename":"UserOutput","user":{"requestLimitInfo":{"isUnlimited":false,"requestLimit":2500,"requestsUsedSinceLastRefresh":625,"nextRefreshTime":"2026-11-01T00:00:00Z"},"bonusGrants":[{"createdAt":"2026-01-01T00:00:00Z","requestCreditsGranted":1000,"requestCreditsRemaining":400,"expiration":"2026-11-15T12:00:00Z"}],"workspaces":[{"uid":"workspace-fixture","bonusGrantsInfo":{"grants":[{"createdAt":"2026-02-01T00:00:00Z","requestCreditsGranted":500,"requestCreditsRemaining":500,"expiration":"2026-12-01T00:00:00Z"}]}}]}}}}"#

    func testReadOnlyGraphQLKeyContractUsesRequiredClientHeaders() async throws {
        let transport = WarpTransport([(200, reply)]), id = UUID(), date = Date(timeIntervalSince1970: 100)
        let key = try ProviderAuthenticationController().credential(provider: .warp, apiKey: " wk-fixture ")
        let snapshot = try await ProviderQuotaClient(provider: .warp, transport: transport, now: { date }).quota(for: id, credential: key)
        XCTAssertEqual(snapshot.accountID, id)
        XCTAssertEqual(snapshot.collectedAt, date)
        XCTAssertEqual(snapshot.windows.count, 3)
        let requests = await transport.requests, request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://app.warp.dev/graphql/v2?op=GetRequestLimitInfo")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer wk-fixture")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-warp-client-id"), "warp-app")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-warp-os-category"), "macOS")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Warp/1.0")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertFalse(request.httpShouldHandleCookies)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String:Any])
        XCTAssertEqual(body["operationName"] as? String, "GetRequestLimitInfo")
        let query = try XCTUnwrap(body["query"] as? String)
        XCTAssertTrue(query.hasPrefix("query GetRequestLimitInfo"))
        XCTAssertFalse(query.contains("mutation"))
        XCTAssertTrue(query.contains("workspaces { uid"))
        XCTAssertTrue(query.contains("createdAt"))
        let context = ((body["variables"] as? [String:Any])?["requestContext"] as? [String:Any])?["osContext"] as? [String:String]
        XCTAssertEqual(context?["version"], request.value(forHTTPHeaderField: "x-warp-os-version"))
        XCTAssertEqual(ProviderAuthenticationController().loginConfiguration(for: .warp).method, .apiKey)
    }

    func testPlanAndPersonalWorkspaceGrantsStaySeparateWithIndependentExpiry() throws {
        let windows = try WarpProviderClient.windows(Data(reply.utf8), now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(windows.map(\.name), ["套餐 credits", "个人 附加 credits 1", "工作区 1 附加 credits 1"])
        XCTAssertEqual(windows.map(\.usedPercentage), [25,60,0])
        XCTAssertEqual(windows.map(\.exactCounts?.total), [2500,1000,500])
        XCTAssertNotNil(windows[0].resetsAt)
        XCTAssertNil(windows[1].resetsAt)
        XCTAssertNil(windows[2].resetsAt)
        XCTAssertNotEqual(windows[1].expiresAt, windows[2].expiresAt)
        XCTAssertEqual(Set(windows.map(\.id)).count,3)
        XCTAssertTrue(windows.allSatisfy { $0.wallet == nil && $0.unit == "credits" })
        let account = SubscriptionAccount(name: "Warp",provider: .warp)
        let widget = WidgetAccountSnapshot(account: account,windows: windows,collectedAt: Date(),lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count,3)
        XCTAssertEqual(widget.displayMetrics[1].valueText,QuotaFormatting.exactCountSummary(windows[1]))
    }

    func testGrantIDsIgnoreConsumptionAndAreStableAcrossWorkspaceReordering() throws {
        let body = #"{"data":{"user":{"user":{"requestLimitInfo":{"isUnlimited":true},"workspaces":[{"uid":"A","bonusGrantsInfo":{"grants":[{"createdAt":"2026-01-01T00:00:00Z","requestCreditsGranted":100,"requestCreditsRemaining":80}]}},{"uid":"B","bonusGrantsInfo":{"grants":[{"createdAt":"2026-01-02T00:00:00Z","requestCreditsGranted":200,"requestCreditsRemaining":100}]}}]}}}}"#
        let before = try WarpProviderClient.windows(Data(body.utf8),now: Date(timeIntervalSince1970:100))
        var root = try ProviderHTTP.json(Data(body.replacingOccurrences(of: "Remaining\":80",with: "Remaining\":70").utf8))
        var data = root["data"] as! [String:Any], output = data["user"] as! [String:Any], user = output["user"] as! [String:Any]
        user["workspaces"] = Array((user["workspaces"] as! [[String:Any]]).reversed())
        output["user"] = user; data["user"] = output; root["data"] = data
        let after = try WarpProviderClient.windows(JSONSerialization.data(withJSONObject: root),now: Date(timeIntervalSince1970:100))
        XCTAssertEqual(Set(before.map(\.id)),Set(after.map(\.id)))
        XCTAssertTrue(before[0].isUnlimited)
        XCTAssertNil(before[0].usedPercentage)
        XCTAssertNil(before[0].resetsAt)
    }

    func testMissingDenominatorDoesNotInventPercentageOrTotalAndExpiredGrantIsOmitted() throws {
        let body = #"{"data":{"user":{"user":{"requestLimitInfo":{"isUnlimited":true},"bonusGrants":[{"requestCreditsRemaining":30},{"requestCreditsGranted":100,"requestCreditsRemaining":80,"expiration":"2020-01-01T00:00:00Z"},{"requestCreditsGranted":0,"requestCreditsRemaining":0}]}}}}"#
        let windows = try WarpProviderClient.windows(Data(body.utf8),now: Date(timeIntervalSince1970:1790000000))
        XCTAssertEqual(windows.count,2)
        XCTAssertNil(windows[1].usedPercentage)
        XCTAssertNil(windows[1].exactCounts?.used)
        XCTAssertNil(windows[1].exactCounts?.total)
        XCTAssertEqual(windows[1].exactCounts?.remaining,30)
        XCTAssertNil(windows[1].isExhausted)
        let duplicate = #"{"data":{"user":{"user":{"requestLimitInfo":{"isUnlimited":true},"bonusGrants":[{"requestCreditsGranted":100,"requestCreditsRemaining":80},{"requestCreditsGranted":100,"requestCreditsRemaining":80}]}}}}"#
        let repeated = try WarpProviderClient.windows(Data(duplicate.utf8),now: Date())
        XCTAssertEqual(Set(repeated.map(\.id)).count,3)
    }

    func testGraphQLErrorsBooleanFlagsInvalidCountsAndTimeOverflowFailExplicitly() throws {
        XCTAssertThrowsError(try WarpProviderClient.windows(Data(#"{"errors":[{"message":"Denied"}]}"#.utf8),now: Date())) { XCTAssertEqual($0 as? RefreshFailure,.server) }
        for body in [
            #"{"data":{"user":{"user":{"requestLimitInfo":{"isUnlimited":1}}}}}"#,
            #"{"data":{"user":{"user":{"requestLimitInfo":{"isUnlimited":false,"requestLimit":true,"requestsUsedSinceLastRefresh":0}}}}}"#,
            #"{"data":{"user":{"user":{"requestLimitInfo":{"isUnlimited":true},"bonusGrants":[{"requestCreditsGranted":10,"requestCreditsRemaining":11}]}}}}"#,
            #"{"data":{"user":{"user":{"requestLimitInfo":{"isUnlimited":false,"requestLimit":100,"requestsUsedSinceLastRefresh":1,"nextRefreshTime":"1e300"}}}}}"#,
            #"{"data":{"user":{"user":{"requestLimitInfo":{"isUnlimited":true},"workspaces":[{"bonusGrantsInfo":{"grants":[{"requestCreditsGranted":10,"requestCreditsRemaining":5}]}}]}}}}"#,
        ] { XCTAssertThrowsError(try WarpProviderClient.windows(Data(body.utf8),now: Date())) { XCTAssertEqual($0 as? RefreshFailure,.unreadableResponse) } }
    }

    func testOnlyPlanSchedulesResetAndGrantExpiryNeverMeansReset() throws {
        let now = Date(timeIntervalSince1970:100), id = UUID()
        let windows = try WarpProviderClient.windows(Data(reply.replacingOccurrences(of: "Refresh\":625",with: "Refresh\":2400").utf8),now: now)
        let snapshot = QuotaSnapshot(accountID:id,windows:windows,collectedAt:now)
        let result = NotificationPlanner().planSuccessfulRefresh(accountID:id,accountName:"Warp",previousSnapshot:nil,newSnapshot:snapshot,settings:.init(),ledger:.init(),now:now)
        XCTAssertEqual(result.ledger.pendingSchedules(accountID:id).count,1)
        XCTAssertEqual(result.ledger.pendingSchedules(accountID:id)[0].windowIDs,Set(["warp.plan"]))
        XCTAssertTrue(result.operations.contains { if case .deliver(let n) = $0 { return n.kind == .quotaAlert }; return false })
        XCTAssertFalse(result.operations.contains { if case .deliver(let n) = $0 { return n.kind == .walletAlert }; return false })
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self,from:JSONEncoder().encode(snapshot)),snapshot)
        let demo = try XCTUnwrap(DemoMode.accounts().first { $0.provider == .warp })
        XCTAssertEqual(DemoMode.snapshot(accountID:demo.id,provider:.warp).windows.count,3)
    }

    @MainActor
    func testAccountRestoreKeyReplacementDeletionAndFailedRefreshIsolation() async throws {
        let store = WarpStore(),transport = WarpTransport([(200,reply),(200,reply),(200,#"{"errors":[{"message":"Denied"}]}"#),(200,reply)])
        let client = ProviderQuotaClient(provider:.warp,transport:transport)
        let monitor = QuotaMonitor(accountStore:store,credentialStore:store,quotaClient:client)
        await monitor.start(refresh:false)
        await monitor.addAccount(name:"Work",credential:try key("work"),provider:.warp)
        await monitor.addAccount(name:"Personal",credential:try key("personal"),provider:.warp)
        let first = try XCTUnwrap(monitor.states.first),second = try XCTUnwrap(monitor.states.last)
        let restored = QuotaMonitor(accountStore:store,credentialStore:store,quotaClient:client)
        await restored.start(refresh:false)
        XCTAssertEqual(restored.states,monitor.states)
        await restored.refresh(accountID:first.id)
        XCTAssertEqual(restored.states[0].snapshot,first.snapshot)
        XCTAssertEqual(restored.states[0].lastFailure,.server)
        await restored.replaceCredential(try key("renewed"),accountID:first.id)
        XCTAssertNil(restored.states[0].lastFailure)
        XCTAssertEqual(restored.states[1],second)
        let deleted = await restored.deleteAccount(accountID:first.id)
        XCTAssertTrue(deleted)
        let removed = await store.credential(for:first.id),retained = await store.credential(for:second.id)
        XCTAssertNil(removed)
        XCTAssertEqual(retained,try key("personal"))
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField:"Authorization") },["Bearer work","Bearer personal","Bearer work","Bearer renewed"])
    }
    func testGrantRecoveryRearmsAlertsWithoutAnyResetClaim() throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let firstWindows = try WarpProviderClient.windows(Data(reply.replacingOccurrences(of: "Remaining\":400", with: "Remaining\":50").utf8), now: now)
        XCTAssertTrue(firstWindows.filter { $0.id.hasPrefix("warp.grant.") }.allSatisfy { $0.resetSemantics == .nonResettingAllowance })
        let first = QuotaSnapshot(accountID: id, windows: firstWindows, collectedAt: now)
        let planner = NotificationPlanner()
        let planned = planner.planSuccessfulRefresh(accountID: id, accountName: "Warp", previousSnapshot: nil,
            newSnapshot: first, settings: .init(), ledger: .init(), now: now)
        let recoveredWindows = try WarpProviderClient.windows(Data(reply.replacingOccurrences(of: "Remaining\":400", with: "Remaining\":900").utf8), now: now)
        let recovered = QuotaSnapshot(accountID: id, windows: recoveredWindows, collectedAt: now.addingTimeInterval(100))
        let after = planner.planSuccessfulRefresh(accountID: id, accountName: "Warp", previousSnapshot: first,
            newSnapshot: recovered, settings: .init(), ledger: planned.ledger, now: recovered.collectedAt)
        XCTAssertFalse(after.operations.contains { if case .deliver(let n) = $0 { return n.kind == .confirmedReset }; return false })
        XCTAssertTrue(after.ledger.pendingSchedules(accountID: id).allSatisfy { $0.windowIDs == Set(["warp.plan"]) })
    }

    private func key(_ token:String) throws -> String { try ProviderCredentialEnvelope(provider:.warp,kind:.apiKey,accessToken:token).encoded() }
}
private actor WarpTransport:ProviderTransport {
    private var replies:[(Int,String)]
    private(set) var requests:[URLRequest] = []
    init(_ replies:[(Int,String)]) { self.replies = replies }
    func data(for request:URLRequest) throws -> (Data,URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let (status,body) = replies.removeFirst()
        return (Data(body.utf8),HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!)
    }
}
private actor WarpStore:AccountStateStoring,CredentialStoring {
    private var states:[AccountQuotaState] = [],keys:[UUID:String] = [:]
    func load() -> [AccountQuotaState] { states }
    func save(_ states:[AccountQuotaState]) { self.states = states }
    func save(_ key:String,for accountID:UUID) { keys[accountID] = key }
    func credential(for accountID:UUID) -> String? { keys[accountID] }
    func deleteCredential(for accountID:UUID) { keys[accountID] = nil }
}
