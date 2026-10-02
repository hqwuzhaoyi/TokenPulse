import Foundation
import XCTest
@testable import TokenPulse

final class GitKrakenProviderTests: XCTestCase {
    private let reply = #"{"data":{"used":25,"limit":100,"resetsOn":"2026-10-09T10:00:00+08:00","organization":{"used":400,"limit":1000},"sharedUsed":20}}"#

    func testPersonalAndSelectedOrganizationCreditsRemainSeparateAndDoNotGuessWeekLength() throws {
        let id = UUID(), time = Date(timeIntervalSince1970: 100)
        let snapshot = try GitKrakenProviderClient.snapshot(Data(reply.utf8), accountID: id, collectedAt: time, organizationID: "org-fixture")
        XCTAssertEqual(snapshot.accountID, id)
        XCTAssertEqual(snapshot.windows.map(\.id), ["gitKraken.personal", "gitKraken.organization"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercentage), [25, 40])
        XCTAssertEqual(snapshot.windows.last?.scope, "组织 org-fixture")
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.period == nil && $0.unit == "credits" && $0.wallet == nil })
        XCTAssertEqual(snapshot.windows.first?.resetsAt, ISO8601DateFormatter().date(from: "2026-10-09T02:00:00Z"))
        let defaultOrg = try GitKrakenProviderClient.snapshot(Data(reply.utf8), accountID: id, collectedAt: time)
        XCTAssertEqual(defaultOrg.windows.last?.scope, "默认组织（接口未提供名称）")
        let widget = WidgetAccountSnapshot(account: .init(id: id, name: "Fixture", provider: .gitKraken), windows: snapshot.windows, collectedAt: time, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 2)
        XCTAssertTrue(widget.displayMetrics.last?.displayTitle.contains("org-fixture") == true)
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }

    func testUnlimitedAndZeroNeverInventPercentagesAndMissingAmountsStayUnknown() throws {
        let unlimited = try GitKrakenProviderClient.snapshot(Data(#"{"data":{"used":0,"limit":-1,"organization":{"used":0,"limit":0}}}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(unlimited.windows.count, 1)
        XCTAssertTrue(unlimited.windows[0].isUnlimited)
        XCTAssertNil(unlimited.windows[0].usedPercentage)
        XCTAssertNil(WidgetQuotaMetric(id: "test", title: "test", window: unlimited.windows[0]).ringFraction)
        for body in [#"{"data":{"used":0,"limit":0}}"#, #"{"data":{"used":0}}"#, #"{"data":{"limit":100}}"#] {
            XCTAssertThrowsError(try GitKrakenProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .noQuotaWindows)
            }
        }
        for body in ["{}", #"{"data":null}"#, #"{"data":{"used":true,"limit":100}}"#, #"{"data":{"used":25,"limit":"100"}}"#] {
            XCTAssertThrowsError(try GitKrakenProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
    }

    func testManualSessionNormalizesBearerHasUnknownExpiryAndBindsOrganizationIdentity() throws {
        let auth = ProviderAuthenticationController()
        let a = try auth.credential(provider: .gitKraken, apiKey: " Bearer fixture-session\n", organizationID: "org-a")
        let envelope = try ProviderCredentialEnvelope.decode(a, expectedProvider: .gitKraken)
        XCTAssertEqual(envelope.kind, .session)
        XCTAssertEqual(envelope.accessToken, "fixture-session")
        XCTAssertNil(envelope.expiresAt)
        XCTAssertEqual(envelope.metadata["organizationID"], "org-a")
        let b = try auth.credential(provider: .gitKraken, apiKey: "fixture-session", organizationID: "org-b")
        XCTAssertNotEqual(envelope.sourceCredentialIdentity, try ProviderCredentialEnvelope.decode(b, expectedProvider: .gitKraken).sourceCredentialIdentity)
        XCTAssertTrue(auth.loginConfiguration(for: .gitKraken).credentialLabel?.contains("会话") == true)
        for token in ["Bearer", "token extra", "\n"] { XCTAssertThrowsError(try auth.credential(provider: .gitKraken, apiKey: token)) }
        XCTAssertThrowsError(try auth.credential(provider: .gitKraken, apiKey: "token", organizationID: "org\r\nInjected"))
    }

    func testKnownJWTExpirationStopsQueryBeforeNetworkAndHTTPRefusalRequestsReconfiguration() async throws {
        let payload = Data(#"{"exp":900}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let auth = ProviderAuthenticationController()
        let expired = try auth.credential(provider: .gitKraken, apiKey: "header.\(payload).signature")
        let transport = GitKrakenTransport(body: reply)
        do { _ = try await ProviderQuotaClient(provider: .gitKraken, transport: transport, now: { Date(timeIntervalSince1970: 1000) }).quota(for: UUID(), credential: expired); XCTFail("Expired session") }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let requests = await transport.requests()
        XCTAssertTrue(requests.isEmpty)
        let credential = try auth.credential(provider: .gitKraken, apiKey: "opaque-session")
        for (status, expected) in [(401, RefreshFailure.invalidCredential), (403, .invalidCredential), (429, .rateLimited), (500, .server)] {
            do { _ = try await ProviderQuotaClient(provider: .gitKraken, transport: GitKrakenTransport(body: reply, status: status)).quota(for: UUID(), credential: credential); XCTFail("Must fail") }
            catch { XCTAssertEqual(error as? RefreshFailure, expected) }
        }
    }

    func testRequestUsesSessionBearerAndConfiguredOrganizationAndNamesNativeClient() async throws {
        let transport = GitKrakenTransport(body: reply)
        let credential = try ProviderAuthenticationController().credential(provider: .gitKraken, apiKey: "Bearer fixture-session", organizationID: "org-fixture")
        let id = UUID()
        let snapshot = try await ProviderQuotaClient(provider: .gitKraken, transport: transport).quota(for: id, credential: credential)
        XCTAssertEqual(snapshot.accountID, id)
        let captured = await transport.requests()
        let request = try XCTUnwrap(captured.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.gitkraken.dev/v1/ai-tasks/usage")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-session")
        XCTAssertEqual(request.value(forHTTPHeaderField: "gk-org-id"), "org-fixture")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Client-Name"), "TokenPulse")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Client-Version"))
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    @MainActor
    func testSwitchingOrganizationPersistsNewBindingAndDiscardsOldPoolBeforeFailure() async throws {
        let suite = "gitkraken-fixture.\(UUID().uuidString)"
        let actualDefaults = UserDefaults(suiteName: suite)!
        defer { actualDefaults.removePersistentDomain(forName: suite) }
        let transport = GitKrakenTransport(body: reply), credentials = GitKrakenCredentials()
        let client = ProviderQuotaClient(provider: .gitKraken, transport: transport)
        let monitor = QuotaMonitor(accountStore: LocalAccountStateStore(suiteName: suite), credentialStore: credentials,
            quotaClient: client, configurationStore: LocalAccountConfigurationStore(suiteName: suite), providerClient: { _ in client })
        let auth = ProviderAuthenticationController()
        await monitor.addAccount(name: "Fixture", credential: try auth.credential(provider: .gitKraken, apiKey: "session", organizationID: "org-a"), provider: .gitKraken)
        let old = try XCTUnwrap(monitor.states.first)
        XCTAssertNotNil(old.snapshot)
        XCTAssertEqual(monitor.configurations.first?.organizationID, "org-a")
        await transport.fail()
        await monitor.replaceCredential(try auth.credential(provider: .gitKraken, apiKey: "session", organizationID: "org-b"), accountID: old.id)
        let changed = try XCTUnwrap(monitor.states.first)
        XCTAssertNil(changed.snapshot)
        XCTAssertEqual(changed.lastFailure, .invalidCredential)
        XCTAssertNotEqual(changed.credentialIdentity, old.credentialIdentity)
        XCTAssertEqual(monitor.configurations.first?.organizationID, "org-b")
        let configs = try await LocalAccountConfigurationStore(suiteName: suite).load()
        XCTAssertEqual(configs, monitor.configurations)
        let deleted = await monitor.deleteAccount(accountID: old.id)
        XCTAssertTrue(deleted)
        let saved = await credentials.credential(for: old.id)
        XCTAssertNil(saved)
    }
}

private actor GitKrakenTransport: ProviderTransport {
    let body: String
    private var status: Int
    private var captured: [URLRequest] = []
    init(body: String, status: Int = 200) { self.body = body; self.status = status }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        captured.append(request)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    func requests() -> [URLRequest] { captured }
    func fail() { status = 401 }
}

private actor GitKrakenCredentials: CredentialStoring {
    private var values: [UUID: String] = [:]
    func save(_ credential: String, for accountID: UUID) { values[accountID] = credential }
    func credential(for accountID: UUID) -> String? { values[accountID] }
    func deleteCredential(for accountID: UUID) { values[accountID] = nil }
}
