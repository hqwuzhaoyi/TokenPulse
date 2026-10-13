import XCTest
@testable import TokenPulse

@MainActor
final class QuotaMonitorTests: XCTestCase {
    func testDeletedAccountCredentialCleanupCanBeRetried() async throws {
        for language in ["zh-Hans", "en"] {
            try await L10n.withLanguage(language) {
                let account = SubscriptionAccount(name: "Delete")
                let store = MemoryAccountStore(initial: [AccountQuotaState(account: account)])
                let credentials = MemoryCredentialStore(values: [account.id: "fixture"], deleteFailuresRemaining: 1)
                let monitor = QuotaMonitor(accountStore: store, credentialStore: credentials, quotaClient: StubQuotaClient())
                await monitor.start(refresh: false)

                await monitor.deleteAccount(accountID: account.id)

                XCTAssertTrue(monitor.states.isEmpty)
                XCTAssertTrue(monitor.hasPendingCredentialCleanup)
                XCTAssertEqual(monitor.storageMessage, language == "en"
                               ? "The account was deleted, but its credentials could not be cleared. Try again."
                               : "账号已删除，凭证清理失败，请重试。")
                await monitor.retryPendingCredentialCleanup()
                XCTAssertFalse(monitor.hasPendingCredentialCleanup)
                let credential = await credentials.credential(for: account.id)
                XCTAssertNil(credential)
            }
        }
    }

    func testRefreshKeepsTwoAccountsIsolatedAndPersistsSuccessfulSnapshots() async throws {
        let first = SubscriptionAccount(name: "工作账号")
        let second = SubscriptionAccount(name: "个人账号")
        let store = MemoryAccountStore(initial: [
            AccountQuotaState(account: first, snapshot: nil, lastFailure: nil),
            AccountQuotaState(account: second, snapshot: nil, lastFailure: nil),
        ])
        let credentials = MemoryCredentialStore(values: [first.id: "first-key", second.id: "second-key"])
        var firstSnapshot = snapshot(accountID: first.id, used: 20, collectedAt: Date(timeIntervalSince1970: 100))
        firstSnapshot.sourceCredentialFingerprint = ProviderCredentialEnvelope(provider: .miniMaxChina, kind: .apiKey, accessToken: "first-key").sourceCredentialIdentity
        var secondSnapshot = snapshot(accountID: second.id, used: 75, collectedAt: Date(timeIntervalSince1970: 200))
        secondSnapshot.sourceCredentialFingerprint = ProviderCredentialEnvelope(provider: .miniMaxChina, kind: .apiKey, accessToken: "second-key").sourceCredentialIdentity
        let client = StubQuotaClient(results: [
            first.id: [.success(firstSnapshot)],
            second.id: [.success(secondSnapshot)],
        ])
        let monitor = QuotaMonitor(accountStore: store, credentialStore: credentials, quotaClient: client)

        await monitor.start()

        XCTAssertEqual(monitor.states.first(where: { $0.id == first.id })?.snapshot, firstSnapshot)
        XCTAssertEqual(monitor.states.first(where: { $0.id == second.id })?.snapshot, secondSnapshot)
        let firstCredential = await client.receivedCredential(for: first.id)
        let secondCredential = await client.receivedCredential(for: second.id)
        let persistedStates = await store.load()
        XCTAssertEqual(firstCredential, "first-key")
        XCTAssertEqual(secondCredential, "second-key")
        XCTAssertEqual(persistedStates, monitor.states)
    }

