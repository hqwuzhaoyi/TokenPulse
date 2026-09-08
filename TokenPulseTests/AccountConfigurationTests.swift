import XCTest
@testable import TokenPulse

@MainActor
final class AccountConfigurationTests: XCTestCase {
    func testFollowOrderAndSettingsSurviveReconstruction() async throws {
        let states = ConfigurationStateStore()
        let configurations = ConfigurationStore()
        let credentials = ConfigurationCredentials()
        let monitor = QuotaMonitor(accountStore: states, credentialStore: credentials,
                                   quotaClient: OfflineClient(), configurationStore: configurations)
        await monitor.start()
        await monitor.addAccount(name: "MiniMax", credential: "fixture")
        await monitor.addAccount(name: "Z.ai", credential: "fixture", provider: .zai)
        await monitor.reorderFollowed(from: IndexSet(integer: 1), to: 0)
        let first = try XCTUnwrap(monitor.followedAccounts.first)
        var settings = first.reminders
        settings.quotaAlertsEnabled = false
        await monitor.updateReminders(settings, accountID: first.id)
        await monitor.setFollowed(false, accountID: first.id)

        let restored = QuotaMonitor(accountStore: states, credentialStore: credentials,
                                    quotaClient: OfflineClient(), configurationStore: configurations)
        await restored.start()
        XCTAssertEqual(restored.states.count, 2)
        XCTAssertEqual(restored.followedAccounts.map(\.account.name), ["MiniMax"])
        XCTAssertEqual(restored.configuration(for: first.id)?.reminders.quotaAlertsEnabled, false)
        XCTAssertEqual(restored.configuration(for: first.id)?.reminders.resetRemindersEnabled, true)
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
    func load() -> [AccountConfiguration] { items }
    func save(_ configurations: [AccountConfiguration]) { items = configurations }
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
