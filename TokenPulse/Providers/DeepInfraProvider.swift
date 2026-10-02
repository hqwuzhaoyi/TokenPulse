import Foundation

struct DeepInfraProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    static let endpoint = URL(string: "https://api.deepinfra.com/payment/checklist?compute_owed=true")!
    private struct Reply: Decodable {
        let stripe_balance: WalletNumericDecimal
        let recent: WalletNumericDecimal
        let limit: WalletNumericDecimal?
    }
    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try await WalletExpansionHTTP.query(endpoint: Self.endpoint, provider: .deepInfra, accountID: accountID,
                                            credential: credential, transport: transport, now: now, parse: Self.snapshot)
    }
    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        let unbilled = max(reply.recent.amount, 0)
        // Prepaid funds are negative in the service ledger; debt stays negative
        // after reversing the ledger and subtracting pending spend exactly once.
        let balance = -1 * (try WalletDecimalArithmetic.add(reply.stripe_balance.amount, unbilled))
        guard !balance.isNaN else { throw RefreshFailure.unreadableResponse }
        var windows = [WalletExpansionHTTP.walletWindow(id: "deepInfra.wallet.USD", wallet: WalletBalance(currency: "USD", total: balance))]
        if let limit = reply.limit?.amount, limit > 0 {
            let remaining = max(try WalletDecimalArithmetic.add(limit, -unbilled), 0)
            windows.append(QuotaWindow(id: "deepInfra.spend", name: "支出上限", scope: nil, period: .other,
                                       isExhausted: unbilled >= limit,
                                       usedPercentage: try WalletDecimalArithmetic.percentage(used: unbilled, total: limit),
                                       remainingCount: nil, totalCount: nil, resetsAt: nil, unit: "USD",
                                       exactCounts: DecimalQuotaCounts(used: unbilled, remaining: remaining, total: limit)))
        }
        // Suspended is a health flag, not a percentage or a reset observation.
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt)
    }
}
