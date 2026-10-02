import Foundation

struct AtlasCloudProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    static let endpoint = URL(string: "https://api.atlascloud.ai/public/v1/balance")!

    private struct Reply: Decodable {
        struct Available: Decodable { let value: String; let currency: String }
        let object: String
        let scope: String
        let available: Available
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try await WalletExpansionHTTP.query(endpoint: Self.endpoint, provider: .atlasCloud, accountID: accountID,
                                            credential: credential, transport: transport, now: now, parse: Self.snapshot)
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              reply.object == "balance", reply.scope == "account",
              reply.available.currency.utf8.count == 3,
              reply.available.currency.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }) else {
            throw RefreshFailure.unreadableResponse
        }
        let wallet = WalletBalance(currency: reply.available.currency.uppercased(),
                                   total: try ProviderDecimal.amount(reply.available.value))
        return QuotaSnapshot(accountID: accountID, windows: [
            WalletExpansionHTTP.walletWindow(id: "atlasCloud.wallet.\(wallet.currency)", wallet: wallet)
        ], collectedAt: collectedAt)
    }
}
