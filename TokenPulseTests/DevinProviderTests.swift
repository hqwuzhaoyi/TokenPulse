import Foundation
import XCTest
@testable import TokenPulse

final class DevinProviderTests: XCTestCase {
    private let token = "auth1_fixture_session_abcdefghijklmnopqrstuvwxyz"
    private let orgA = "org-11111111111111111111111111111111"
    private let orgB = "org-22222222222222222222222222222222"
    private let quota = #"{"daily_percentage":2,"weekly_percentage":1,"daily_reset_at":"2026-09-14T00:00:00-08:00","weekly_reset_at":"2026-09-20T00:00:00-08:00","hide_daily_quota":false,"has_quota_allocation":true,"is_quota_plan":true,"overage_balance":10}"#

    private func storage() -> [String: String] {
        ["auth1_session": "{\"token\":\"\(token)\",\"userId\":\"user-fixture\"}",
         DevinWebSession.organizationPrefix + "null": orgA,
         DevinWebSession.organizationPrefix + "another": "\"\(orgB)\""]
    }

    func testOnlyFixedOriginAndObservedKeysProduceExplicitOrganizationChoices() throws {
        let id = UUID()
        let choices = try DevinWebSession.credentials(storage: storage(), accountID: id)
        XCTAssertEqual(choices.map(\.id), [orgA, orgB])
        let first = try ProviderCredentialEnvelope.decode(choices[0].credential, expectedProvider: .devin)
        let second = try ProviderCredentialEnvelope.decode(choices[1].credential, expectedProvider: .devin)
        XCTAssertEqual(first.accountID, "user-fixture")
        XCTAssertEqual(first.accessToken, token)
        XCTAssertEqual(first.metadata["organizationID"], orgA)
        XCTAssertEqual(first.metadata["localAccountID"], id.uuidString)
        XCTAssertNotEqual(first.metadata["sourceCredentialFingerprint"], second.metadata["sourceCredentialFingerprint"])
        XCTAssertThrowsError(try DevinWebSession.credentials(storage: storage(), accountID: id, origin: "https://windsurf.com"))
        XCTAssertThrowsError(try DevinWebSession.credentials(storage: ["unknown": storage()["auth1_session"]!, "devin_primary_org_id": orgA], accountID: id))
        XCTAssertThrowsError(try DevinWebSession.credentials(storage: ["auth1_session": storage()["auth1_session"]!, DevinWebSession.organizationPrefix + "null": "https://evil.example/org"], accountID: id))
        XCTAssertEqual(Provider.devin.webLoginProfile?.storageKeys, ["auth1_session"])
        XCTAssertEqual(Provider.devin.webLoginProfile?.storagePrefixes, [DevinWebSession.organizationPrefix])
        XCTAssertFalse(Provider.devin.webLoginProfile!.permits(URL(string: "https://app.devin.ai.evil.example/")))
    }

