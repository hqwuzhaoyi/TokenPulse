import Foundation
import XCTest
@testable import TokenPulse

final class XAIAPIProviderTests: XCTestCase {
    private func reading(_ cents: String, date: Date = Date(timeIntervalSince1970: 100)) throws -> QuotaSnapshot {
        let body = try JSONSerialization.data(withJSONObject: ["total": ["val": cents]])
        return try XAIAPIProviderClient.snapshot(body, accountID: UUID(), teamID: "team-1", collectedAt: date)
    }

    func testInvertedCentsUseExactDecimalAndNeverInventAllowanceOrWalletBreakdown() throws {
        for (cents, expected) in [("-1234", "12.34"), ("-1", "0.01"), ("1", "-0.01"), ("0", "0"), ("-0.000000000000000001", "0.00000000000000000001")] {
            let snapshot = try reading(cents)
            let window = try XCTUnwrap(snapshot.windows.first)
            XCTAssertEqual(window.wallet?.total, Decimal(string: expected))
            XCTAssertEqual(window.wallet?.currency, "USD")
            XCTAssertNil(window.wallet?.granted)
            XCTAssertNil(window.wallet?.toppedUp)
            XCTAssertNil(window.usedPercentage)
            XCTAssertNil(window.remainingCount)
            XCTAssertNil(window.totalCount)
            XCTAssertNil(window.resetsAt)
            XCTAssertNil(snapshot.walletAvailable)
            XCTAssertEqual(snapshot.collectedAt, Date(timeIntervalSince1970: 100))
            XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        }
    }

    func testMalformedCentsAndMissingTotalsFailInsteadOfLookingLikeZero() throws {
        for amount in ["", "NaN", "Infinity", "1e3", "+1", "-", "1,000", "1oops", " 1", "1\n", "123456789012345678901234567890123456789", "0." + String(repeating: "0", count: 150) + "1"] {
            XCTAssertThrowsError(try reading(amount), amount)
        }
        for body in ["{}", #"{"total":{}}"#, #"{"total":{"val":null}}"#, #"{"total":{"val":1234}}"#, #"{"total":{"val":true}}"#, #"{"changes":[{"amount":{"val":"-1000"}}]}"#] {
            XCTAssertThrowsError(try XAIAPIProviderClient.snapshot(Data(body.utf8), accountID: UUID(), teamID: "team-1", collectedAt: Date()))
        }
    }

    func testTeamAndManagementCredentialAreStrictlyBoundAndSafeForPath() throws {
        let parsed = try XAIManagementCredential("team-1:management:with:colons")
        XCTAssertEqual(parsed.teamID, "team-1")
        XCTAssertEqual(parsed.managementKey, "management:with:colons")
        XCTAssertEqual(parsed.endpoint.absoluteString, "https://management-api.x.ai/v1/billing/teams/team-1/prepaid/balance")
        for team in ["", ".", "..", "../other", "a/b", "a%2Fb", "evil?x", "evil#x", "team 1", "team\n1", "team:1", "https://evil.example", String(repeating: "a", count: 129)] {
            XCTAssertThrowsError(try XAIManagementCredential(teamID: team, managementKey: "fixture-key"), team)
        }
        for key in ["", "key with spaces", "key\r\nHost:evil", "key\u{0}suffix"] {
            XCTAssertThrowsError(try XAIManagementCredential(teamID: "team-1", managementKey: key))
        }
        let original = parsed.envelope()
        let restored = try ProviderCredentialEnvelope.decode(original.encoded(), expectedProvider: .xaiAPI)
        XCTAssertEqual(restored.metadata["teamID"], "team-1")
        XCTAssertEqual(restored.metadata["credentialRole"], "management")
        XCTAssertEqual(restored.sourceCredentialIdentity, parsed.fingerprint)
        var moved = original
        moved.metadata["teamID"] = "team-2"
        XCTAssertNotEqual(moved.sourceCredentialIdentity, original.sourceCredentialIdentity)
        moved.accessToken = "another-management-key"
        XCTAssertNotEqual(moved.sourceCredentialIdentity, try XAIManagementCredential("team-2:management:with:colons").fingerprint)
        XCTAssertThrowsError(try ProviderCredentialEnvelope.decode(original.encoded(), expectedProvider: .superGrok))
        XCTAssertTrue(Provider.xaiAPI.hasMonetaryWallet)
        XCTAssertNotEqual(Provider.xaiAPI, .superGrok)
    }

