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
        if provider == .jetBrainsAI {
            guard let local = credentialStore as? any DeviceOAuthVaultProviding else { throw RefreshFailure.invalidCredential }
            return try await JetBrainsSessionCoordinator.shared.quota(accountID: accountID, vault: local.deviceOAuthVault,
                transport: transport ?? URLSessionProviderTransport.rejectingRedirects(), now: now)
        }
        if provider == .nousPortal {
            guard let local = credentialStore as? any DeviceOAuthVaultProviding else { throw RefreshFailure.invalidCredential }
            return try await NousSessionCoordinator.shared.quota(accountID: accountID, vault: local.deviceOAuthVault,
                transport: transport ?? URLSessionProviderTransport.rejectingRedirects(), now: now)
        }
        do {
            let authentication = ProviderAuthenticationController(transport: transport ?? URLSessionProviderTransport(), now: now)
            let refreshed = try await authentication.refreshCredentialIfNeeded(provider: provider, credential: credential)
            if refreshed.changed { try await credentialStore.save(refreshed.credential, for: accountID, provider: provider) }
            let result = try await ProviderQuotaClient(provider: provider, transport: transport, now: now)
                .quotaResult(for: accountID, credential: refreshed.credential)
            if let updated = result.updatedCredential { try await credentialStore.save(updated, for: accountID, provider: provider) }
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
