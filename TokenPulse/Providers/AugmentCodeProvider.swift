import Foundation

struct AugmentCodeProviderClient: Sendable {
    static let origin = "https://app.augmentcode.com"
    static let policy = CookieWebSessionPolicy(domains: ["app.augmentcode.com", "augmentcode.com"], path: "/api/credits",
        names: ["_session", "web_rpc_proxy_session"], requiredNames: ["_session"])
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try WebProviderSession.validate(credential, provider: .augmentCode, accountID: accountID,
                                        origins: [Self.origin], now: now())
        _ = try Self.policy.values(in: credential.accessToken)
        func fetch(_ path: String) async throws -> Data {
            var request = URLRequest(url: URL(string: "\(Self.origin)/api/\(path)")!)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpShouldHandleCookies = false
            request.setValue(credential.accessToken, forHTTPHeaderField: "Cookie")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            return data
        }
        do {
            let credits = try await fetch("credits")
            let subscription: Data?
            do { subscription = try await fetch("subscription") }
            catch is CancellationError { throw CancellationError() }
            catch { subscription = nil }
            var snapshot = try Self.snapshot(credits: credits, subscription: subscription, accountID: accountID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = try WebProviderSession.fingerprint(credential)
            return .init(snapshot: snapshot, updatedCredential: nil)
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
    private struct Credits: Decodable {
        let usageUnitsRemaining: Amount?
        let usageUnitsConsumedThisBillingCycle: Amount?
    }
    private struct Subscription: Decodable { let planName: String?; let billingPeriodEnd: String? }

    static func snapshot(credits: Data, subscription: Data?, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let value = try? JSONDecoder().decode(Credits.self, from: credits) else { throw RefreshFailure.unreadableResponse }
        let used = value.usageUnitsConsumedThisBillingCycle?.value, remaining = value.usageUnitsRemaining?.value
        guard used != nil || remaining != nil else { throw RefreshFailure.noQuotaWindows }
        let about = subscription.flatMap { try? JSONDecoder().decode(Subscription.self, from: $0) }
        let name = about?.planName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reset = about?.billingPeriodEnd.flatMap(ProviderHTTP.isoDate).flatMap {
            Int64(exactly: ($0.timeIntervalSince1970 * 1000).rounded()) != nil ? $0 : nil
        }
        // Available's allowance-vs-remainder meaning is not verified in an official
        // contract. Do not turn its name, or used+remaining, into a denominator.
        let window = QuotaWindow(id: "augmentCode.credits", name: "本账期 credits", scope: nil, period: .other,
            usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: reset, unit: "credits",
            exactCounts: .init(used: used, remaining: remaining, total: nil))
        return .init(accountID: accountID, windows: [window], collectedAt: collectedAt,
            providerPlanName: name.flatMap { $0.isEmpty ? nil : String($0.prefix(128)) },
            quotaStatusText: "总额度口径未确认，仅显示报告计数")
    }

    static var loginProfile: WebProviderLoginProfile {
        .init(loginURL: URL(string: "\(origin)/")!, allowedOrigins: [origin], makeCredentials: { cookies, _, id, now in
            let envelope = try WebProviderSession.cookieCredential(cookies: cookies, policy: policy, provider: .augmentCode,
                origin: origin, accountID: id, now: now, metadata: ["cookiePolicy": "augmentCode-v1"])
            return [.init(id: id.uuidString, title: L10n.text("Augment Code 当前登录账号"), credential: try envelope.encoded())]
        })
    }
}