    func testFixedManagementRequestNeverSendsTeamAsHostOrCallsInference() async throws {
        let transport = XAITransport(status: 200, body: #"{"total":{"val":"-1234"}}"#)
        let encoded = try ProviderAuthenticationController().credential(provider: .xaiAPI, apiKey: "team-1:fixture-management")
        let result = try await ProviderQuotaClient(provider: .xaiAPI, transport: transport, now: { Date(timeIntervalSince1970: 100) }).quotaResult(for: UUID(), credential: encoded)
        XCTAssertEqual(result.snapshot.windows[0].wallet?.total, Decimal(string: "12.34"))
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://management-api.x.ai/v1/billing/teams/team-1/prepaid/balance")
        XCTAssertEqual(requests[0].httpMethod, "GET")
        XCTAssertNil(requests[0].httpBody)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer fixture-management")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(requests[0].cachePolicy, .reloadIgnoringLocalCacheData)
        let model = WidgetAccountSnapshot(account: SubscriptionAccount(name: "team", provider: .xaiAPI), windows: result.snapshot.windows, collectedAt: result.snapshot.collectedAt, lastFailure: nil)
        XCTAssertEqual(model.displayMetrics.first?.window?.wallet?.total, result.snapshot.windows[0].wallet?.total)
        XCTAssertEqual(model.displayMetrics.first?.window?.wallet?.currency, "USD")
        XCTAssertNil(model.displayMetrics.first?.window?.usedPercentage)
    }

    func testInvalidRoleOrTeamFailsBeforeAnyRequestAndHTTPFailuresStayFailures() async throws {
        let transport = XAITransport(status: 200, body: #"{"total":{"val":"-1234"}}"#)
        let invalid = ProviderCredentialEnvelope(provider: .xaiAPI, kind: .apiKey, accessToken: "inference-fixture", metadata: ["teamID": "team-1"])
        do {
            _ = try await XAIAPIProviderClient(transport: transport, now: { Date() }).quota(accountID: UUID(), credential: invalid)
            XCTFail("An inference-format envelope without management role cannot be queried")
        } catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let sent = await transport.requests
        XCTAssertTrue(sent.isEmpty)
        for (status, failure) in [(401, RefreshFailure.invalidCredential), (403, .invalidCredential), (404, .server), (429, .rateLimited), (500, .server), (302, .server)] {
            do {
                _ = try await XAIAPIProviderClient(transport: XAITransport(status: status, body: "{}"), now: { Date() }).quota(accountID: UUID(), credential: XAIManagementCredential("team-1:fixture-management").envelope())
                XCTFail("Expected \(status) failure")
            } catch { XCTAssertEqual(error as? RefreshFailure, failure) }
        }
    }

    @MainActor
    func testMultipleTeamsPersistLocallyAndChangedTeamCannotDisplayOrMergeOldBalance() async throws {
        let suite = "com.tokenpulse.tests.xai.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let accounts = LocalAccountStateStore(suiteName: suite)
        let configurations = LocalAccountConfigurationStore(suiteName: suite)
        let credentials = XAIMemoryCredentials()
        let query = XAILocalQuery()
        let monitor = QuotaMonitor(accountStore: accounts, credentialStore: credentials, quotaClient: query, configurationStore: configurations)
        await monitor.addAccount(name: "First", credential: try XAIManagementCredential("team-1:first-management").envelope().encoded(), provider: .xaiAPI)
        await monitor.addAccount(name: "Second", credential: try XAIManagementCredential("team-2:second-management").envelope().encoded(), provider: .xaiAPI)
        XCTAssertEqual(monitor.states.map { $0.snapshot?.windows.first?.wallet?.total }, [Decimal(12), Decimal(99)])
        let original = monitor.states[0]
        let originalConfig = try XCTUnwrap(monitor.configuration(for: original.id))
        await query.fail()
        await monitor.replaceCredential(try XAIManagementCredential("team-3:first-management").envelope().encoded(), accountID: original.id)
        XCTAssertNil(monitor.states[0].snapshot)
        XCTAssertEqual(monitor.states[1].snapshot?.windows.first?.wallet?.total, 99)
        var stale = original
        if let snapshot = stale.snapshot {
            stale.snapshot = QuotaSnapshot(accountID: stale.id, windows: snapshot.windows, collectedAt: .distantFuture,
                                           sourceCredentialFingerprint: snapshot.sourceCredentialFingerprint,
                                           providerPlanName: snapshot.providerPlanName)
        }
        await monitor.mergeSynchronized(configurations: [originalConfig], states: [stale])
        XCTAssertNil(monitor.states[0].snapshot)
        let reopened = QuotaMonitor(accountStore: accounts, credentialStore: credentials, quotaClient: query, configurationStore: configurations)
        await reopened.start(refresh: false)
        XCTAssertEqual(reopened.states.count, 2)
        XCTAssertNil(reopened.states[0].snapshot)
        XCTAssertNotNil(reopened.states[1].snapshot)
        let deleted = await reopened.deleteAccount(accountID: original.id)
        XCTAssertTrue(deleted)
        let removed = await credentials.credential(for: original.id)
        XCTAssertNil(removed)
    }

    func testUSDLowBalanceRecoveryAndDemoHaveNoQuotaOrResetAlerts() throws {
        let id = UUID()
        let planner = NotificationPlanner()
        func low(_ cents: String, at: Double, ledger: ReminderLedger) throws -> NotificationPlanningResult {
            let data = try JSONSerialization.data(withJSONObject: ["total": ["val": cents]])
            let snapshot = try XAIAPIProviderClient.snapshot(data, accountID: id, teamID: "team-1", collectedAt: Date(timeIntervalSince1970: at))
            return planner.planSuccessfulRefresh(accountID: id, accountName: "xAI", previousSnapshot: nil, newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: ledger, now: snapshot.collectedAt)
        }
        let first = try low("-100", at: 100, ledger: ReminderLedger())
        XCTAssertEqual(first.operations.count, 1)
        if case .deliver(let notification) = first.operations[0] { XCTAssertEqual(notification.kind, .walletAlert) }
        else { XCTFail("Expected low-balance delivery") }
        let repeated = try low("-50", at: 101, ledger: first.ledger)
        XCTAssertTrue(repeated.operations.isEmpty)
        let restored = try low("-300", at: 102, ledger: repeated.ledger)
        XCTAssertTrue(restored.operations.isEmpty)
        let again = try low("-100", at: 103, ledger: restored.ledger)
        XCTAssertEqual(again.operations.count, 1)
        XCTAssertTrue(DemoMode.accounts().contains { $0.provider == .xaiAPI })
        let demo = DemoMode.snapshot(accountID: id, provider: .xaiAPI)
        XCTAssertEqual(demo.windows[0].wallet?.currency, "USD")
        XCTAssertNil(demo.windows[0].usedPercentage)
        XCTAssertNil(demo.windows[0].resetsAt)
    }
}

private actor XAITransport: ProviderTransport {
    let status: Int
    let body: String
    var requests: [URLRequest] = []
    init(status: Int, body: String) { self.status = status; self.body = body }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
private actor XAIMemoryCredentials: CredentialStoring {
    var keys: [UUID: String] = [:]
    func save(_ value: String, for id: UUID) { keys[id] = value }
    func credential(for id: UUID) -> String? { keys[id] }
    func deleteCredential(for id: UUID) { keys[id] = nil }
}
private actor XAILocalQuery: QuotaQuerying {
    var failed = false
    func fail() { failed = true }
    func quota(for id: UUID, credential: String) async throws -> QuotaSnapshot {
        if failed { throw RefreshFailure.network }
        let envelope = try ProviderCredentialEnvelope.decode(credential, expectedProvider: .xaiAPI)
        let cents = envelope.metadata["teamID"] == "team-1" ? "-1200" : "-9900"
        return try XAIAPIProviderClient.snapshot(Data("{\"total\":{\"val\":\"\(cents)\"}}".utf8), accountID: id, teamID: envelope.metadata["teamID"]!, collectedAt: Date())
    }
}
