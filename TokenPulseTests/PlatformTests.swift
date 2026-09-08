import Security
import XCTest
@testable import TokenPulse

final class PlatformTests: XCTestCase {
    func testAvailableResetCountReachesWidgetStorage() async throws {
        let suite = "com.tokenpulse.tests.reset-count.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = WidgetSnapshotStore(defaults: UserDefaults(suiteName: suite), key: "reset-count")
        let account = SubscriptionAccount(name: "测试", provider: .codex)
        let snapshot = QuotaSnapshot(accountID: account.id, windows: [], collectedAt: Date(), remainingResetCount: 3)
        try await store.save(states: [AccountQuotaState(account: account, snapshot: snapshot)])
        let loaded = await store.load()
        XCTAssertEqual(loaded.first?.remainingResetCount, 3)
        XCTAssertEqual(QuotaFormatting.remainingResets(0), "0 次")
        XCTAssertEqual(QuotaFormatting.remainingResets(nil), "未提供")
    }

    func testWidgetCombinesGLMPeriodsAndUsesWeeklyOnlyForCodexAndMiniMax() {
        let weekly = QuotaWindow(id: "general.weekly", name: "每周额度", scope: nil,
                                 usedPercentage: 70, remainingCount: nil, totalCount: nil, resetsAt: nil)
        let short = QuotaWindow(id: "general.interval", name: "5 小时额度", scope: nil,
                                usedPercentage: 20, remainingCount: nil, totalCount: nil, resetsAt: nil)
        for (provider, expected) in [(Provider.zai, [70.0, 20.0]), (.codex, [70.0]), (.miniMaxChina, [70.0])] {
            let snapshot = WidgetAccountSnapshot(account: SubscriptionAccount(name: "测试", provider: provider),
                                                 windows: [short, weekly], collectedAt: Date(), lastFailure: nil)
            XCTAssertEqual(snapshot.displayMetrics.compactMap { $0.window?.usedPercentage }, expected)
            if provider == .miniMaxChina {
                XCTAssertFalse(snapshot.displayMetrics[0].showsReset)
                XCTAssertEqual(snapshot.homeScreenMetrics.map(\.title), ["5 小时已用"])
                XCTAssertEqual(snapshot.homeScreenMetrics.first?.window?.usedPercentage, 20)
                XCTAssertFalse(snapshot.homeScreenMetrics[0].showsReset)
            }
        }
    }

    func testWidgetDoesNotRelabelFiveHourUsageAsMissingWeeklyQuota() {
        let short = QuotaWindow(id: "general.interval", name: "5 小时额度", scope: nil,
                                usedPercentage: 20, remainingCount: nil, totalCount: nil, resetsAt: nil)
        let snapshot = WidgetAccountSnapshot(account: SubscriptionAccount(name: "测试", provider: .miniMaxChina),
                                             windows: [short], collectedAt: Date(), lastFailure: nil)
        XCTAssertEqual(snapshot.displayMetrics.count, 1)
        XCTAssertEqual(snapshot.displayMetrics[0].title, "每周已用")
        XCTAssertNil(snapshot.displayMetrics[0].window)
        XCTAssertEqual(snapshot.homeScreenMetrics.first?.window?.usedPercentage, 20)
        let weekly = QuotaWindow(id: "general.weekly", name: "每周额度", scope: nil,
                                 usedPercentage: 70, remainingCount: nil, totalCount: nil, resetsAt: nil)
        let weeklyOnly = WidgetAccountSnapshot(account: snapshot.account,
                                              windows: [weekly], collectedAt: Date(), lastFailure: nil)
        XCTAssertNil(weeklyOnly.homeScreenMetrics[0].window)
    }

