import Foundation

protocol AccountStateStoring: Sendable {
    func load() async throws -> [AccountQuotaState]
    func save(_ states: [AccountQuotaState]) async throws
}
protocol CredentialStoring: Sendable {
    func save(_ credential: String, for accountID: UUID) async throws
    func credential(for accountID: UUID) async throws -> String?
    func deleteCredential(for accountID: UUID) async throws
}

protocol QuotaQuerying: Sendable {
    func quota(for accountID: UUID, credential: String) async throws -> QuotaSnapshot
}