    func testFailedRefreshRetainsLastSuccessfulDataAndMarksInvalidKey() async throws {
        let account = SubscriptionAccount(name: "失效 Key")
        var oldSnapshot = snapshot(accountID: account.id, used: 42, collectedAt: Date(timeIntervalSince1970: 100))
        oldSnapshot.sourceCredentialFingerprint = ProviderCredentialEnvelope(provider: .miniMaxChina, kind: .apiKey, accessToken: "expired-key").sourceCredentialIdentity
        let store = MemoryAccountStore(initial: [
            AccountQuotaState(account: account, snapshot: oldSnapshot, lastFailure: nil),
        ])
        let credentials = MemoryCredentialStore(values: [account.id: "expired-key"])
        let client = StubQuotaClient(results: [account.id: [.failure(.invalidCredential)]])
        let monitor = QuotaMonitor(accountStore: store, credentialStore: credentials, quotaClient: client)

        await monitor.start()

        XCTAssertEqual(monitor.states[0].snapshot, oldSnapshot)
        XCTAssertEqual(monitor.states[0].lastFailure, .invalidCredential)
        let persistedStates = await store.load()
        XCTAssertEqual(persistedStates[0].snapshot, oldSnapshot)
    }

    func testLocalStateCanBeRestoredWithoutCloudService() async throws {
        let store = MemoryAccountStore()
        let credentials = MemoryCredentialStore()
        let client = StubQuotaClient(defaultResult: .failure(.network))
        let firstMonitor = QuotaMonitor(accountStore: store, credentialStore: credentials, quotaClient: client)

        await firstMonitor.addAccount(name: "本地账号", credential: "local-only-key")

        let restoredMonitor = QuotaMonitor(accountStore: store, credentialStore: credentials, quotaClient: client)
        await restoredMonitor.start()
        XCTAssertEqual(restoredMonitor.states.map(\.account.name), ["本地账号"])
        XCTAssertEqual(restoredMonitor.states[0].lastFailure, .network)
    }

    func testBecomingActiveRefreshesLoadedAccountsAgain() async throws {
        let account = SubscriptionAccount(name: "前台刷新账号")
        let firstSnapshot = snapshot(accountID: account.id, used: 20, collectedAt: Date(timeIntervalSince1970: 100))
        var secondSnapshot = snapshot(accountID: account.id, used: 30, collectedAt: Date(timeIntervalSince1970: 200))
        secondSnapshot.sourceCredentialFingerprint = ProviderCredentialEnvelope(provider: .miniMaxChina, kind: .apiKey, accessToken: "placeholder-key").sourceCredentialIdentity
        let store = MemoryAccountStore(initial: [
            AccountQuotaState(account: account, snapshot: nil, lastFailure: nil),
        ])
        let credentials = MemoryCredentialStore(values: [account.id: "placeholder-key"])
        let client = StubQuotaClient(results: [account.id: [.success(firstSnapshot), .success(secondSnapshot)]])
        let monitor = QuotaMonitor(accountStore: store, credentialStore: credentials, quotaClient: client)

        await monitor.start()
        await monitor.applicationDidBecomeActive()

        XCTAssertEqual(monitor.states[0].snapshot, secondSnapshot)
        let requestCount = await client.requestCount(for: account.id)
        XCTAssertEqual(requestCount, 2)
    }

    func testAddAccountRollsBackStateAndCredentialWhenMetadataSaveFails() async throws {
        let store = MemoryAccountStore(saveError: TestStoreError.failed)
        let credentials = MemoryCredentialStore()
        let client = StubQuotaClient(defaultResult: .failure(.server))
        let monitor = QuotaMonitor(accountStore: store, credentialStore: credentials, quotaClient: client)

        await monitor.addAccount(name: "不能保存", credential: "placeholder-key")

        XCTAssertTrue(monitor.states.isEmpty)
        let credentialCount = await credentials.credentialCount()
        let requestCount = await client.totalRequestCount()
        XCTAssertEqual(credentialCount, 0)
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(monitor.storageMessage, L10n.text("无法安全保存账号"))
    }

