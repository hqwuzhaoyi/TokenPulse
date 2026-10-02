import Foundation

/// Device-side GET for the fixed balance routes; credentials never enter URLs.
enum WalletExpansionHTTP {
    static func query(endpoint: URL, provider: Provider, accountID: UUID,
                      credential: ProviderCredentialEnvelope, transport: any ProviderTransport,
                      now: @Sendable () -> Date,
                      parse: (Data, UUID, Date) throws -> QuotaSnapshot) async throws -> ProviderQueryResult {
        guard credential.provider == provider, credential.kind == .apiKey,
              !credential.accessToken.isEmpty else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            return ProviderQueryResult(snapshot: try parse(data, accountID, now()), updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    static func walletWindow(id: String, wallet: WalletBalance) -> QuotaWindow {
        QuotaWindow(id: id, name: wallet.isMonetary ? "API 钱包余额" : "剩余 \(wallet.currency)", scope: nil,
                    usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                    unit: wallet.currency, wallet: wallet)
    }
}
