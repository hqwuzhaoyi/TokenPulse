import Foundation

struct ClawRouterProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    private struct Reply: Decodable {
        struct Budget: Decodable {
            let configured: Bool
            let limitMicros: Int64?
            let spentMicros: Int64?
            let windowKey: String?
        }
        let budget: Budget
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try await KeyQuotaRequest.fetch(provider: .clawRouter, endpoint: "https://clawrouter.openclaw.ai/v1/usage",
            accountID: accountID, credential: credential, transport: transport, now: now, parse: Self.snapshot)
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let reply = try KeyQuotaRequest.decode(Reply.self, from: data)
        guard reply.budget.configured, let total = reply.budget.limitMicros, total > 0,
              let spent = reply.budget.spentMicros, spent >= 0 else {
            return .init(accountID: accountID, windows: [], collectedAt: collectedAt)
        }
        let used = Decimal(spent) / 1_000_000
        let limit = Decimal(total) / 1_000_000
        guard let percentage = HostedQuotaMath.percentage(used: used, limit: limit),
              let counts = HostedQuotaMath.counts(used: used, limit: limit) else {
            throw RefreshFailure.unreadableResponse
        }
        let cycle = reply.budget.windowKey.flatMap { $0.isEmpty ? nil : $0 }
        return .init(accountID: accountID, windows: [
            QuotaWindow(id: "clawRouter.monthly", name: "每月预算", scope: nil, period: .monthly,
                usedPercentage: percentage, remainingCount: nil, totalCount: nil, resetsAt: nil,
                cycleID: cycle, unit: "USD", exactCounts: counts)
        ], collectedAt: collectedAt)
    }
}