    func testCancelledRefreshDoesNotOverwriteOrPersistOldState() async throws {
        let account = SubscriptionAccount(name: "取消刷新账号")
        var oldSnapshot = snapshot(accountID: account.id, used: 42, collectedAt: Date(timeIntervalSince1970: 100))
        let identity = ProviderCredentialEnvelope(provider: .miniMaxChina, kind: .apiKey, accessToken: "placeholder-key").sourceCredentialIdentity
        oldSnapshot.sourceCredentialFingerprint = identity
        let oldState = AccountQuotaState(account: account, snapshot: oldSnapshot, lastFailure: .rateLimited, credentialIdentity: identity)
        let store = MemoryAccountStore(initial: [oldState])
        let credentials = MemoryCredentialStore(values: [account.id: "placeholder-key"])
        let client = StubQuotaClient(cancelledAccountIDs: [account.id])
        let monitor = QuotaMonitor(accountStore: store, credentialStore: credentials, quotaClient: client)

        await monitor.start()

        XCTAssertEqual(monitor.states, [oldState])
        let saveCount = await store.saveCount()
        XCTAssertEqual(saveCount, 0)
    }

    func testFailedStateSaveAndCredentialRollbackRemainVisibleAndRetryable() async throws {
        for language in ["zh-Hans", "en"] {
            try await L10n.withLanguage(language) {
                let store = MemoryAccountStore(saveError: TestStoreError.failed)
                let credentials = MemoryCredentialStore(deleteFailuresRemaining: 2)
                let client = StubQuotaClient(defaultResult: .failure(.server))
                let monitor = QuotaMonitor(accountStore: store, credentialStore: credentials, quotaClient: client)

                await monitor.addAccount(name: "双重失败", credential: "placeholder-key")

                let retainedCredentialCount = await credentials.credentialCount()
                XCTAssertTrue(monitor.states.isEmpty)
                XCTAssertTrue(monitor.hasPendingCredentialCleanup)
                XCTAssertEqual(retainedCredentialCount, 1)
                XCTAssertEqual(monitor.storageMessage, language == "en"
                               ? "The account was not saved and its credentials could not be cleared. Try again."
                               : "账号未保存，凭证清理失败，请重试。")

                await monitor.retryPendingCredentialCleanup()

                let retainedAfterRetryCount = await credentials.credentialCount()
                XCTAssertTrue(monitor.hasPendingCredentialCleanup)
                XCTAssertEqual(retainedAfterRetryCount, 1)
                XCTAssertEqual(monitor.storageMessage, language == "en"
                               ? "Credentials still could not be cleared. Try again."
                               : "凭证清理仍失败，请重试。")

                await monitor.retryPendingCredentialCleanup()

                let cleanedCredentialCount = await credentials.credentialCount()
                XCTAssertFalse(monitor.hasPendingCredentialCleanup)
                XCTAssertEqual(cleanedCredentialCount, 0)
                XCTAssertNil(monitor.storageMessage)
            }
        }
    }

    private func snapshot(accountID: UUID, used: Double, collectedAt: Date) -> QuotaSnapshot {
        QuotaSnapshot(
            accountID: accountID,
            windows: [QuotaWindow(
                id: "general.weekly",
                name: "每周额度",
                scope: nil,
                usedPercentage: used,
                remainingCount: 100 - used,
                totalCount: 100,
                resetsAt: nil
            )],
            collectedAt: collectedAt
        )
    }
}

private actor MemoryAccountStore: AccountStateStoring {
    private var states: [AccountQuotaState]
    private let saveError: (any Error)?
    private var saves = 0

    init(initial: [AccountQuotaState] = [], saveError: (any Error)? = nil) {
        states = initial
        self.saveError = saveError
    }

    func load() -> [AccountQuotaState] { states }
    func save(_ states: [AccountQuotaState]) throws {
        if let saveError { throw saveError }
        self.states = states
        saves += 1
    }

    func saveCount() -> Int { saves }
}

