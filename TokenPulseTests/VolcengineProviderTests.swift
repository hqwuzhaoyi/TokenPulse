import Foundation
import XCTest
@testable import TokenPulse

final class VolcengineProviderTests: XCTestCase {
    private let coding = #"{"ResponseMetadata":{"RequestId":"synthetic"},"Result":{"Status":"Active","QuotaUsage":[{"Level":"weekly","Percent":41.5,"ResetTimestamp":1789085506000},{"Level":"5h","Percent":12,"ResetTimestamp":1788780000},{"Level":"fortnightly","Percent":3}]}}"#
    private let agent = #"{"Result":{"AFPFiveHour":{"Quota":1000,"Used":250,"ResetTime":1788780000},"AFPWeekly":{"Quota":20000,"Used":0,"ResetTime":1789085506},"AFPMonthly":{"Quota":0,"Used":0,"ResetTime":0},"AFPDaily":{"Quota":500,"Used":100}}}"#
    private let fixed = Date(timeIntervalSince1970: 1_788_773_400)

    func testSignerMatchesIndependentPythonSDKBasedVectors() throws {
        let keys = try VolcengineAccessKeys("AKLTTestAccessKeyId:dGVzdC1zZWNyZXQtYWNjZXNzLWtleQ==")
        let vectors = [
            ("https://open.volcengineapi.com/?Action=GetCodingPlanUsage&Version=2024-01-01", "3bc6ebb4fd6da065cae0c05dbfc35285cdced26090d7c0aea87b2f2330cd031d"),
            ("https://open.volcengineapi.com/?Version=2024-01-01&Action=GetAFPUsage", "8b82148b15d249ff000720303008f50d646187fb28622e2a9d4a4a6f3bc19d0c"),
            ("https://open.volcengineapi.com/?Action=%E4%B8%AD%E6%96%87~%20x&Version=2024-01-01", "97d7fdc4ac468aa0e4a67a230f1827caadd03d0250c19d47667eb083fa25d07b")
        ]
        for (url, expected) in vectors {
            let headers = VolcengineRequestSigner.headers(url: try XCTUnwrap(URL(string: url)), keys: keys, date: fixed)
            XCTAssertEqual(headers["Authorization"], "HMAC-SHA256 Credential=AKLTTestAccessKeyId/20260907/cn-beijing/ark/request, SignedHeaders=content-type;host;x-content-sha256;x-date, Signature=\(expected)")
            XCTAssertEqual(headers["X-Date"], "20260907T093000Z")
            XCTAssertEqual(headers["X-Content-Sha256"], "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
            XCTAssertEqual(headers["Host"], "open.volcengineapi.com")
        }
        let forward = URL(string: "https://open.volcengineapi.com/?Action=A&Version=B")!
        let reversed = URL(string: "https://open.volcengineapi.com/?Version=B&Action=A")!
        XCTAssertEqual(VolcengineRequestSigner.headers(url: forward, keys: keys, date: fixed), VolcengineRequestSigner.headers(url: reversed, keys: keys, date: fixed))
        XCTAssertNotEqual(VolcengineRequestSigner.headers(url: forward, keys: keys, date: fixed)["Authorization"], VolcengineRequestSigner.headers(url: forward, keys: keys, date: fixed, body: Data("{}".utf8))["Authorization"])
    }

    func testSecureCompositePairRejectsInjectionAndPreservesSecretColons() throws {
        let pair = try VolcengineAccessKeys("AKLTFixture:secret:with:colons")
        XCTAssertEqual(pair.accessKeyID, "AKLTFixture")
        XCTAssertEqual(pair.secretAccessKey, "secret:with:colons")
        for malformed in ["", "single", ":secret", "id:", "id with space:secret", "id/path:secret", "id:secret\r\nHost:evil", "id:se\u{0}cret", "id:two words"] {
            XCTAssertThrowsError(try VolcengineAccessKeys(malformed))
        }
        let encoded = try ProviderAuthenticationController().credential(provider: .volcengine, apiKey: pair.value)
        let restored = try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .volcengine)
        XCTAssertEqual(restored.accessToken, pair.value)
        XCTAssertEqual(restored.sourceCredentialIdentity, pair.fingerprint)
        XCTAssertNotEqual(pair.fingerprint, try VolcengineAccessKeys("AKLTFixture:other").fingerprint)
        XCTAssertThrowsError(try VolcengineRequestSigner.request(action: "Other&Host=evil", keys: pair, date: fixed))
    }

