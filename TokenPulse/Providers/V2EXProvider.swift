import Foundation

struct V2EXProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.provider == .v2ex, credential.kind == .apiKey,
              credential.metadata["sourceCredentialFingerprint"] == credential.apiKeySourceFingerprint else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: URL(string: "https://edge.v2ex.com/api/v2/chat/quota")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            var snapshot = try Self.snapshot(data, accountID: accountID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = credential.apiKeySourceFingerprint
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private struct Lane: Decodable {
        let total_tokens: Double?
        let used_tokens: Double?
        let remaining_tokens: Double?
        let pack_count: Int?
    }
    private struct Reply: Decodable {
        struct Quota: Decodable {
            let active: Bool
            let total_tokens: Double?
            let used_tokens: Double?
            let remaining_tokens: Double?
            let period_start: Double?
            let period_end: Double?
            let extra_usage: Lane?
        }
        let success: Bool
        let result: Quota?
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        guard reply.success else { throw RefreshFailure.invalidCredential }
        guard let quota = reply.result else { throw RefreshFailure.unreadableResponse }
        try validate(total: quota.total_tokens, used: quota.used_tokens, remaining: quota.remaining_tokens)
        try validateTimestamp(quota.period_start)
        try validateTimestamp(quota.period_end)
        var windows: [QuotaWindow] = []
        if let total = quota.total_tokens, total > 0, quota.used_tokens != nil || quota.remaining_tokens != nil {
            let reset: Date?
            let cycleID: String?
            if quota.active {
                guard let start = quota.period_start, let end = quota.period_end, start > 0, end > start else {
                    throw RefreshFailure.unreadableResponse
                }
                reset = Date(timeIntervalSince1970: end)
                // The provider's actual window start is evidence; never derive an identity from a predicted reset.
                cycleID = "v2ex.start.\(start)"
            } else { reset = nil; cycleID = nil }
            windows.append(QuotaWindow(id: "v2ex.five_hour", name: quota.active ? "5 小时额度" : "5 小时额度（尚未开始）",
                scope: nil, period: .fiveHour, isExhausted: quota.remaining_tokens.map { $0 <= 0 },
                usedPercentage: quota.used_tokens.map { min($0 / total * 100, 100) },
                remainingCount: quota.remaining_tokens, totalCount: total, resetsAt: reset,
                cycleID: cycleID, unit: "tokens", resetSemantics: quota.active ? nil : .nonResettingAllowance))
        }
        if let extra = quota.extra_usage {
            guard extra.pack_count.map({ $0 >= 0 }) != false else { throw RefreshFailure.unreadableResponse }
            try validate(total: extra.total_tokens, used: extra.used_tokens, remaining: extra.remaining_tokens)
            if let count = extra.pack_count, count > 0, let total = extra.total_tokens, total > 0,
               extra.used_tokens != nil || extra.remaining_tokens != nil {
                windows.append(QuotaWindow(id: "v2ex.extra", name: "额外用量补充包", scope: nil, period: .other,
                    isExhausted: extra.remaining_tokens.map { $0 <= 0 },
                    usedPercentage: extra.used_tokens.map { min($0 / total * 100, 100) },
                    remainingCount: extra.remaining_tokens, totalCount: total, resetsAt: nil, unit: "tokens",
                    resetSemantics: .nonResettingAllowance))
            }
        }
        guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt)
    }

    private static func validate(total: Double?, used: Double?, remaining: Double?) throws {
        guard [total, used].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }),
              remaining.map(\.isFinite) != false else { throw RefreshFailure.unreadableResponse }
    }
    private static func validateTimestamp(_ value: Double?) throws {
        guard value.map({ $0.isFinite && $0 >= 0 && $0 <= 253_402_300_799 }) != false else { throw RefreshFailure.unreadableResponse }
    }
}
