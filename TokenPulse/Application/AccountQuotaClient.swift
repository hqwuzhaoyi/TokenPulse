import Foundation

struct AccountQuotaClient: QuotaQuerying {
    let provider: Provider
    let credentialStore: any CredentialStoring
    private let transport: (any ProviderTransport)?
    private let now: @Sendable () -> Date

    init(provider: Provider, credentialStore: any CredentialStoring,
         transport: (any ProviderTransport)? = nil, now: @escaping @Sendable () -> Date = Date.init) {
        self.provider = provider
        self.credentialStore = credentialStore
        self.transport = transport
        self.now = now
    }

    func quota(for accountID: UUID, credential: String) async throws -> QuotaSnapshot {
        if provider == .miniMaxChina {
            return try await MiniMaxQuotaClient().quota(for: accountID, credential: credential)
        }
        do {
            let authentication = ProviderAuthenticationController(transport: transport ?? URLSessionProviderTransport(), now: now)
            let refreshed = try await authentication.refreshCredentialIfNeeded(provider: provider, credential: credential)
            if refreshed.changed { try await credentialStore.save(refreshed.credential, for: accountID) }
            let result = try await ProviderQuotaClient(provider: provider, transport: transport, now: now)
                .quotaResult(for: accountID, credential: refreshed.credential)
            if let updated = result.updatedCredential { try await credentialStore.save(updated, for: accountID) }
            return result.snapshot
        } catch let error as ProviderIntegrationError {
            switch error {
            case .invalidCredential, .invalidCredentialData, .loginExpired, .invalidCallback, .unsupportedLogin:
                throw RefreshFailure.invalidCredential
            case .rateLimited: throw RefreshFailure.rateLimited
            case .network: throw RefreshFailure.network
            case .noQuotaWindows: throw RefreshFailure.noQuotaWindows
            case .unreadableResponse: throw RefreshFailure.unreadableResponse
            case .server, .loginPending: throw RefreshFailure.server
            }
        }
    }
}
