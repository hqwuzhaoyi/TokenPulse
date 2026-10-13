import Foundation

struct GrokBotProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        var request = URLRequest(url: URL(string: "https://cursor.com/api/dashboard/get-sand-usage-status")!)
        request.httpMethod = "POST"; request.timeoutInterval = 20; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.httpBody = Data("{}".utf8)
        request.setValue(try CursorAccountSession.cookie(credential, expectedProvider: .grokBot, accountID: accountID, now: now()), forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            var snapshot = try Self.snapshot(data, accountID: accountID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = credential.metadata["sourceCredentialFingerprint"]
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private struct Reply: Decodable {
        let usagePercent: Double?
        let nextResetTimestampUtc: String?
        let hasNonZeroIncludedLimit: Bool?
        let includedLimitZero: Bool?
        let usesPooledEnterpriseAllowance: Bool?
        let grokPlanLabel: String?
    }
    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let r = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        guard !(r.includedLimitZero == true && r.hasNonZeroIncludedLimit == true) else { throw RefreshFailure.unreadableResponse }
        if r.usesPooledEnterpriseAllowance == true {
            return .init(accountID: accountID, windows: [], collectedAt: collectedAt,
                quotaStatusText: "Grok Bot 使用组织共享额度，未返回个人份额")
        }
        if r.includedLimitZero == true || r.hasNonZeroIncludedLimit == false {
            return .init(accountID: accountID, windows: [], collectedAt: collectedAt,
                quotaStatusText: "此账号未包含 Grok Bot 个人额度")
        }
        guard r.hasNonZeroIncludedLimit == true else { throw RefreshFailure.unreadableResponse }
        guard let used = r.usagePercent else { throw RefreshFailure.noQuotaWindows }
        guard used.isFinite, used >= 0 else { throw RefreshFailure.unreadableResponse }
        let reset: Date?
        if let text = r.nextResetTimestampUtc {
            guard let date = ProviderHTTP.isoDate(text), Int64(exactly: (date.timeIntervalSince1970 * 1000).rounded()) != nil else { throw RefreshFailure.unreadableResponse }
            reset = date
        } else { reset = nil }
        // currentPeriodStart is not a promised reset and never becomes start+7days or Monday.
        let window = QuotaWindow(id: "grokBot.weekly", name: "Grok Bot 每周额度", scope: nil, period: .weekly,
            isExhausted: used >= 100, usedPercentage: min(used, 100), remainingCount: nil, totalCount: nil, resetsAt: reset)
        let plan = r.grokPlanLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(accountID: accountID, windows: [window], collectedAt: collectedAt,
            providerPlanName: plan.flatMap { $0.isEmpty ? nil : String($0.prefix(128)) })
    }
}
