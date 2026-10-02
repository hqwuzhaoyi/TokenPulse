import Foundation
import XCTest
@testable import TokenPulse

final class HuggingFaceProviderTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_000)
    private let body = #"{"base":2400,"current":1800,"resetsAt":"2026-10-03T09:12:03Z","overquotaUsed":20}"#

    func testZeroGPUCountsRemainGPUSecondsWithReportedResetOnly() throws {
        let id = UUID(), snapshot = try HuggingFaceProviderClient.snapshot(Data(body.utf8), accountID: id, collectedAt: time)
        let window = try XCTUnwrap(snapshot.windows.first)
        XCTAssertEqual(snapshot.accountID, id)
        XCTAssertEqual(snapshot.collectedAt, time)
        XCTAssertEqual(window.id, "huggingFace.zeroGPU")
        XCTAssertEqual(window.unit, "GPU 秒")
        XCTAssertEqual(window.remainingCount, 1800)
        XCTAssertEqual(window.totalCount, 2400)
        XCTAssertEqual(window.usedPercentage, 25)
        XCTAssertNil(window.wallet)
        XCTAssertNil(window.period)
        XCTAssertEqual(window.resetsAt, ISO8601DateFormatter().date(from: "2026-10-03T09:12:03Z"))
        XCTAssertFalse(Provider.huggingFace.hasMonetaryWallet)
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        let widget = WidgetAccountSnapshot(account: .init(id: id, name: "Fixture", provider: .huggingFace), windows: snapshot.windows, collectedAt: time, lastFailure: nil)
        XCTAssertTrue(widget.displayMetrics.first?.valueText.contains("GPU 秒") == true)
    }

    func testNullResetHasNoInventedDayAndEpochSecondsHaveCorrectScale() throws {
        let unused = try HuggingFaceProviderClient.snapshot(Data(#"{"base":2400,"current":2400,"resetsAt":null}"#.utf8), accountID: UUID(), collectedAt: time)
        XCTAssertNil(unused.windows.first?.resetsAt)
        XCTAssertEqual(unused.windows.first?.usedPercentage, 0)
        let numeric = try HuggingFaceProviderClient.snapshot(Data(#"{"base":2400,"current":0,"resetsAt":1791018723}"#.utf8), accountID: UUID(), collectedAt: time)
        XCTAssertEqual(numeric.windows.first?.resetsAt, Date(timeIntervalSince1970: 1791018723))
        XCTAssertEqual(numeric.windows.first?.usedPercentage, 100)
        XCTAssertEqual(numeric.windows.first?.isExhausted, true)
        let missingReset = try HuggingFaceProviderClient.snapshot(Data(#"{"base":10,"current":12}"#.utf8), accountID: UUID(), collectedAt: time)
        XCTAssertNil(missingReset.windows.first?.resetsAt)
        XCTAssertEqual(missingReset.windows.first?.remainingCount, 12)
        XCTAssertEqual(missingReset.windows.first?.usedPercentage, 0)
    }

    func testZeroMissingOrNegativeQuotaNeverBecomesFalseWindowAndBooleanIsMalformed() {
        for body in [#"{"base":0,"current":0}"#, #"{"base":-1,"current":0}"#, #"{"base":2400}"#, #"{"current":100}"#, #"{"base":100,"current":-1}"#] {
            XCTAssertThrowsError(try HuggingFaceProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: time)) {
                XCTAssertEqual($0 as? RefreshFailure, .noQuotaWindows)
            }
        }
        for body in [#"{"base":true,"current":0}"#, #"{"base":100,"current":false}"#, #"{"base":"100","current":0}"#, #"{"base":100,"current":0,"resetsAt":true}"#, "[]"] {
            XCTAssertThrowsError(try HuggingFaceProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: time)) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
    }

    func testDirectSingleGETUsesUserTokenAndNeverRequestsBillingInferenceOrWhoami() async throws {
        let transport = HuggingFaceTransport(body: body)
        let auth = ProviderAuthenticationController(), id = UUID()
        let credential = try auth.credential(provider: .huggingFace, apiKey: " fixture-a \n")
        XCTAssertTrue(auth.loginConfiguration(for: .huggingFace).credentialLabel?.contains("读取账单权限") == true)
        XCTAssertNotNil(try ProviderCredentialEnvelope.decode(credential, expectedProvider: .huggingFace).sourceCredentialIdentity)
        let snapshot = try await ProviderQuotaClient(provider: .huggingFace, transport: transport).quota(for: id, credential: credential)
        XCTAssertEqual(snapshot.accountID, id)
        let captured = await transport.requests()
        XCTAssertEqual(captured.count, 1)
        let request = try XCTUnwrap(captured.first)
        XCTAssertEqual(request.url?.absoluteString, "https://huggingface.co/api/spaces/zero-gpu/quota")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-a")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(request.httpBody)
        for (status, expected) in [(401, RefreshFailure.invalidCredential), (403, .invalidCredential), (429, .rateLimited), (500, .server)] {
            do { _ = try await ProviderQuotaClient(provider: .huggingFace, transport: HuggingFaceTransport(body: body, status: status)).quota(for: UUID(), credential: credential); XCTFail("Must fail") }
            catch { XCTAssertEqual(error as? RefreshFailure, expected) }
        }
    }

    func testGPUUsageNotifiesQuotaAndReportedResetButNeverWalletOrInventedReset() throws {
        let id = UUID(), snapshot = try HuggingFaceProviderClient.snapshot(Data(#"{"base":2400,"current":0}"#.utf8), accountID: id, collectedAt: time)
        let result = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "HF", previousSnapshot: nil,
            newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: time)
        let notifications = result.operations.compactMap { if case .deliver(let notice) = $0 { return notice }; return nil }
        XCTAssertTrue(notifications.contains { $0.kind == .quotaAlert })
        XCTAssertFalse(notifications.contains { $0.kind == .walletAlert || $0.kind == .confirmedReset })
        XCTAssertFalse(result.operations.contains { if case .schedule = $0 { return true }; return false })
        let reported = try HuggingFaceProviderClient.snapshot(Data(#"{"base":2400,"current":0,"resetsAt":2000}"#.utf8), accountID: id, collectedAt: time)
        let planned = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "HF", previousSnapshot: nil,
            newSnapshot: reported, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: time)
        XCTAssertTrue(planned.operations.contains { if case .schedule = $0 { return true }; return false })
    }

    @MainActor
    func testLocalTwoAccountsFailureRetentionPersistenceAndDelete() async throws {
        let suite = "huggingface-fixture.\(UUID().uuidString)"
        let actual = UserDefaults(suiteName: suite)!
        defer { actual.removePersistentDomain(forName: suite) }
        let credentials = HuggingFaceCredentials(), transport = HuggingFaceTransport(body: body)
        let client = ProviderQuotaClient(provider: .huggingFace, transport: transport)
        let monitor = QuotaMonitor(accountStore: LocalAccountStateStore(suiteName: suite), credentialStore: credentials,
            quotaClient: client, configurationStore: LocalAccountConfigurationStore(suiteName: suite), providerClient: { _ in client })
        let auth = ProviderAuthenticationController()
        for name in ["a", "b"] {
            await monitor.addAccount(name: name, credential: try auth.credential(provider: .huggingFace, apiKey: "fixture-\(name)"), provider: .huggingFace)
        }
        let a = try XCTUnwrap(monitor.states.first { $0.account.name == "a" }), b = try XCTUnwrap(monitor.states.first { $0.account.name == "b" })
        XCTAssertNotEqual(a.credentialIdentity, b.credentialIdentity)
        XCTAssertNotEqual(a.snapshot?.windows.first?.totalCount, b.snapshot?.windows.first?.totalCount)
        await transport.failA()
        await monitor.refreshAll()
        let failed = try XCTUnwrap(monitor.states.first { $0.id == a.id })
        XCTAssertEqual(failed.snapshot, a.snapshot)
        XCTAssertEqual(failed.lastFailure, .invalidCredential)
        let persisted = try await LocalAccountStateStore(suiteName: suite).load()
        XCTAssertEqual(persisted, monitor.states)
        let deleted = await monitor.deleteAccount(accountID: a.id)
        XCTAssertTrue(deleted)
        let secret = await credentials.credential(for: a.id)
        XCTAssertNil(secret)
        XCTAssertEqual(monitor.states.map(\.id), [b.id])
    }
}

private actor HuggingFaceTransport: ProviderTransport {
    let body: String
    let status: Int
    private var failKeyA = false
    private var captured: [URLRequest] = []
    init(body: String, status: Int = 200) { self.body = body; self.status = status }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        captured.append(request)
        let key = request.value(forHTTPHeaderField: "Authorization")
        let response = key == "Bearer fixture-b" ? #"{"base":1200,"current":600}"# : body
        return (Data(response.utf8), HTTPURLResponse(url: request.url!, statusCode: failKeyA && key == "Bearer fixture-a" ? 401 : status, httpVersion: nil, headerFields: nil)!)
    }
    func requests() -> [URLRequest] { captured }
    func failA() { failKeyA = true }
}

private actor HuggingFaceCredentials: CredentialStoring {
    private var values: [UUID: String] = [:]
    func save(_ credential: String, for accountID: UUID) { values[accountID] = credential }
    func credential(for accountID: UUID) -> String? { values[accountID] }
    func deleteCredential(for accountID: UUID) { values[accountID] = nil }
}
