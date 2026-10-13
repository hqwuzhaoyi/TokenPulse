import XCTest
@testable import TokenPulse

final class DemoModeTests: XCTestCase {
    func testNativeLanguageFallbackDoesNotChangeDemoIdentityOrQuota() throws {
        let accounts = DemoMode.accounts()
        let account = try XCTUnwrap(accounts.first { $0.name == "演示 · Claude" })
        let snapshot = DemoMode.snapshot(accountID: account.id, provider: account.provider)
        XCTAssertEqual(L10n.text("主屏幕", language: "en"), "Home")
        XCTAssertEqual(L10n.text("主屏幕", language: "zh-Hans"), "主屏幕")
        XCTAssertEqual(L10n.text("主屏幕", language: "fr"), "Home")
        XCTAssertEqual(L10n.demoAccountName(account, language: "en"), "Demo · Claude")
        XCTAssertEqual(L10n.demoAccountName(account, language: "zh-Hans"), "演示 · Claude")
        let custom = SubscriptionAccount(name: "演示 · 我的 Claude", provider: .claude)
        XCTAssertEqual(L10n.demoAccountName(custom, language: "en"), custom.name)
        XCTAssertEqual(snapshot.accountID, account.id)
        XCTAssertEqual(snapshot.windows.first?.usedPercentage, 36)
        XCTAssertEqual(account.name, "演示 · Claude")
        XCTAssertEqual(snapshot.windows.first?.id, "demo.five-hour")
    }

    @MainActor
    func testDemoCoversEveryProviderAndSupportsAccountOperationsWithoutCredentials() async throws {
        let suite = "com.tokenpulse.tests.demo.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let monitor = DemoMode.makeMonitor(suiteName: suite)
        await monitor.start(refresh: false)
        XCTAssertEqual(Set(monitor.states.map(\.account.provider)), Set(Provider.allCases))
        XCTAssertEqual(Set(monitor.states.filter { $0.account.provider == .codex }.compactMap(\.snapshot?.subscriptionPlan)),
                       Set([.plus, .pro]))
        let account = try XCTUnwrap(monitor.states.first)
        await monitor.refresh(accountID: account.id)
        XCTAssertNotEqual(account.snapshot?.windows, monitor.states.first?.snapshot?.windows)
        XCTAssertNil(monitor.states.first?.lastFailure)

        await monitor.addAccount(name: "演示 · 新账号", credential: "demo", provider: .claude)
        let added = try XCTUnwrap(monitor.states.last)
        XCTAssertNotNil(added.snapshot)
        let settings = AccountReminderSettings(quotaAlertsEnabled: false, resetRemindersEnabled: false, thresholds: [50])
        await monitor.updateReminders(settings, accountID: added.id)
        monitor.reorderAccounts(from: IndexSet(integer: monitor.states.count - 1), to: 0)
        await monitor.persistAccountOrder()
        let restored = DemoMode.makeMonitor(suiteName: suite)
        await restored.start(refresh: false)
        XCTAssertEqual(restored.states.first?.id, added.id)
        XCTAssertEqual(restored.configuration(for: added.id)?.reminders, settings)
        let deleted = await restored.deleteAccount(accountID: added.id)
        XCTAssertTrue(deleted)
        XCTAssertFalse(restored.states.contains { $0.id == added.id })
    }

