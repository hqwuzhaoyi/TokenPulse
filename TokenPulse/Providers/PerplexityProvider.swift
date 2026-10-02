import Foundation

/// API credits only: grant allocations do not identify which pool funded usage.
struct PerplexityProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    static let origin = "https://www.perplexity.ai"
    static let cookieName = "__Secure-next-auth.session-token"
    static let cookiePolicy = CookieWebSessionPolicy(domains: ["perplexity.ai", "www.perplexity.ai"], path: "/rest/billing/credits",
        names: [cookieName], prefixes: [cookieName + "."])
    static var loginProfile: WebProviderLoginProfile {
        .init(loginURL: URL(string: origin + "/login")!, allowedOrigins: [origin, "https://perplexity.ai", "https://accounts.google.com", "https://appleid.apple.com"]) { cookies, _, id, now in
            let captured = try cookiePolicy.select(cookies, now: now)
            let values = try cookiePolicy.values(in: captured.header)
            let names = try sessionNames(values)
            var narrowed = cookiePolicy
            narrowed.names = names; narrowed.prefixes = []; narrowed.requiredNames = Set(names)
            let envelope = try WebProviderSession.cookieCredential(cookies: cookies, policy: narrowed,
                provider: .perplexity, origin: origin, accountID: id, now: now)
            return [.init(id: "perplexity.session", title: "Perplexity API credits", credential: try envelope.encoded())]
        }
    }
    static func sessionNames(_ values: [String: String]) throws -> [String] {
        if values[cookieName] != nil { return [cookieName] }
        let indices = try values.keys.map { name -> Int in
            guard name.hasPrefix(cookieName + ".") else { throw RefreshFailure.invalidCredential }
            let suffix = String(name.dropFirst(cookieName.count + 1))
            guard let index = Int(suffix), (0..<32).contains(index), String(index) == suffix else { throw RefreshFailure.invalidCredential }
            return index
        }.sorted()
        guard !indices.isEmpty, indices == Array(0..<indices.count) else { throw RefreshFailure.invalidCredential }
        return indices.map { cookieName + ".\($0)" }
    }
    private struct Reply: Decodable {
        struct Grant: Decodable { let type: String? }
        let balance: WalletDecimalValue?
        let grants: [Grant]
        private enum CodingKeys: String, CodingKey { case balance_cents, balanceCents, credit_grants, creditGrants }
        init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            balance = try fields.decodeIfPresent(WalletDecimalValue.self, forKey: .balance_cents)
                ?? fields.decodeIfPresent(WalletDecimalValue.self, forKey: .balanceCents)
            if fields.contains(.credit_grants) { grants = try fields.decode([Grant].self, forKey: .credit_grants) }
            else { grants = try fields.decode([Grant].self, forKey: .creditGrants) }
        }
    }
    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try WebProviderSession.validate(credential, provider: .perplexity, accountID: accountID, origins: [Self.origin], now: now())
        let values = try Self.cookiePolicy.values(in: credential.accessToken)
        let names = try Self.sessionNames(values)
        var request = URLRequest(url: URL(string: Self.origin + "/rest/billing/credits?version=2.18&source=default")!)
        request.timeoutInterval = 15; request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.httpShouldHandleCookies = false
        request.setValue(names.map { "\($0)=\(values[$0]!)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.origin, forHTTPHeaderField: "Origin")
        request.setValue(Self.origin + "/account/usage", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        let secured: any ProviderTransport = transport is URLSessionProviderTransport ? URLSessionProviderTransport.rejectingRedirects() : transport
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: secured)
            if (300..<400).contains(response.statusCode) { throw RefreshFailure.invalidCredential }
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            var snapshot = try Self.snapshot(data, accountID: accountID, collectedAt: now())
            snapshot.sourceCredentialFingerprint = try WebProviderSession.fingerprint(credential)
            return .init(snapshot: snapshot, updatedCredential: nil)
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }
    static func snapshot(_ data: Data, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw RefreshFailure.unreadableResponse }
        guard var cents = reply.balance?.amount, cents >= 0 else { throw RefreshFailure.noQuotaWindows }
        var hundred = Decimal(100), dollars = Decimal()
        guard NSDecimalDivide(&dollars, &cents, &hundred, .plain) == .noError, !dollars.isNaN else { throw RefreshFailure.unreadableResponse }
        return .init(accountID: accountID, windows: [
            QuotaWindow(id: "perplexity.apiCredits.USD", name: "API credits 余额", scope: nil,
                usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                wallet: .init(currency: "USD", total: dollars))
        ], collectedAt: collectedAt)
    }
}
