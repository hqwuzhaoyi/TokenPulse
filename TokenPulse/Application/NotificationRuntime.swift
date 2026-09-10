import Combine
import Foundation

enum NotificationPermissionFeedback: Equatable {
    case enabled
    case disabled
    case denied
    case failed

    var message: String {
        switch self {
        case .enabled: "通知权限已开启。达到账号设置的阈值或重置时间时会提醒。"
        case .disabled: "TokenPulse 通知已关闭，账号内的提醒设置会保留。"
        case .denied:
            #if os(watchOS)
            "通知权限未开启。请在 iPhone 的 Watch App → 通知中检查 TokenPulse 的设置。"
            #else
            "通知权限未开启。请在系统设置 → 通知中检查 TokenPulse 的权限。"
            #endif
        case .failed: "暂时无法申请通知权限，请稍后重试。"
        }
    }
}

@MainActor
final class NotificationRuntime: ObservableObject {
    @Published private(set) var isEnabled: Bool
    private(set) var ledger: ReminderLedger
    private let defaults: UserDefaults
    private let adapter: any NotificationApplying
    private let planner = NotificationPlanner()
    private let enabledKey = "notificationsEnabled"
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(defaults: UserDefaults = .standard, adapter: any NotificationApplying = UserNotificationCenterAdapter()) {
        self.defaults = defaults
        self.adapter = adapter
        isEnabled = defaults.bool(forKey: enabledKey)
        adapter.configure()
        if let data = defaults.data(forKey: "reminderLedger"),
           let saved = try? JSONDecoder().decode(ReminderLedger.self, from: data) {
            ledger = saved
        } else { ledger = ReminderLedger() }
    }

    func requestAuthorization() async -> NotificationPermissionFeedback {
        let feedback: NotificationPermissionFeedback
        switch await adapter.authorizationStatus() {
        case .authorized: feedback = .enabled
        case .denied: feedback = .denied
        case .notDetermined:
            do { feedback = try await adapter.requestAuthorization() ? .enabled : .denied }
            catch { feedback = .failed }
        }
        isEnabled = feedback == .enabled
        defaults.set(isEnabled, forKey: enabledKey)
        return feedback
    }

    func setEnabled(_ enabled: Bool,
                    configurations: [AccountConfiguration],
                    states: [AccountQuotaState]) async -> NotificationPermissionFeedback {
        if enabled {
            let feedback = await requestAuthorization()
            guard feedback == .enabled else { return feedback }
        } else {
            isEnabled = false
            defaults.set(false, forKey: enabledKey)
        }
        do {
            try await settingsChanged(configurations: configurations, states: states)
            return enabled ? .enabled : .disabled
        } catch {
            return .failed
        }
    }

    func merge(_ incoming: ReminderLedger) async throws {
        await acquire()
        defer { release() }
        ledger = ledger.merging(incoming)
        try persist()
    }

    func fresh(state: AccountQuotaState, previous: AccountQuotaState?, settings: AccountReminderSettings) async throws {
        await acquire()
        defer { release() }
        guard let snapshot = reminderSnapshot(state.snapshot, provider: state.account.provider) else { return }
        let result = planner.planSuccessfulRefresh(
            accountID: state.id, accountName: state.account.name,
            previousSnapshot: reminderSnapshot(previous?.snapshot, provider: state.account.provider),
            newSnapshot: snapshot, settings: effective(settings), ledger: ledger, now: Date()
        )
        try await adapter.apply(result.operations)
        ledger = result.ledger
        try persist()
    }

    func settingsChanged(configurations: [AccountConfiguration], states: [AccountQuotaState]) async throws {
        await acquire()
        defer { release() }
        let removedIDs = ledger.scheduledAccountIDs.subtracting(configurations.map(\.id))
        for accountID in removedIDs {
            let identifiers = ledger.pendingSchedules(accountID: accountID).map(\.notificationID)
            try await adapter.apply([.cancel(identifiers: identifiers)])
            ledger.replacePendingSchedules(accountID: accountID, with: [])
            try persist()
        }
        for configuration in configurations {
            let result = planner.planSettingsChange(
                accountID: configuration.id, accountName: configuration.account.name,
                latestSnapshot: reminderSnapshot(
                    states.first(where: { $0.id == configuration.id })?.snapshot,
                    provider: configuration.account.provider
                ),
                settings: effective(configuration.reminders), ledger: ledger, now: Date()
            )
            try await adapter.apply(result.operations)
            ledger = result.ledger
            try persist()
        }
    }

    private func persist() throws {
        defaults.set(try JSONEncoder().encode(ledger), forKey: "reminderLedger")
    }

    private func effective(_ settings: AccountReminderSettings) -> AccountReminderSettings {
        guard !isEnabled else { return settings }
        return AccountReminderSettings(
            quotaAlertsEnabled: false,
            resetRemindersEnabled: false,
            thresholds: settings.thresholds
        )
    }

    private func reminderSnapshot(_ snapshot: QuotaSnapshot?, provider: Provider) -> QuotaSnapshot? {
        guard let snapshot else { return nil }
        return QuotaSnapshot(
            accountID: snapshot.accountID,
            windows: snapshot.windows(for: provider, surface: .notification),
            collectedAt: snapshot.collectedAt,
            subscriptionPlan: snapshot.subscriptionPlan,
            remainingResetCount: snapshot.remainingResetCount
        )
    }

    private func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { busy = false }
        else { waiters.removeFirst().resume() }
    }
}
