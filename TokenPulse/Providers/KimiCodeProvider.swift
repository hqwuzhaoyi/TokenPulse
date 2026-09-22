import Foundation

struct KimiCodeProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.kind == .oauth else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: URL(string: "https://api.kimi.com/coding/v1/usages")!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            let windows = Self.windows(try ProviderHTTP.json(data))
            guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
            return .init(snapshot: QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: now()),
                         updatedCredential: nil)
        } catch {
            throw ProviderHTTP.refreshFailure(error)
        }
    }

    private static func windows(_ root: [String: Any]) -> [QuotaWindow] {
        let usages = root["usages"] as? [String: Any] ?? [:]
        let definitions: [(String, String, QuotaPeriod)] = [
            ("limit_5h", "5 小时额度", .fiveHour),
            ("limit_7d", "每周额度", .weekly),
            ("limit_month_total", "每月总额度", .monthly),
        ]
        var windows = definitions.compactMap { key, name, period -> QuotaWindow? in
            guard let entry = usages[key] as? [String: Any],
                  let ratio = ProviderHTTP.number(entry["used_ratio"]), ratio.isFinite else { return nil }
            return QuotaWindow(id: "kimiCode.\(key)", name: name, scope: nil, period: period,
                               usedPercentage: min(max(ratio, 0), 1) * 100, remainingCount: nil, totalCount: nil,
                               resetsAt: ProviderHTTP.isoDate(entry["reset_time"]))
        }
        if let wallet = root["boosterWallet"] as? [String: Any],
           let balance = wallet["balance"] as? [String: Any], balance["type"] as? String == "BOOSTER",
           let total = ProviderHTTP.number(balance["amount"]), total.isFinite, total > 0 {
            // Kimi stores millionths of a cent and rounds a positive sub-cent balance up.
            func amount(_ raw: Double) -> Double {
                let cents = raw.rounded(.towardZero) / 1_000_000
                return (cents > 0 && cents < 1 ? 1 : cents.rounded()) / 100
            }
            let currency = ["monthlyChargeLimit", "monthlyUsed"].compactMap {
                (wallet[$0] as? [String: Any])?["currency"] as? String
            }.first { !$0.isEmpty } ?? "USD"
            let remaining = ProviderHTTP.number(balance["amountLeft"])
            windows.append(QuotaWindow(
                id: "kimiCode.extraUsage", name: "加量余额", scope: nil,
                usedPercentage: nil, remainingCount: remaining.flatMap { $0.isFinite ? amount($0) : nil },
                totalCount: amount(total), resetsAt: nil, unit: currency
            ))
        }
        return windows
    }
}

struct KimiCodeProviderAuthenticator: Sendable {
    private static let clientID = "17e5f671-d194-4dfb-9706-5516cb48c098"
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func begin() async throws -> ProviderLoginSession {
        let (data, response) = try await send(path: "device_authorization", form: [:])
        if let failure = ProviderHTTP.integrationFailure(status: response.statusCode) { throw failure }
        let root = try ProviderHTTP.json(data)
        guard let userCode = root["user_code"] as? String, !userCode.isEmpty,
              let deviceCode = root["device_code"] as? String, !deviceCode.isEmpty,
              let link = root["verification_uri_complete"] as? String,
              let url = URL(string: link), url.scheme == "https",
              ["www.kimi.com", "kimi.com", "auth.kimi.com"].contains(url.host ?? ""),
              let lifetime = ProviderHTTP.number(root["expires_in"]), lifetime.isFinite, lifetime > 0 else {
            throw ProviderIntegrationError.unreadableResponse
        }
        let interval = ProviderHTTP.number(root["interval"]) ?? 5
        guard interval.isFinite else { throw ProviderIntegrationError.unreadableResponse }
        return ProviderLoginSession(
            provider: .kimiCode, authorizationURL: url, userCode: userCode, deviceCode: deviceCode,
            state: nil, codeVerifier: nil, callbackURL: nil, pollingInterval: max(interval, 1),
            expiresAt: now().addingTimeInterval(lifetime), metadata: [:]
        )
    }

    func poll(_ session: ProviderLoginSession) async throws -> ProviderLoginProgress {
        guard session.provider == .kimiCode,
              session.expiresAt.map({ $0 > now() }) == true,
              let deviceCode = session.deviceCode, !deviceCode.isEmpty else {
            throw ProviderIntegrationError.loginExpired
        }
        let (data, response) = try await send(path: "token", form: [
            "device_code": deviceCode, "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])
        if response.statusCode >= 500 { throw ProviderIntegrationError.server }
        let root = try ProviderHTTP.json(data)
        switch root["error"] as? String {
        case "authorization_pending": return .pending(retryAfter: session.pollingInterval ?? 5)
        case "slow_down": return .pending(retryAfter: (session.pollingInterval ?? 5) + 5)
        case "expired_token": throw ProviderIntegrationError.loginExpired
        case "access_denied", "invalid_grant": throw ProviderIntegrationError.invalidCredential
        default: break
        }
        if let failure = ProviderHTTP.integrationFailure(status: response.statusCode) { throw failure }
        return .completed(credential: try credential(root).encoded())
    }

    func refreshIfNeeded(_ prior: ProviderCredentialEnvelope) async throws -> ProviderCredentialRefresh {
        guard prior.kind == .oauth else { throw ProviderIntegrationError.invalidCredentialData }
        guard prior.expiresAt.map({ $0 <= now().addingTimeInterval(300) }) == true else {
            return .init(credential: try prior.encoded(), changed: false)
        }
        guard let refreshToken = prior.refreshToken, !refreshToken.isEmpty else {
            throw ProviderIntegrationError.invalidCredential
        }
        let (data, response) = try await send(path: "token", form: [
            "refresh_token": refreshToken, "grant_type": "refresh_token",
        ])
        if response.statusCode >= 500 { throw ProviderIntegrationError.server }
        let root = try ProviderHTTP.json(data)
        if root["error"] as? String == "invalid_grant" { throw ProviderIntegrationError.invalidCredential }
        if let failure = ProviderHTTP.integrationFailure(status: response.statusCode) { throw failure }
        return .init(credential: try credential(root, prior: prior).encoded(), changed: true)
    }

    private func credential(_ root: [String: Any], prior: ProviderCredentialEnvelope? = nil) throws -> ProviderCredentialEnvelope {
        guard let accessToken = root["access_token"] as? String, !accessToken.isEmpty,
              let lifetime = ProviderHTTP.number(root["expires_in"]), lifetime.isFinite, lifetime > 0 else {
            throw ProviderIntegrationError.unreadableResponse
        }
        var metadata = prior?.metadata ?? [:]
        for key in ["token_type", "scope"] {
            if let value = root[key] as? String { metadata[key] = value }
        }
        return ProviderCredentialEnvelope(
            provider: .kimiCode, kind: .oauth, accessToken: accessToken,
            refreshToken: (root["refresh_token"] as? String) ?? prior?.refreshToken,
            expiresAt: now().addingTimeInterval(lifetime), metadata: metadata
        )
    }

    private func send(path: String, form: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "https://auth.kimi.com/api/oauth/\(path)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = ProviderHTTP.formBody(form.merging(["client_id": Self.clientID]) { _, new in new })
        return try await ProviderHTTP.send(request, transport: transport)
    }
}