    func testResetDateUsesChosenLocaleAndLocalTimeZone() throws {
        let date = Date(timeIntervalSince1970: 0)
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let taipei = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3600))
        let local = QuotaFormatting.resetDate(date, locale: Locale(identifier: "en_US"), timeZone: taipei)
        XCTAssertTrue(local.contains("8:00"))
        XCTAssertNotEqual(local, QuotaFormatting.resetDate(date, locale: Locale(identifier: "en_US"), timeZone: utc))
        XCTAssertNotEqual(local, QuotaFormatting.resetDate(date, locale: Locale(identifier: "zh_CN"), timeZone: taipei))
        XCTAssertEqual(QuotaFormatting.resetDate(nil), "未提供")
    }

    @MainActor
    func testSyncSettingsPersistAndDisabledSyncDoesNotRun() async throws {
        let suite = "com.tokenpulse.tests.sync.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = CloudSyncSettings(defaults: defaults)
        XCTAssertTrue(settings.isEnabled)
        settings.setEnabled(false)
        var requests = 0
        await settings.perform { requests += 1 }
        settings.received()
        XCTAssertEqual(requests, 0)
        XCTAssertNil(settings.lastRequestedAt)
        XCTAssertNil(settings.lastReceivedAt)
        XCTAssertFalse(CloudSyncSettings(defaults: defaults).isEnabled)
    }

    @MainActor
    func testSyncTimesOnlyAdvanceOnSuccessfulRequestOrReceivedUpdate() async throws {
        let suite = "com.tokenpulse.tests.sync.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = Date(timeIntervalSince1970: 100)
        let settings = CloudSyncSettings(defaults: defaults, now: { now })
        await settings.perform {}
        XCTAssertEqual(settings.lastRequestedAt, now)
        XCTAssertNil(settings.lastReceivedAt, "A submitted request is not a remote receipt")
        now = Date(timeIntervalSince1970: 200)
        await settings.perform { throw CloudSyncError.unavailable }
        XCTAssertEqual(settings.lastRequestedAt, Date(timeIntervalSince1970: 100))
        XCTAssertNotNil(settings.errorMessage)
        XCTAssertFalse(settings.isSyncing)
        settings.received()
        XCTAssertEqual(settings.lastReceivedAt, now)
        let restored = CloudSyncSettings(defaults: defaults)
        XCTAssertEqual(restored.lastRequestedAt, settings.lastRequestedAt)
        XCTAssertEqual(restored.lastReceivedAt, settings.lastReceivedAt)
        await settings.perform {}
        XCTAssertNil(settings.errorMessage)
        XCTAssertEqual(settings.lastRequestedAt, now)
    }

    @MainActor
    func testDuplicateRequestsAreIgnoredAndDisableDuringRequestDoesNotStampSuccess() async throws {
        let suite = "com.tokenpulse.tests.sync.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = CloudSyncSettings(defaults: defaults)
        var nestedCalls = 0
        await settings.perform {
            XCTAssertTrue(settings.isSyncing)
            await settings.perform { nestedCalls += 1 }
            settings.setEnabled(false)
        }
        XCTAssertEqual(nestedCalls, 0)
        XCTAssertNil(settings.lastRequestedAt)
        XCTAssertFalse(settings.isSyncing)
    }

    func testDisabledCredentialSyncOnlyUsesLocalItem() async throws {
        let fixture = KeychainFixture()
        defer { fixture.removeAll() }
        let store = SynchronizableCredentialStore(service: fixture.service, accessGroup: nil, syncEnabled: false)
        try await store.save("local-only", for: fixture.accountID)
        XCTAssertEqual(try fixture.read(synchronizable: false), "local-only")
        XCTAssertNil(try fixture.read(synchronizable: true))
        try fixture.add("cloud-item", synchronizable: true)
        let local = try await store.credential(for: fixture.accountID)
        XCTAssertEqual(local, "local-only")
        XCTAssertEqual(try fixture.read(synchronizable: true), "cloud-item")
    }

    func testNewerLocalCredentialWinsAndBackfillsSynchronizableItem() async throws {
        let fixture = KeychainFixture()
        defer { fixture.removeAll() }
        try fixture.add("old-synchronized", synchronizable: true)
        try await Task.sleep(for: .seconds(1.1))
        try fixture.add("new-local", synchronizable: false)

        let store = SynchronizableCredentialStore(
            service: fixture.service,
            accessGroup: nil
        )
        let value = try await store.credential(for: fixture.accountID)

        XCTAssertEqual(value, "new-local")
        XCTAssertEqual(try fixture.read(synchronizable: true), "new-local")
    }

    func testNewerSynchronizableCredentialWinsAndBackfillsLocalItem() async throws {
        let fixture = KeychainFixture()
        defer { fixture.removeAll() }
        try fixture.add("old-local", synchronizable: false)
        try await Task.sleep(for: .seconds(1.1))
        try fixture.add("new-synchronized", synchronizable: true)

        let store = SynchronizableCredentialStore(
            service: fixture.service,
            accessGroup: nil
        )
        let value = try await store.credential(for: fixture.accountID)

        XCTAssertEqual(value, "new-synchronized")
        XCTAssertEqual(try fixture.read(synchronizable: false), "new-synchronized")
    }

    func testCloudPayloadMergeKeepsNewestConfigurationAndSnapshot() {
        let account = SubscriptionAccount(name: "A", provider: .miniMaxChina)
        let oldConfiguration = AccountConfiguration(
            account: account,
            modifiedAt: Date(timeIntervalSince1970: 10)
        )
        let newConfiguration = AccountConfiguration(
            account: account,
            modifiedAt: Date(timeIntervalSince1970: 20)
        )
        let oldState = AccountQuotaState(
            account: account,
            snapshot: QuotaSnapshot(accountID: account.id, windows: [], collectedAt: Date(timeIntervalSince1970: 10))
        )
        let newState = AccountQuotaState(
            account: account,
            snapshot: QuotaSnapshot(accountID: account.id, windows: [], collectedAt: Date(timeIntervalSince1970: 20))
        )

        let merged = ICloudSyncRuntime.merge(
            PlatformAccountPayload(configurations: [oldConfiguration], states: [oldState], ledger: ReminderLedger()),
            PlatformAccountPayload(configurations: [newConfiguration], states: [newState], ledger: ReminderLedger())
        )

        XCTAssertEqual(merged.configurations, [newConfiguration])
        XCTAssertEqual(merged.states, [newState])
    }
}

private final class KeychainFixture {
    let service = "com.tokenpulse.tests.platform.\(UUID().uuidString)"
    let accountID = UUID()

    func add(_ credential: String, synchronizable: Bool) throws {
        var query = baseQuery(synchronizable: synchronizable)
        query[kSecValueData as String] = Data(credential.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecNotAvailable {
            throw XCTSkip("Synchronizable Keychain is unavailable in this test environment")
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func read(synchronizable: Bool) throws -> String? {
        var query = baseQuery(synchronizable: synchronizable)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { throw KeychainError(status: status) }
        return value
    }

    func removeAll() {
        for synchronizable in [true, false] {
            SecItemDelete(baseQuery(synchronizable: synchronizable) as CFDictionary)
        }
    }

    private func baseQuery(synchronizable: Bool) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
            kSecAttrSynchronizable as String: synchronizable,
        ]
    }
}
