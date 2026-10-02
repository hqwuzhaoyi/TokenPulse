import Foundation

struct HyperProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    static let endpoint = URL(string: "https://hyper.charm.land/v1/credits")!
    private struct Reply: Decodable { let balance: WalletNumericDecimal }
    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try await WalletExpansionHTTP.query(endpoint: Self.endpoint, provider: .hyper, accountID: accountID,
                                            credential: credential, transport: transport, now: now, parse: Self.snapshot)
    }
    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data), reply.balance.amount >= 0 else {
            throw RefreshFailure.unreadableResponse
        }
        let wallet = WalletBalance(currency: "HC", total: reply.balance.amount, isMonetary: false)
        return QuotaSnapshot(accountID: accountID,
                             windows: [WalletExpansionHTTP.walletWindow(id: "hyper.HC", wallet: wallet)], collectedAt: collectedAt)
    }
}
