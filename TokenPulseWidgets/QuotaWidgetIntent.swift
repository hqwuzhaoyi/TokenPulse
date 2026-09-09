import AppIntents
import Foundation
import WidgetKit

struct WidgetAccountEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "订阅账号")
    static let defaultQuery = WidgetAccountQuery()

    let id: String
    let name: String
    let providerName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(providerName)")
    }
}

struct WidgetAccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetAccountEntity] {
        let wanted = Set(identifiers)
        return await WidgetSnapshotStore().load()
            .filter { wanted.contains($0.id.uuidString) }
            .map(WidgetAccountEntity.init)
    }

    func suggestedEntities() async throws -> [WidgetAccountEntity] {
        await WidgetSnapshotStore().load()
            .map(WidgetAccountEntity.init)
    }
}

struct QuotaWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "选择展示账号"
    static let description = IntentDescription("从 TokenPulse 主屏幕账号列表选择要在组件中展示的账号。")

    @Parameter(
        title: "展示账号",
        description: "选择顺序就是组件中的展示顺序。",
        size: [
            .systemSmall: IntentCollectionSize(exactly: 1),
            .systemMedium: IntentCollectionSize(min: 1, max: 2),
            .systemLarge: IntentCollectionSize(min: 1, max: 4),
            .systemExtraLarge: IntentCollectionSize(min: 1, max: 4),
            .accessoryCorner: IntentCollectionSize(exactly: 1),
            .accessoryCircular: IntentCollectionSize(exactly: 1),
            .accessoryRectangular: IntentCollectionSize(exactly: 1),
            .accessoryInline: IntentCollectionSize(exactly: 1),
        ]
    )
    var accounts: [WidgetAccountEntity]?

}

struct WatchQuotaWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "TokenPulse 表盘额度"
    static let description = IntentDescription("显示在 TokenPulse Watch App 设置中选择的账号。")
}

private extension WidgetAccountEntity {
    init(_ snapshot: WidgetAccountSnapshot) {
        id = snapshot.id.uuidString
        name = snapshot.account.name
        providerName = snapshot.account.provider.displayName
    }
}
