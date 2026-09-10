import Combine
import XCTest
@testable import TokenPulse

@MainActor
final class AccountConfigurationTests: XCTestCase {
    func testStartupFinishesInterruptedDeletion() async throws {
        let states = ConfigurationStateStore()
        let configurations = ConfigurationStore()
        let credentials = ConfigurationCredentials()
        let account = SubscriptionAccount(name: "Deleted before exit")
        var deleted = AccountConfiguration(account: account)
        deleted.deletedAt = Date()
        try await configurations.save([deleted])
        await states.save([AccountQuotaState(account: account)])
        await credentials.save("fixture", for: account.id)
        let monitor = QuotaMonitor(accountStore: states, credentialStore: credentials,
                                   quotaClient: OfflineClient(), configurationStore: configurations)

        await monitor.start(refresh: false)

        XCTAssertTrue(monitor.states.isEmpty)
        XCTAssertTrue(monitor.configurations.isEmpty)
        let saved = await states.load()
        XCTAssertTrue(saved.isEmpty)
        let credential = await credentials.credential(for: account.id)
        XCTAssertNil(credential)
    }

    func testDeletionPersistsAndStaleSyncCannotRestoreAccount() async throws {
        let states = ConfigurationStateStore()
        let configurations = ConfigurationStore()
        let credentials = ConfigurationCredentials()
        let monitor = QuotaMonitor(accountStore: states, credentialStore: credentials,
                                   quotaClient: OfflineClient(), configurationStore: configurations)
        await monitor.start(refresh: false)
        await monitor.addAccount(name: "MiniMax A", credential: "first")
        await monitor.addAccount(name: "MiniMax B", credential: "second")
        let deleted = try XCTUnwrap(monitor.states.first)
        let kept = try XCTUnwrap(monitor.states.last)
        var staleConfigurations = monitor.configurations
        staleConfigurations[0].modifiedAt = .distantFuture
        var publishedIDs: [UUID] = []
        monitor.onChange = { publishedIDs = monitor.states.map(\.id) }

        let succeeded = await monitor.deleteAccount(accountID: deleted.id)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(publishedIDs, [kept.id])
        XCTAssertEqual(monitor.configurations.map(\.id), [kept.id])
        let removedCredential = await credentials.credential(for: deleted.id)
        let keptCredential = await credentials.credential(for: kept.id)
        XCTAssertNil(removedCredential)
        XCTAssertEqual(keptCredential, "second")
        await monitor.mergeSynchronized(configurations: staleConfigurations, states: [deleted, kept])
        let restored = QuotaMonitor(accountStore: states, credentialStore: credentials,
                                    quotaClient: OfflineClient(), configurationStore: configurations)
        await restored.start(refresh: false)
        XCTAssertEqual(restored.states.map(\.id), [kept.id])
        XCTAssertEqual(restored.configurations.map(\.id), [kept.id])
        XCTAssertNotNil(restored.synchronizedConfigurations.first { $0.id == deleted.id }?.deletedAt)
    }

    func testRemoteDeletionRemovesLocalAccountAndCredential() async throws {
        let states = ConfigurationStateStore()
        let configurations = ConfigurationStore()
        let credentials = ConfigurationCredentials()
        let account = SubscriptionAccount(name: "Remote")
        await credentials.save("fixture", for: account.id)
        await states.save([AccountQuotaState(account: account)])
        let monitor = QuotaMonitor(accountStore: states, credentialStore: credentials,
                                   quotaClient: OfflineClient(), configurationStore: configurations)
        await monitor.start(refresh: false)
        var deleted = AccountConfiguration(account: account)
        deleted.deletedAt = Date()

        await monitor.mergeSynchronized(configurations: [deleted], states: [AccountQuotaState(account: account)])

        XCTAssertTrue(monitor.states.isEmpty)
        XCTAssertTrue(monitor.configurations.isEmpty)
        let credential = await credentials.credential(for: account.id)
        XCTAssertNil(credential)
        let saved = await states.load()
        XCTAssertTrue(saved.isEmpty)
    }

