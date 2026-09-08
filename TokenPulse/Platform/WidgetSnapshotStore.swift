import Foundation
import WidgetKit

struct WidgetAccountSnapshot: Codable, Equatable, Identifiable, Sendable {
    let account: SubscriptionAccount
    let followOrder: Int?
    let windows: [QuotaWindow]
    let collectedAt: Date?
    let lastFailure: RefreshFailure?
    var remainingResetCount: Int? = nil

    var id: UUID { account.id }

    func needsUpdate(at date: Date) -> Bool {
        windows.contains { $0.needsUpdate(at: date) }
    }

    var homeScreenMetrics: [WidgetQuotaMetric] {
        guard account.provider == .miniMaxChina else { return displayMetrics }
        let fiveHour = windows.filter { $0.name == "5 小时额度" }
        let general = fiveHour.filter { $0.scope == nil }
        let selected = general.isEmpty ? fiveHour : general
        return selected.isEmpty
            ? [WidgetQuotaMetric(id: "fiveHour", title: "5 小时已用", window: nil, showsReset: false)]
            : selected.map {
                WidgetQuotaMetric(id: $0.id, title: $0.scope.map { "\($0) 5 小时已用" } ?? "5 小时已用",
                                  window: $0, showsReset: false)
            }
    }

    var displayMetrics: [WidgetQuotaMetric] {
        let weekly = windows.filter { $0.name == "每周额度" || $0.id.hasSuffix(".weekly") }
        switch account.provider {
        case .codex:
            return [WidgetQuotaMetric(id: "weekly", title: "每周已用", window: weekly.first { $0.scope == nil }, showsReset: true)]
        case .superGrok:
            return [WidgetQuotaMetric(id: "weekly", title: "每周已用", window: windows.first { $0.id == "superGrok.pool" }, showsReset: true)]
        case .zai:
            return [
                WidgetQuotaMetric(id: "weekly", title: "每周已用", window: weekly.first { $0.scope == nil }, showsReset: false),
                WidgetQuotaMetric(id: "fiveHour", title: "5 小时已用", window: windows.first { $0.name == "5 小时额度" && $0.scope == nil }, showsReset: false),
            ]
        case .miniMaxChina:
            let general = weekly.filter { $0.scope == nil }
            let selected = general.isEmpty ? weekly : general
            return selected.isEmpty
                ? [WidgetQuotaMetric(id: "weekly", title: "每周已用", window: nil, showsReset: false)]
                : selected.map { WidgetQuotaMetric(id: $0.id, title: $0.scope.map { "\($0) 每周已用" } ?? "每周已用", window: $0, showsReset: false) }
        case .claude:
            return windows.map { WidgetQuotaMetric(id: $0.id, title: $0.name, window: $0, showsReset: true) }
        }
    }
}

struct WidgetQuotaMetric: Identifiable {
    let id: String
    let title: String
    let window: QuotaWindow?
    let showsReset: Bool
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

    func save(states: [AccountQuotaState], configurations: [AccountConfiguration]) throws {
        let configurationByID = Dictionary(uniqueKeysWithValues: configurations.map { ($0.id, $0) })
        let snapshots = states.map { state in
            WidgetAccountSnapshot(
                account: state.account,
                followOrder: configurationByID[state.id]?.followOrder,
                windows: state.snapshot?.windows ?? [],
                collectedAt: state.snapshot?.collectedAt,
                lastFailure: state.lastFailure,
                remainingResetCount: state.snapshot?.remainingResetCount
            )
        }
        try save(snapshots)
    }

    func save(_ snapshots: [WidgetAccountSnapshot]) throws {
        defaults.set(try JSONEncoder().encode(snapshots), forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
