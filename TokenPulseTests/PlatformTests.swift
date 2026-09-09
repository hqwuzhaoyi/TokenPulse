import Security
import XCTest
@testable import TokenPulse

final class PlatformTests: XCTestCase {
    func testExhaustedWindowHasConsistentAppAndWidgetPresentation() {
        let window = QuotaWindow(
            id: "opencode-go.weekly", name: "每周额度", scope: nil,
            period: .weekly, isExhausted: true, usedPercentage: 60,
            remainingCount: nil, totalCount: nil, resetsAt: nil
        )
        let metric = WidgetQuotaMetric(id: window.id, title: window.name, window: window)

        XCTAssertEqual(QuotaFormatting.usage(window), "已用尽")
        XCTAssertEqual(QuotaFormatting.effectiveUsedPercentage(window), 100)
        XCTAssertEqual(metric.valueText, "已用尽")
        XCTAssertEqual(metric.ringFraction, 1)
    }

    func testQuotaPolicyRoutesAccountAndAuxiliaryWindowsBySurface() {
        let fiveHour = QuotaWindow(
            id: "account.five-hour", name: "5 小时额度", scope: nil, period: .fiveHour,
            usedPercentage: 20, remainingCount: nil, totalCount: nil, resetsAt: nil
        )
        let weekly = QuotaWindow(
            id: "account.weekly", name: "每周额度", scope: nil, period: .weekly,
            usedPercentage: 70, remainingCount: nil, totalCount: nil, resetsAt: nil
        )
        let spark = QuotaWindow(
            id: "spark.five-hour", name: "5 小时额度", scope: "GPT-5.3-Codex-Spark", period: .fiveHour,
            usedPercentage: 10, remainingCount: nil, totalCount: nil, resetsAt: nil
        )
        let windows = [fiveHour, weekly, spark]

        XCTAssertEqual(
            QuotaPolicy.windows(windows, provider: .codex, plan: .plus, surface: .summary).map(\.id),
            ["account.five-hour", "account.weekly"]
        )
        XCTAssertEqual(
            QuotaPolicy.windows(windows, provider: .codex, plan: .pro, surface: .summary).map(\.id),
            ["account.weekly"]
        )
        XCTAssertEqual(
            QuotaPolicy.windows(windows, provider: .codex, plan: .pro, surface: .detail).map(\.id),
            ["account.weekly", "spark.five-hour"]
        )
        XCTAssertEqual(
            QuotaPolicy.windows(windows, provider: .codex, plan: .pro, surface: .notification).map(\.id),
            ["account.weekly"]
        )
        XCTAssertEqual(
            QuotaPolicy.windows(windows, provider: .codex, plan: .plus, surface: .notification).map(\.id),
            ["account.five-hour", "account.weekly"]
        )
        XCTAssertEqual(
            QuotaPolicy.windows(windows, provider: .claude, plan: nil, surface: .notification).map(\.id),
            windows.map(\.id)
        )
    }

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

    func testWidgetResetCountIsAccountLevelForCodexAndSuperGrokOnly() {
        func snapshot(_ provider: Provider, count: Int?) -> WidgetAccountSnapshot {
            WidgetAccountSnapshot(
                account: SubscriptionAccount(name: "测试", provider: provider),
                windows: [], collectedAt: nil, lastFailure: nil,
                remainingResetCount: count
            )
        }

        XCTAssertTrue(snapshot(.codex, count: 3).supportsManualResetCount)
        XCTAssertTrue(snapshot(.superGrok, count: nil).supportsManualResetCount)
        XCTAssertFalse(snapshot(.zai, count: 3).supportsManualResetCount)
        XCTAssertFalse(snapshot(.openCodeGo, count: nil).supportsManualResetCount)
        XCTAssertEqual(QuotaFormatting.remainingResets(3), "3 次")
        XCTAssertEqual(QuotaFormatting.remainingResets(nil), "未提供")
    }

    func testWatchWidgetSelectionPersistsAndClearsSelectedAccount() async throws {
        let suite = "com.tokenpulse.tests.watch-widget-selection.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WatchWidgetSelectionStore(suiteName: suite)
        let reader = WatchWidgetSelectionStore(suiteName: suite)
        let accountID = UUID()

        let initial = await store.load()
        XCTAssertNil(initial)
        await store.save(accountID)
        let saved = await reader.load()
        XCTAssertEqual(saved, accountID)
        await store.save(nil)
        let cleared = await store.load()
        XCTAssertNil(cleared)
    }

