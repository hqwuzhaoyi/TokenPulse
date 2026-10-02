import Foundation

enum ManusWebSession {
    static let origin = "https://manus.im"
    static let policy = CookieWebSessionPolicy(domains: ["manus.im"], path: "/", names: ["session_id"], requiredNames: ["session_id"])

    static func credential(cookies: [HTTPCookie], accountID: UUID, now: Date) throws -> ProviderCredentialEnvelope {
        let selected = try policy.select(cookies, now: now)
        guard let token = try policy.values(in: selected.header)["session_id"] else { throw RefreshFailure.invalidCredential }
        return try WebProviderSession.credential(provider: .manus, origin: origin, accountID: accountID, accessToken: token,
            expiresAt: selected.expiresByName["session_id"], metadata: ["cookieName": "session_id"])
    }
}

struct ManusProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try WebProviderSession.validate(credential, provider: .manus, accountID: accountID, origins: [ManusWebSession.origin], now: now())
        guard credential.metadata["cookieName"] == "session_id",
              credential.accessToken.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: URL(string: "https://api.manus.im/user.v1.UserService/GetAvailableCredits")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        for (name, value) in ["Authorization": "Bearer \(credential.accessToken)", "Content-Type": "application/json",
                              "Accept": "application/json", "Connect-Protocol-Version": "1", "Origin": ManusWebSession.origin,
                              "Referer": ManusWebSession.origin + "/",
                              "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"] {
            request.setValue(value, forHTTPHeaderField: name)
        }
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if 300..<400 ~= response.statusCode { throw RefreshFailure.invalidCredential }
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            var snapshot = try Self.snapshot(data, accountID: accountID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = try WebProviderSession.fingerprint(credential)
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private struct RefreshTime: Decodable {
        let date: Date?
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                if let date = ProviderHTTP.isoDate(text) { self.date = date }
                else {
                    _ = try ProviderDecimal.amount(text)
                    date = nil // Numeric timestamps have no confirmed epoch. Never guess 1970 or 2001.
                }
            } else {
                _ = try container.decode(Decimal.self)
                date = nil
            }
        }
    }
    private struct Credits: Decodable {
        let totalCredits: WalletDecimalValue?
        let periodicCredits: WalletDecimalValue?
        let proMonthlyCredits: WalletDecimalValue?
        let refreshCredits: WalletDecimalValue?
        let maxRefreshCredits: WalletDecimalValue?
        let nextRefreshTime: RefreshTime?
        let refreshInterval: String?
        var hasFigure: Bool {
            [totalCredits, periodicCredits, proMonthlyCredits, refreshCredits, maxRefreshCredits].contains { $0 != nil }
        }
    }
    private struct Envelope: Decodable {
        let data: Credits?
        let result: Credits?
        let response: Credits?
        let availableCredits: Credits?
    }

    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let decoder = JSONDecoder()
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw RefreshFailure.unreadableResponse }
        let candidates: [Credits]
        if ["data", "result", "response", "availableCredits"].contains(where: { object[$0] != nil }) {
            guard let wrapped = try? decoder.decode(Envelope.self, from: data) else { throw RefreshFailure.unreadableResponse }
            candidates = [wrapped.data, wrapped.result, wrapped.response, wrapped.availableCredits].compactMap { $0 }
        } else {
            guard let bare = try? decoder.decode(Credits.self, from: data) else { throw RefreshFailure.unreadableResponse }
            candidates = [bare]
        }
        guard let credits = candidates.first(where: \.hasFigure) else { throw RefreshFailure.unreadableResponse }
        guard [credits.totalCredits, credits.periodicCredits, credits.proMonthlyCredits, credits.refreshCredits, credits.maxRefreshCredits]
            .compactMap({ $0?.amount }).allSatisfy({ $0 >= 0 }) else { throw RefreshFailure.unreadableResponse }
        let daily = credits.refreshInterval?.lowercased() == "daily"
        var windows: [QuotaWindow] = []
        for (id, name, period, size, left, reset, semantics) in [
            ("manus.refresh", daily ? "每日恢复额度" : "恢复额度", QuotaPeriod.other,
             credits.maxRefreshCredits?.amount, credits.refreshCredits?.amount, credits.nextRefreshTime?.date, Optional<QuotaResetSemantics>.none),
            ("manus.monthly", "每月额度", .monthly, credits.proMonthlyCredits?.amount,
             credits.periodicCredits?.amount, nil, .nonResettingAllowance)
        ] {
            guard let size, size > 0, let left else { continue }
            let used = max(size - left, 0)
            guard !used.isNaN else { throw RefreshFailure.unreadableResponse }
            windows.append(QuotaWindow(id: id, name: name, scope: nil, period: period, isExhausted: left == 0,
                usedPercentage: try WalletDecimalArithmetic.percentage(used: used, total: size), remainingCount: nil,
                totalCount: nil, resetsAt: reset, unit: "credits",
                exactCounts: DecimalQuotaCounts(used: used, remaining: left, total: size), resetSemantics: semantics))
        }
        if let total = credits.totalCredits?.amount {
            windows.append(QuotaWindow(id: "manus.total", name: "总 credits", scope: nil, usedPercentage: nil,
                remainingCount: nil, totalCount: nil, resetsAt: nil,
                wallet: WalletBalance(currency: "credits", total: total, isMonetary: false)))
        }
        guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt)
    }
}