    func testBothPlansAreSignedDirectlyAndKeepSeparateWindowsAndUnits() async throws {
        let transport = VolcengineTransport(coding: (200, coding), agent: (200, agent))
        let envelope = try VolcengineAccessKeys("AKLTFixture:fixture-secret").envelope()
        let id = UUID()
        let result = try await ProviderQuotaClient(provider: .volcengine, transport: transport, now: { Date(timeIntervalSince1970: 1_788_773_400) }).quotaResult(for: id, credential: envelope.encoded())
        XCTAssertEqual(result.snapshot.accountID, id)
        XCTAssertEqual(result.snapshot.collectedAt, fixed)
        XCTAssertEqual(result.snapshot.sourceCredentialFingerprint, envelope.sourceCredentialIdentity)
        XCTAssertEqual(Set(result.snapshot.windows.compactMap(\.scope)), Set(["Coding Plan", "Agent Plan"]))
        XCTAssertEqual(Set(result.snapshot.windows.map(\.id)).count, result.snapshot.windows.count)
        let codingWindow = try XCTUnwrap(result.snapshot.windows.first { $0.id == "volcengine.coding.weekly" })
        XCTAssertEqual(codingWindow.usedPercentage, 41.5)
        XCTAssertEqual(codingWindow.resetsAt, Date(timeIntervalSince1970: 1_789_085_506))
        XCTAssertNil(codingWindow.remainingCount)
        let agentWindow = try XCTUnwrap(result.snapshot.windows.first { $0.id == "volcengine.agent.fiveHour" })
        XCTAssertEqual(agentWindow.usedPercentage, 25)
        XCTAssertEqual(agentWindow.remainingCount, 750)
        XCTAssertEqual(agentWindow.totalCount, 1000)
        XCTAssertEqual(agentWindow.unit, "AFP")
        XCTAssertTrue(result.snapshot.windows.allSatisfy { $0.wallet == nil })
        XCTAssertFalse(result.snapshot.windows.contains { $0.period == .monthly || $0.id.contains("fortnightly") })
        XCTAssertEqual(result.snapshot.windows(for: .volcengine, surface: .widget), result.snapshot.windows)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(Set(requests.compactMap { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "Action" }?.value }), Set(["GetCodingPlanUsage", "GetAFPUsage"]))
        for request in requests {
            XCTAssertEqual(request.url?.host, "open.volcengineapi.com")
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.path, "/")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.contains("/cn-beijing/ark/request") == true)
            XCTAssertFalse(request.value(forHTTPHeaderField: "Authorization")?.contains("fixture-secret") == true)
        }
    }

    func testOneUnsubscribedOrFailedPlanNeverErasesTheOther() async throws {
        for missing in [(404, "{}"), (403, "{}"), (200, #"{"Result":{"Status":"Inactive"}}"#), (200, #"{"Result":{"QuotaUsage":[{"Level":"5h","Percent":true}]}}"#)] {
            let result = try await VolcengineProviderClient(transport: VolcengineTransport(coding: missing, agent: (200, agent)), now: { Date() }).quota(accountID: UUID(), credential: VolcengineAccessKeys("AKLTFixture:secret").envelope())
            XCTAssertTrue(result.snapshot.windows.allSatisfy { $0.scope == "Agent Plan" })
            XCTAssertFalse(result.snapshot.windows.isEmpty)
        }
        let codingOnly = try await VolcengineProviderClient(transport: VolcengineTransport(coding: (200, coding), agent: (404, "{}")), now: { Date() }).quota(accountID: UUID(), credential: VolcengineAccessKeys("AKLTFixture:secret").envelope())
        XCTAssertTrue(codingOnly.snapshot.windows.allSatisfy { $0.scope == "Coding Plan" })
    }

    func testBothFailuresPreferCredentialRefusalAndNoSubscriptionIsDistinct() async throws {
        for (codingReply, agentReply, expected) in [((401, "{}"), (500, "{}"), RefreshFailure.invalidCredential), ((404, "{}"), (404, "{}"), .subscriptionRequired), ((429, "{}"), (404, "{}"), .rateLimited), ((200, "{}"), (404, "{}"), .unreadableResponse)] {
            do {
                _ = try await VolcengineProviderClient(transport: VolcengineTransport(coding: codingReply, agent: agentReply), now: { Date() }).quota(accountID: UUID(), credential: VolcengineAccessKeys("AKLTFixture:secret").envelope())
                XCTFail("Expected failure")
            } catch { XCTAssertEqual(error as? RefreshFailure, expected) }
        }
        XCTAssertThrowsError(try VolcengineProviderClient.windows(Data(#"{"ResponseMetadata":{"Error":{"Code":"SignatureDoesNotMatch"}}}"#.utf8), action: "GetCodingPlanUsage")) {
            XCTAssertEqual($0 as? RefreshFailure, .invalidCredential)
        }
    }

    func testMissingMetricsStayUnknownAndMalformedMetricsDoNotBecomeZero() throws {
        let unknown = try VolcengineProviderClient.windows(Data(#"{"Result":{"QuotaUsage":[{"Level":"weekly"}]}}"#.utf8), action: "GetCodingPlanUsage")
        XCTAssertNil(unknown[0].usedPercentage)
        XCTAssertNil(unknown[0].isExhausted)
        XCTAssertNil(unknown[0].resetsAt)
        let unknownUsed = try VolcengineProviderClient.windows(Data(#"{"Result":{"AFPFiveHour":{"Quota":100}}}"#.utf8), action: "GetAFPUsage")
        XCTAssertNil(unknownUsed[0].usedPercentage)
        XCTAssertNil(unknownUsed[0].remainingCount)
        for percent in ["true", "-1", "\"NaN\"", "\"oops\""] {
            XCTAssertThrowsError(try VolcengineProviderClient.windows(Data("{\"Result\":{\"QuotaUsage\":[{\"Level\":\"weekly\",\"Percent\":\(percent)}]}}".utf8), action: "GetCodingPlanUsage"))
        }
        XCTAssertThrowsError(try VolcengineProviderClient.windows(Data(#"{"Result":{"QuotaUsage":[{"Level":"weekly","Percent":1},{"Level":"week","Percent":2}]}}"#.utf8), action: "GetCodingPlanUsage"))
        XCTAssertThrowsError(try VolcengineProviderClient.windows(Data(#"{"Result":{"AFPFiveHour":{"Quota":true,"Used":0}}}"#.utf8), action: "GetAFPUsage"))
        XCTAssertTrue(try VolcengineProviderClient.windows(Data(#"{"Result":{"AFPFiveHour":{"Quota":0,"Used":0}}}"#.utf8), action: "GetAFPUsage").isEmpty)
    }

    @MainActor
    func testAKSKReplacementInvalidatesOldCacheAndPersistsLocalBinding() async throws {
        let suite = "com.tokenpulse.tests.volcengine.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let accounts = LocalAccountStateStore(suiteName: suite)
        let configurations = LocalAccountConfigurationStore(suiteName: suite)
        let credentials = VolcengineMemoryCredentials()
        let query = VolcengineLocalQuery(windows: try VolcengineProviderClient.windows(Data(coding.utf8), action: "GetCodingPlanUsage"))
        let monitor = QuotaMonitor(accountStore: accounts, credentialStore: credentials, quotaClient: query, configurationStore: configurations)
        let first = try VolcengineAccessKeys("AKLTFirst:secret-one").envelope().encoded()
        await monitor.addAccount(name: "Coding", credential: first, provider: .volcengine)
        let id = try XCTUnwrap(monitor.states.first?.id)
        XCTAssertNotNil(monitor.states[0].snapshot)
        let old = try XCTUnwrap(monitor.configuration(for: id)?.credentialIdentity)
        let second = try VolcengineAccessKeys("AKLTSecond:secret-two").envelope().encoded()
        await monitor.replaceCredential(second, accountID: id)
        XCTAssertNil(monitor.states[0].snapshot)
        XCTAssertEqual(monitor.states[0].lastFailure, .network)
        XCTAssertNotEqual(monitor.configuration(for: id)?.credentialIdentity, old)
        let restored = QuotaMonitor(accountStore: accounts, credentialStore: credentials, quotaClient: query, configurationStore: configurations)
        await restored.start(refresh: false)
        XCTAssertNil(restored.states[0].snapshot)
        XCTAssertEqual(restored.configuration(for: id)?.credentialIdentity, monitor.configuration(for: id)?.credentialIdentity)
        let deleted = await restored.deleteAccount(accountID: id)
        XCTAssertTrue(deleted)
        let key = await credentials.credential(for: id)
        XCTAssertNil(key)
    }

    func testIndependentPlanReminderScopesAndDemo() throws {
        let id = UUID()
        let windows = [QuotaWindow(id: "volcengine.coding.weekly", name: "每周额度", scope: "Coding Plan", period: .weekly, usedPercentage: 95, remainingCount: nil, totalCount: nil, resetsAt: Date(timeIntervalSince1970: 200)), QuotaWindow(id: "volcengine.agent.weekly", name: "每周额度", scope: "Agent Plan", period: .weekly, usedPercentage: 95, remainingCount: 5, totalCount: 100, resetsAt: Date(timeIntervalSince1970: 300), unit: "AFP")]
        let snapshot = QuotaSnapshot(accountID: id, windows: windows, collectedAt: Date(timeIntervalSince1970: 100))
        let plan = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "Ark", previousSnapshot: nil, newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: snapshot.collectedAt)
        let alerts = plan.operations.compactMap { if case .deliver(let value) = $0 { return value }; return nil }
        XCTAssertEqual(alerts.first?.kind, .quotaAlert)
        XCTAssertTrue(alerts.first?.body.contains("Coding Plan") == true)
        XCTAssertTrue(alerts.first?.body.contains("Agent Plan") == true)
        let schedules = plan.operations.filter { if case .schedule = $0 { return true }; return false }
        XCTAssertEqual(schedules.count, 2)
        XCTAssertTrue(DemoMode.accounts().contains { $0.provider == .volcengine })
        let demo = DemoMode.snapshot(accountID: id, provider: .volcengine)
        XCTAssertEqual(Set(demo.windows.compactMap(\.scope)), Set(["Coding Plan", "Agent Plan"]))
    }
}

private actor VolcengineTransport: ProviderTransport {
    let coding: (Int, String)
    let agent: (Int, String)
    var requests: [URLRequest] = []
    init(coding: (Int, String), agent: (Int, String)) { self.coding = coding; self.agent = agent }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let action = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "Action" }?.value
        let reply = action == "GetCodingPlanUsage" ? coding : agent
        return (Data(reply.1.utf8), HTTPURLResponse(url: request.url!, statusCode: reply.0, httpVersion: nil, headerFields: nil)!)
    }
}
private actor VolcengineMemoryCredentials: CredentialStoring {
    var keys: [UUID: String] = [:]
    func save(_ value: String, for id: UUID) { keys[id] = value }
    func credential(for id: UUID) -> String? { keys[id] }
    func deleteCredential(for id: UUID) { keys[id] = nil }
}
private actor VolcengineLocalQuery: QuotaQuerying {
    let windows: [QuotaWindow]
    var calls = 0
    init(windows: [QuotaWindow]) { self.windows = windows }
    func quota(for id: UUID, credential: String) async throws -> QuotaSnapshot {
        calls += 1
        if calls > 1 { throw RefreshFailure.network }
        return QuotaSnapshot(accountID: id, windows: windows, collectedAt: Date())
    }
}
