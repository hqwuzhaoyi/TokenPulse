import Foundation
import WidgetKit

struct WidgetAccountSnapshot: Codable, Equatable, Identifiable, Sendable {
    let account: SubscriptionAccount
    var windows: [QuotaWindow]
    let collectedAt: Date?
    let lastFailure: RefreshFailure?
    var remainingResetCount: Int? = nil
    var subscriptionPlan: SubscriptionPlan? = nil
    var walletCurrency: String? = nil
    var walletAvailable: Bool? = nil
    var quotaExceeded: Bool? = nil
    var walletCollectedAt: Date? = nil
    var walletFailure: RefreshFailure? = nil
    var providerPlanName: String? = nil

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
        let limit = account.provider == .openCodeGo || account.provider == .claude || account.provider == .copilot || account.provider == .synthetic || account.provider == .cursor ? 3 : 2
        return Array(displayMetrics.prefix(limit))
    }

    var displayMetrics: [WidgetQuotaMetric] {
        let visible = QuotaPolicy.windows(windows, provider: account.provider, plan: subscriptionPlan, surface: .widget)
        if account.provider.balancePresentation == .mixed {
            return visible.map { WidgetQuotaMetric(id: $0.id, title: $0.displayName, window: $0) }
        }
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
        case .qoderInternational, .kimiCode, .elevenLabs, .poe, .zhipu, .miniMaxInternational, .stepFun, .copilot, .newAPI, .clinePass, .factory, .codebuff, .neuralwatt, .aixy, .clawRouter, .kiloCode, .deepInfra, .hyper, .venice, .commandCode, .amp, .gitKraken, .huggingFace, .synthetic, .v2ex, .xKiro, .zenMux, .alibabaCodingPlan, .chutes, .cursor, .volcengine, .ibmBob:
            return visible.map { WidgetQuotaMetric(id: $0.id, title: $0.displayName, window: $0) }
        case .deepSeek, .vercelAIGateway, .moonshot, .atlasCloud, .xaiAPI:
            let currency = walletCurrency ?? visible.compactMap(\.wallet?.currency).first
            return currency.map { currency in
                [WidgetQuotaMetric(
                    id: "wallet.\(currency)", title: currency,
                    window: visible.first { $0.wallet?.currency == currency }
                )]
            } ?? []
        }
    }

}

struct WidgetQuotaMetric: Identifiable {
    let id: String
    let title: String
    let window: QuotaWindow?

    var displayTitle: String {
        window?.wallet?.isMonetary == true ? "钱包余额" : title
    }

    var valueText: String {
        guard let window else { return "未提供" }
        if let wallet = window.wallet {
            return QuotaFormatting.balance(wallet.total, wallet: wallet)
        }
        if let overage = QuotaFormatting.overageDescription(window) { return overage }
        if window.isExhausted == true { return "已用尽" }
        if window.isUnlimited { return "无限" }
        if let value = QuotaFormatting.exactCountSummary(window) { return value }
        if window.unit != nil, window.remainingCount != nil || window.totalCount != nil {
            let remaining = QuotaFormatting.count(window.remainingCount, maximumFractionDigits: window.unit == "USD 预算额度" ? 6 : 2)
            let total = QuotaFormatting.count(window.totalCount, maximumFractionDigits: window.unit == "USD 预算额度" ? 6 : 2)
            let values = window.remainingCount == nil ? total : window.totalCount == nil ? remaining : "\(remaining) / \(total)"
            return window.unit.map { "\(values) \($0)" } ?? values
        }
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

enum WidgetAccountEntityResolution {
    static func snapshots(_ snapshots: [WidgetAccountSnapshot], matching identifiers: [String]) -> [WidgetAccountSnapshot] {
        let byID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        return identifiers.compactMap(UUID.init(uuidString:)).compactMap { byID[$0] }
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

    private var activeKey: String {
        defaults.bool(forKey: "demoModeEnabled") ? key + ".demo" : key
    }

    func load() -> UUID? {
        defaults.string(forKey: activeKey).flatMap(UUID.init(uuidString:))
    }

    func save(_ accountID: UUID?) {
        if let accountID { defaults.set(accountID.uuidString, forKey: activeKey) }
        else { defaults.removeObject(forKey: activeKey) }
        defaults.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: PlatformConstants.watchWidgetKind)
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
        let activeKey = defaults.bool(forKey: "demoModeEnabled") ? key + ".demo" : key
        guard let data = defaults.data(forKey: activeKey) else { return [] }
        return (try? JSONDecoder().decode([WidgetAccountSnapshot].self, from: data)) ?? []
    }

    func save(states: [AccountQuotaState], configurations: [AccountConfiguration] = [], isDemoMode: Bool = false) throws {
        let settingsByID = Dictionary(uniqueKeysWithValues: configurations.map { ($0.id, $0.reminders) })
        let snapshots = states.map { state in
            WidgetAccountSnapshot(
                account: state.account,
                windows: state.snapshot?.windows ?? [],
                collectedAt: state.snapshot?.collectedAt,
                lastFailure: state.lastFailure,
                remainingResetCount: state.snapshot?.remainingResetCount,
                subscriptionPlan: state.snapshot?.subscriptionPlan,
                walletCurrency: settingsByID[state.id]?.walletCurrency,
                walletAvailable: state.snapshot?.walletAvailable,
                quotaExceeded: state.snapshot?.quotaExceeded,
                walletCollectedAt: state.snapshot?.walletCollectedAt,
                walletFailure: state.snapshot?.walletFailure,
                providerPlanName: state.snapshot?.providerPlanName
            )
        }
        try save(snapshots, isDemoMode: isDemoMode)
    }

    func setDemoMode(_ enabled: Bool) {
        defaults.set(enabled, forKey: "demoModeEnabled")
        defaults.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func save(_ snapshots: [WidgetAccountSnapshot], isDemoMode: Bool = false) throws {
        defaults.set(try JSONEncoder().encode(snapshots), forKey: isDemoMode ? key + ".demo" : key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
