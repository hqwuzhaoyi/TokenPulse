import Combine
import Foundation

@MainActor
final class AppRuntime: ObservableObject {
    @Published private(set) var monitor: QuotaMonitor
    @Published private(set) var notifications: NotificationRuntime
    @Published private(set) var isDemoMode: Bool
    @Published private(set) var isSwitchingMode = false
    let cloudSync: CloudSyncSettings
    private let defaults: UserDefaults
    private let demoDefaults: UserDefaults
    private let defaultsSuiteName: String?
    private let demoSuiteName: String
    private let widgetStore: WidgetSnapshotStore
    private let credentials: SynchronizableCredentialStore
    private let accountCredentials: ProviderScopedCredentialStore
    private var realMonitor: QuotaMonitor?
    private var realNotifications: NotificationRuntime?
    private var started = false
    private lazy var sync = ICloudSyncRuntime(
        onIncoming: { [weak self] payload, isExternalUpdate in
            await self?.receive(payload, isExternalUpdate: isExternalUpdate)
        },
        onError: { [weak self] error in await self?.reportSyncError(error) }
    )
    #if os(iOS)
    private let background = IOSBackgroundRefreshAdapter()
    #endif

    init(defaultsSuiteName: String? = nil,
         demoSuiteName: String = DemoMode.suiteName,
         widgetStore: WidgetSnapshotStore = WidgetSnapshotStore()) {
        let defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        let demoDefaults = UserDefaults(suiteName: demoSuiteName)!
        self.defaultsSuiteName = defaultsSuiteName
        self.demoSuiteName = demoSuiteName
        self.defaults = defaults
        self.demoDefaults = demoDefaults
        self.widgetStore = widgetStore
        let cloudSync = CloudSyncSettings(defaults: defaults)
        self.cloudSync = cloudSync
        let credentials = SynchronizableCredentialStore(syncEnabled: cloudSync.isEnabled)
        self.credentials = credentials
        let accountCredentials = ProviderScopedCredentialStore(synchronized: credentials)
        self.accountCredentials = accountCredentials
        let demoEnabled = defaults.bool(forKey: DemoMode.enabledKey)
        isDemoMode = demoEnabled
        if demoEnabled {
            monitor = DemoMode.makeMonitor(suiteName: demoSuiteName)
            notifications = NotificationRuntime(defaults: demoDefaults)
        } else {
            monitor = Self.makeRealMonitor(suiteName: defaultsSuiteName, credentials: accountCredentials)
            notifications = NotificationRuntime(defaults: defaults)
            realMonitor = monitor
            realNotifications = notifications
        }
        bindMonitor()
    }

    private static func makeRealMonitor(suiteName: String?,
                                        credentials: any CredentialStoring) -> QuotaMonitor {
        QuotaMonitor(
            accountStore: LocalAccountStateStore(suiteName: suiteName), credentialStore: credentials,
            quotaClient: MiniMaxQuotaClient(), configurationStore: LocalAccountConfigurationStore(suiteName: suiteName),
            providerClient: { provider in AccountQuotaClient(provider: provider, credentialStore: credentials) }
        )
    }

    private func bindMonitor() {
        let source = monitor
        let sourceNotifications = notifications
        source.onChange = { [weak self, weak source] in
            guard let self, let source, self.monitor === source, !self.isSwitchingMode else { return }
            await self.publish()
        }
        source.onFreshSnapshot = { [weak self, weak source] state, previous in
            guard let self, let source, self.monitor === source, !self.isSwitchingMode else { return }
            do {
                try await sourceNotifications.fresh(
                    state: state, previous: previous,
                    settings: source.configuration(for: state.id)?.reminders ?? AccountReminderSettings()
                )
            } catch { source.setSynchronizationMessage("额度已更新，提醒暂未投递。") }
        }
    }

    func setDemoMode(_ enabled: Bool) async {
        guard enabled != isDemoMode, !isSwitchingMode else { return }
        isSwitchingMode = true
        defer { isSwitchingMode = false }
        // Pause incoming sync before swapping observable objects. In-flight work retains its own stores.
        await sync.stop()
        if enabled {
            realMonitor = monitor
            realNotifications = notifications
            monitor = DemoMode.makeMonitor(suiteName: demoSuiteName)
            notifications = NotificationRuntime(defaults: demoDefaults)
        } else {
            do { try await notifications.deactivate() }
            catch {
                monitor.setSynchronizationMessage("演示提醒清理失败，请稍后重试退出演示。")
                return
            }
            monitor = realMonitor ?? Self.makeRealMonitor(suiteName: defaultsSuiteName, credentials: accountCredentials)
            notifications = realNotifications ?? NotificationRuntime(defaults: defaults)
            realMonitor = monitor
            realNotifications = notifications
        }
        notifications.activate()
        isDemoMode = enabled
        defaults.set(enabled, forKey: DemoMode.enabledKey)
        bindMonitor()
        await monitor.start(refresh: false)
        do { try await widgetStore.save(states: monitor.states, configurations: monitor.configurations, isDemoMode: enabled) }
        catch { monitor.setSynchronizationMessage("小组件更新失败，本机账号与查询仍可使用。") }
        await widgetStore.setDemoMode(enabled)
        started = true
        do {
            try await notifications.settingsChanged(configurations: monitor.configurations, states: monitor.states)
        } catch { monitor.setSynchronizationMessage("提醒未启用或投递失败，可在账号设置中检查通知权限。") }
        await scheduleBackgroundRefresh()
        let source = monitor
        Task { [weak self] in
            guard let self, self.monitor === source else { return }
            await self.synchronizeNow()
        }
    }

