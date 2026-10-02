import Foundation
import XCTest
@testable import TokenPulse

final class AlibabaCodingPlanProviderTests: XCTestCase {
    private let body = #"{"status_code":0,"data":{"codingPlanInstanceInfos":[{"planName":"Expired","status":"EXPIRED","codingPlanQuotaInfo":{"per5HourUsedQuota":99,"per5HourTotalQuota":100}},{"planName":"Pro","status":"VALID","codingPlanQuotaInfo":{"per5HourUsedQuota":0,"per5HourTotalQuota":1000,"per5HourQuotaNextRefreshTime":1800000000000,"perWeekUsedQuota":"950","perWeekTotalQuota":"1000","perWeekQuotaNextRefreshTime":1800100000000,"perBillMonthUsedQuota":1200,"perBillMonthTotalQuota":20000,"perBillMonthQuotaNextRefreshTime":1801000000000}}]}}"#

    func testRegionRequestContractUsesOnlySelectedConsoleAndCommodity() async throws {
        let now = Date(timeIntervalSince1970: 1000)
        for region in ProviderRegion.allCases {
            let transport = AlibabaTestTransport([(200, body)])
            let encoded = try ProviderAuthenticationController().credential(provider: .alibabaCodingPlan, apiKey: "fixture", region: region)
            let snapshot = try await ProviderQuotaClient(provider: .alibabaCodingPlan, transport: transport, now: { now }).quota(for: UUID(), credential: encoded)
            XCTAssertEqual(snapshot.providerPlanName, "Pro")
            XCTAssertEqual(snapshot.windows.map(\.period), [.fiveHour, .weekly, .monthly])
            XCTAssertEqual(snapshot.windows.map(\.usedPercentage), [0, 95, 6])
            XCTAssertEqual(snapshot.collectedAt, now)
            XCTAssertNotNil(snapshot.sourceCredentialFingerprint)
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
            let request = requests[0]
            XCTAssertEqual(request.url, region.alibabaEndpoint)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "fixture")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-DashScope-API-Key"), "fixture")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), region.alibabaOrigin)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), region.alibabaPage)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            let body = try JSONDecoder().decode([String: [String: String]].self, from: XCTUnwrap(request.httpBody))
            XCTAssertEqual(body, ["queryCodingPlanInstanceInfoRequest":["commodityCode":region.alibabaCommodity]])
        }
        XCTAssertThrowsError(try ProviderAuthenticationController().credential(provider: .alibabaCodingPlan, apiKey: "fixture"))
    }

    func testConsoleLoginRequiredIsExplicitAndNeverRetriedOrConvertedToEmptyPlan() async throws {
        for region in ProviderRegion.allCases {
            for status in [200, 401, 403] {
                let transport = AlibabaTestTransport([(status, #"{"code":"ConsoleNeedLogin","message":"请登录","successResponse":false}"#), (200, body)])
                let encoded = try ProviderAuthenticationController().credential(provider: .alibabaCodingPlan, apiKey: "fixture", region: region)
                do { _ = try await ProviderQuotaClient(provider: .alibabaCodingPlan, transport: transport).quota(for: UUID(), credential: encoded); XCTFail() }
                catch { XCTAssertEqual(error as? RefreshFailure, .consoleSessionRequired) }
                let requests = await transport.requests
                XCTAssertEqual(requests.count, 1)
                XCTAssertEqual(requests[0].url?.host, region.alibabaEndpoint.host)
            }
        }
        XCTAssertTrue(RefreshFailure.consoleSessionRequired.displayName.contains("控制台"))
    }

    func testNamedStringEnvelopeIsSupportedWithoutRecursiveQuotaSalvage() throws {
        let nested = try JSONSerialization.jsonObject(with: Data(body.utf8)) as! [String: Any]
        let inner = try JSONSerialization.data(withJSONObject: nested["data"]!)
        let data = try JSONSerialization.data(withJSONObject: ["code":200, "data":String(decoding:inner, as:UTF8.self)])
        let snapshot = try AlibabaCodingPlanProviderClient.snapshot(data, accountID: UUID(), collectedAt: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(snapshot.windows.count, 3)
        let unrelated = #"{"successResponse":true,"unrelated":{"codingPlanInstanceInfos":[{"status":"VALID","codingPlanQuotaInfo":{"per5HourUsedQuota":5,"per5HourTotalQuota":100}}]}}"#
        XCTAssertThrowsError(try AlibabaCodingPlanProviderClient.snapshot(Data(unrelated.utf8), accountID: UUID(), collectedAt: Date())) {
            XCTAssertEqual($0 as? RefreshFailure, .noQuotaWindows)
        }
    }

    func testExpiredPlanCanNeverStandInForActivePlanWithMissingQuota() {
        for data in [
            #"{"data":{"codingPlanInstanceInfos":[{"status":"EXPIRED","codingPlanQuotaInfo":{"per5HourUsedQuota":50,"per5HourTotalQuota":100}},{"status":"ACTIVE"}]}}"#,
            #"{"data":{"codingPlanInstanceInfos":[{"status":"VALID","endTime":500000,"codingPlanQuotaInfo":{"per5HourUsedQuota":50,"per5HourTotalQuota":100}}]}}"#
        ] {
            XCTAssertThrowsError(try AlibabaCodingPlanProviderClient.snapshot(Data(data.utf8), accountID: UUID(), collectedAt: Date(timeIntervalSince1970: 1_000_000)))
        }
        for data in [#"{"data":{"codingPlanInstanceInfos":[]}}"#,
                     #"{"data":{"codingPlanInstanceInfos":[{"status":"EXPIRED"}]}}"#] {
            XCTAssertThrowsError(try AlibabaCodingPlanProviderClient.snapshot(Data(data.utf8), accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .subscriptionRequired)
            }
        }
    }

    func testMissingOrInvalidFiguresAndPastResetAreNotGuessed() throws {
        let data = Data(#"{"data":{"codingPlanInstanceInfos":[{"status":"VALID","codingPlanQuotaInfo":{"per5HourUsedQuota":5,"per5HourTotalQuota":10,"per5HourQuotaNextRefreshTime":500,"perWeekTotalQuota":100,"perWeekQuotaNextRefreshTime":1801000000000,"perBillMonthUsedQuota":true,"perBillMonthTotalQuota":100}}]}}"#.utf8)
        let snapshot = try AlibabaCodingPlanProviderClient.snapshot(data, accountID: UUID(), collectedAt: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].usedPercentage, 50)
        XCTAssertNil(snapshot.windows[0].resetsAt)
        for used in ["-1", "\"NaN\"", "true"] {
            let body = "{\"data\":{\"codingPlanInstanceInfos\":[{\"status\":\"VALID\",\"codingPlanQuotaInfo\":{\"per5HourUsedQuota\":\(used),\"per5HourTotalQuota\":100}}]}}"
            XCTAssertThrowsError(try AlibabaCodingPlanProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date()))
        }
    }

    func testStrictFlagsCannotFabricateSuccessOrActivePlan() {
        for data in [
            #"{"successResponse":1,"data":{"codingPlanInstanceInfos":[]}}"#,
            #"{"code":true,"data":{"codingPlanInstanceInfos":[]}}"#,
            #"{"data":{"codingPlanInstanceInfos":[{"active":1,"codingPlanQuotaInfo":{"per5HourUsedQuota":1,"per5HourTotalQuota":100}}]}}"#
        ] {
            XCTAssertThrowsError(try AlibabaCodingPlanProviderClient.snapshot(Data(data.utf8), accountID: UUID(), collectedAt: Date()))
        }
    }

    func testHTTPBusinessFailuresCancellationAndRegionsStayIsolated() async throws {
        let credential = try ProviderAuthenticationController().credential(provider: .alibabaCodingPlan, apiKey: "fixture", region: .china)
        for (status, body, expected) in [(401, "{}", RefreshFailure.invalidCredential), (403, "{}", .invalidCredential), (429, "{}", .rateLimited), (500, "{}", .server),
                                       (200, #"{"statusCode":401}"#, .invalidCredential), (200, #"{"statusCode":429}"#, .rateLimited),
                                       (200, #"{"successResponse":false}"#, .server)] {
            let transport = AlibabaTestTransport([(status, body)])
            do { _ = try await ProviderQuotaClient(provider: .alibabaCodingPlan, transport: transport).quota(for: UUID(), credential: credential); XCTFail() }
            catch { XCTAssertEqual(error as? RefreshFailure, expected) }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
        let transport = AlibabaTestTransport([], cancelled: true)
        do { _ = try await ProviderQuotaClient(provider: .alibabaCodingPlan, transport: transport).quota(for: UUID(), credential: credential); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        let missingRegion = try ProviderCredentialEnvelope(provider: .alibabaCodingPlan, kind: .apiKey, accessToken: "fixture").encoded()
        let unused = AlibabaTestTransport([])
        do { _ = try await ProviderQuotaClient(provider: .alibabaCodingPlan, transport: unused).quota(for: UUID(), credential: missingRegion); XCTFail() }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let requests = await unused.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testAllWindowsFeedWidgetAndSharedNotificationPolicies() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let account = SubscriptionAccount(name: "fixture", provider: .alibabaCodingPlan)
        let snapshot = try AlibabaCodingPlanProviderClient.snapshot(Data(body.utf8), accountID: account.id, collectedAt: now)
        let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows, collectedAt: now, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 3)
        XCTAssertTrue(widget.displayMetrics.allSatisfy { $0.window?.wallet == nil })
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        let result = NotificationPlanner().planSuccessfulRefresh(accountID: account.id, accountName: account.name, previousSnapshot: nil,
            newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: now)
        let delivered = result.operations.compactMap { if case .deliver(let value) = $0 { return value }; return nil }
        XCTAssertEqual(delivered.map(\.kind), [.quotaAlert])
        XCTAssertFalse(delivered[0].body.contains("5 小时"))
        XCTAssertFalse(result.operations.contains { if case .deliver(let value) = $0 { return value.kind == .walletAlert }; return false })
    }

    @MainActor
    func testMultipleAccountsRestoreFailureKeepsOldDataAndRegionSwitchCannotKeepOldQuota() async throws {
        let suite = "alibaba.tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let credentials = AlibabaTestCredentials()
        let transport = AlibabaTestTransport([(200, body), (200, body), (200, #"{"code":"ConsoleNeedLogin","successResponse":false}"#), (401, "{}")])
        let client = ProviderQuotaClient(provider: .alibabaCodingPlan, transport: transport)
        let store = LocalAccountStateStore(suiteName: suite)
        let configurations = LocalAccountConfigurationStore(suiteName: suite)
        let monitor = QuotaMonitor(accountStore: store, credentialStore: credentials, quotaClient: client, configurationStore: configurations)
        await monitor.start(refresh: false)
        let auth = ProviderAuthenticationController()
        let cn = try auth.credential(provider: .alibabaCodingPlan, apiKey: "cn-fixture", region: .china)
        let intl = try auth.credential(provider: .alibabaCodingPlan, apiKey: "intl-fixture", region: .international)
        await monitor.addAccount(name: "A", credential: cn, provider: .alibabaCodingPlan)
        await monitor.addAccount(name: "B", credential: cn, provider: .alibabaCodingPlan)
        let first = try XCTUnwrap(monitor.states.first)
        let other = try XCTUnwrap(monitor.states.last)
        await monitor.refresh(accountID: first.id)
        XCTAssertEqual(monitor.states[0].snapshot, first.snapshot)
        XCTAssertEqual(monitor.states[0].lastFailure, .consoleSessionRequired)
        await monitor.replaceCredential(intl, accountID: first.id)
        XCTAssertNil(monitor.states[0].snapshot)
        XCTAssertEqual(monitor.configuration(for: first.id)?.providerRegion, .international)
        XCTAssertEqual(monitor.states[1], other)
        let restored = QuotaMonitor(accountStore: store, credentialStore: credentials, quotaClient: client, configurationStore: configurations)
        await restored.start(refresh: false)
        XCTAssertEqual(restored.states, monitor.states)
        let didDelete = await restored.deleteAccount(accountID: first.id)
        XCTAssertTrue(didDelete)
        let kept = await credentials.credential(for: other.id)
        let deleted = await credentials.credential(for: first.id)
        XCTAssertEqual(kept, cn)
        XCTAssertNil(deleted)
    }
}

private actor AlibabaTestTransport: ProviderTransport {
    private var replies: [(Int, String)]
    private let cancelled: Bool
    private(set) var requests: [URLRequest] = []
    init(_ replies: [(Int, String)], cancelled: Bool = false) { self.replies = replies; self.cancelled = cancelled }
    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        if cancelled { throw CancellationError() }
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let (status, body) = replies.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
private actor AlibabaTestCredentials: CredentialStoring {
    private var items: [UUID: String] = [:]
    func save(_ credential: String, for accountID: UUID) { items[accountID] = credential }
    func credential(for accountID: UUID) -> String? { items[accountID] }
    func deleteCredential(for accountID: UUID) { items[accountID] = nil }
}
