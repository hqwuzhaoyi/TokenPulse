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
            .sorted {
                (($0.followOrder ?? .max), $0.id.uuidString)
                    < (($1.followOrder ?? .max), $1.id.uuidString)
            }
            .map(WidgetAccountEntity.init)
    }
}

struct QuotaWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "选择账号"
    static let description = IntentDescription("按渠道在同一个组件中汇总显示账号额度。")

    @Parameter(title: "账号")
    var account: WidgetAccountEntity?

}

private extension WidgetAccountEntity {
    init(_ snapshot: WidgetAccountSnapshot) {
        id = snapshot.id.uuidString
        name = snapshot.account.name
        providerName = snapshot.account.provider.displayName
    }
}