    func registerBackgroundRefresh() {
        #if os(iOS)
        background.register { [weak self] in
            await self?.refresh()
            await self?.scheduleBackgroundRefresh()
        }
        #endif
    }

    func start() async {
        guard !started, !isSwitchingMode else { return }
        started = true
        let source = monitor
        let demo = isDemoMode
        await source.start(refresh: false)
        guard monitor === source, !isSwitchingMode else { return }
        await widgetStore.setDemoMode(demo)
        guard monitor === source, !isSwitchingMode else { return }
        if !demo, cloudSync.isEnabled {
            do { try await sync.start() }
            catch { cloudSync.report(error) }
        }
        guard monitor === source, !isSwitchingMode else { return }
        await source.refreshAll()
        guard monitor === source, !isSwitchingMode else { return }
        await publish()
        await scheduleBackgroundRefresh()
    }

    func refresh() async {
        guard !isSwitchingMode else { return }
        if !started { await start() }
        else { await monitor.refreshAll() }
    }

    func publish() async {
        guard !isSwitchingMode else { return }
        let source = monitor
        let sourceNotifications = notifications
        let demo = isDemoMode
        do {
            try await sourceNotifications.settingsChanged(configurations: source.configurations, states: source.states)
        } catch { source.setSynchronizationMessage("提醒未启用或投递失败，可在账号设置中检查通知权限。") }
        do {
            try await widgetStore.save(states: source.states, configurations: source.configurations, isDemoMode: demo)
        } catch { source.setSynchronizationMessage("小组件更新失败，本机账号与查询仍可使用。") }
        guard monitor === source, !demo else { return }
        await synchronizeNow()
    }

    func setCloudSyncEnabled(_ enabled: Bool) async {
        guard !isDemoMode, !isSwitchingMode else { return }
        cloudSync.setEnabled(enabled)
        await credentials.setSyncEnabled(enabled)
        if enabled { await synchronizeNow() }
        else { await sync.stop() }
    }

    func synchronizeNow() async {
        guard !isDemoMode, !isSwitchingMode else { return }
        let source = monitor
        let sourceNotifications = notifications
        await cloudSync.perform {
            try await sync.start()
            guard cloudSync.isEnabled, !isDemoMode, !isSwitchingMode, monitor === source else { return }
            var credentialSyncFailed = false
            for configuration in source.configurations where !configuration.account.provider.requiresDeviceLocalCredential {
                guard cloudSync.isEnabled, !isDemoMode, !isSwitchingMode, monitor === source else { return }
                _ = try await credentials.credential(for: configuration.id)
                if await credentials.credentialSyncIssue != nil { credentialSyncFailed = true }
            }
            guard cloudSync.isEnabled, !isDemoMode, !isSwitchingMode, monitor === source else { return }
            try await sync.push(configurations: source.synchronizedConfigurations, states: source.states,
                                ledger: sourceNotifications.ledger)
            if credentialSyncFailed { throw CloudSyncError.unavailable }
        }
    }

    private func reportSyncError(_ error: CloudSyncError) {
        guard cloudSync.isEnabled, !isDemoMode, !isSwitchingMode else { return }
        cloudSync.report(error)
    }

    private func receive(_ payload: PlatformAccountPayload, isExternalUpdate: Bool) async {
        guard cloudSync.isEnabled, !isDemoMode, !isSwitchingMode else { return }
        let source = monitor
        let sourceNotifications = notifications
        guard !isDemoMode, !isSwitchingMode, monitor === source else { return }
        await source.mergeSynchronized(configurations: payload.configurations, states: payload.states)
        guard !isDemoMode, !isSwitchingMode, monitor === source else { return }
        if isExternalUpdate { cloudSync.received() }
        do {
            try await sourceNotifications.settingsChanged(configurations: source.configurations, states: source.states)
            try await sourceNotifications.merge(payload.ledger)
        } catch { source.setSynchronizationMessage("提醒尚不可用，可检查通知权限。") }
        do {
            try await widgetStore.save(states: source.states, configurations: source.configurations)
        } catch { source.setSynchronizationMessage("同步数据已到达，显示或提醒更新失败。") }
    }

    func scheduleBackgroundRefresh() async {
        #if os(iOS)
        try? background.schedule()
        #elseif os(watchOS)
        try? await WatchBackgroundRefreshAdapter().schedule()
        #endif
    }
}
