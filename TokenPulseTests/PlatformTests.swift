import Security
import SwiftUI
import XCTest
@testable import TokenPulse

final class PlatformTests: XCTestCase {
    @MainActor
    func testDetailRevealReportsIntermediateRowHeightsWithoutCompressingContent() {
        for expansion in [0.0, 0.25, 0.5, 0.75, 1.0, 0.5, 0.0] {
            let host = UIHostingController(rootView: VStack(spacing: 0) {
                Color.clear.frame(height: 40)
                QuotaDetailsLayout(expansion: expansion) {
                    Color.clear.frame(height: 120)
                }
            })

            let size = host.sizeThatFits(in: CGSize(width: 240, height: 500))

            XCTAssertEqual(size.width, 240, accuracy: 0.5)
            XCTAssertEqual(size.height, 40 + 120 * expansion, accuracy: 0.5)
        }
    }

    func testCloudDeletionWinsOverStaleAccountInEitherMergeDirection() {
        let account = SubscriptionAccount(name: "Deleted")
        var deleted = AccountConfiguration(account: account)
        deleted.deletedAt = Date()
        let tombstone = PlatformAccountPayload(configurations: [deleted], states: [], ledger: ReminderLedger())
        let stale = PlatformAccountPayload(
            configurations: [AccountConfiguration(account: account, modifiedAt: .distantFuture)],
            states: [AccountQuotaState(account: account)], ledger: ReminderLedger()
        )

        for merged in [ICloudSyncRuntime.merge(tombstone, stale), ICloudSyncRuntime.merge(stale, tombstone)] {
            XCTAssertEqual(merged.configurations, [deleted])
            XCTAssertTrue(merged.states.isEmpty)
        }
    }

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

