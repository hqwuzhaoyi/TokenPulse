import Combine
import Foundation

@MainActor
final class AppRuntime: ObservableObject {
    let monitor: QuotaMonitor
    let cloudSync: CloudSyncSettings
    let notifications = NotificationRuntime()
    private let widgetStore = WidgetSnapshotStore()
    private let credentials: SynchronizableCredentialStore
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

    init() {
        let cloudSync = CloudSyncSettings()
        self.cloudSync = cloudSync
        let credentials = SynchronizableCredentialStore(syncEnabled: cloudSync.isEnabled)
        self.credentials = credentials
        monitor = QuotaMonitor(
            accountStore: LocalAccountStateStore(), credentialStore: credentials,
            quotaClient: MiniMaxQuotaClient(), configurationStore: LocalAccountConfigurationStore(),
            providerClient: { provider in AccountQuotaClient(provider: provider, credentialStore: credentials) }
        )
        monitor.onChange = { [weak self] in await self?.publish() }
        monitor.onFreshSnapshot = { [weak self] state, previous in
            guard let self else { return }
            do {
                try await notifications.fresh(state: state, previous: previous,
                                              settings: monitor.configuration(for: state.id)?.reminders ?? AccountReminderSettings())
            } catch { monitor.setSynchronizationMessage("额度已更新，提醒暂未投递。") }
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
        guard !started else { return }
        started = true
        await monitor.start(refresh: false)
        if cloudSync.isEnabled {
            do { try await sync.start() }
            catch { cloudSync.report(error) }
        }
        await publishWidgetSnapshots(
            failureMessage: "小组件账号暂未更新，本机账号与查询仍可使用。"
        )
        await monitor.refreshAll()
        await publish()
        await scheduleBackgroundRefresh()
    }

    func refresh() async {
        if !started { await start() }
        else { await monitor.refreshAll() }
    }

    func publish() async {
        do {
            try await notifications.settingsChanged(configurations: monitor.configurations, states: monitor.states)
        } catch { monitor.setSynchronizationMessage("提醒未启用或投递失败，可在账号设置中检查通知权限。") }
        await publishWidgetSnapshots(
            failureMessage: "小组件更新失败，本机账号与查询仍可使用。"
        )
        await synchronizeNow()
    }

    func setCloudSyncEnabled(_ enabled: Bool) async {
        cloudSync.setEnabled(enabled)
        await credentials.setSyncEnabled(enabled)
        if enabled { await synchronizeNow() }
        else { await sync.stop() }
    }

    func synchronizeNow() async {
        await cloudSync.perform {
            try await sync.start()
            guard cloudSync.isEnabled else { return }
            var credentialSyncFailed = false
            for configuration in monitor.configurations {
                guard cloudSync.isEnabled else { return }
                _ = try await credentials.credential(for: configuration.id)
                if await credentials.credentialSyncIssue != nil { credentialSyncFailed = true }
            }
            guard cloudSync.isEnabled else { return }
            try await sync.push(configurations: monitor.configurations, states: monitor.states, ledger: notifications.ledger)
            if credentialSyncFailed { throw CloudSyncError.unavailable }
        }
    }

    private func reportSyncError(_ error: CloudSyncError) {
        guard cloudSync.isEnabled else { return }
        cloudSync.report(error)
    }

    private func receive(_ payload: PlatformAccountPayload, isExternalUpdate: Bool) async {
        guard cloudSync.isEnabled else { return }
        do { try await notifications.merge(payload.ledger) }
        catch { monitor.setSynchronizationMessage("提醒记录同步失败") }
        await monitor.mergeSynchronized(configurations: payload.configurations, states: payload.states)
        if isExternalUpdate { cloudSync.received() }
        do {
            try await notifications.settingsChanged(configurations: monitor.configurations, states: monitor.states)
        } catch { monitor.setSynchronizationMessage("提醒尚不可用，可检查通知权限。") }
        await publishWidgetSnapshots(
            failureMessage: "同步数据已到达，显示或提醒更新失败。"
        )
    }

    private func publishWidgetSnapshots(failureMessage: String) async {
        do { try await widgetStore.save(states: monitor.states) }
        catch { monitor.setSynchronizationMessage(failureMessage) }
    }

    func scheduleBackgroundRefresh() async {
        #if os(iOS)
        try? background.schedule()
        #elseif os(watchOS)
        try? await WatchBackgroundRefreshAdapter().schedule()
        #endif
    }
}
