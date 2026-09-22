import Foundation

struct AccountReminderSettings: Codable, Equatable, Sendable {
    var quotaAlertsEnabled: Bool
    var resetRemindersEnabled: Bool
    var thresholds: [Double]
    var walletCurrency: String?
    var walletThresholds: [String: Decimal]?

    init(quotaAlertsEnabled: Bool = true,
         resetRemindersEnabled: Bool = true,
         thresholds: [Double] = [80, 95, 100],
         walletCurrency: String? = nil,
         walletThresholds: [String: Decimal]? = nil) {
        self.quotaAlertsEnabled = quotaAlertsEnabled
        self.resetRemindersEnabled = resetRemindersEnabled
        self.thresholds = thresholds
        self.walletCurrency = walletCurrency
        self.walletThresholds = walletThresholds
    }

    func walletThreshold(for currency: String) -> Decimal {
        if let threshold = walletThresholds?[currency], !threshold.isNaN, threshold >= 0 {
            return threshold
        }
        return currency == "CNY" ? 10 : 2
    }
}

enum ReminderNotificationKind: String, Codable, Equatable, Sendable {
    case quotaAlert
    case expectedReset
    case confirmedReset
    case walletAlert
}

struct ReminderNotification: Codable, Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let kind: ReminderNotificationKind
}

enum NotificationOperation: Codable, Equatable, Sendable {
    case deliver(ReminderNotification)
    case schedule(ReminderNotification, at: Date)
    case cancel(identifiers: [String])
}

struct NotificationPlanningResult: Codable, Equatable, Sendable {
    let operations: [NotificationOperation]
    let ledger: ReminderLedger
}

struct ReminderLedger: Codable, Equatable, Sendable {
    private var quotaAlerts: Set<QuotaAlertRecord> = []
    private var expectedResets: Set<ResetOccurrenceRecord> = []
    private var confirmedResets: Set<ResetOccurrenceRecord> = []
    private var windowCycles: [WindowCycleState] = []
    private var pendingResetSchedules: [PendingResetSchedule] = []
    private var walletAlerts: [WalletAlertState]?

    init() {}

    func merging(_ remote: ReminderLedger) -> ReminderLedger {
        var result = self
        result.quotaAlerts.formUnion(remote.quotaAlerts)
        result.expectedResets.formUnion(remote.expectedResets)
        result.confirmedResets.formUnion(remote.confirmedResets)

        for state in remote.windowCycles {
            guard let local = result.cycleState(accountID: state.accountID, windowID: state.windowID) else {
                result.setCycleState(state)
                continue
            }
            if state.observedAt > local.observedAt {
                result.setCycleState(state)
            }
        }

        for state in remote.walletAlerts ?? [] {
            let local = result.walletAlertState(accountID: state.accountID, currency: state.currency)
            if local == nil || state.observedAt > local!.observedAt
                || (state.observedAt == local!.observedAt && state.isActive) {
                result.setWalletAlertState(state)
            }
        }

        // Pending requests belong to the local device. Only delivered/planned records merge.
        return result
    }

    func containsQuotaAlert(accountID: UUID,
                            windowID: String,
                            cycle: ReminderCycleIdentity,
                            threshold: Double) -> Bool {
        quotaAlerts.contains(QuotaAlertRecord(
            accountID: accountID,
            windowID: windowID,
            cycle: cycle,
            threshold: threshold
        ))
    }

    func containsQuotaAlert(accountID: UUID,
                            windowID: String,
                            cycle: ReminderCycleIdentity) -> Bool {
        quotaAlerts.contains {
            $0.accountID == accountID && $0.windowID == windowID && $0.cycle == cycle
        }
    }

    func walletAlertState(accountID: UUID, currency: String?) -> WalletAlertState? {
        walletAlerts?.first { $0.accountID == accountID && $0.currency == currency }
    }

    mutating func setWalletAlertState(_ state: WalletAlertState) {
        var states = walletAlerts ?? []
        states.removeAll { $0.accountID == state.accountID && $0.currency == state.currency }
        states.append(state)
        walletAlerts = states
    }

    mutating func recordQuotaAlert(accountID: UUID,
                                   windowID: String,
                                   cycle: ReminderCycleIdentity,
                                   threshold: Double) {
        quotaAlerts.insert(QuotaAlertRecord(
            accountID: accountID,
            windowID: windowID,
            cycle: cycle,
            threshold: threshold
        ))
    }

    func hasExpectedReset(_ occurrence: ResetOccurrenceRecord) -> Bool {
        expectedResets.contains(occurrence)
    }

    func hasConfirmedReset(_ occurrence: ResetOccurrenceRecord) -> Bool {
        confirmedResets.contains(occurrence)
    }

    mutating func recordExpectedReset(_ occurrence: ResetOccurrenceRecord) {
        expectedResets.insert(occurrence)
    }

    mutating func removeExpectedReset(_ occurrence: ResetOccurrenceRecord) {
        expectedResets.remove(occurrence)
    }

    mutating func recordConfirmedReset(_ occurrence: ResetOccurrenceRecord) {
        confirmedResets.insert(occurrence)
    }

    func cycleState(accountID: UUID, windowID: String) -> WindowCycleState? {
        windowCycles.first { $0.accountID == accountID && $0.windowID == windowID }
    }

    mutating func setCycleState(_ state: WindowCycleState) {
        windowCycles.removeAll { $0.accountID == state.accountID && $0.windowID == state.windowID }
        windowCycles.append(state)
    }

    func pendingSchedules(accountID: UUID) -> [PendingResetSchedule] {
        pendingResetSchedules.filter { $0.accountID == accountID }
    }

    var scheduledAccountIDs: Set<UUID> {
        Set(pendingResetSchedules.map(\.accountID))
    }

    mutating func replacePendingSchedules(accountID: UUID,
                                          with schedules: [PendingResetSchedule]) {
        pendingResetSchedules.removeAll { $0.accountID == accountID }
        pendingResetSchedules.append(contentsOf: schedules)
    }
}

/// A nil currency tracks API availability independently of any selected wallet currency.
struct WalletAlertState: Codable, Equatable, Sendable {
    let accountID: UUID
    let currency: String?
    let isActive: Bool
    let observedAt: Date
}

enum ReminderCycleIdentity: Codable, Hashable, Sendable {
    case provider(String)
    case resetBoundary(Date)
    case inferred(Date)
    case unidentified
}

struct QuotaAlertRecord: Codable, Hashable, Sendable {
    let accountID: UUID
    let windowID: String
    let cycle: ReminderCycleIdentity
    let threshold: Double
}

enum ResetOccurrenceIdentity: Codable, Hashable, Sendable {
    case expectedAt(Date)
    case providerCycle(String)
    case inferred(Date)
}

struct ResetOccurrenceRecord: Codable, Hashable, Sendable {
    let accountID: UUID
    let windowID: String
    let identity: ResetOccurrenceIdentity
}

struct WindowCycleState: Codable, Equatable, Sendable {
    let accountID: UUID
    let windowID: String
    let identity: ReminderCycleIdentity
    let resetAt: Date?
    let usedPercentage: Double?
    let observedAt: Date
}

struct PendingResetSchedule: Codable, Equatable, Sendable {
    let accountID: UUID
    let notificationID: String
    let resetAt: Date
    let windowIDs: Set<String>
}
