import Foundation

protocol AccountStateStoring: Sendable {
    func load() async throws -> [AccountQuotaState]
    func save(_ states: [AccountQuotaState]) async throws
}
protocol CredentialStoring: Sendable {
    func save(_ credential: String, for accountID: UUID) async throws
    func credential(for accountID: UUID) async throws -> String?
    func deleteCredential(for accountID: UUID) async throws
    func save(_ credential: String, for accountID: UUID, provider: Provider) async throws
    func credential(for accountID: UUID, provider: Provider) async throws -> String?
    func deleteCredential(for accountID: UUID, provider: Provider) async throws
}

extension CredentialStoring {
    func save(_ credential: String, for accountID: UUID, provider: Provider) async throws {
        try await save(credential, for: accountID)
    }
    func credential(for accountID: UUID, provider: Provider) async throws -> String? {
        try await credential(for: accountID)
    }
    func deleteCredential(for accountID: UUID, provider: Provider) async throws {
        try await deleteCredential(for: accountID)
    }
}

protocol QuotaQuerying: Sendable {
    func quota(for accountID: UUID, credential: String) async throws -> QuotaSnapshot
}
