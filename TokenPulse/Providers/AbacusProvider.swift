import Foundation

struct AbacusProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    static let origin = "https://apps.abacus.ai"
    static let cookiePolicy = CookieWebSessionPolicy(domains: ["abacus.ai", "apps.abacus.ai"], path: "/api/",
        names: ["sessionid", "session_id", "session_token", "auth_token", "access_token"],
        requiredAnyNames: ["sessionid", "session_id", "session_token", "auth_token", "access_token"])
    static var loginProfile: WebProviderLoginProfile {
        .init(loginURL: URL(string: origin)!, allowedOrigins: [origin, "https://abacus.ai", "https://accounts.google.com"]) { cookies, _, id, now in
            let envelope = try WebProviderSession.cookieCredential(cookies: cookies, policy: cookiePolicy,
                provider: .abacus, origin: origin, accountID: id, now: now)
            return [.init(id: "abacus.session", title: "Abacus AI", credential: try envelope.encoded())]
        }
    }
    private struct Envelope<T: Decodable>: Decodable { let success: Bool?; let result: T?; let error: String? }
    private struct Points: Decodable { let totalComputePoints: WalletDecimalValue?; let computePointsLeft: WalletDecimalValue? }
    private struct Billing: Decodable { let nextBillingDate: String?; let currentTier: String? }

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        try WebProviderSession.validate(credential, provider: .abacus, accountID: accountID, origins: [Self.origin], now: now())
        _ = try Self.cookiePolicy.values(in: credential.accessToken)
        let points = try await send(path: "_getOrganizationComputePoints", method: "GET", cookie: credential.accessToken)
        let collectedAt = now()
        // Optional billing never replaces successfully collected compute points.
        let billing: Data?
        do { billing = try await send(path: "_getBillingInfo", method: "POST", cookie: credential.accessToken) }
        catch is CancellationError { throw CancellationError() }
        catch { billing = nil }
        var snapshot = try Self.snapshot(points, billing: billing, accountID: accountID, collectedAt: collectedAt)
        snapshot.sourceCredentialFingerprint = try WebProviderSession.fingerprint(credential)
        return .init(snapshot: snapshot, updatedCredential: nil)
    }
    private func send(path: String, method: String, cookie: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "\(Self.origin)/api/\(path)")!)
        request.httpMethod = method; request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.httpShouldHandleCookies = false
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method == "POST" { request.httpBody = Data("{}".utf8); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let secured: any ProviderTransport = transport is URLSessionProviderTransport ? URLSessionProviderTransport.rejectingRedirects() : transport
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: secured)
            if (300..<400).contains(response.statusCode) { throw RefreshFailure.invalidCredential }
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            return data
        } catch { throw ProviderHTTP.refreshFailure(error) }
    }
    static func snapshot(_ points: Data, billing: Data?, accountID: UUID, collectedAt: Date) throws -> QuotaSnapshot {
        let reply = try payload(Points.self, data: points)
        guard let total = reply.totalComputePoints?.amount, total > 0,
              let left = reply.computePointsLeft?.amount else { throw RefreshFailure.noQuotaWindows }
        let used = left >= total ? Decimal(0) : exactDifference(total, left)
        let plan = billing.flatMap { try? payload(Billing.self, data: $0) }
        let percentage = used.flatMap { HostedQuotaMath.percentage(used: $0, limit: total) }
            ?? (left <= 0 ? 100 : nil)
        let name = plan?.currentTier?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(accountID: accountID, windows: [
            QuotaWindow(id: "abacus.computePoints", name: "Compute points 额度", scope: nil, period: .other,
                isExhausted: left <= 0, usedPercentage: percentage, remainingCount: nil, totalCount: nil,
                resetsAt: ProviderHTTP.isoDate(plan?.nextBillingDate), unit: "compute points",
                exactCounts: .init(used: used, remaining: left, total: total))
        ], collectedAt: collectedAt, providerPlanName: name?.isEmpty == false ? name : nil)
    }
    private static func payload<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
        guard let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data) else { throw RefreshFailure.unreadableResponse }
        if envelope.success == true, let result = envelope.result { return result }
        guard envelope.success == false else { throw RefreshFailure.unreadableResponse }
        let message = envelope.error?.lowercased() ?? ""
        if ["expired", "session", "login", "authenticate", "unauthorized", "unauthenticated", "forbidden"].contains(where: message.contains) {
            throw RefreshFailure.invalidCredential
        }
        throw RefreshFailure.server
    }
    private static func exactDifference(_ lhs: Decimal, _ rhs: Decimal) -> Decimal? {
        var a = lhs, b = rhs, result = Decimal(), reverse = Decimal()
        guard NSDecimalSubtract(&result, &a, &b, .plain) == .noError,
              NSDecimalSubtract(&reverse, &a, &result, .plain) == .noError, reverse == rhs else { return nil }
        return result
    }
}