    func testWidgetEntityResolutionRestoresSelectedAccountAfterIdentifierNormalization() {
        let snapshot = WidgetAccountSnapshot(
            account: SubscriptionAccount(name: "现有账号", provider: .zai),
            windows: [], collectedAt: nil, lastFailure: nil
        )

        let resolved = WidgetAccountEntityResolution.snapshots(
            [snapshot], matching: [snapshot.id.uuidString.lowercased()]
        )

        XCTAssertEqual(resolved.map(\.id), [snapshot.id])
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
        for language in ["zh-Hans", "en"] {
            try await L10n.withLanguage(language) {
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
                XCTAssertEqual(settings.errorMessage, language == "en"
                               ? "Unable to submit an iCloud sync request. Check your iCloud sign-in and sync permissions."
                               : "无法提交 iCloud 同步请求，请检查 iCloud 登录和同步权限。")
                XCTAssertFalse(settings.isSyncing)
                settings.received()
                XCTAssertEqual(settings.lastReceivedAt, now)
                let restored = CloudSyncSettings(defaults: defaults)
                XCTAssertEqual(restored.lastRequestedAt, settings.lastRequestedAt)
                XCTAssertEqual(restored.lastReceivedAt, settings.lastReceivedAt)
                settings.report(CloudSyncError.invalidPayload)
                XCTAssertEqual(settings.errorMessage, language == "en"
                               ? "Unable to read iCloud account data. Make sure both devices use the same app version."
                               : "无法读取 iCloud 账号数据，请确认两端应用版本一致。")
                let rawError = NSError(domain: "private-server", code: 1,
                                       userInfo: [NSLocalizedDescriptionKey: "Raw 服务 message"])
                settings.report(rawError)
                XCTAssertEqual(settings.errorMessage, language == "en"
                               ? "Sync failed. Try again later."
                               : "同步失败，请稍后重试。")
                XCTAssertEqual(settings.lastRequestedAt, Date(timeIntervalSince1970: 100))
                XCTAssertEqual(settings.lastReceivedAt, now)
                await settings.perform {}
                XCTAssertNil(settings.errorMessage)
                XCTAssertEqual(settings.lastRequestedAt, now)
            }
        }
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

/// Replays configuration, snapshot, notification and Keychain arrivals independently.
final class CloudIdentityMergeTests: XCTestCase {
    func testOldDevicePushCannotReplaceWinningIdentityReadingOrAlertHistory() {
        let account = SubscriptionAccount(name: "Gateway", provider: .newAPI)
        let old = payload(account: account, identity: "A", modified: 10, collected: 100, threshold: 80)
        let changed = payload(account: account, identity: "B", modified: 20, collected: 30, threshold: 95)
        for merged in [ICloudSyncRuntime.merge(old, changed), ICloudSyncRuntime.merge(changed, old)] {
            XCTAssertEqual(merged.configurations, changed.configurations)
            XCTAssertEqual(merged.states, changed.states)
            assertOnlyBHistory(merged.ledger, accountID: account.id)
            // An old device can push repeatedly after changing accounts elsewhere.
            let pushedAgain = ICloudSyncRuntime.merge(old, merged)
            XCTAssertEqual(pushedAgain.states, changed.states)
            assertOnlyBHistory(pushedAgain.ledger, accountID: account.id)
        }
    }

    func testConfigurationThenReadingAndLedgerPreserveIdentityThroughEmptyLocalHistory() {
        let account = SubscriptionAccount(name: "Gateway", provider: .newAPI)
        let old = payload(account: account, identity: "A", modified: 10, collected: 100, threshold: 80)
        let changed = payload(account: account, identity: "B", modified: 20, collected: 30, threshold: 95)
        let configurationFirst = PlatformAccountPayload(configurations: changed.configurations, states: [], ledger: ReminderLedger())
        let awaitingReading = ICloudSyncRuntime.merge(old, configurationFirst)
        XCTAssertNil(awaitingReading.states.first?.snapshot)
        XCTAssertEqual(awaitingReading.states.first?.credentialIdentity, "B")
        let delivered = ICloudSyncRuntime.merge(awaitingReading, changed)
        XCTAssertEqual(delivered.states, changed.states)
        assertOnlyBHistory(delivered.ledger, accountID: account.id)
        let emptyDevice = PlatformAccountPayload(configurations: changed.configurations, states: [], ledger: ReminderLedger())
        let recovered = ICloudSyncRuntime.merge(emptyDevice, delivered)
        assertOnlyBHistory(recovered.ledger, accountID: account.id)
        // NotificationRuntime binds the configured identity after receipt. This
        // must keep B history rather than erase records imported without a tag.
        var rebound = recovered.ledger
        XCTAssertTrue(rebound.bindCredentialIdentity("B", accountID: account.id).isEmpty)
        assertOnlyBHistory(rebound, accountID: account.id)
    }

    func testWinningIdentityRejectsContradictorySnapshotTagAndUnknownLegacyReading() {
        let account = SubscriptionAccount(name: "Gateway", provider: .newAPI)
        let changed = payload(account: account, identity: "B", modified: 20, collected: 30, threshold: 95)
        var contradictory = changed
        contradictory.states[0].snapshot = QuotaSnapshot(accountID: account.id, windows: [],
                                                         collectedAt: Date(timeIntervalSince1970: 200),
                                                         sourceCredentialFingerprint: "A")
        let safe = ICloudSyncRuntime.merge(changed, contradictory)
        XCTAssertEqual(safe.states, changed.states)
        var untagged = changed
        untagged.states[0].credentialIdentity = nil
        untagged.states[0].snapshot = QuotaSnapshot(accountID: account.id, windows: [], collectedAt: .distantFuture)
        XCTAssertEqual(ICloudSyncRuntime.merge(untagged, changed).states, changed.states)
    }

    func testLegacyProviderWithoutIdentityStillMergesLatestReadingAndHistory() {
        let account = SubscriptionAccount(name: "Legacy", provider: .miniMaxChina)
        let old = payload(account: account, identity: nil, modified: 10, collected: 20, threshold: 80)
        let newer = payload(account: account, identity: nil, modified: 30, collected: 40, threshold: 95)
        let merged = ICloudSyncRuntime.merge(old, newer)
        XCTAssertEqual(merged.configurations, newer.configurations)
        XCTAssertEqual(merged.states, newer.states)
        for threshold in [80.0, 95.0] {
            XCTAssertTrue(merged.ledger.containsQuotaAlert(accountID: account.id, windowID: "quota", cycle: .unidentified, threshold: threshold))
        }
    }

    func testScopedMergeDoesNotClearAnotherLegacyAccount() {
        let scoped = SubscriptionAccount(name: "Gateway", provider: .newAPI)
        let legacy = SubscriptionAccount(name: "Legacy", provider: .miniMaxChina)
        var old = payload(account: scoped, identity: "A", modified: 10, collected: 100, threshold: 80)
        let other = payload(account: legacy, identity: nil, modified: 10, collected: 50, threshold: 80)
        old.configurations += other.configurations
        old.states += other.states
        old.ledger = old.ledger.merging(other.ledger)
        let changed = payload(account: scoped, identity: "B", modified: 20, collected: 30, threshold: 95)
        let merged = ICloudSyncRuntime.merge(old, changed)
        XCTAssertEqual(merged.states.first { $0.id == legacy.id }, other.states.first)
        XCTAssertTrue(merged.ledger.containsQuotaAlert(accountID: legacy.id, windowID: "quota", cycle: .unidentified, threshold: 80))
        assertOnlyBHistory(merged.ledger, accountID: scoped.id)
    }

    @MainActor
    func testCorrectNewSnapshotSurvivesOldKeychainRefreshRestartAndLaterKeyArrival() async throws {
        let suite = "com.tokenpulse.tests.identity-order.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let account = SubscriptionAccount(name: "Gateway", provider: .newAPI)
        let keys = IdentitySyncCredentials()
        let controller = ProviderAuthenticationController()
        let keyA = try controller.credential(provider: .newAPI, apiKey: "old-fixture", serverAddress: "https://old.example")
        let keyB = try controller.credential(provider: .newAPI, apiKey: "new-fixture", serverAddress: "https://new.example")
        let identityA = try XCTUnwrap(ProviderCredentialEnvelope.decode(keyA, expectedProvider: .newAPI).sourceCredentialIdentity)
        let identityB = try XCTUnwrap(ProviderCredentialEnvelope.decode(keyB, expectedProvider: .newAPI).sourceCredentialIdentity)
        let old = payload(account: account, identity: identityA, modified: 10, collected: 100, threshold: 80)
        let changed = payload(account: account, identity: identityB, modified: 20, collected: 30, threshold: 95)
        let accounts = LocalAccountStateStore(suiteName: suite)
        let configs = LocalAccountConfigurationStore(suiteName: suite)
        try await accounts.save(old.states)
        try await configs.save(old.configurations)
        try await keys.save(keyA, for: account.id)
        let query = IdentitySyncFailedQuery()
        func monitor() -> QuotaMonitor {
            QuotaMonitor(accountStore: accounts, credentialStore: keys, quotaClient: query, configurationStore: configs)
        }
        let first = monitor()
        await first.start(refresh: false)
        // Configuration arrives before its reading; clear A, then accept B even
        // though A had the newer collection timestamp.
        await first.mergeSynchronized(configurations: changed.configurations, states: [])
        XCTAssertNil(first.states.first?.snapshot)
        await first.mergeSynchronized(configurations: changed.configurations, states: changed.states)
        XCTAssertEqual(first.states.first?.snapshot, changed.states.first?.snapshot)
        await first.refresh(accountID: account.id)
        XCTAssertEqual(first.states.first?.snapshot, changed.states.first?.snapshot)
        XCTAssertEqual(first.states.first?.lastFailure, .invalidCredential)
        let oldRequests = await query.credentials
        XCTAssertTrue(oldRequests.isEmpty)
        let savedStates = defaults.data(forKey: "accountQuotaStates")
        let savedConfigurations = defaults.data(forKey: "accountConfigurations")
        let reopened = monitor()
        await reopened.start(refresh: false)
        XCTAssertEqual(defaults.data(forKey: "accountQuotaStates"), savedStates)
        XCTAssertEqual(defaults.data(forKey: "accountConfigurations"), savedConfigurations)
        XCTAssertEqual(reopened.states.first?.snapshot, changed.states.first?.snapshot)
        XCTAssertEqual(reopened.states.first?.credentialIdentity, identityB)
        XCTAssertEqual(reopened.states.first?.lastFailure, .invalidCredential)
        // A subsequent stale push still cannot restore A.
        await reopened.mergeSynchronized(configurations: old.configurations, states: old.states)
        XCTAssertEqual(reopened.states.first?.snapshot, changed.states.first?.snapshot)
        try await keys.save(keyB, for: account.id)
        await reopened.refresh(accountID: account.id)
        let newRequests = await query.credentials
        XCTAssertEqual(newRequests, [keyB])
        XCTAssertEqual(reopened.states.first?.snapshot, changed.states.first?.snapshot)
        XCTAssertEqual(reopened.states.first?.lastFailure, .network)
    }

    private func payload(account: SubscriptionAccount, identity: String?, modified: TimeInterval,
                         collected: TimeInterval, threshold: Double) -> PlatformAccountPayload {
        var configuration = AccountConfiguration(account: account, modifiedAt: Date(timeIntervalSince1970: modified))
        configuration.credentialIdentity = identity
        let state = AccountQuotaState(account: account,
                                      snapshot: QuotaSnapshot(accountID: account.id, windows: [],
                                                              collectedAt: Date(timeIntervalSince1970: collected),
                                                              sourceCredentialFingerprint: identity),
                                      credentialIdentity: identity)
        var ledger = ReminderLedger()
        if let identity { _ = ledger.bindCredentialIdentity(identity, accountID: account.id) }
        ledger.recordQuotaAlert(accountID: account.id, windowID: "quota", cycle: .unidentified, threshold: threshold)
        let occurrence = ResetOccurrenceRecord(accountID: account.id, windowID: "quota",
                                                identity: .providerCycle(identity ?? "legacy"))
        ledger.recordExpectedReset(occurrence)
        ledger.recordConfirmedReset(occurrence)
        ledger.setCycleState(WindowCycleState(accountID: account.id, windowID: "quota", identity: .unidentified,
                                              resetAt: nil, usedPercentage: threshold,
                                              observedAt: Date(timeIntervalSince1970: collected)))
        ledger.setWalletAlertState(WalletAlertState(accountID: account.id, currency: "USD", isActive: true,
                                                   observedAt: Date(timeIntervalSince1970: collected)))
        return PlatformAccountPayload(configurations: [configuration], states: [state], ledger: ledger)
    }

    private func assertOnlyBHistory(_ ledger: ReminderLedger, accountID: UUID, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(ledger.containsQuotaAlert(accountID: accountID, windowID: "quota", cycle: .unidentified, threshold: 95), file: file, line: line)
        XCTAssertFalse(ledger.containsQuotaAlert(accountID: accountID, windowID: "quota", cycle: .unidentified, threshold: 80), file: file, line: line)
        for identity in ["A", "B"] {
            let occurrence = ResetOccurrenceRecord(accountID: accountID, windowID: "quota", identity: .providerCycle(identity))
            XCTAssertEqual(ledger.hasExpectedReset(occurrence), identity == "B", file: file, line: line)
            XCTAssertEqual(ledger.hasConfirmedReset(occurrence), identity == "B", file: file, line: line)
        }
        XCTAssertEqual(ledger.cycleState(accountID: accountID, windowID: "quota")?.observedAt,
                       Date(timeIntervalSince1970: 30), file: file, line: line)
        XCTAssertEqual(ledger.walletAlertState(accountID: accountID, currency: "USD")?.observedAt,
                       Date(timeIntervalSince1970: 30), file: file, line: line)
    }
}

private actor IdentitySyncCredentials: CredentialStoring {
    private var values: [UUID: String] = [:]
    func save(_ credential: String, for accountID: UUID) async throws { values[accountID] = credential }
    func credential(for accountID: UUID) async throws -> String? { values[accountID] }
    func deleteCredential(for accountID: UUID) async throws { values[accountID] = nil }
}

private actor IdentitySyncFailedQuery: QuotaQuerying {
    private(set) var credentials: [String] = []
    func quota(for accountID: UUID, credential: String) async throws -> QuotaSnapshot {
        credentials.append(credential)
        throw RefreshFailure.network
    }
}

extension PlatformTests {
    func testWidgetEmptyStatesAndSavedEntityDisplayFollowLanguageWithoutChangingBinding() throws {
        let sample = try XCTUnwrap(DemoMode.accounts().first { $0.provider == .miniMaxChina })
        let custom = SubscriptionAccount(name: "演示 · 用户自定 🌙", provider: .miniMaxChina)
        for language in ["zh-Hans", "en", "fr"] {
            L10n.withLanguage(language) {
                let chinese = language == "zh-Hans"
                XCTAssertEqual(WidgetContentPresentation.emptyMessage(selectionRequired: true, accountSelectionMissing: false, hasAvailableAccounts: false),
                               chinese ? "请先添加账号" : "Add an account first")
                XCTAssertEqual(WidgetContentPresentation.emptyMessage(selectionRequired: true, accountSelectionMissing: false, hasAvailableAccounts: true),
                               chinese ? "请选择展示账号" : "Choose an account to display")
                XCTAssertEqual(WidgetContentPresentation.emptyMessage(selectionRequired: false, accountSelectionMissing: true, hasAvailableAccounts: true),
                               chinese ? "所选账号尚未同步" : "The selected account has not synced yet")
                XCTAssertEqual(WidgetContentPresentation.entityTitle(name: custom.name, identifier: custom.id.uuidString), custom.name)
                XCTAssertEqual(WidgetContentPresentation.entityTitle(name: sample.name, identifier: sample.id.uuidString),
                               chinese ? "演示 · MiniMax 国内版" : "Demo · MiniMax China")
                XCTAssertEqual(WidgetContentPresentation.entitySubtitle("MiniMax 国内版"), chinese ? "MiniMax 国内版" : "MiniMax China")
                XCTAssertEqual(WidgetContentPresentation.entitySubtitle("Unknown Provider Label 🌙"), "Unknown Provider Label 🌙")
                XCTAssertEqual(custom.provider.rawValue, "miniMaxChina")
                XCTAssertEqual(sample.name, "演示 · MiniMax 国内版")
            }
        }
    }

    func testWidgetAccessibleOutputKeepsPluralResetCountsAndStaleStatesDistinct() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let account = SubscriptionAccount(name: "我的 Codex 🌙", provider: .codex)
        let window = QuotaWindow(id: "codex.weekly", name: "每周额度", scope: nil, period: .weekly,
                                 usedPercentage: 50, remainingCount: nil, totalCount: nil, resetsAt: date.addingTimeInterval(-60))
        for language in ["zh-Hans", "en"] {
            L10n.withLanguage(language) {
                for count in [0, 1, 3] {
                    let snapshot = WidgetAccountSnapshot(account: account, windows: [window], collectedAt: date,
                                                         lastFailure: .network, remainingResetCount: count, subscriptionPlan: .pro)
                    let summary = WidgetContentPresentation.accessibilitySummary(snapshot, at: date)
                    XCTAssertTrue(summary.contains(account.name))
                    XCTAssertTrue(summary.contains(language == "en" ? "Needs Update" : "待更新"))
                    XCTAssertTrue(summary.contains(language == "en" ? "Network connection failed" : "网络连接失败"))
                    XCTAssertTrue(summary.contains(language == "en" ? "Previous successful data" : "上次成功数据"))
                    XCTAssertEqual(WidgetContentPresentation.resetCount(snapshot),
                                   language == "en" ? "Available: \(count) \(count == 1 ? "reset" : "resets")" : "可重置 \(count) 次")
                    XCTAssertEqual(snapshot.id, account.id)
                    XCTAssertEqual(snapshot.windows.first?.name, "每周额度")
                }
                let failedFirst = WidgetAccountSnapshot(account: account, windows: [], collectedAt: nil, lastFailure: .network)
                XCTAssertEqual(WidgetContentPresentation.status(failedFirst), language == "en" ? "Refresh Failed" : "刷新失败")
                XCTAssertFalse(WidgetContentPresentation.accessibilitySummary(failedFirst, at: date)
                    .contains(language == "en" ? "Previous data retained" : "保留旧数据"))
            }
        }
    }

    func testWidgetTimingPreservesContinuousRecoveryAndDateOnlyPrecisionAndWalletUnits() {
        let boundary = Date(timeIntervalSince1970: 1_788_220_800)
        let continuous = QuotaWindow(id: "codex.weekly", name: "每周额度", scope: nil,
                                     usedPercentage: 40, remainingCount: nil, totalCount: nil, resetsAt: nil,
                                     resetSemantics: .continuousReplenishment)
        let day = QuotaWindow(id: "codex.weekly", name: "每周额度", scope: nil,
                              usedPercentage: 40, remainingCount: nil, totalCount: nil, resetsAt: boundary, resetDatePrecision: .day)
        let wallet = QuotaWindow(id: "poe.points", name: "points 余额", scope: nil,
                                 usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                                 wallet: WalletBalance(currency: "points", total: 1234, isMonetary: false))
        for language in ["zh-Hans", "en"] {
            L10n.withLanguage(language) {
                let continuousMetric = WidgetQuotaMetric(id: continuous.id, title: "Weekly", window: continuous)
                let dayMetric = WidgetQuotaMetric(id: day.id, title: "Weekly", window: day)
                let walletMetric = WidgetQuotaMetric(id: wallet.id, title: "points", window: wallet)
                XCTAssertEqual(WidgetContentPresentation.resetText(continuousMetric),
                               language == "en" ? "Allowance replenishment Continuous replenishment" : "额度补充 持续补充")
                XCTAssertTrue(WidgetContentPresentation.resetText(dayMetric).contains("2026-09-01"))
                XCTAssertEqual(WidgetContentPresentation.resetText(walletMetric), language == "en" ? "Service Credit Balance" : "服务积分余额")
                XCTAssertTrue(WidgetContentPresentation.metricSummary(walletMetric).contains("points"))
                XCTAssertFalse(WidgetContentPresentation.metricSummary(walletMetric).contains("USD"))
                XCTAssertEqual(wallet.wallet?.total, 1234)
            }
        }
    }
}

#if DEBUG
extension PlatformTests {
    func testWidgetDebugEntriesExerciseRealRendererFamiliesWithoutWritingAccountData() {
        let date = Date(timeIntervalSince1970: 1_788_220_800)
        for family in [WidgetPresentationFamily.single, .medium, .large] {
            for scenario in WidgetDebugFixture.supportedScenarios {
                let entry = WidgetDebugFixture.entry(scenario: scenario, family: family, date: date)
                XCTAssertEqual(entry.date, date)
                if ["empty", "unselected", "missing"].contains(scenario) {
                    XCTAssertTrue(entry.accounts.isEmpty)
                    XCTAssertEqual(entry.accountSelectionMissing, scenario == "missing")
                    XCTAssertEqual(entry.hasAvailableAccounts, scenario != "empty")
                } else {
                    XCTAssertEqual(entry.accounts.count, family.accountLimit)
                    XCTAssertEqual(Set(entry.accounts.map(\.id)).count, family.accountLimit)
                    if scenario == "replenishment" {
                        XCTAssertEqual(entry.accounts.first?.displayMetrics.first?.window?.resetSemantics, .continuousReplenishment)
                        XCTAssertNil(entry.accounts.first?.displayMetrics.first?.window?.resetsAt)
                    }
                    if scenario == "wallet" {
                        XCTAssertEqual(entry.accounts.first?.displayMetrics.first?.window?.wallet?.currency, "USD")
                        XCTAssertNil(entry.accounts.first?.displayMetrics.first?.ringFraction)
                    }
                    if scenario == "dateOnly" {
                        XCTAssertEqual(entry.accounts.first?.displayMetrics.first?.window?.resetDatePrecision, .day)
                        XCTAssertEqual(entry.accounts.first?.needsUpdate(at: date.addingTimeInterval(7 * 86_400)), false)
                    }
                }
            }
        }
    }
}
#endif
