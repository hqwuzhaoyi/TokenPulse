import Combine
import Foundation

enum NotificationPermissionFeedback: Equatable {
    case enabled
    case disabled
    case denied
    case failed

    var message: String {
        switch self {
        case .enabled: L10n.text("通知权限已开启。达到账号设置的阈值或重置时间时会提醒。")
        case .disabled: L10n.text("TokenPulse 通知已关闭，账号内的提醒设置会保留。")
        case .denied:
            #if os(watchOS)
            L10n.text("通知权限未开启。请在 iPhone 的 Watch App → 通知中检查 TokenPulse 的设置。")
            #else
            L10n.text("通知权限未开启。请在系统设置 → 通知中检查 TokenPulse 的权限。")
            #endif
        case .failed: L10n.text("暂时无法申请通知权限，请稍后重试。")
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
    private var active = true
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

    func activate() {
        active = true
        adapter.configure()
    }

    func requestAuthorization() async -> NotificationPermissionFeedback {
        guard active else { return .disabled }
        let feedback: NotificationPermissionFeedback
        switch await adapter.authorizationStatus() {
        case .authorized: feedback = .enabled
        case .denied: feedback = .denied
        case .notDetermined:
            do { feedback = try await adapter.requestAuthorization() ? .enabled : .denied }
            catch { feedback = .failed }
        }
        guard active else { return .disabled }
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
        guard active else { return }
        guard let snapshot = reminderSnapshot(state.snapshot, provider: state.account.provider) else { return }
        if let identity = state.credentialIdentity {
            try await bindCredentialIdentity(identity, accountID: state.id)
        }
        let result = planner.planSuccessfulRefresh(
            accountID: state.id, accountName: L10n.demoAccountName(state.account), provider: state.account.provider,
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
        guard active else { return }
        let removedIDs = ledger.scheduledAccountIDs.subtracting(configurations.map(\.id))
        for accountID in removedIDs {
            let identifiers = ledger.pendingSchedules(accountID: accountID).map(\.notificationID)
            try await adapter.apply([.cancel(identifiers: identifiers)])
            ledger.replacePendingSchedules(accountID: accountID, with: [])
            try persist()
        }
        for configuration in configurations {
            if let identity = configuration.credentialIdentity {
                try await bindCredentialIdentity(identity, accountID: configuration.id)
            }
            let result = planner.planSettingsChange(
                accountID: configuration.id, accountName: L10n.demoAccountName(configuration.account), provider: configuration.account.provider,
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

    /// Only the schedules recorded by this runtime are cancelled; other accounts are untouched.
    func deactivate() async throws {
        await acquire()
        defer { release() }
        active = false
        for accountID in ledger.scheduledAccountIDs {
            let identifiers = ledger.pendingSchedules(accountID: accountID).map(\.notificationID)
            try await adapter.apply([.cancel(identifiers: identifiers)])
            ledger.replacePendingSchedules(accountID: accountID, with: [])
        }
        try persist()
    }

    func sendDemoNotification() async -> NotificationPermissionFeedback {
        let feedback = await requestAuthorization()
        guard feedback == .enabled else { return feedback }
        await acquire()
        defer { release() }
        guard active else { return .disabled }
        do {
            try await adapter.apply([.deliver(ReminderNotification(
                identifier: "tokenpulse.demo.preview", title: L10n.text("TokenPulse 演示提醒"),
                body: L10n.text("这是示例通知。你可以在演示账号设置中调整额度阈值和重置提醒。"),
                kind: .quotaAlert
            ))])
            return .enabled
        } catch { return .failed }
    }

    func codexResetPreview(_ status: CodexResetStatus, configurations: [AccountConfiguration], now: Date = Date()) async throws {
        await acquire()
        defer { release() }
        guard active, isEnabled,
              configurations.contains(where: { $0.deletedAt == nil && $0.account.provider == .codex && $0.reminders.resetRemindersEnabled }),
              let notification = status.previewNotification(at: now) else { return }
        let key = "codexResetPreviewDelivered"
        var delivered = defaults.stringArray(forKey: key) ?? []
        guard !delivered.contains(notification.identifier) else { return }
        try await adapter.apply([.deliver(notification)])
        delivered.append(notification.identifier)
        defaults.set(Array(delivered.suffix(256)), forKey: key)
    }

    private func bindCredentialIdentity(_ identity: String, accountID: UUID) async throws {
        var updated = ledger
        let identifiers = updated.bindCredentialIdentity(identity, accountID: accountID)
        if !identifiers.isEmpty { try await adapter.apply([.cancel(identifiers: identifiers)]) }
        ledger = updated
    }

    private func persist() throws {
        defaults.set(try JSONEncoder().encode(ledger), forKey: "reminderLedger")
    }

    private func effective(_ settings: AccountReminderSettings) -> AccountReminderSettings {
        guard !isEnabled else { return settings }
        var disabled = settings
        disabled.quotaAlertsEnabled = false
        disabled.walletAlertsEnabled = false
        disabled.resetRemindersEnabled = false
        return disabled
    }

    private func reminderSnapshot(_ snapshot: QuotaSnapshot?, provider: Provider) -> QuotaSnapshot? {
        guard let snapshot else { return nil }
        return QuotaSnapshot(
            accountID: snapshot.accountID,
            windows: snapshot.windows(for: provider, surface: .notification),
            collectedAt: snapshot.collectedAt,
            subscriptionPlan: snapshot.subscriptionPlan,
            remainingResetCount: snapshot.remainingResetCount,
            walletAvailable: snapshot.walletAvailable,
            quotaExceeded: snapshot.quotaExceeded,
            walletCollectedAt: snapshot.walletCollectedAt,
            walletFailure: snapshot.walletFailure
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
