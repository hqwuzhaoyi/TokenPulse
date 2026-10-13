import Foundation

/// Narrow compatibility with Pulse's pinned, second-hand legacy credit_summary contract.
/// This is not the public Organization Costs API, and its key compatibility is not universal.
struct OpenAIAPIProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    static let endpoint = URL(string: "https://api.openai.com/v1/dashboard/billing/credit_grants")!
    static let connectionNotice = "使用旧版余额接口，兼容性因账号与 Key 而异；该接口不可用时无法显示余额。"

    private struct Reply: Decodable {
        let total_available: WalletNumericDecimal
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .openAIAPI, credential.kind == .apiKey,
              !credential.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RefreshFailure.invalidCredential
        }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            guard ProviderRedirectPolicy.permits(origin: Self.endpoint, target: response.url) else {
                throw RefreshFailure.server
            }
            // Billing permission and route failures do not imply a key is unusable for inference.
            if response.statusCode == 403 { throw RefreshFailure.insufficientPermissions }
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            return .init(snapshot: try Self.snapshot(data, accountID: accountID, collectedAt: now()),
                         updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw RefreshFailure.unreadableResponse
        }
        // USD is specified by the pinned legacy contract, not inferred from Costs or another wallet.
        // Lifetime granted/used and individual grant expiry are not quota or replenishment periods.
        let wallet = WalletBalance(currency: "USD", total: reply.total_available.amount)
        return .init(accountID: accountID, windows: [
            WalletExpansionHTTP.walletWindow(id: "openAIAPI.wallet.USD", wallet: wallet)
        ], collectedAt: collectedAt)
    }
}
