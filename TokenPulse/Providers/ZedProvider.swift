import Foundation

struct ZedProviderClient: Sendable {
    static let origin = "https://cloud.zed.dev"
    static let policy = CookieWebSessionPolicy(domains: ["zed.dev", "dashboard.zed.dev", "cloud.zed.dev"],
        path: "/frontend/billing/usage", names: ["zed.session"], requiredNames: ["zed.session"])
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try WebProviderSession.validate(credential, provider: .zed, accountID: accountID, origins: [Self.origin], now: now())
        _ = try Self.policy.values(in: credential.accessToken)
        var request = URLRequest(url: URL(string: "\(Self.origin)/frontend/billing/usage")!)
        request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData; request.httpShouldHandleCookies = false
        request.setValue(credential.accessToken, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            var result = try Self.snapshot(data, accountID: accountID, collectedAt: now())
            result.sourceCredentialFingerprint = try WebProviderSession.fingerprint(credential)
            return .init(snapshot: result, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }

    private struct Amount: Decodable {
        let value: Decimal
        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let text = try? c.decode(String.self) { value = try ProviderDecimal.amount(text) }
            else { value = try c.decode(Decimal.self) }
            guard !value.isNaN, value >= 0 else { throw RefreshFailure.unreadableResponse }
        }
    }
    private struct PredictionLimit: Decodable {
        let value: Decimal?
        let unlimited: Bool
        private enum Keys: String, CodingKey { case limited }
        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { value = nil; unlimited = false; return }
            if let text = try? c.decode(String.self), text == "unlimited" { value = nil; unlimited = true; return }
            if let value = try? c.decode(Amount.self) { self.value = value.value; unlimited = false; return }
            let nested = try decoder.container(keyedBy: Keys.self)
            value = try nested.decode(Amount.self, forKey: .limited).value; unlimited = false
        }
    }
    private struct Reply: Decodable {
        struct Predictions: Decodable { let used: Amount?; let limit: PredictionLimit? }
        struct Spend: Decodable { let spend_in_cents: Amount?; let limit_in_cents: Amount? }
        struct Usage: Decodable { let edit_predictions: Predictions?; let token_spend: Spend? }
        let plan: String?
        let current_usage: Usage
    }
    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let root = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        var windows: [QuotaWindow] = [], notes: [String] = []
        if let p = root.current_usage.edit_predictions {
            if p.limit?.unlimited == true {
                windows.append(.init(id: "zed.editPredictions", name: "编辑预测", scope: nil, period: .monthly, isUnlimited: true,
                    usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil, unit: "次"))
            } else if let used = p.used?.value {
                windows.append(try window(id: "zed.editPredictions", name: "编辑预测", used: used, total: p.limit?.value, unit: "次"))
            }
        }
        if let spend = root.current_usage.token_spend, let cents = spend.spend_in_cents?.value {
            let used = try usd(cents), total = try (spend.limit_in_cents?.value).map(usd)
            windows.append(try window(id: "zed.tokenSpend", name: "AI 支出预算", used: used, total: total, unit: "USD 预算"))
            if total == nil { notes.append("未返回支出预算上限，仅显示已花金额") }
            else if total == 0 { notes.append("已设置零支出预算") }
        }
        guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
        let plan = root.plan?.split(whereSeparator: { $0 == "_" || $0 == " " }).map { $0.capitalized }.joined(separator: " ")
        return .init(accountID: accountID, windows: windows, collectedAt: collectedAt,
            providerPlanName: plan?.isEmpty == false ? plan : nil, quotaStatusText: notes.isEmpty ? nil : notes.joined(separator: "；"))
    }
    private static func usd(_ cents: Decimal) throws -> Decimal {
        var lhs = cents, divisor = Decimal(100), value = Decimal(0)
        guard NSDecimalDivide(&value, &lhs, &divisor, .plain) == .noError else { throw RefreshFailure.unreadableResponse }
        return value
    }
    private static func window(id: String, name: String, used: Decimal, total: Decimal?, unit: String) throws -> QuotaWindow {
        var remaining: Decimal?, percent: Double?
        if let total {
            if used >= total { remaining = 0 }
            else {
                var lhs = total, rhs = used, value = Decimal(0)
                guard NSDecimalSubtract(&value, &lhs, &rhs, .plain) == .noError else { throw RefreshFailure.unreadableResponse }; remaining = value
            }
            if total > 0 {
                let value = NSDecimalNumber(decimal: used).doubleValue / NSDecimalNumber(decimal: total).doubleValue * 100
                guard value.isFinite else { throw RefreshFailure.unreadableResponse }; percent = value
            }
        }
        return .init(id: id, name: name, scope: nil, period: .monthly, isExhausted: total.flatMap { $0 > 0 ? used >= $0 : nil },
            usedPercentage: percent, remainingCount: nil, totalCount: nil, resetsAt: nil, unit: unit,
            exactCounts: .init(used: used, remaining: remaining, total: total))
    }
    static var loginProfile: WebProviderLoginProfile {
        .init(loginURL: URL(string: "https://dashboard.zed.dev/")!,
            allowedOrigins: ["https://zed.dev", "https://dashboard.zed.dev", origin], makeCredentials: { cookies, _, id, now in
                let envelope = try WebProviderSession.cookieCredential(cookies: cookies, policy: policy, provider: .zed,
                    origin: origin, accountID: id, now: now, metadata: ["cookiePolicy": "zed-v1"])
                return [.init(id: id.uuidString, title: "Zed 当前登录账号", credential: try envelope.encoded())]
            })
    }
}