private actor MemoryCredentialStore: CredentialStoring {
    private var values: [UUID: String]
    private var deleteFailuresRemaining: Int

    init(values: [UUID: String] = [:], deleteFailuresRemaining: Int = 0) {
        self.values = values
        self.deleteFailuresRemaining = deleteFailuresRemaining
    }

    func save(_ credential: String, for accountID: UUID) { values[accountID] = credential }
    func credential(for accountID: UUID) -> String? { values[accountID] }
    func deleteCredential(for accountID: UUID) throws {
        if deleteFailuresRemaining > 0 {
            deleteFailuresRemaining -= 1
            throw TestCredentialStoreError.deleteFailed
        }
        values[accountID] = nil
    }
    func credentialCount() -> Int { values.count }
}

private actor StubQuotaClient: QuotaQuerying {
    private var results: [UUID: [Result<QuotaSnapshot, RefreshFailure>]]
    private let defaultResult: Result<QuotaSnapshot, RefreshFailure>?
    private var received: [UUID: String] = [:]
    private var requests: [UUID: Int] = [:]
    private let cancelledAccountIDs: Set<UUID>

    init(results: [UUID: [Result<QuotaSnapshot, RefreshFailure>]] = [:],
         defaultResult: Result<QuotaSnapshot, RefreshFailure>? = nil,
         cancelledAccountIDs: Set<UUID> = []) {
        self.results = results
        self.defaultResult = defaultResult
        self.cancelledAccountIDs = cancelledAccountIDs
    }

    func quota(for accountID: UUID, credential: String) throws -> QuotaSnapshot {
        received[accountID] = credential
        requests[accountID, default: 0] += 1
        if cancelledAccountIDs.contains(accountID) { throw CancellationError() }
        let result: Result<QuotaSnapshot, RefreshFailure>
        if var accountResults = results[accountID], !accountResults.isEmpty {
            result = accountResults.removeFirst()
            results[accountID] = accountResults
        } else if let defaultResult {
            result = defaultResult
        } else {
            result = .failure(.server)
        }
        return try result.get()
    }

    func receivedCredential(for accountID: UUID) -> String? { received[accountID] }
    func requestCount(for accountID: UUID) -> Int { requests[accountID, default: 0] }
    func totalRequestCount() -> Int { requests.values.reduce(0, +) }
}

private enum TestStoreError: Error {
    case failed
}

private enum TestCredentialStoreError: Error {
    case deleteFailed
}

final class LocalAccountStateStoreTests: XCTestCase {
    func testRoundTripsThroughIsolatedUserDefaultsSuite() async throws {
        let suiteName = "com.tokenpulse.tests.local-state.\(UUID().uuidString)"
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let key = "isolated-account-states-\(UUID().uuidString)"
        let account = SubscriptionAccount(name: "持久化账号")
        let expected = [AccountQuotaState(
            account: account,
            snapshot: QuotaSnapshot(
                accountID: account.id,
                windows: [QuotaWindow(
                    id: "general.weekly",
                    name: "每周额度",
                    scope: nil,
                    usedPercentage: 25,
                    remainingCount: 75,
                    totalCount: 100,
                    resetsAt: Date(timeIntervalSince1970: 2_000)
                )],
                collectedAt: Date(timeIntervalSince1970: 1_000)
            ),
            lastFailure: .network
        )]

        let writer = LocalAccountStateStore(
            defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)),
            key: key
        )
        try await writer.save(expected)
        let reader = LocalAccountStateStore(
            defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)),
            key: key
        )

        let restored = try await reader.load()
        XCTAssertEqual(restored, expected)
        XCTAssertNil(UserDefaults.standard.data(forKey: key))
    }
}

