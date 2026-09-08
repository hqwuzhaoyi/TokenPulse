import Foundation

enum NotificationPermissionFeedback: Equatable {
    case enabled
    case denied
    case failed

    var message: String {
        switch self {
        case .enabled: "通知权限已开启。达到账号设置的阈值或重置时间时会提醒。"
        case .denied: "通知权限未开启。请在 iPhone 的 Watch App → 通知中检查 TokenPulse 的设置。"
        case .failed: "暂时无法申请通知权限，请稍后重试。"
        }
    }
}

@MainActor
final class NotificationRuntime {
    private(set) var ledger: ReminderLedger
    private let defaults: UserDefaults
    private let adapter: any NotificationApplying
    private let planner = NotificationPlanner()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(defaults: UserDefaults = .standard, adapter: any NotificationApplying = UserNotificationCenterAdapter()) {
        self.defaults = defaults
        self.adapter = adapter
        adapter.configure()
        if let data = defaults.data(forKey: "reminderLedger"),
           let saved = try? JSONDecoder().decode(ReminderLedger.self, from: data) {
            ledger = saved
        } else { ledger = ReminderLedger() }
    }

    func requestAuthorization() async -> NotificationPermissionFeedback {
        switch await adapter.authorizationStatus() {
        case .authorized: return .enabled
        case .denied: return .denied
        case .notDetermined:
            do { return try await adapter.requestAuthorization() ? .enabled : .denied }
            catch { return .failed }
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
        guard let snapshot = state.snapshot else { return }
        let result = planner.planSuccessfulRefresh(
            accountID: state.id, accountName: state.account.name, previousSnapshot: previous?.snapshot,
            newSnapshot: snapshot, settings: settings, ledger: ledger, now: Date()
        )
        try await adapter.apply(result.operations)
        ledger = result.ledger
        try persist()
    }

    func settingsChanged(configurations: [AccountConfiguration], states: [AccountQuotaState]) async throws {
        await acquire()
        defer { release() }
        for configuration in configurations {
            let result = planner.planSettingsChange(
                accountID: configuration.id, accountName: configuration.account.name,
                latestSnapshot: states.first(where: { $0.id == configuration.id })?.snapshot,
                settings: configuration.reminders, ledger: ledger, now: Date()
            )
            try await adapter.apply(result.operations)
            ledger = result.ledger
            try persist()
        }
    }

    private func persist() throws {
        defaults.set(try JSONEncoder().encode(ledger), forKey: "reminderLedger")
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
