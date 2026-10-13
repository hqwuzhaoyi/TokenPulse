import Foundation

struct AixyProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    private struct Reply: Decodable {
        struct Key: Decodable { let id: String; let project_id: String? }
        struct Budget: Decodable {
            struct Target: Decodable { let api_key_id: String?; let project_id: String? }
            struct Availability: Decodable {
                let status: String?
                let spent_usd: HostedQuotaAmount?
                let reserved_usd: HostedQuotaAmount?
            }
            let id: String?
            let scope: String?
            let target_name: String?
            let shared: Bool?
            let interval: String?
            let enforcement: String?
            let limit_usd: HostedQuotaAmount?
            let applies_to: [Target]?
            let availability: Availability?
            let spend_status: String?
            let spend_usd: HostedQuotaAmount?
            let resets_at: String?
        }
        let object: String
        let currency: String
        let key: Key
        let budgets: [Budget]
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try await KeyQuotaRequest.fetch(provider: .aixy, endpoint: "https://api.aixy-gateway.com/v1/usage",
            accountID: accountID, credential: credential, transport: transport, now: now, parse: Self.snapshot)
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let reply = try KeyQuotaRequest.decode(Reply.self, from: data)
        guard reply.object == "key.usage", reply.currency == "USD", !reply.key.id.isEmpty else {
            throw RefreshFailure.unreadableResponse
        }
        let periods: [(String, String, QuotaPeriod?)] = [
            ("daily", "每日", .other), ("weekly", "每周", .weekly),
            ("monthly", "每月", .monthly), ("lifetime", "累计", nil),
        ]
        var knownIDs: Set<String> = []
        let candidates = try reply.budgets.compactMap { budget -> (String, Bool, QuotaWindow)? in
            guard let id = budget.id, !id.isEmpty,
                  let interval = budget.interval, let shape = periods.first(where: { $0.0 == interval }),
                  let targets = budget.applies_to, !targets.isEmpty,
                  targets.allSatisfy({ $0.api_key_id == reply.key.id && $0.project_id == reply.key.project_id }),
                  let limit = budget.limit_usd?.positive else { return nil }
            guard knownIDs.insert(id).inserted else { throw RefreshFailure.unreadableResponse }
            let hard = budget.enforcement == "hard"
            let used: Decimal?
            if hard {
                if budget.availability?.status == "available",
                   let spent = budget.availability?.spent_usd?.nonnegative,
                   let reserved = budget.availability?.reserved_usd?.nonnegative {
                    guard let amount = HostedQuotaMath.sum(spent, reserved) else { throw RefreshFailure.unreadableResponse }
                    used = amount
                } else { used = nil }
            } else {
                guard budget.enforcement == "monitor" else { return nil }
                used = budget.spend_status == "available" ? budget.spend_usd?.nonnegative : nil
            }
            let counts: DecimalQuotaCounts
            let percentage: Double?
            if let used {
                guard let value = HostedQuotaMath.counts(used: used, limit: limit),
                      let percent = HostedQuotaMath.percentage(used: used, limit: limit) else {
                    throw RefreshFailure.unreadableResponse
                }
                counts = value; percentage = percent
            } else { counts = .init(total: limit); percentage = nil }
            let scopeName = ["organization": "组织", "project": "项目", "team": "团队", "user": "用户", "api_key": "Key"][budget.scope ?? ""]
            let scope = [scopeName, budget.target_name, budget.shared == true ? "共享" : nil]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            let scopePresentation = QuotaScopePresentation(kind: budget.scope.flatMap(QuotaScopePresentation.Kind.init(rawValue:)),
                                                           name: budget.target_name, isShared: budget.shared == true)
            let window = QuotaWindow(id: "aixy.\(id)", name: "\(shape.1)\(hard ? "预算" : "监控预算")\(used == nil ? "（用量未提供）" : "")", scope: scope.isEmpty ? nil : scope,
                period: shape.2, usedPercentage: percentage, remainingCount: nil, totalCount: nil,
                resetsAt: interval == "lifetime" ? nil : KeyQuotaRequest.date(budget.resets_at), unit: "USD",
                exactCounts: counts, resetSemantics: interval == "lifetime" ? .nonResettingAllowance : nil,
                presentationScope: scope.isEmpty ? nil : scopePresentation)
            return (interval, hard, window)
        }
        // Applicable limits overlap, so keep them separate rather than discarding a scope.
        let windows = periods.flatMap { interval, _, _ in
            candidates.filter { $0.0 == interval }.sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 }
                if lhs.2.usedPercentage != rhs.2.usedPercentage {
                    return (lhs.2.usedPercentage ?? 0) > (rhs.2.usedPercentage ?? 0)
                }
                return lhs.2.id < rhs.2.id
            }.map(\.2)
        }
        return .init(accountID: accountID, windows: windows, collectedAt: collectedAt)
    }
}
