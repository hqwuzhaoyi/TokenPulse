import Foundation
import WidgetKit

struct WidgetAccountSnapshot: Codable, Equatable, Identifiable, Sendable {
    let account: SubscriptionAccount
    let windows: [QuotaWindow]
    let collectedAt: Date?
    let lastFailure: RefreshFailure?
    var remainingResetCount: Int? = nil
    var subscriptionPlan: SubscriptionPlan? = nil

    var id: UUID { account.id }

    var supportsManualResetCount: Bool {
        account.provider == .codex || account.provider == .superGrok
    }

    func needsUpdate(at date: Date) -> Bool {
        QuotaPolicy.windows(windows, provider: account.provider, plan: subscriptionPlan, surface: .widget)
            .contains { $0.needsUpdate(at: date) }
    }

    var homeScreenMetrics: [WidgetQuotaMetric] {
        displayMetrics
    }

    var ringMetrics: [WidgetQuotaMetric] {
        let limit = account.provider == .openCodeGo || account.provider == .claude ? 3 : 2
        return Array(displayMetrics.prefix(limit))
    }

    var displayMetrics: [WidgetQuotaMetric] {
        let visible = QuotaPolicy.windows(windows, provider: account.provider, plan: subscriptionPlan, surface: .widget)
        let weekly = visible.filter { $0.period == .weekly }
        let fiveHour = visible.filter { $0.period == .fiveHour }
        switch account.provider {
        case .codex:
            let weeklyMetric = WidgetQuotaMetric(
                id: "weekly", title: "每周已用",
                window: weekly.first { $0.scope == nil }
            )
            guard let short = fiveHour.first(where: { $0.scope == nil }) else { return [weeklyMetric] }
            return [
                WidgetQuotaMetric(
                    id: "fiveHour", title: "5 小时已用",
                    window: short
                ),
                weeklyMetric,
            ]
        case .openCodeGo:
            return visible.map {
                WidgetQuotaMetric(id: $0.id, title: $0.name, window: $0)
            }
        case .superGrok:
            return [WidgetQuotaMetric(id: "weekly", title: "每周已用", window: visible.first { $0.id == "superGrok.pool" })]
        case .zai:
            return [
                WidgetQuotaMetric(id: "weekly", title: "每周已用", window: weekly.first { $0.scope == nil }),
                WidgetQuotaMetric(id: "fiveHour", title: "5 小时已用", window: fiveHour.first { $0.scope == nil }),
            ]
        case .miniMaxChina:
            let general = fiveHour.filter { $0.scope == nil }
            let selected = general.isEmpty ? fiveHour : general
            return selected.isEmpty
                ? [WidgetQuotaMetric(id: "fiveHour", title: "5 小时已用", window: nil)]
                : selected.map { WidgetQuotaMetric(id: $0.id, title: $0.scope.map { "\($0) 5 小时已用" } ?? "5 小时已用", window: $0) }
        case .claude:
            return visible.map { WidgetQuotaMetric(id: $0.id, title: $0.displayName, window: $0) }
        }
    }
}

struct WidgetQuotaMetric: Identifiable {
    let id: String
    let title: String
    let window: QuotaWindow?

    var valueText: String {
        guard let window else { return "未提供" }
        if window.isExhausted == true { return "已用尽" }
        if window.isUnlimited { return "无限" }
        guard let value = window.usedPercentage, value.isFinite else { return "未提供" }
        return value.formatted(.number.precision(.fractionLength(0...1))) + "%"
    }

    var ringFraction: Double? {
        guard let window,
              let value = QuotaFormatting.effectiveUsedPercentage(window),
              value.isFinite
        else { return nil }
        return min(max(value / 100, 0), 1)
    }
}

enum WidgetPresentationFamily: Equatable {
    case single
    case medium
    case large

    var accountLimit: Int {
        switch self {
        case .single: 1
        case .medium: 2
        case .large: 4
        }
    }
}

struct WidgetPresentationSelection: Equatable {
    let accounts: [WidgetAccountSnapshot]
    let selectionRequired: Bool
    let accountSelectionMissing: Bool
    let hasAvailableAccounts: Bool
}

enum WidgetPresentation {
    static func select(
        _ snapshots: [WidgetAccountSnapshot],
        selectedIDs: [UUID],
        family: WidgetPresentationFamily
    ) -> WidgetPresentationSelection {
        var seen: Set<UUID> = []
        let requestedIDs = Array(
            selectedIDs.filter { seen.insert($0).inserted }.prefix(family.accountLimit)
        )
        let accountsByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        let accounts = requestedIDs.compactMap { accountsByID[$0] }
        return WidgetPresentationSelection(
            accounts: accounts,
            selectionRequired: requestedIDs.isEmpty,
            accountSelectionMissing: accounts.count != requestedIDs.count,
            hasAvailableAccounts: !snapshots.isEmpty
        )
    }
}

actor WatchWidgetSelectionStore {
    private let defaults: UserDefaults
    private let key: String

    init(
        suiteName: String = PlatformConstants.appGroupIdentifier,
        key: String = "watch.widget.selectedAccountID"
    ) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.key = key
    }

    func load() -> UUID? {
        defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    func save(_ accountID: UUID?) {
        if let accountID { defaults.set(accountID.uuidString, forKey: key) }
        else { defaults.removeObject(forKey: key) }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

actor WidgetSnapshotStore {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults? = UserDefaults(suiteName: PlatformConstants.appGroupIdentifier),
        key: String = "widget.accountSnapshots"
    ) {
        self.defaults = defaults ?? .standard
        self.key = key
    }

    func load() -> [WidgetAccountSnapshot] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([WidgetAccountSnapshot].self, from: data)) ?? []
    }

    func save(states: [AccountQuotaState]) throws {
        let snapshots = states.map { state in
            WidgetAccountSnapshot(
                account: state.account,
                windows: state.snapshot?.windows ?? [],
                collectedAt: state.snapshot?.collectedAt,
                lastFailure: state.lastFailure,
                remainingResetCount: state.snapshot?.remainingResetCount,
                subscriptionPlan: state.snapshot?.subscriptionPlan
            )
        }
        try save(snapshots)
    }

    func save(_ snapshots: [WidgetAccountSnapshot]) throws {
        defaults.set(try JSONEncoder().encode(snapshots), forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