@MainActor
final class APIKeyScopeRegressionTests: XCTestCase {
    func testLegacyAPIKeyEnvelopeGetsActualIdentityIgnoringClaimedAndUnrelatedWebMetadata() throws {
        for provider in [Provider.deepSeek, .poe, .elevenLabs, .vercelAIGateway, .zai, .openCodeGo] {
            let first = ProviderCredentialEnvelope(provider: provider, kind: .apiKey, accessToken: "synthetic-A")
            let oldIdentity = try XCTUnwrap(first.sourceCredentialIdentity)
            var second = first
            second.accessToken = "synthetic-B"
            second.metadata["sourceCredentialFingerprint"] = oldIdentity
            second.metadata["webSessionFormat"] = "v1"
            XCTAssertNotNil(second.sourceCredentialIdentity)
            XCTAssertNotEqual(second.sourceCredentialIdentity, oldIdentity)
            second.metadata = [:]
            let restored = try ProviderCredentialEnvelope.decode(second.encoded(), expectedProvider: provider)
            XCTAssertEqual(restored.sourceCredentialIdentity, second.sourceCredentialIdentity)
            XCTAssertNotEqual(restored.sourceCredentialIdentity, oldIdentity)
        }
    }

    func testPublishedKeyFingerprintFormatsRemainCompatibleAndDedicatedScopesWin() throws {
        for provider in [Provider.synthetic, .v2ex, .xKiro, .zenMux] {
            let envelope = ProviderCredentialEnvelope(provider: provider, kind: .apiKey, accessToken: "synthetic-key",
                                                       metadata: ["sourceCredentialFingerprint": "false-claim"])
            XCTAssertEqual(envelope.sourceCredentialIdentity, envelope.apiKeySourceFingerprint)
            XCTAssertNotEqual(envelope.sourceCredentialIdentity, "false-claim")
        }
        for provider in [Provider.factory, .devPass, .v0, .warp, .clinePass, .amp, .commandCode, .huggingFace] {
            let envelope = ProviderCredentialEnvelope(provider: provider, kind: .apiKey, accessToken: "synthetic-key")
            XCTAssertEqual(envelope.sourceCredentialIdentity, try KeyQuotaRequest.fingerprint(provider: provider, key: envelope.accessToken))
        }
        let gateway = try GatewayCredentials.make(provider: .newAPI, key: "synthetic-key", server: "https://one.example")
        var moved = gateway
        moved.metadata["serverAddress"] = "https://two.example"
        moved.metadata["sourceCredentialFingerprint"] = gateway.sourceCredentialIdentity
        moved.metadata["webSessionFormat"] = "v1"
        XCTAssertEqual(moved.sourceCredentialIdentity, moved.gatewayIdentity)
        XCTAssertNotEqual(moved.sourceCredentialIdentity, gateway.sourceCredentialIdentity)
        let china = ProviderCredentialEnvelope(provider: .moonshot, kind: .apiKey, accessToken: "synthetic-key", metadata: ["region": "china"])
        var international = china
        international.metadata["region"] = "international"
        XCTAssertEqual(china.sourceCredentialIdentity, china.regionalIdentity)
        XCTAssertEqual(international.sourceCredentialIdentity, international.regionalIdentity)
        XCTAssertNotEqual(china.sourceCredentialIdentity, international.sourceCredentialIdentity)
    }

    func testLegalWebAndCompositeCredentialsRetainDedicatedScopePriority() throws {
        let web = try WebProviderSession.credential(provider: .raycastAI, origin: "https://www.raycast.com", accountID: UUID(),
                                                     accessToken: "__raycast_session=synthetic", metadata: ["workspaceID": "one"])
        XCTAssertEqual(web.sourceCredentialIdentity, try WebProviderSession.fingerprint(web))
        var otherWorkspace = web
        otherWorkspace.metadata["workspaceID"] = "two"
        XCTAssertEqual(otherWorkspace.sourceCredentialIdentity, try WebProviderSession.fingerprint(otherWorkspace))
        XCTAssertNotEqual(web.sourceCredentialIdentity, otherWorkspace.sourceCredentialIdentity)
        let ibm = try IBMBobCredential("apikey:synthetic-key").envelope()
        XCTAssertEqual(ibm.sourceCredentialIdentity, try IBMBobCredential(envelope: ibm).fingerprint)
        let xai = try XAIManagementCredential("team-one:synthetic-key").envelope()
        XCTAssertEqual(xai.sourceCredentialIdentity, try XAIManagementCredential(envelope: xai).fingerprint)
        let volc = try VolcengineAccessKeys("synthetic-AK:synthetic-SK").envelope()
        XCTAssertEqual(volc.sourceCredentialIdentity, try VolcengineAccessKeys(volc.accessToken).fingerprint)
    }

