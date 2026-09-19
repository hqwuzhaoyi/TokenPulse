import Foundation

actor LocalAccountStateStore: AccountStateStoring {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, key: String = "accountQuotaStates") {
        self.defaults = defaults
        self.key = key
    }

    init(suiteName: String?) {
        self.defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.key = "accountQuotaStates"
    }

    func load() throws -> [AccountQuotaState] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return try decoder.decode([AccountQuotaState].self, from: data)
    }

    func save(_ states: [AccountQuotaState]) throws {
        defaults.set(try encoder.encode(states), forKey: key)
    }
}
