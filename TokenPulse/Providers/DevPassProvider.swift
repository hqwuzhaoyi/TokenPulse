import Foundation

struct DevPassProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .devPass, credential.kind == .apiKey else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: URL(string: "https://api.llmgateway.io/v1/key")!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            return .init(snapshot: try Self.snapshot(data, accountID: accountID, collectedAt: now()), updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private struct Reply: Decodable {
        struct Key: Decodable {
            let usage: String?
            let limit: String?
            let devPlan: String
            let devPlanCreditsUsed: String?
            let devPlanCreditsLimit: String?
            let devPlanPremiumCreditsUsed: String?
            let devPlanPremiumWeeklyLimit: String?
            let devPlanPremiumWeekResetsAt: String?
        }
        let data: Key
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let key = try? JSONDecoder().decode(Reply.self, from: data).data,
              ["none", "lite", "pro", "max"].contains(key.devPlan) else { throw RefreshFailure.unreadableResponse }
        var windows: [QuotaWindow] = []
        if key.devPlan != "none" {
            let reset: Date?
            if let text = key.devPlanPremiumWeekResetsAt {
                guard let value = ProviderHTTP.isoDate(text), value.timeIntervalSince1970.isFinite,
                      Int64(exactly: (value.timeIntervalSince1970 * 1000).rounded()) != nil else { throw RefreshFailure.unreadableResponse }
                reset = value
            } else { reset = nil }
            if let premium = try window(id: "devpass.premium_weekly", name: "Premium 每周额度", period: .weekly,
                                        used: key.devPlanPremiumCreditsUsed, total: key.devPlanPremiumWeeklyLimit, reset: reset) { windows.append(premium) }
            if let cycle = try window(id: "devpass.cycle", name: "账期 credits", period: .other,
                                      used: key.devPlanCreditsUsed, total: key.devPlanCreditsLimit, reset: nil) { windows.append(cycle) }
        }
        if let budget = try window(id: "devpass.key_limit", name: "Key 累计限额", period: .other,
                                   used: key.usage, total: key.limit, reset: nil) { windows.append(budget) }
        guard key.devPlan == "none" || !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt,
                             providerPlanName: key.devPlan == "none" ? "按量计费" : key.devPlan.capitalized,
                             isNoPlan: key.devPlan == "none" && windows.isEmpty ? true : nil)
    }

    private static func window(id: String, name: String, period: QuotaPeriod, used rawUsed: String?,
                               total rawTotal: String?, reset: Date?) throws -> QuotaWindow? {
        let used = try amount(rawUsed)
        let total = try amount(rawTotal)
        guard let used, let total, total > 0 else { return nil }
        var remaining = Decimal(0)
        if used <= total {
            var lhs = total, rhs = used
            guard NSDecimalSubtract(&remaining, &lhs, &rhs, .plain) == .noError else { throw RefreshFailure.unreadableResponse }
        }
        let percentage = NSDecimalNumber(decimal: used).doubleValue / NSDecimalNumber(decimal: total).doubleValue * 100
        guard percentage.isFinite else { throw RefreshFailure.unreadableResponse }
        return QuotaWindow(id: id, name: name, scope: nil, period: period, isExhausted: used >= total,
                           usedPercentage: min(percentage, 100), remainingCount: nil, totalCount: nil,
                           resetsAt: reset, unit: "USD credits", exactCounts: .init(used: used, remaining: remaining, total: total))
    }

    static func amount(_ text: String?) throws -> Decimal? {
        guard let text else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.utf8.count <= 256,
              cleaned.range(of: #"\A[0-9]+(?:\.[0-9]+)?\z"#, options: .regularExpression) != nil else { throw RefreshFailure.unreadableResponse }
        let digits = cleaned.filter { $0 != "." }.drop(while: { $0 == "0" })
        guard digits.count <= 38,
              let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN,
              value >= 0, digits.isEmpty || value > 0 else { throw RefreshFailure.unreadableResponse }
        return value
    }
}