    func testChangedKeyFailureClearsOldCacheAndRejectsLaterOldCloudSnapshot() async throws {
        for provider in [Provider.deepSeek, .poe, .elevenLabs] {
            let id = UUID()
            let old = ProviderCredentialEnvelope(provider: provider, kind: .apiKey, accessToken: "synthetic-A")
            let snapshot = QuotaSnapshot(accountID: id, windows: [
                QuotaWindow(id: "fixture", name: "Fixture", scope: nil, usedPercentage: nil, remainingCount: nil, totalCount: nil,
                            resetsAt: nil, wallet: WalletBalance(currency: "USD", total: 12))
            ], collectedAt: Date(timeIntervalSince1970: 100))
            let configurations = APIKeyScopeConfigurations()
            let client = StubQuotaClient(results: [id: [.success(snapshot), .failure(.network)]])
            let monitor = QuotaMonitor(accountStore: MemoryAccountStore(), credentialStore: MemoryCredentialStore(), quotaClient: client,
                                       configurationStore: configurations)
            await monitor.addAccount(name: "Synthetic", credential: try old.encoded(), provider: provider, accountID: id)
            let previous = try XCTUnwrap(monitor.states.first)
            let previousConfiguration = try XCTUnwrap(monitor.configuration(for: id))
            var replacement = old
            replacement.accessToken = "synthetic-B"
            replacement.metadata["sourceCredentialFingerprint"] = old.sourceCredentialIdentity
            replacement.metadata["webSessionFormat"] = "v1"
            await monitor.replaceCredential(try replacement.encoded(), accountID: id)
            XCTAssertNil(monitor.states[0].snapshot)
            XCTAssertEqual(monitor.states[0].lastFailure, .network)
            XCTAssertNotEqual(monitor.configuration(for: id)?.credentialIdentity, previousConfiguration.credentialIdentity)
            var stale = previous
            if let reading = stale.snapshot {
                stale.snapshot = QuotaSnapshot(accountID: id, windows: reading.windows, collectedAt: .distantFuture,
                                               sourceCredentialFingerprint: reading.sourceCredentialFingerprint)
            }
            await monitor.mergeSynchronized(configurations: [previousConfiguration], states: [stale])
            XCTAssertNil(monitor.states[0].snapshot)
            XCTAssertEqual(monitor.configuration(for: id)?.credentialIdentity, replacement.sourceCredentialIdentity)
        }
    }

    func testSameKeyFailureRetainsCorrectScopedSnapshot() async throws {
        let id = UUID()
        let envelope = ProviderCredentialEnvelope(provider: .deepSeek, kind: .apiKey, accessToken: "synthetic-key")
        let snapshot = QuotaSnapshot(accountID: id, windows: [], collectedAt: Date(timeIntervalSince1970: 100))
        let monitor = QuotaMonitor(accountStore: MemoryAccountStore(), credentialStore: MemoryCredentialStore(),
                                   quotaClient: StubQuotaClient(results: [id: [.success(snapshot), .failure(.network)]]),
                                   configurationStore: APIKeyScopeConfigurations())
        await monitor.addAccount(name: "Synthetic", credential: try envelope.encoded(), provider: .deepSeek, accountID: id)
        let previous = monitor.states[0].snapshot
        await monitor.refresh(accountID: id)
        XCTAssertEqual(monitor.states[0].snapshot, previous)
        XCTAssertEqual(monitor.states[0].lastFailure, .network)
    }
}

private actor APIKeyScopeConfigurations: AccountConfigurationStoring {
    private var values: [AccountConfiguration] = []
    func load() -> [AccountConfiguration] { values }
    func save(_ values: [AccountConfiguration]) { self.values = values }
}