    func testWidgetUsesPlanSpecificCodexWindows() {
        let shortReset = Date(timeIntervalSince1970: 100)
        let weeklyReset = Date(timeIntervalSince1970: 200)
        let weekly = QuotaWindow(id: "general.weekly", name: "每周额度", scope: nil,
                                 period: .weekly,
                                 usedPercentage: 70, remainingCount: nil, totalCount: nil, resetsAt: weeklyReset)
        let short = QuotaWindow(id: "general.interval", name: "5 小时额度", scope: nil,
                                period: .fiveHour,
                                usedPercentage: 20, remainingCount: nil, totalCount: nil, resetsAt: shortReset)
        let account = SubscriptionAccount(name: "测试", provider: .codex)
        let plus = WidgetAccountSnapshot(account: account, windows: [short, weekly], collectedAt: Date(),
                                         lastFailure: nil, subscriptionPlan: .plus)
        let pro = WidgetAccountSnapshot(account: account, windows: [short, weekly], collectedAt: Date(),
                                        lastFailure: nil, subscriptionPlan: .pro)

        XCTAssertEqual(plus.displayMetrics.compactMap { $0.window?.usedPercentage }, [20, 70])
        XCTAssertEqual(plus.displayMetrics.compactMap { $0.window?.resetsAt }, [shortReset, weeklyReset])
        XCTAssertEqual(pro.displayMetrics.compactMap { $0.window?.usedPercentage }, [70])
        XCTAssertEqual(pro.displayMetrics.compactMap { $0.window?.resetsAt }, [weeklyReset])

        let monthly = QuotaWindow(
            id: "opencode-go.monthly", name: "每月额度", scope: nil, period: .monthly,
            usedPercentage: 35, remainingCount: nil, totalCount: nil, resetsAt: nil
        )
        let openCode = WidgetAccountSnapshot(
            account: SubscriptionAccount(name: "OpenCode", provider: .openCodeGo),
            windows: [short, weekly, monthly], collectedAt: Date(), lastFailure: nil
        )
        XCTAssertEqual(openCode.displayMetrics.map(\.title), ["5 小时额度", "每周额度", "每月额度"])
        XCTAssertEqual(openCode.ringMetrics.map(\.title), ["5 小时额度", "每周额度", "每月额度"])
        XCTAssertEqual(plus.ringMetrics.count, 2)

        let fable = QuotaWindow(
            id: "claude.weekly.fable", name: "每周额度", scope: "Fable", period: .weekly,
            usedPercentage: 15, remainingCount: nil, totalCount: nil, resetsAt: nil
        )
        let claude = WidgetAccountSnapshot(
            account: SubscriptionAccount(name: "Claude", provider: .claude),
            windows: [short, weekly, fable], collectedAt: Date(), lastFailure: nil
        )
        XCTAssertEqual(claude.ringMetrics.map(\.title), ["5 小时额度", "每周额度", "Fable 每周额度"])

        for (provider, expected) in [(Provider.zai, [70.0, 20.0]), (.miniMaxChina, [20.0])] {
            let snapshot = WidgetAccountSnapshot(account: SubscriptionAccount(name: "测试", provider: provider),
                                                 windows: [short, weekly], collectedAt: Date(), lastFailure: nil)
            XCTAssertEqual(snapshot.displayMetrics.compactMap { $0.window?.usedPercentage }, expected)
            if provider == .miniMaxChina {
                XCTAssertEqual(snapshot.displayMetrics.map(\.title), ["5 小时已用"])
                XCTAssertEqual(snapshot.homeScreenMetrics.map(\.title), ["5 小时已用"])
                XCTAssertEqual(snapshot.homeScreenMetrics.first?.window?.usedPercentage, 20)
                XCTAssertEqual(snapshot.homeScreenMetrics.first?.window?.resetsAt, shortReset)
            } else {
                XCTAssertEqual(snapshot.displayMetrics.compactMap { $0.window?.resetsAt }, [weeklyReset, shortReset])
            }
        }
    }

