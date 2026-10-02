import Foundation

struct HostedQuotaAmount: Decodable, Sendable {
    let value: Decimal

    init(from decoder: any Decoder) throws {
        let field = try decoder.singleValueContainer()
        if let text = try? field.decode(String.self) {
            value = try ProviderDecimal.amount(text)
        } else {
            value = try field.decode(Decimal.self)
        }
        guard !value.isNaN else { throw RefreshFailure.unreadableResponse }
    }
    var nonnegative: Decimal? { value >= 0 ? value : nil }
    var positive: Decimal? { value > 0 ? value : nil }
}

enum HostedQuotaMath {
    static func sum(_ lhs: Decimal, _ rhs: Decimal) -> Decimal? {
        var a = lhs, b = rhs, result = Decimal()
        return NSDecimalAdd(&result, &a, &b, .plain) == .noError ? result : nil
    }
    static func difference(_ lhs: Decimal, _ rhs: Decimal) -> Decimal? {
        var a = lhs, b = rhs, result = Decimal()
        return NSDecimalSubtract(&result, &a, &b, .plain) == .noError ? result : nil
    }
    static func percentage(used: Decimal, limit: Decimal) -> Double? {
        guard used >= 0, limit > 0 else { return nil }
        var numerator = used, denominator = limit, ratio = Decimal()
        let status = NSDecimalDivide(&ratio, &numerator, &denominator, .down)
        guard status == .noError || status == .lossOfPrecision, !ratio.isNaN else { return nil }
        let result = NSDecimalNumber(decimal: ratio).doubleValue * 100
        guard result.isFinite else { return nil }
        return used < limit ? min(result, Double(100).nextDown) : result
    }
    static func counts(used: Decimal, limit: Decimal) -> DecimalQuotaCounts? {
        guard used >= 0, limit > 0, let left = difference(limit, used) else { return nil }
        return .init(used: used, remaining: max(0, left), total: limit)
    }
}

private struct CodebuffReset: Decodable {
    let date: Date?
    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let text = try? value.decode(String.self) {
            date = KeyQuotaRequest.date(text) ?? Self.epoch(Double(text))
        } else {
            date = Self.epoch(try? value.decode(Double.self))
        }
    }
    private static func epoch(_ value: Double?) -> Date? {
        guard let value, value.isFinite, value > 0 else { return nil }
        let seconds = value > 10_000_000_000 ? value / 1000 : value
        guard Int64(exactly: (seconds * 1000).rounded()) != nil else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

struct CodebuffProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    private struct Reply: Decodable {
        let usage: HostedQuotaAmount?
        let used: HostedQuotaAmount?
        let quota: HostedQuotaAmount?
        let limit: HostedQuotaAmount?
        let remainingBalance: HostedQuotaAmount?
        let remaining: HostedQuotaAmount?
        let next_quota_reset: CodebuffReset?
    }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        // API keys read credits. The weekly subscription route needs a different CLI session.
        try await KeyQuotaRequest.fetch(provider: .codebuff, endpoint: "https://www.codebuff.com/api/v1/usage",
            accountID: accountID, credential: credential, transport: transport, now: now,
            body: Data(#"{"fingerprintId":"tokenpulse-usage"}"#.utf8), parse: Self.snapshot)
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let reply = try KeyQuotaRequest.decode(Reply.self, from: data)
        var windows: [QuotaWindow] = []
        let used = (reply.usage ?? reply.used)?.nonnegative
        let total = (reply.quota ?? reply.limit)?.positive
        if let used, let total, let counts = HostedQuotaMath.counts(used: used, limit: total),
           let percent = HostedQuotaMath.percentage(used: used, limit: total) {
            windows.append(QuotaWindow(id: "codebuff.credits", name: "credits 额度", scope: nil,
                usedPercentage: percent, remainingCount: nil, totalCount: nil,
                resetsAt: reply.next_quota_reset?.date, unit: "credits", exactCounts: counts))
        }
        if let balance = (reply.remainingBalance ?? reply.remaining)?.nonnegative {
            windows.append(QuotaWindow(id: "codebuff.balance", name: "剩余 credits", scope: nil,
                usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                wallet: WalletBalance(currency: "credits", total: balance, isMonetary: false)))
        }
        return .init(accountID: accountID, windows: windows, collectedAt: collectedAt)
    }
}
