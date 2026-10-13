import Foundation

struct VeniceProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    static let endpoint = URL(string: "https://api.venice.ai/api/v1/billing/balance")!
    private struct Figure: Decodable {
        let amount: Decimal?
        init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer()
            if value.decodeNil() { amount = nil; return }
            if let text = try? value.decode(String.self) {
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                amount = trimmed.isEmpty ? nil : try ProviderDecimal.amount(trimmed)
            } else {
                let parsed = try value.decode(Decimal.self)
                guard !parsed.isNaN else { throw RefreshFailure.unreadableResponse }
                amount = parsed
            }
        }
    }
    private struct Reply: Decodable {
        struct Balances: Decodable {
            let usd: Figure?
            let diem: Figure?
            let bundledCredits: Figure?
            let earnedCredits: Figure?
        }
        let canConsume: Bool
        let consumptionCurrency: String?
        let balances: Balances
    }
    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try await WalletExpansionHTTP.query(endpoint: Self.endpoint, provider: .venice, accountID: accountID,
                                            credential: credential, transport: transport, now: now, parse: Self.snapshot)
    }
    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        let preference = reply.consumptionCurrency?.uppercased()
        let usd = reply.balances.usd?.amount, diem = reply.balances.diem?.amount
        let bundled = reply.balances.bundledCredits?.amount, earned = reply.balances.earnedCredits?.amount
        let currency: String
        let amount: Decimal?
        switch preference {
        case "USD": (currency, amount) = ("USD", usd)
        case "DIEM": (currency, amount) = ("DIEM", diem)
        // The official API describes VCU as the deprecated Legacy Diem name.
        // Preserve the returned consumption unit; this is an alias, not a rate.
        case "VCU": (currency, amount) = ("VCU", diem)
        case "BUNDLED_CREDITS": (currency, amount) = ("BUNDLED_CREDITS", bundled)
        case "EARNED_CREDITS": (currency, amount) = ("EARNED_CREDITS", earned)
        case nil, "":
            if let usd { (currency, amount) = ("USD", usd) }
            else if let diem { (currency, amount) = ("DIEM", diem) }
            else if let earned { (currency, amount) = ("EARNED_CREDITS", earned) }
            else { (currency, amount) = ("BUNDLED_CREDITS", bundled) }
        default: throw RefreshFailure.unreadableResponse
        }
        guard let amount else { throw RefreshFailure.noQuotaWindows }
        let wallet = WalletBalance(currency: currency, total: amount, isMonetary: currency == "USD")
        // canConsume and diemEpochAllocation are not usage percentages. No
        // exchange rate or reset period is inferred from either field.
        return QuotaSnapshot(accountID: accountID,
                             windows: [WalletExpansionHTTP.walletWindow(id: "venice.balance.\(wallet.currency)", wallet: wallet)],
                             collectedAt: collectedAt)
    }
}
