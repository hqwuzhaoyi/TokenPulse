import Foundation
import XCTest
@testable import TokenPulse

final class NewAPIProviderTests: XCTestCase {
    private let subscription = #"{"hard_limit_usd":25.5,"soft_limit_usd":25.5,"system_hard_limit_usd":25.5}"#
    private let usage = #"{"total_usage":1234.5}"#
    private func status(_ type: String) -> String { "{\"success\":true,\"data\":{\"quota_display_type\":\"\(type)\"}}" }

    private func reading(_ display: String = "USD", total: String? = nil, used: String? = nil,
                         publicStatus: String? = nil, accountID: UUID = UUID()) throws -> QuotaSnapshot {
        try NewAPIProviderClient.snapshot(subscription: Data((total ?? subscription).utf8),
                                          usage: Data((used ?? usage).utf8),
                                          status: Data((publicStatus ?? status(display)).utf8),
                                          accountID: accountID, collectedAt: Date(timeIntervalSince1970: 100))
    }

    func testCentsConversionAndMissingBreakdownNeverBecomeInventedPercentages() throws {
        for currency in ["USD", "CNY"] {
            let window = try XCTUnwrap(reading(currency).windows.first)
            XCTAssertEqual(window.wallet?.total, Decimal(string: "13.155"))
            XCTAssertEqual(window.wallet?.currency, currency)
            XCTAssertNil(window.wallet?.granted)
            XCTAssertNil(window.wallet?.toppedUp)
            XCTAssertNil(window.usedPercentage)
            XCTAssertNil(window.totalCount)
            XCTAssertNil(window.resetsAt)
        }
        XCTAssertEqual(try reading(total: #"{"hard_limit_usd":"0.30"}"#, used: #"{"total_usage":"10"}"#).windows[0].wallet?.total,
                       Decimal(string: "0.20"))
    }

    func testUnknownCustomAndTokenModesNeverProduceMoneyOrFalseZero() throws {
        for type in ["CUSTOM", "TOKENS", "EUR", ""] {
            let snapshot = try reading(type)
            XCTAssertNil(snapshot.windows[0].wallet)
            XCTAssertNil(snapshot.windows[0].usedPercentage)
        }
        XCTAssertEqual(try reading("TOKENS").windows[0].remainingCount, 13.155)
        XCTAssertEqual(try reading("TOKENS").windows[0].unit, "tokens")
        XCTAssertNil(try reading(publicStatus: #"{"success":true,"data":{}}"#).windows[0].wallet)
        XCTAssertNil(try reading(publicStatus: #"{"success":true,"data":{"display_in_currency":false}}"#).windows[0].wallet)
        XCTAssertEqual(try reading(publicStatus: #"{"success":true,"data":{"display_in_currency":true}}"#).windows[0].wallet?.currency, "USD")
        XCTAssertNil(try reading(publicStatus: #"{"success":true,"data":{"quota_display_type":"CUSTOM","display_in_currency":true}}"#).windows[0].wallet)
    }

    func testUnlimitedRequiresAllThreeSentinelsAndNeverComputesHugeWallet() throws {
        let sentinel = #"{"hard_limit_usd":100000000,"soft_limit_usd":100000000,"system_hard_limit_usd":100000000}"#
        let unlimited = try reading(total: sentinel).windows[0]
        XCTAssertTrue(unlimited.isUnlimited)
        XCTAssertNil(unlimited.wallet)
        XCTAssertNil(unlimited.remainingCount)
        XCTAssertNil(unlimited.usedPercentage)
        XCTAssertFalse(try reading(total: #"{"hard_limit_usd":100000000,"soft_limit_usd":99999999,"system_hard_limit_usd":100000000}"#).windows[0].isUnlimited)
    }

    func testMalformedAndMissingMetricsFailAndNegativeRemainingRemainsReal() throws {
        for total in ["{}", #"{"error":{"message":"no"}}"#, #"{"hard_limit_usd":true}"#,
                      #"{"hard_limit_usd":-1}"#, #"{"hard_limit_usd":"NaN"}"#] {
            XCTAssertThrowsError(try reading(total: total))
        }
        for used in ["{}", #"{"total_usage":null}"#, #"{"total_usage":false}"#, #"{"total_usage":-1}"#] {
            XCTAssertThrowsError(try reading(used: used))
        }
        XCTAssertThrowsError(try reading(publicStatus: #"{"success":false,"data":{"quota_display_type":"USD"}}"#))
        XCTAssertEqual(try reading(total: #"{"hard_limit_usd":0}"#).windows[0].wallet?.total, Decimal(string: "-12.345"))
    }

    func testAddressNormalizationAndTrustBoundary() throws {
        XCTAssertEqual(try GatewayServerAddress(" https://EXAMPLE.com:443/proxy/v1/ ").value, "https://example.com/proxy")
        XCTAssertEqual(try GatewayServerAddress("https://example.com/v1").endpoint("api/status").path, "/api/status")
        for address in ["", "http://example.com", "http://192.168.1.2", "http://localhost", "https://user:pass@example.com",
                        "https://example.com?key=secret", "https://example.com#secret", "https://example.com/?", "https://example.com/#",
                        "https://example.com:0", "https://example.com:65536", "https://example.com/a/../b", "https://example.com/%2e%2e/b",
                        "https://example.com/a%2Fb", "https://exa mple.com", "https://example.com\\evil"] {
            XCTAssertThrowsError(try GatewayServerAddress(address), address)
        }
        let root = URL(string: "https://example.com/v1")!
        XCTAssertTrue(GatewayServerAddress.sameOrigin(root, URL(string: "https://example.com:443/new")!))
        for target in ["https://other.example.com", "http://example.com", "https://example.com:8443"] {
            XCTAssertFalse(GatewayServerAddress.sameOrigin(root, URL(string: target)!))
        }
    }

    func testRequestContractPublicStatusHasNoCredentialAndPreservesPrefix() async throws {
        let transport = NewAPITransport(replies: [subscription, usage, status("CNY")])
        let credential = try ProviderAuthenticationController().credential(provider: .newAPI, apiKey: "fixture-key",
                                                                          serverAddress: "https://relay.example/prefix/v1/")
        let result = try await ProviderQuotaClient(provider: .newAPI, transport: transport)
            .quotaResult(for: UUID(), credential: credential)
        XCTAssertEqual(result.snapshot.windows[0].wallet?.total, Decimal(string: "13.155"))
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.url?.path), ["/prefix/v1/dashboard/billing/subscription", "/prefix/v1/dashboard/billing/usage", "/prefix/api/status"])
        XCTAssertEqual(requests.map { $0.httpMethod }, ["GET", "GET", "GET"])
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
        XCTAssertNil(requests[2].value(forHTTPHeaderField: "Authorization"))
    }

    func testRedirectDelegateRejectsCrossOriginBeforeFollowingRequest() async throws {
        let original = URLRequest(url: URL(string: "https://relay.example/billing")!)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: original)
        let delegate = GatewayRedirectDelegate()
        for target in ["https://evil.example/billing", "http://relay.example/billing", "https://relay.example:8443/billing"] {
            let redirected = URLRequest(url: URL(string: target)!)
            let response = HTTPURLResponse(url: original.url!, statusCode: 302, httpVersion: nil, headerFields: ["Location": target])!
            let followed: URLRequest? = await withCheckedContinuation { continuation in
                delegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: redirected) {
                    continuation.resume(returning: $0)
                }
            }
            XCTAssertNil(followed, target)
        }
        let safe = URLRequest(url: URL(string: "https://relay.example/new")!)
        let followed: URLRequest? = await withCheckedContinuation { continuation in
            delegate.urlSession(session, task: task,
                                willPerformHTTPRedirection: HTTPURLResponse(url: original.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!,
                                newRequest: safe) { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(followed?.url, safe.url)
    }

    func testHTTPFailuresAndRedirectResponsesDoNotBecomeZeroBalance() async throws {
        for (status, failure) in [(401, RefreshFailure.invalidCredential), (403, .invalidCredential), (429, .rateLimited), (500, .server), (302, .server)] {
            let transport = NewAPITransport(replies: ["{}"], statusCode: status)
            let credential = try ProviderAuthenticationController().credential(provider: .newAPI, apiKey: "fixture", serverAddress: "https://relay.example")
            do {
                _ = try await ProviderQuotaClient(provider: .newAPI, transport: transport).quotaResult(for: UUID(), credential: credential)
                XCTFail("Expected HTTP \(status) to fail")
            } catch let error as RefreshFailure {
                XCTAssertEqual(error, failure)
            }
        }
    }

    func testIdentityIncludesServerAndKeyAndKeepsFixedAddressProvidersCompatible() throws {
        func envelope(_ server: String, _ key: String = "fixture-key") throws -> ProviderCredentialEnvelope {
            try ProviderCredentialEnvelope.decode(ProviderAuthenticationController().credential(provider: .newAPI, apiKey: key,
                                                                                               serverAddress: server), expectedProvider: .newAPI)
        }
        let first = try envelope("https://one.example/v1/")
        XCTAssertEqual(first.gatewayIdentity, try envelope("https://ONE.example:443").gatewayIdentity)
        XCTAssertNotEqual(first.gatewayIdentity, try envelope("https://two.example").gatewayIdentity)
        XCTAssertNotEqual(first.gatewayIdentity, try envelope("https://one.example", "new-key").gatewayIdentity)
        let restored = try ProviderCredentialEnvelope.decode(first.encoded(), expectedProvider: .newAPI)
        XCTAssertEqual(restored.metadata["serverAddress"], "https://one.example")
        XCTAssertEqual(restored.gatewayIdentity, first.gatewayIdentity)
        let fixed = try ProviderAuthenticationController().credential(provider: .deepSeek, apiKey: "fixture-key")
        XCTAssertTrue(try ProviderCredentialEnvelope.decode(fixed, expectedProvider: .deepSeek).metadata.isEmpty)
    }

    @MainActor
    func testReplacementFailureCannotShowOldServerBalanceAndRestoresBinding() async throws {
        let suite = "com.tokenpulse.tests.gateway.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let accounts = LocalAccountStateStore(suiteName: suite)
        let configs = LocalAccountConfigurationStore(suiteName: suite)
        let keys = NewAPICredentials()
        let monitor = QuotaMonitor(accountStore: accounts, credentialStore: keys, quotaClient: NewAPIFailedQuery(), configurationStore: configs)
        let old = try ProviderAuthenticationController().credential(provider: .newAPI, apiKey: "old-fixture-key", serverAddress: "https://old.example")
        await monitor.addAccount(name: "gateway", credential: old, provider: .newAPI)
        let account = try XCTUnwrap(monitor.states.first?.account)
        var config = try XCTUnwrap(monitor.configuration(for: account.id))
        let oldSnapshot = try reading(accountID: account.id)
        let oldState = AccountQuotaState(account: account, snapshot: oldSnapshot, credentialIdentity: config.credentialIdentity)
        await monitor.mergeSynchronized(configurations: [config], states: [oldState])
        XCTAssertNotNil(monitor.states[0].snapshot)
        let new = try ProviderAuthenticationController().credential(provider: .newAPI, apiKey: "new-fixture-key", serverAddress: "https://new.example/v1")
        await monitor.replaceCredential(new, accountID: account.id)
        XCTAssertNil(monitor.states[0].snapshot)
        XCTAssertEqual(monitor.states[0].lastFailure, .network)
        XCTAssertEqual(monitor.configuration(for: account.id)?.serverAddress, "https://new.example")
        // Even a later observation from the old binding cannot be merged back.
        var stale = oldState
        stale.snapshot = QuotaSnapshot(accountID: account.id, windows: oldSnapshot.windows, collectedAt: Date.distantFuture)
        config.modifiedAt = .distantPast
        await monitor.mergeSynchronized(configurations: [config], states: [stale])
        XCTAssertNil(monitor.states[0].snapshot)
        let reopened = QuotaMonitor(accountStore: accounts, credentialStore: keys, quotaClient: NewAPIFailedQuery(), configurationStore: configs)
        await reopened.start(refresh: false)
        XCTAssertNil(reopened.states[0].snapshot)
        XCTAssertEqual(reopened.configuration(for: account.id)?.serverAddress, "https://new.example")
        let deleted = await reopened.deleteAccount(accountID: account.id)
        XCTAssertTrue(deleted)
        let deletedKey = await keys.credential(for: account.id)
        XCTAssertNil(deletedKey)
    }

    @MainActor
    func testNewConfigurationBeforeKeychainNeverQueriesOldCredential() async throws {
        let suite = "com.tokenpulse.tests.gateway-sync.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let keys = NewAPICredentials()
        let query = NewAPIFailedQuery()
        let monitor = QuotaMonitor(accountStore: LocalAccountStateStore(suiteName: suite), credentialStore: keys,
                                   quotaClient: query, configurationStore: LocalAccountConfigurationStore(suiteName: suite))
        let old = try ProviderAuthenticationController().credential(provider: .newAPI, apiKey: "old", serverAddress: "https://old.example")
        await monitor.addAccount(name: "gateway", credential: old, provider: .newAPI)
        let oldCount = await query.count
        let id = monitor.states[0].id
        var incoming = try XCTUnwrap(monitor.configuration(for: id))
        let newer = try ProviderCredentialEnvelope.decode(ProviderAuthenticationController().credential(provider: .newAPI, apiKey: "new", serverAddress: "https://new.example"), expectedProvider: .newAPI)
        incoming.credentialIdentity = newer.gatewayIdentity
        incoming.serverAddress = newer.gatewayAddress?.value
        incoming.modifiedAt = .distantFuture
        await monitor.mergeSynchronized(configurations: [incoming], states: [])
        await monitor.refresh(accountID: id)
        let requestsAfterMismatch = await query.count
        XCTAssertEqual(requestsAfterMismatch, oldCount)
        XCTAssertNil(monitor.states[0].snapshot)
        XCTAssertEqual(monitor.states[0].lastFailure, .invalidCredential)
        try await keys.save(newer.encoded(), for: id)
        await monitor.refresh(accountID: id)
        let requestsAfterKeyArrival = await query.count
        XCTAssertEqual(requestsAfterKeyArrival, oldCount + 1)
    }

    @MainActor
    func testInFlightOldRequestCannotRestoreBalanceAfterKeyReplacement() async throws {
        let suite = "com.tokenpulse.tests.gateway-flight.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let account = SubscriptionAccount(name: "relay", provider: .newAPI)
        let old = try ProviderAuthenticationController().credential(provider: .newAPI, apiKey: "old", serverAddress: "https://old.example")
        let oldEnvelope = try ProviderCredentialEnvelope.decode(old, expectedProvider: .newAPI)
        var configuration = AccountConfiguration(account: account)
        configuration.credentialIdentity = oldEnvelope.gatewayIdentity
        configuration.serverAddress = oldEnvelope.gatewayAddress?.value
        let accounts = LocalAccountStateStore(suiteName: suite)
        let configurations = LocalAccountConfigurationStore(suiteName: suite)
        try await accounts.save([AccountQuotaState(account: account, credentialIdentity: oldEnvelope.gatewayIdentity)])
        try await configurations.save([configuration])
        let keys = NewAPICredentials()
        await keys.save(old, for: account.id)
        let query = NewAPIHeldQuery(snapshot: try reading(accountID: account.id))
        let monitor = QuotaMonitor(accountStore: accounts, credentialStore: keys, quotaClient: query, configurationStore: configurations)
        await monitor.start(refresh: false)
        let request = Task { await monitor.refresh(accountID: account.id) }
        await query.waitForRequest(1)
        let new = try ProviderAuthenticationController().credential(provider: .newAPI, apiKey: "new", serverAddress: "https://new.example")
        await monitor.replaceCredential(new, accountID: account.id)
        await query.release()
        await request.value
        await query.waitForRequest(2)
        XCTAssertNil(monitor.states[0].snapshot)
        XCTAssertEqual(monitor.configuration(for: account.id)?.serverAddress, "https://new.example")
        let queried = await query.credentials
        XCTAssertEqual(queried, [old, new])
    }

    func testLegacyStateConfigurationAndReminderLedgerDecodeWithNoIdentity() throws {
        let state = AccountQuotaState(account: SubscriptionAccount(name: "old"), snapshot: try reading())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object.removeValue(forKey: "credentialIdentity")
        var snapshot = try XCTUnwrap(object["snapshot"] as? [String: Any])
        snapshot.removeValue(forKey: "sourceCredentialFingerprint")
        object["snapshot"] = snapshot
        let decoded = try JSONDecoder().decode(AccountQuotaState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.credentialIdentity)
        XCTAssertNil(decoded.snapshot?.sourceCredentialFingerprint)
        let configuration = AccountConfiguration(account: state.account)
        let restored = try JSONDecoder().decode(AccountConfiguration.self, from: JSONEncoder().encode(configuration))
        XCTAssertNil(restored.credentialIdentity)
        XCTAssertNil(restored.serverAddress)
        let ledger = try JSONDecoder().decode(ReminderLedger.self, from: JSONEncoder().encode(ReminderLedger()))
        XCTAssertNil(ledger.walletAlertState(accountID: state.id, currency: "USD"))
    }

    func testChangingIdentityRearmsWalletReminderAndRejectsStaleRemoteLedger() throws {
        let id = UUID()
        let snapshot = try reading(total: #"{"hard_limit_usd":1}"#, used: #"{"total_usage":0}"#, accountID: id)
        let planner = NotificationPlanner()
        var original = ReminderLedger()
        _ = original.bindCredentialIdentity("old", accountID: id)
        let first = planner.planSuccessfulRefresh(accountID: id, accountName: "relay", previousSnapshot: nil,
                                                   newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: original, now: snapshot.collectedAt)
        XCTAssertTrue(first.operations.contains { if case .deliver(let message) = $0 { return message.kind == .walletAlert }; return false })
        var changed = first.ledger
        _ = changed.bindCredentialIdentity("new", accountID: id)
        changed = changed.merging(first.ledger)
        XCTAssertNil(changed.walletAlertState(accountID: id, currency: "USD"))
        let next = planner.planSuccessfulRefresh(accountID: id, accountName: "relay", previousSnapshot: nil,
                                                 newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: changed, now: snapshot.collectedAt)
        XCTAssertTrue(next.operations.contains { if case .deliver(let message) = $0 { return message.kind == .walletAlert }; return false })
        let tokens = try reading("TOKENS", accountID: id)
        let nonmoney = planner.planSuccessfulRefresh(accountID: id, accountName: "relay", previousSnapshot: nil,
                                                     newSnapshot: tokens, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: tokens.collectedAt)
        XCTAssertTrue(nonmoney.operations.isEmpty)
    }
}

private actor NewAPITransport: ProviderTransport {
    var replies: [String]
    var requests: [URLRequest] = []
    let statusCode: Int
    init(replies: [String], statusCode: Int = 200) { self.replies = replies; self.statusCode = statusCode }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return (Data(replies.removeFirst().utf8), HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!)
    }
}
private actor NewAPICredentials: CredentialStoring {
    var values: [UUID: String] = [:]
    func save(_ value: String, for id: UUID) { values[id] = value }
    func credential(for id: UUID) -> String? { values[id] }
    func deleteCredential(for id: UUID) { values[id] = nil }
}
private actor NewAPIFailedQuery: QuotaQuerying {
    var count = 0
    func quota(for id: UUID, credential: String) async throws -> QuotaSnapshot {
        count += 1
        throw RefreshFailure.network
    }
}

private actor NewAPIHeldQuery: QuotaQuerying {
    let snapshot: QuotaSnapshot
    var credentials: [String] = []
    private var held: CheckedContinuation<Void, Never>?
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    init(snapshot: QuotaSnapshot) { self.snapshot = snapshot }
    func waitForRequest(_ count: Int) async {
        if credentials.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func release() { held?.resume(); held = nil }
    func quota(for id: UUID, credential: String) async throws -> QuotaSnapshot {
        credentials.append(credential)
        let started = credentials.count
        if started == 1 {
            await withCheckedContinuation { continuation in
                held = continuation
                signalWaiters()
            }
            return snapshot
        }
        signalWaiters()
        throw RefreshFailure.network
    }
    private func signalWaiters() {
        let ready = waiters.filter { $0.0 <= credentials.count }
        waiters.removeAll { $0.0 <= credentials.count }
        for (_, waiter) in ready { waiter.resume() }
    }
}
