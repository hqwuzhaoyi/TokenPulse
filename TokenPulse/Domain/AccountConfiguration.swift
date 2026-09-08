import Foundation

struct AccountConfiguration: Codable, Equatable, Identifiable, Sendable {
    var account: SubscriptionAccount
    var followOrder: Int?
    var reminders: AccountReminderSettings
    var modifiedAt: Date

    var id: UUID { account.id }

    init(account: SubscriptionAccount, followOrder: Int? = nil,
         reminders: AccountReminderSettings = AccountReminderSettings(), modifiedAt: Date = Date()) {
        self.account = account
        self.followOrder = followOrder
        self.reminders = reminders
        self.modifiedAt = modifiedAt
    }
}

protocol AccountConfigurationStoring: Sendable {
    func load() async throws -> [AccountConfiguration]
    func save(_ configurations: [AccountConfiguration]) async throws
}

actor LocalAccountConfigurationStore: AccountConfigurationStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() throws -> [AccountConfiguration] {
        guard let data = defaults.data(forKey: "accountConfigurations") else { return [] }
        return try JSONDecoder().decode([AccountConfiguration].self, from: data)
    }

    func save(_ configurations: [AccountConfiguration]) throws {
        defaults.set(try JSONEncoder().encode(configurations), forKey: "accountConfigurations")
    }
}
