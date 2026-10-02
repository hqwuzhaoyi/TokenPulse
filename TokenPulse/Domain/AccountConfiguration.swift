import Foundation

enum AlibabaTokenPlanSite: String, Codable, CaseIterable, Identifiable, Sendable {
    case domestic, international
    var id: String { rawValue }
    var displayName: String { self == .domestic ? "阿里云国内站" : "Alibaba Cloud 国际站" }
}

struct AccountConfiguration: Codable, Equatable, Identifiable, Sendable {
    var account: SubscriptionAccount
    var reminders: AccountReminderSettings
    var modifiedAt: Date
    var deletedAt: Date?
    var isWatchFavorite: Bool?
    var serverAddress: String?
    var providerRegion: ProviderRegion?
    var organizationID: String?
    var tokenPlanSite: AlibabaTokenPlanSite?
    var credentialIdentity: String?

    var id: UUID { account.id }

    init(account: SubscriptionAccount,
         reminders: AccountReminderSettings = AccountReminderSettings(), modifiedAt: Date = Date()) {
        self.account = account
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

    init(suiteName: String?) {
        self.defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    func load() throws -> [AccountConfiguration] {
        guard let data = defaults.data(forKey: "accountConfigurations") else { return [] }
        return try JSONDecoder().decode([AccountConfiguration].self, from: data)
    }

    func save(_ configurations: [AccountConfiguration]) throws {
        defaults.set(try JSONEncoder().encode(configurations), forKey: "accountConfigurations")
    }
}