    func testDeletionSaveFailureKeepsAccountAndCredential() async throws {
        let states = ConfigurationStateStore()
        let configurations = ConfigurationStore()
        let credentials = ConfigurationCredentials()
        let monitor = QuotaMonitor(accountStore: states, credentialStore: credentials,
                                   quotaClient: OfflineClient(), configurationStore: configurations)
        await monitor.start(refresh: false)
        await monitor.addAccount(name: "Keep", credential: "fixture")
        let account = try XCTUnwrap(monitor.states.first)
        await configurations.failSaves()

        let succeeded = await monitor.deleteAccount(accountID: account.id)

        XCTAssertFalse(succeeded)
        XCTAssertEqual(monitor.states, [account])
        XCTAssertNotNil(monitor.configuration(for: account.id))
        let credential = await credentials.credential(for: account.id)
        XCTAssertEqual(credential, "fixture")
        XCTAssertNotNil(monitor.storageMessage)
    }

    func testRefreshFinishingAfterDeletionCannotRestoreDataOrCredential() async throws {
        let states = ConfigurationStateStore()
        let credentials = ConfigurationCredentials()
        let account = SubscriptionAccount(name: "Refreshing")
        await states.save([AccountQuotaState(account: account)])
        await credentials.save("fixture", for: account.id)
        let client = SuspendedClient(credentials: credentials)
        let monitor = QuotaMonitor(accountStore: states, credentialStore: credentials,
                                   quotaClient: client, configurationStore: ConfigurationStore())
        await monitor.start(refresh: false)
        let refresh = Task { await monitor.refresh(accountID: account.id) }
        await client.waitUntilRequested()

        await monitor.deleteAccount(accountID: account.id)
        await client.finish()
        await refresh.value

        XCTAssertTrue(monitor.states.isEmpty)
        let credential = await credentials.credential(for: account.id)
        XCTAssertNil(credential)
        let saved = await states.load()
        XCTAssertTrue(saved.isEmpty)
    }

    func testReorderPublishesOnlyCompleteAccountLists() async {
        let store = ConfigurationStateStore()
        let accounts = (0..<4).map { SubscriptionAccount(name: "Account \($0)") }
        await store.save(accounts.map { AccountQuotaState(account: $0) })
        let monitor = QuotaMonitor(accountStore: store, credentialStore: ConfigurationCredentials(),
                                   quotaClient: OfflineClient())
        await monitor.start(refresh: false)
        var publishedIDs: [[UUID]] = []
        let subscription = monitor.$states.dropFirst().sink { publishedIDs.append($0.map(\.id)) }

        monitor.reorderAccounts(from: IndexSet([0, 2]), to: 4)

        XCTAssertEqual(monitor.states.map(\.id), [accounts[1].id, accounts[3].id, accounts[0].id, accounts[2].id])
        XCTAssertEqual(publishedIDs.count, 1)
        for ids in publishedIDs { XCTAssertEqual(Set(ids), Set(accounts.map(\.id))) }
        withExtendedLifetime(subscription) {}
    }

    func testAccountSettingsSurviveReconstruction() async throws {
        let states = ConfigurationStateStore()
        let configurations = ConfigurationStore()
        let credentials = ConfigurationCredentials()
        let monitor = QuotaMonitor(accountStore: states, credentialStore: credentials,
                                   quotaClient: OfflineClient(), configurationStore: configurations)
        await monitor.start()
        await monitor.addAccount(name: "MiniMax", credential: "fixture")
        await monitor.addAccount(name: "Z.ai", credential: "fixture", provider: .zai)
        monitor.reorderAccounts(from: IndexSet(integer: 1), to: 0)
        await monitor.persistAccountOrder()
        let account = try XCTUnwrap(monitor.configurations.last)
        var settings = account.reminders
        settings.quotaAlertsEnabled = false
        await monitor.updateReminders(settings, accountID: account.id)

        let restored = QuotaMonitor(accountStore: states, credentialStore: credentials,
                                    quotaClient: OfflineClient(), configurationStore: configurations)
        await restored.start()
        XCTAssertEqual(restored.states.count, 2)
        XCTAssertEqual(restored.states.map(\.account.name), ["Z.ai", "MiniMax"])
        XCTAssertEqual(restored.configurations.map(\.account.name), ["Z.ai", "MiniMax"])
        XCTAssertEqual(restored.configuration(for: account.id)?.reminders.quotaAlertsEnabled, false)
        XCTAssertEqual(restored.configuration(for: account.id)?.reminders.resetRemindersEnabled, true)
    }