@MainActor
final class MiniMaxRawKeyScopeRegressionTests: XCTestCase {
    func testRawKeyReplacementFailureRejectsOldCacheAndCloudButKeepsRawContract() async throws {
        let id = UUID()
        let accounts = MemoryAccountStore()
        let keys = MemoryCredentialStore()
        let configurations = APIKeyScopeConfigurations()
        let snapshot = QuotaSnapshot(accountID: id, windows: [], collectedAt: Date(timeIntervalSince1970: 100))
        let client = StubQuotaClient(results: [id: [.success(snapshot), .failure(.network)]])
        let monitor = QuotaMonitor(accountStore: accounts, credentialStore: keys, quotaClient: client, configurationStore: configurations)
        await monitor.addAccount(name: "Synthetic raw", credential: "raw-synthetic-A", provider: .miniMaxChina, accountID: id)
        let previous = monitor.states[0]
        let configuration = try XCTUnwrap(monitor.configuration(for: id))
        let firstStored = await keys.credential(for: id)
        let firstSent = await client.receivedCredential(for: id)
        XCTAssertEqual(firstStored, "raw-synthetic-A")
        XCTAssertEqual(firstSent, "raw-synthetic-A")
        await monitor.replaceCredential("raw-synthetic-B", accountID: id)
        XCTAssertNil(monitor.states[0].snapshot)
        XCTAssertEqual(monitor.states[0].lastFailure, .network)
        let secondStored = await keys.credential(for: id)
        let secondSent = await client.receivedCredential(for: id)
        XCTAssertEqual(secondStored, "raw-synthetic-B")
        XCTAssertEqual(secondSent, "raw-synthetic-B")
        var stale = previous
        stale.snapshot = QuotaSnapshot(accountID: id, windows: [], collectedAt: .distantFuture,
                                       sourceCredentialFingerprint: previous.snapshot?.sourceCredentialFingerprint)
        await monitor.mergeSynchronized(configurations: [configuration], states: [stale])
        XCTAssertNil(monitor.states[0].snapshot)
        let reopened = QuotaMonitor(accountStore: accounts, credentialStore: keys, quotaClient: client, configurationStore: configurations)
        await reopened.start(refresh: false)
        XCTAssertNil(reopened.states[0].snapshot)
        XCTAssertEqual(reopened.configuration(for: id)?.credentialIdentity, monitor.configuration(for: id)?.credentialIdentity)
    }

    func testMiniMaxDemoRawValueRemainsUnscopedAndCanRefresh() async throws {
        let id = UUID()
        let initial = QuotaSnapshot(accountID: id, windows: [], collectedAt: Date(timeIntervalSince1970: 100))
        let fresh = QuotaSnapshot(accountID: id, windows: [], collectedAt: Date(timeIntervalSince1970: 200))
        let keys = MemoryCredentialStore()
        let client = StubQuotaClient(results: [id: [.success(initial), .success(fresh)]])
        let monitor = QuotaMonitor(accountStore: MemoryAccountStore(), credentialStore: keys, quotaClient: client,
                                   configurationStore: APIKeyScopeConfigurations())
        await monitor.addAccount(name: "Demo", credential: "demo", provider: .miniMaxChina, accountID: id)
        XCTAssertNil(monitor.configuration(for: id)?.credentialIdentity)
        await monitor.replaceCredential("demo", accountID: id)
        XCTAssertEqual(monitor.states[0].snapshot, fresh)
        XCTAssertNil(monitor.states[0].lastFailure)
        let sent = await client.receivedCredential(for: id)
        XCTAssertEqual(sent, "demo")
    }
}

