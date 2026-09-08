import XCTest
@testable import TokenPulse

@MainActor
final class QuotaMonitorTests: XCTestCase {
    func testRefreshKeepsTwoAccountsIsolatedAndPersistsSuccessfulSnapshots() async throws {
        let first = SubscriptionAccount(name: "工作账号")
        let second = SubscriptionAccount(name: "个人账号")
        let store = MemoryAccountStore(initial: [
            AccountQuotaState(account: first, snapshot: nil, lastFailure: nil),
            AccountQuotaState(account: second, snapshot: nil, lastFailure: nil),
        ])
        let credentials = MemoryCredentialStore(values: [first.id: "first-key", second.id: "second-key"])
        let firstSnapshot = snapshot(accountID: first.id, used: 20, collectedAt: Date(timeIntervalSince1970: 100))
        let secondSnapshot = snapshot(accountID: second.id, used: 75, collectedAt: Date(timeIntervalSince1970: 200))
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
        let oldSnapshot = snapshot(accountID: account.id, used: 42, collectedAt: Date(timeIntervalSince1970: 100))
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
        let secondSnapshot = snapshot(accountID: account.id, used: 30, collectedAt: Date(timeIntervalSince1970: 200))
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
        XCTAssertEqual(monitor.storageMessage, "无法安全保存账号")
    }

    func testCancelledRefreshDoesNotOverwriteOrPersistOldState() async throws {
        let account = SubscriptionAccount(name: "取消刷新账号")
        let oldSnapshot = snapshot(accountID: account.id, used: 42, collectedAt: Date(timeIntervalSince1970: 100))
        let oldState = AccountQuotaState(account: account, snapshot: oldSnapshot, lastFailure: .rateLimited)
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
        let store = MemoryAccountStore(saveError: TestStoreError.failed)
        let credentials = MemoryCredentialStore(deleteFailuresRemaining: 2)
        let client = StubQuotaClient(defaultResult: .failure(.server))
        let monitor = QuotaMonitor(accountStore: store, credentialStore: credentials, quotaClient: client)

        await monitor.addAccount(name: "双重失败", credential: "placeholder-key")

        let retainedCredentialCount = await credentials.credentialCount()
        XCTAssertTrue(monitor.states.isEmpty)
        XCTAssertTrue(monitor.hasPendingCredentialCleanup)
        XCTAssertEqual(retainedCredentialCount, 1)
        XCTAssertEqual(monitor.storageMessage, "账号未保存，凭证清理失败，请重试。")

        await monitor.retryPendingCredentialCleanup()

        let retainedAfterRetryCount = await credentials.credentialCount()
        XCTAssertTrue(monitor.hasPendingCredentialCleanup)
        XCTAssertEqual(retainedAfterRetryCount, 1)
        XCTAssertEqual(monitor.storageMessage, "凭证清理仍失败，请重试。")

        await monitor.retryPendingCredentialCleanup()

        let cleanedCredentialCount = await credentials.credentialCount()
        XCTAssertFalse(monitor.hasPendingCredentialCleanup)
        XCTAssertEqual(cleanedCredentialCount, 0)
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
