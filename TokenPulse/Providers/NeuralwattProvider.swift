import Foundation

struct NeuralwattProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    private struct Reply: Decodable {
        struct Balance: Decodable {
            let credits_remaining_usd: HostedQuotaAmount?
            let total_credits_usd: HostedQuotaAmount?
            let credits_used_usd: HostedQuotaAmount?
        }
        struct Subscription: Decodable {
            let plan: String?
            let billing_interval: String?
            let current_period_start: String?
            let current_period_end: String?
            let kwh_included: HostedQuotaAmount?
            let kwh_used: HostedQuotaAmount?
        }
        struct Key: Decodable {
            struct Allowance: Decodable {
                let limit_usd: HostedQuotaAmount?
                let spent_usd: HostedQuotaAmount?
                let period: String?
            }
            let allowance: Allowance?
        }
        let balance: Balance
        let subscription: Subscription?
        let key: Key?
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try await KeyQuotaRequest.fetch(provider: .neuralwatt, endpoint: "https://api.neuralwatt.com/v1/quota",
            accountID: accountID, credential: credential, transport: transport, now: now, parse: Self.snapshot)
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let reply = try KeyQuotaRequest.decode(Reply.self, from: data)
        var windows: [QuotaWindow] = []
        if let sub = reply.subscription, let used = sub.kwh_used?.nonnegative, let total = sub.kwh_included?.positive,
           let counts = HostedQuotaMath.counts(used: used, limit: total),
           let percent = HostedQuotaMath.percentage(used: used, limit: total) {
            let end = KeyQuotaRequest.date(sub.current_period_end)
            let period: QuotaPeriod? = switch sub.billing_interval?.lowercased() {
            case "month", "monthly": .monthly
            default: KeyQuotaRequest.date(sub.current_period_start).flatMap { start in
                end.flatMap { date in
                    guard date > start, let seconds = Int(exactly: date.timeIntervalSince(start)) else { return nil }
                    return QuotaPeriod(seconds: seconds)
                }
            }
            }
            windows.append(QuotaWindow(id: "neuralwatt.subscription", name: "订阅能量额度", scope: nil, period: period,
                usedPercentage: percent, remainingCount: nil, totalCount: nil, resetsAt: end,
                unit: "kWh", exactCounts: counts))
        }
        if let allowance = reply.key?.allowance, let used = allowance.spent_usd?.nonnegative,
           let total = allowance.limit_usd?.positive,
           let counts = HostedQuotaMath.counts(used: used, limit: total),
           let percent = HostedQuotaMath.percentage(used: used, limit: total) {
            let period: QuotaPeriod? = switch allowance.period?.lowercased() {
            case "weekly", "week": .weekly
            case "daily", "day": .other
            case "monthly", "month": .monthly
            default: nil
            }
            windows.append(QuotaWindow(id: "neuralwatt.key", name: "Key 支出限额", scope: nil, period: period,
                usedPercentage: percent, remainingCount: nil, totalCount: nil, resetsAt: nil,
                unit: "USD", exactCounts: counts))
        }
        let money: Decimal?
        if let available = reply.balance.credits_remaining_usd?.value {
            money = available
        } else if let total = reply.balance.total_credits_usd?.nonnegative,
                  let spent = reply.balance.credits_used_usd?.nonnegative {
            guard let difference = HostedQuotaMath.difference(total, spent) else { throw RefreshFailure.unreadableResponse }
            money = difference
        } else { money = nil }
        if let money {
            windows.append(QuotaWindow(id: "neuralwatt.wallet", name: "API 钱包余额", scope: nil,
                usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                wallet: WalletBalance(currency: "USD", total: money)))
        }
        return .init(accountID: accountID, windows: windows, collectedAt: collectedAt,
                     providerPlanName: reply.subscription?.plan)
    }
}