    func testRemotePercentagesAreUsedNotRemainingAndNoPlanIsBorrowedFromDesktop() throws {
        let result = try DevinProviderClient.snapshot(Data(quota.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(result.windows.map(\.id), ["devin.daily", "devin.weekly", "devin.overage"])
        XCTAssertEqual(result.windows.map(\.usedPercentage), [2, 1, nil])
        XCTAssertEqual(result.windows[0].resetsAt, ISO8601DateFormatter().date(from: "2026-09-14T08:00:00Z"))
        XCTAssertEqual(result.windows[2].wallet?.total, 10)
        XCTAssertNil(result.providerPlanName)
        let fraction = try DevinProviderClient.snapshot(Data(#"{"daily_percentage":0.4,"weekly_percentage":0.6,"hide_daily_quota":true,"plan_name":"Pro","overage_balance_cents":1000}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(fraction.windows.map(\.id), ["devin.weekly", "devin.overage"])
        XCTAssertEqual(fraction.windows[0].usedPercentage, 0.6)
        XCTAssertEqual(fraction.windows[1].wallet?.total, 10)
        XCTAssertEqual(fraction.providerPlanName, "Pro")
    }

    func testExplicitNoAllocationClearsQuotaWhileMissingAndMalformedValuesNeverBecomeZero() throws {
        let noQuota = try DevinProviderClient.snapshot(Data(#"{"has_quota_allocation":false,"daily_percentage":0,"weekly_percentage":0}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertTrue(noQuota.windows.isEmpty)
        for body in ["{}", #"{"daily_percentage":true}"#, #"{"daily_percentage":"nan"}"#,
                     #"{"daily_percentage":101}"#, #"{"daily_percentage":2,"daily_reset_at":"bad"}"#] {
            XCTAssertThrowsError(try DevinProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
        let partial = try DevinProviderClient.snapshot(Data(#"{"weekly_percentage":12}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(partial.windows.map(\.id), ["devin.weekly"])
        XCTAssertNil(partial.windows[0].resetsAt)
    }

    func testRequestIsOrganizationScopedAndOnly404TriesTheSameOrganizationsAlternativePath() async throws {
        let id = UUID()
        let credential = try DevinWebSession.credentials(storage: storage(), accountID: id)[0].credential
        let transport = DevinTransport([.response(404, "{}"), .response(200, quota)])
        let result = try await ProviderQuotaClient(provider: .devin, transport: transport).quota(for: id, credential: credential)
        XCTAssertEqual(result.accountID, id)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/\(orgA)/billing/quota/usage", "/api/organizations/\(orgA)/billing/quota/usage"])
        for request in requests {
            XCTAssertEqual(request.url?.host, "app.devin.ai")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-cog-org-id"), orgA)
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertFalse(request.httpShouldHandleCookies)
        }
    }

    func testExpiredSessionAndWrongAccountOrTamperedScopeNeverMakeFallbackQueries() async throws {
        let id = UUID()
        let original = try ProviderCredentialEnvelope.decode(DevinWebSession.credentials(storage: storage(), accountID: id)[0].credential, expectedProvider: .devin)
        let transport = DevinTransport([])
        for change in ["owner", "organization", "expiry", "origin", "remoteUser"] {
            var altered = original
            switch change {
            case "owner": altered.metadata["localAccountID"] = UUID().uuidString
            case "organization": altered.metadata["organizationID"] = orgB
            case "origin": altered.metadata["origin"] = "https://windsurf.com"
            case "remoteUser": altered.accountID = "different-user"
            default: altered.expiresAt = Date(timeIntervalSince1970: 1)
            }
            do { _ = try await ProviderQuotaClient(provider: .devin, transport: transport).quota(for: id, credential: altered.encoded()); XCTFail("Invalid session") }
            catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        }
        let before = await transport.requests
        XCTAssertTrue(before.isEmpty)
        for (status, expected) in [(401, RefreshFailure.invalidCredential), (403, .invalidCredential), (302, .invalidCredential), (429, .rateLimited), (500, .server)] {
            let failure = DevinTransport([.response(status, "{}")])
            do { _ = try await ProviderQuotaClient(provider: .devin, transport: failure).quota(for: id, credential: original.encoded()); XCTFail("Expected failure") }
            catch { XCTAssertEqual(error as? RefreshFailure, expected) }
            let requests = await failure.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    @MainActor
    func testLocalLifecycleRetainsFailedCollectionAndDeleteCleansOnlyThisAccount() async throws {
        let store = DevinMemoryStore()
        let id = UUID()
        let key = try DevinWebSession.credentials(storage: storage(), accountID: id)[0].credential
        let transport = DevinTransport([.response(200, quota), .response(500, "{}")])
        let monitor = QuotaMonitor(accountStore: store, credentialStore: store,
            quotaClient: ProviderQuotaClient(provider: .devin, transport: transport))
        await monitor.start(refresh: false)
        await monitor.addAccount(name: "Devin", credential: key, provider: .devin, accountID: id)
        let snapshot = monitor.states.first?.snapshot
        await monitor.refresh(accountID: id)
        XCTAssertEqual(monitor.states.first?.snapshot, snapshot)
        XCTAssertEqual(monitor.states.first?.lastFailure, .server)
        let deleted = await monitor.deleteAccount(accountID: id)
        XCTAssertTrue(deleted)
        let saved = await store.credential(for: id)
        XCTAssertNil(saved)
    }

    func testDemoIconAndAllDisplayWindowsAreRegistered() throws {
        let account = try XCTUnwrap(DemoMode.accounts().first { $0.provider == .devin })
        let data = DemoMode.snapshot(accountID: account.id, provider: .devin)
        let widget = WidgetAccountSnapshot(account: account, windows: data.windows, collectedAt: data.collectedAt, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 3)
        XCTAssertEqual(Provider.devin.balancePresentation, .mixed)
        XCTAssertEqual(Provider.devin.iconAssetName, "ProviderDevin")
        XCTAssertEqual(ProviderAuthenticationController().loginConfiguration(for: .devin).method, .webSession)
    }
}

private actor DevinTransport: ProviderTransport {
    enum Reply: Sendable { case response(Int, String) }
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.timedOut) }
        switch replies.removeFirst() {
        case .response(let status, let body): return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}
private actor DevinMemoryStore: AccountStateStoring, CredentialStoring {
    private var states: [AccountQuotaState] = []
    private var credentials: [UUID: String] = [:]
    func load() -> [AccountQuotaState] { states }
    func save(_ states: [AccountQuotaState]) { self.states = states }
    func save(_ credential: String, for accountID: UUID) { credentials[accountID] = credential }
    func credential(for accountID: UUID) -> String? { credentials[accountID] }
    func deleteCredential(for accountID: UUID) { credentials[accountID] = nil }
}