extension QuotaMonitorTests {
    func testBilingualAPIKeyAccountsKeepNamesCredentialsAndGatewayScopeOnSave() async throws {
        for language in ["zh-Hans", "en"] {
            try await L10n.withLanguage(language) {
                for provider in [Provider.miniMaxChina, .newAPI] {
                    let id = UUID()
                    let name = "我的 work 🌙 · \(provider.rawValue)"
                    let credential = try ProviderAuthenticationController().credential(
                        provider: provider, apiKey: " synthetic-fixture ", serverAddress: "https://relay.example/prefix/v1/")
                    let snapshot = QuotaSnapshot(accountID: id, windows: [], collectedAt: Date(timeIntervalSince1970: 100))
                    let states = MemoryAccountStore()
                    let keys = MemoryCredentialStore()
                    let client = StubQuotaClient(results: [id: [.success(snapshot)]])
                    let monitor = QuotaMonitor(accountStore: states, credentialStore: keys, quotaClient: client)
                    await monitor.addAccount(name: name, credential: credential, provider: provider, accountID: id)
                    let account = try XCTUnwrap(monitor.states.first?.account)
                    XCTAssertEqual(account.id, id)
                    XCTAssertEqual(account.name, name)
                    XCTAssertEqual(account.provider, provider)
                    XCTAssertEqual(monitor.states.first?.snapshot?.accountID, id)
                    let stored = await keys.credential(for: id)
                    let sent = await client.receivedCredential(for: id)
                    XCTAssertEqual(stored, credential)
                    XCTAssertEqual(sent, credential)
                    // Presentation follows language; persisted inputs and provider scopes remain unchanged.
                    XCTAssertEqual(provider.displayName(language: language), provider == .newAPI ? "New API" : language == "en" ? "MiniMax China" : "MiniMax 国内版")
                    if provider == .newAPI {
                        XCTAssertEqual(monitor.configuration(for: id)?.serverAddress, "https://relay.example/prefix")
                        let envelope = try ProviderCredentialEnvelope.decode(credential, expectedProvider: provider)
                        XCTAssertEqual(envelope.accessToken, "synthetic-fixture")
                    } else {
                        XCTAssertEqual(credential, "synthetic-fixture")
                }
                let reopened = QuotaMonitor(accountStore: states, credentialStore: keys, quotaClient: client)
                await reopened.start(refresh: false)
                XCTAssertEqual(reopened.states.first?.account, account)
                }
            }
        }
    }

    func testBilingualAPIKeySaveFailureRollsBackDirectAndGatewayAccountsWithoutQuery() async throws {
        for language in ["zh-Hans", "en"] {
            try await L10n.withLanguage(language) {
                for provider in [Provider.miniMaxChina, .newAPI] {
                    let id = UUID()
                    let credential = try ProviderAuthenticationController().credential(
                        provider: provider, apiKey: "synthetic-fixture", serverAddress: "https://relay.example/v1")
                    let keys = MemoryCredentialStore()
                    let client = StubQuotaClient()
                    let monitor = QuotaMonitor(accountStore: MemoryAccountStore(saveError: TestStoreError.failed),
                                               credentialStore: keys, quotaClient: client)
                    await monitor.addAccount(name: "保存失败 fixture", credential: credential, provider: provider, accountID: id)
                    XCTAssertTrue(monitor.states.isEmpty)
                    let stored = await keys.credential(for: id)
                    let requests = await client.totalRequestCount()
                    XCTAssertNil(stored)
                    XCTAssertEqual(requests, 0)
                    XCTAssertEqual(monitor.storageMessage, L10n.text("无法安全保存账号"))
                    XCTAssertEqual(L10n.text("账号未保存，请重试。", language: language),
                                   language == "en" ? "The account was not saved. Please try again." : "账号未保存，请重试。")
                }
            }
        }
        XCTAssertThrowsError(try ProviderAuthenticationController().credential(provider: .miniMaxChina, apiKey: "  "))
        XCTAssertThrowsError(try ProviderAuthenticationController().credential(provider: .newAPI, apiKey: "fixture", serverAddress: "https://user:password@relay.example"))
    }
}