    func testSyncKeepsCollectionTimeAndDoesNotRunFreshResultHandler() async throws {
        let store = ConfigurationStateStore()
        let monitor = QuotaMonitor(accountStore: store, credentialStore: ConfigurationCredentials(),
                                   quotaClient: OfflineClient())
        await monitor.start()
        var freshCount = 0
        monitor.onFreshSnapshot = { _, _ in freshCount += 1 }
        let account = SubscriptionAccount(name: "同步账号")
        let collectedAt = Date(timeIntervalSince1970: 100)
        let snapshot = QuotaSnapshot(accountID: account.id, windows: [], collectedAt: collectedAt)
        await monitor.mergeSynchronized(configurations: [AccountConfiguration(account: account)],
                                        states: [AccountQuotaState(account: account, snapshot: snapshot)])
        XCTAssertEqual(monitor.states.first?.snapshot?.collectedAt, collectedAt)
        XCTAssertEqual(freshCount, 0)
        let older = QuotaSnapshot(accountID: account.id, windows: [], collectedAt: .distantPast)
        await monitor.mergeSynchronized(configurations: [], states: [AccountQuotaState(account: account, snapshot: older)])
        XCTAssertEqual(monitor.states.first?.snapshot, snapshot)
    }

    func testCrossingResetTimeOnlyChangesFreshness() {
        let window = QuotaWindow(id: "short", name: "短周期", scope: nil, usedPercentage: 95,
                                 remainingCount: 5, totalCount: 100,
                                 resetsAt: Date(timeIntervalSince1970: 200))
        XCTAssertFalse(window.needsUpdate(at: Date(timeIntervalSince1970: 199)))
        XCTAssertTrue(window.needsUpdate(at: Date(timeIntervalSince1970: 201)))
        XCTAssertEqual(window.usedPercentage, 95)
    }
}

private actor ConfigurationStore: AccountConfigurationStoring {
    private var items: [AccountConfiguration] = []
    private var shouldFail = false
    func load() -> [AccountConfiguration] { items }
    func failSaves() { shouldFail = true }
    func save(_ configurations: [AccountConfiguration]) throws {
        if shouldFail { throw CocoaError(.fileWriteUnknown) }
        items = configurations
    }
}

private actor ConfigurationStateStore: AccountStateStoring {
    private var items: [AccountQuotaState] = []
    func load() -> [AccountQuotaState] { items }
    func save(_ states: [AccountQuotaState]) { items = states }
}

private actor ConfigurationCredentials: CredentialStoring {
    private var items: [UUID: String] = [:]
    func save(_ credential: String, for accountID: UUID) { items[accountID] = credential }
    func credential(for accountID: UUID) -> String? { items[accountID] }
    func deleteCredential(for accountID: UUID) { items[accountID] = nil }
}

private struct OfflineClient: QuotaQuerying {
    func quota(for accountID: UUID, credential: String) async throws -> QuotaSnapshot { throw RefreshFailure.network }
}

private actor SuspendedClient: QuotaQuerying {
    let credentials: ConfigurationCredentials
    private var response: CheckedContinuation<Void, Never>?
    private var request: CheckedContinuation<Void, Never>?

    init(credentials: ConfigurationCredentials) { self.credentials = credentials }

    func waitUntilRequested() async {
        if response != nil { return }
        await withCheckedContinuation { request = $0 }
    }

    func finish() { response?.resume() }

    func quota(for accountID: UUID, credential: String) async -> QuotaSnapshot {
        await withCheckedContinuation {
            response = $0
            request?.resume()
        }
        await credentials.save("renewed credential", for: accountID)
        return QuotaSnapshot(accountID: accountID, windows: [], collectedAt: Date())
    }
}