    func testWidgetDoesNotRelabelFiveHourUsageAsMissingWeeklyQuota() {
        let short = QuotaWindow(id: "general.interval", name: "5 小时额度", scope: nil,
                                period: .fiveHour,
                                usedPercentage: 20, remainingCount: nil, totalCount: nil, resetsAt: nil)
        let snapshot = WidgetAccountSnapshot(account: SubscriptionAccount(name: "测试", provider: .miniMaxChina),
                                             windows: [short], collectedAt: Date(), lastFailure: nil)
        XCTAssertEqual(snapshot.displayMetrics.count, 1)
        XCTAssertEqual(snapshot.displayMetrics[0].title, "5 小时已用")
        XCTAssertEqual(snapshot.displayMetrics[0].window?.usedPercentage, 20)
        XCTAssertEqual(snapshot.homeScreenMetrics.first?.window?.usedPercentage, 20)
        let weekly = QuotaWindow(id: "general.weekly", name: "每周额度", scope: nil,
                                 period: .weekly,
                                 usedPercentage: 70, remainingCount: nil, totalCount: nil, resetsAt: nil)
        let weeklyOnly = WidgetAccountSnapshot(account: snapshot.account,
                                              windows: [weekly], collectedAt: Date(), lastFailure: nil)
        XCTAssertNil(weeklyOnly.homeScreenMetrics[0].window)
    }

    func testWidgetPresentationUsesConfiguredAccountsInConfiguredOrder() {
        let snapshots = (0..<5).map { index in
            WidgetAccountSnapshot(
                account: SubscriptionAccount(name: "账号 \(index)", provider: .zai),
                windows: [], collectedAt: nil, lastFailure: nil
            )
        }

        XCTAssertEqual(
            WidgetPresentation.select(
                snapshots,
                selectedIDs: [snapshots[3].id, snapshots[1].id],
                family: .single
            ).accounts.map(\.id),
            [snapshots[3].id]
        )
        XCTAssertEqual(
            WidgetPresentation.select(
                snapshots,
                selectedIDs: [snapshots[3].id, snapshots[1].id],
                family: .medium
            )
                .accounts.map(\.id),
            [snapshots[3].id, snapshots[1].id]
        )
        XCTAssertEqual(
            WidgetPresentation.select(
                snapshots,
                selectedIDs: [snapshots[4].id, snapshots[0].id, snapshots[4].id, snapshots[2].id, snapshots[1].id],
                family: .large
            )
                .accounts.map(\.id),
            [snapshots[4].id, snapshots[0].id, snapshots[2].id, snapshots[1].id]
        )
    }

    func testWidgetPresentationDistinguishesRequiredAndUnsynchronizedSelections() {
        let snapshot = WidgetAccountSnapshot(
            account: SubscriptionAccount(name: "现有账号", provider: .zai),
            windows: [], collectedAt: nil, lastFailure: nil
        )
        let missingID = UUID()

        let required = WidgetPresentation.select([snapshot], selectedIDs: [], family: .medium)
        XCTAssertTrue(required.selectionRequired)
        XCTAssertFalse(required.accountSelectionMissing)

        let missing = WidgetPresentation.select(
            [snapshot], selectedIDs: [snapshot.id, missingID], family: .medium
        )
        XCTAssertEqual(missing.accounts.map(\.id), [snapshot.id])
        XCTAssertFalse(missing.selectionRequired)
        XCTAssertTrue(missing.accountSelectionMissing)
    }

    func testWidgetRingStateDoesNotRenderUnknownOrUnlimitedAsZero() {
        func metric(used: Double?, unlimited: Bool = false) -> WidgetQuotaMetric {
            WidgetQuotaMetric(
                id: "test",
                title: "测试额度",
                window: QuotaWindow(
                    id: "test", name: "测试额度", scope: nil,
                    isUnlimited: unlimited,
                    usedPercentage: used, remainingCount: nil, totalCount: nil, resetsAt: nil
                )
            )
        }

        XCTAssertNil(metric(used: nil).ringFraction)
        XCTAssertEqual(metric(used: nil).valueText, "未提供")
        XCTAssertNil(metric(used: nil, unlimited: true).ringFraction)
        XCTAssertEqual(metric(used: nil, unlimited: true).valueText, "无限")
        XCTAssertEqual(metric(used: -5).ringFraction, 0)
        XCTAssertEqual(metric(used: 125).ringFraction, 1)
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

    func testWidgetDeepLinksTargetTheAccountOrAccountList() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        XCTAssertEqual(
            PlatformConstants.accountDeepLink(for: id).absoluteString,
            "tokenpulse://account/00000000-0000-0000-0000-000000000001"
        )
        XCTAssertEqual(PlatformConstants.accountsDeepLink.absoluteString, "tokenpulse://accounts")
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
