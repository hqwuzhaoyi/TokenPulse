import Foundation

struct CursorProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        var request = URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue(try CursorAccountSession.cookie(credential, accountID: accountID, now: now()), forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            var snapshot = try Self.snapshot(data, accountID: accountID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = credential.metadata["sourceCredentialFingerprint"]
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private struct Amount: Decodable {
        let value: Decimal
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) { value = try ProviderDecimal.amount(text) }
            else { value = try container.decode(Decimal.self) }
            guard !value.isNaN else { throw RefreshFailure.unreadableResponse }
        }
    }
    private struct Allowance: Decodable {
        let enabled: Bool?
        let used: Amount?
        let limit: Amount?
        let remaining: Amount?
        let autoPercentUsed: Double?
        let apiPercentUsed: Double?
    }
    private struct Reply: Decodable {
        struct Individual: Decodable { let plan: Allowance?; let onDemand: Allowance? }
        struct Team: Decodable { let pooled: Allowance?; let onDemand: Allowance? }
        let billingCycleEnd: String?
        let membershipType: String?
        let individualUsage: Individual?
        let teamUsage: Team?
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        let reset = reply.billingCycleEnd.flatMap(ProviderHTTP.isoDate)
        let plan = reply.individualUsage?.plan ?? reply.teamUsage?.pooled
        var windows: [QuotaWindow] = []
        if plan?.enabled != false {
            for (raw, id, scope) in [(plan?.autoPercentUsed, "cursorModels", "Cursor Models"), (plan?.apiPercentUsed, "otherModels", "Other Models")] {
                guard let raw, raw.isFinite, raw >= 0 else { continue }
                // 0.0267 is 0.0267%, never interpreted as a fraction.
                windows.append(.init(id: "cursor.\(id)", name: "每月额度", scope: scope, period: .monthly,
                    isExhausted: raw >= 100, usedPercentage: min(raw, 100), remainingCount: nil, totalCount: nil, resetsAt: reset))
            }
        }
        // The plan's cash value is a different denominator from its model
        // pools. It can only be a fallback when neither pool is reported.
        if windows.isEmpty, let cash = money(plan, id: "planCash", name: "套餐金额额度", reset: reset) { windows.append(cash) }
        if let demand = money(reply.individualUsage?.onDemand ?? reply.teamUsage?.onDemand,
                              id: "onDemand", name: "额外支出额度", reset: reset) { windows.append(demand) }
        guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        let planName = reply.membershipType?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(accountID: accountID, windows: windows, collectedAt: collectedAt,
                     providerPlanName: planName?.isEmpty == false ? planName : nil)
    }

    private static func money(_ allowance: Allowance?, id: String, name: String, reset: Date?) -> QuotaWindow? {
        guard let allowance, allowance.enabled != false,
              let limitCents = allowance.limit?.value, limitCents > 0 else { return nil }
        let total = limitCents / 100
        let used = (allowance.used?.value).flatMap { $0 >= 0 ? $0 / 100 : nil }
        let remaining = (allowance.remaining?.value).map { $0 / 100 } ?? used.map { max(total - $0, 0) }
        let exact = used.flatMap { used in remaining.map { DecimalQuotaCounts(used: used, remaining: $0, total: total) } }
        let percentage = used.map { NSDecimalNumber(decimal: $0 / total * 100).doubleValue }.flatMap { $0.isFinite ? $0 : nil }
        return .init(id: "cursor.\(id)", name: name, scope: nil, period: .monthly,
            isExhausted: used.map { $0 >= total }, usedPercentage: percentage,
            remainingCount: remaining.map { NSDecimalNumber(decimal: $0).doubleValue }, totalCount: NSDecimalNumber(decimal: total).doubleValue,
            resetsAt: reset, unit: "USD 预算", exactCounts: exact)
    }
}