    @MainActor
    func testSwitchingDemoPreservesRealPersistenceAndWidgetSnapshots() async throws {
        let suffix = UUID().uuidString
        let realSuite = "com.tokenpulse.tests.real.\(suffix)"
        let demoSuite = "com.tokenpulse.tests.demo.\(suffix)"
        let widgetSuite = "com.tokenpulse.tests.widgets.\(suffix)"
        let real = UserDefaults(suiteName: realSuite)!
        let demo = UserDefaults(suiteName: demoSuite)!
        let widgets = UserDefaults(suiteName: widgetSuite)!
        defer {
            real.removePersistentDomain(forName: realSuite)
            demo.removePersistentDomain(forName: demoSuite)
            widgets.removePersistentDomain(forName: widgetSuite)
        }
        real.set(false, forKey: "cloudSyncEnabled")
        let account = SubscriptionAccount(name: "Real account")
        let state = AccountQuotaState(account: account)
        let stateData = try JSONEncoder().encode([state])
        let configurationData = try JSONEncoder().encode([AccountConfiguration(account: account)])
        let ledgerData = try JSONEncoder().encode(ReminderLedger())
        real.set(stateData, forKey: "accountQuotaStates")
        real.set(configurationData, forKey: "accountConfigurations")
        real.set(ledgerData, forKey: "reminderLedger")
        let widgetStore = WidgetSnapshotStore(defaults: UserDefaults(suiteName: widgetSuite))
        try await widgetStore.save(states: [state])
        let realWidgetData = widgets.data(forKey: "widget.accountSnapshots")
        let runtime = AppRuntime(defaultsSuiteName: realSuite, demoSuiteName: demoSuite, widgetStore: widgetStore)
        let originalMonitor = runtime.monitor
        await runtime.setDemoMode(true)
        XCTAssertTrue(runtime.isDemoMode)
        let demoSnapshots = await widgetStore.load()
        XCTAssertEqual(demoSnapshots.count, DemoMode.accounts().count)
        await runtime.monitor.refreshAll()
        let demoAccount = try XCTUnwrap(runtime.monitor.states.first)
        _ = await runtime.monitor.deleteAccount(accountID: demoAccount.id)
        await runtime.setCloudSyncEnabled(true)
        XCTAssertFalse(runtime.cloudSync.isEnabled)
        XCTAssertEqual(real.data(forKey: "accountQuotaStates"), stateData)
        XCTAssertEqual(real.data(forKey: "accountConfigurations"), configurationData)
        XCTAssertEqual(real.data(forKey: "reminderLedger"), ledgerData)
        XCTAssertEqual(widgets.data(forKey: "widget.accountSnapshots"), realWidgetData)

        await runtime.setDemoMode(false)
        XCTAssertFalse(runtime.isDemoMode)
        XCTAssertTrue(runtime.monitor === originalMonitor)
        XCTAssertEqual(runtime.monitor.states, [state])
        let restoredSnapshots = await widgetStore.load()
        XCTAssertEqual(restoredSnapshots.map(\.id), [account.id])
        XCTAssertEqual(real.data(forKey: "accountQuotaStates"), stateData)
        XCTAssertEqual(real.data(forKey: "accountConfigurations"), configurationData)
    }

    func testWatchSelectionAndLateRealWidgetWritesStayInTheirOwnMode() async throws {
        let suite = "com.tokenpulse.tests.watch-demo.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshots = WidgetSnapshotStore(defaults: UserDefaults(suiteName: suite))
        let selection = WatchWidgetSelectionStore(suiteName: suite)
        let real = SubscriptionAccount(name: "Real")
        let demo = DemoMode.accounts()[0]
        await selection.save(real.id)
        try await snapshots.save(states: [AccountQuotaState(account: demo)], isDemoMode: true)
        await snapshots.setDemoMode(true)
        let emptyDemoSelection = await selection.load()
        XCTAssertNil(emptyDemoSelection)
        await selection.save(demo.id)
        try await snapshots.save(states: [AccountQuotaState(account: real)])
        let visibleDemo = await snapshots.load()
        XCTAssertEqual(visibleDemo.map(\.id), [demo.id])
        await snapshots.setDemoMode(false)
        let realSelection = await selection.load()
        let visibleReal = await snapshots.load()
        XCTAssertEqual(realSelection, real.id)
        XCTAssertEqual(visibleReal.map(\.id), [real.id])
    }

    @MainActor
    func testDemoNotificationShutdownCancelsOnlyDemoSchedulesAndBlocksLateRefresh() async throws {
        let suite = "com.tokenpulse.tests.demo-notifications.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "notificationsEnabled")
        let adapter = DemoRecordingNotificationAdapter()
        let runtime = NotificationRuntime(defaults: defaults, adapter: adapter)
        let account = DemoMode.accounts()[0]
        let state = AccountQuotaState(account: account, snapshot: DemoMode.snapshot(accountID: account.id, provider: account.provider))
        let settings = AccountReminderSettings()
        try await runtime.fresh(state: state, previous: nil, settings: settings)
        let pendingIDs = runtime.ledger.pendingSchedules(accountID: account.id).map(\.notificationID)
        XCTAssertFalse(pendingIDs.isEmpty)
        try await runtime.deactivate()
        let afterShutdown = await adapter.operations
        let cancelled = afterShutdown.flatMap { operation -> [String] in
            if case let .cancel(identifiers) = operation { return identifiers }
            return []
        }
        XCTAssertEqual(Set(cancelled), Set(pendingIDs))
        try await runtime.fresh(state: state, previous: nil, settings: settings)
        try await runtime.settingsChanged(configurations: [AccountConfiguration(account: account)], states: [state])
        let afterLateRefresh = await adapter.operations
        XCTAssertEqual(afterLateRefresh, afterShutdown)
    }
}

private actor DemoRecordingNotificationAdapter: NotificationApplying {
    private(set) var operations: [NotificationOperation] = []
    @MainActor func configure() {}
    func requestAuthorization() async throws -> Bool { true }
    func authorizationStatus() async -> NotificationAuthorizationStatus { .authorized }
    func apply(_ operations: [NotificationOperation]) async throws { self.operations += operations }
}
