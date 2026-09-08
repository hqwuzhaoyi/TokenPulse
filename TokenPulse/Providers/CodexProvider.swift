import Foundation

struct CodexProviderClient: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func quota(accountID: UUID, credential: ProviderCredentialEnvelope) async throws -> ProviderQueryResult {
        guard credential.kind == .oauth else { throw RefreshFailure.invalidCredential }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        if let providerAccountID = credential.accountID, !providerAccountID.isEmpty {
            request.setValue(providerAccountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            let windows = Self.windows(try ProviderHTTP.json(data))
            guard !windows.isEmpty else { throw RefreshFailure.noQuotaWindows }
            return .init(
                snapshot: QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: now(),
                                        remainingResetCount: Self.remainingResetCount(data)),
                updatedCredential: nil
            )
        } catch {
            throw ProviderHTTP.refreshFailure(error)
        }
    }

    private static func remainingResetCount(_ data: Data) -> Int? {
        struct Envelope: Decodable {
            struct ResetCredits: Decodable {
                let availableCount: Int
                enum CodingKeys: String, CodingKey { case availableCount = "available_count" }
            }
            let resetCredits: ResetCredits?
            enum CodingKeys: String, CodingKey { case resetCredits = "rate_limit_reset_credits" }
        }
        guard let count = (try? JSONDecoder().decode(Envelope.self, from: data))?.resetCredits?.availableCount,
              count >= 0 else { return nil }
        return count
    }

    static func windows(_ root: [String: Any]) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []
        if let rateLimit = root["rate_limit"] as? [String: Any] {
            windows += windowGroup(rateLimit, prefix: "codex", scope: nil)
        }
        for extra in root["additional_rate_limits"] as? [[String: Any]] ?? [] {
            guard let rateLimit = extra["rate_limit"] as? [String: Any] else { continue }
            let scope = extra["limit_name"] as? String
            let prefix = (extra["metered_feature"] as? String) ?? scope ?? "extra"
            windows += windowGroup(rateLimit, prefix: prefix, scope: scope)
        }
        return windows
    }

    private static func windowGroup(_ group: [String: Any], prefix: String, scope: String?) -> [QuotaWindow] {
        ["primary_window", "secondary_window"].compactMap { slot in
            guard let node = group[slot] as? [String: Any] else { return nil }
            let seconds = ProviderHTTP.number(node["limit_window_seconds"]).map(Int.init)
            let resetsAt = ProviderHTTP.number(node["reset_at"]).map(Date.init(timeIntervalSince1970:))
            let id = "\(prefix).\(slot)"
            return QuotaWindow(
                id: id,
                name: ProviderHTTP.windowName(seconds: seconds),
                scope: scope,
                usedPercentage: ProviderHTTP.number(node["used_percent"]),
                remainingCount: nil,
                totalCount: nil,
                resetsAt: resetsAt,
                cycleID: ProviderHTTP.cycleID(prefix: id, resetsAt: resetsAt)
            )
        }
    }
}

struct CodexProviderAuthenticator: Sendable {
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let scopes = [
        "openid", "profile", "email", "offline_access",
        "api.connectors.read", "api.connectors.invoke",
    ]
    private let transport: any ProviderTransport
    private let now: @Sendable () -> Date

    init(transport: any ProviderTransport, now: @escaping @Sendable () -> Date) {
        self.transport = transport
        self.now = now
    }

    func begin() async throws -> ProviderLoginSession {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/deviceauth/usercode")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["client_id": Self.clientID])
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        if let failure = ProviderHTTP.integrationFailure(status: response.statusCode) { throw failure }
        let root = try ProviderHTTP.json(data)
        guard let userCode = (root["user_code"] as? String) ?? (root["usercode"] as? String),
              let deviceID = root["device_auth_id"] as? String else {
            throw ProviderIntegrationError.unreadableResponse
        }
        let interval = max(ProviderHTTP.number(root["interval"]) ?? 5, 1)
        return ProviderLoginSession(
            provider: .codex,
            authorizationURL: URL(string: "https://auth.openai.com/codex/device")!,
            userCode: userCode,
            deviceCode: deviceID,
            state: nil,
            codeVerifier: nil,
            callbackURL: nil,
            pollingInterval: interval,
            expiresAt: now().addingTimeInterval(15 * 60),
            metadata: [:]
        )
    }

    func poll(_ session: ProviderLoginSession) async throws -> ProviderLoginProgress {
        guard session.provider == .codex,
              session.expiresAt.map({ $0 > now() }) != false,
              let deviceID = session.deviceCode,
              let userCode = session.userCode else { throw ProviderIntegrationError.loginExpired }
        var request = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/deviceauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "device_auth_id": deviceID,
            "user_code": userCode,
        ])
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        if response.statusCode == 403 || response.statusCode == 404 {
            return .pending(retryAfter: session.pollingInterval ?? 5)
        }
        if let failure = ProviderHTTP.integrationFailure(status: response.statusCode) { throw failure }
        let root = try ProviderHTTP.json(data)
        guard let code = root["authorization_code"] as? String,
              let verifier = root["code_verifier"] as? String else {
            throw ProviderIntegrationError.unreadableResponse
        }
        let credential = try await token(form: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": "https://auth.openai.com/deviceauth/callback",
            "client_id": Self.clientID,
            "code_verifier": verifier,
        ], prior: nil)
        return .completed(credential: try credential.encoded())
    }

    func refreshIfNeeded(_ credential: ProviderCredentialEnvelope) async throws -> ProviderCredentialRefresh {
        guard credential.kind == .oauth else { throw ProviderIntegrationError.invalidCredentialData }
        guard credential.expiresAt.map({ $0 <= now().addingTimeInterval(60) }) == true else {
            return .init(credential: try credential.encoded(), changed: false)
        }
        guard let refreshToken = credential.refreshToken, !refreshToken.isEmpty else {
            throw ProviderIntegrationError.invalidCredential
        }
        let renewed = try await token(form: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
            "scope": Self.scopes.joined(separator: " "),
        ], prior: credential)
        return .init(credential: try renewed.encoded(), changed: true)
    }

    private func token(form: [String: String], prior: ProviderCredentialEnvelope?) async throws -> ProviderCredentialEnvelope {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = ProviderHTTP.formBody(form)
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        if let failure = ProviderHTTP.integrationFailure(status: response.statusCode) { throw failure }
        let root = try ProviderHTTP.json(data)
        guard let accessToken = root["access_token"] as? String,
              let lifetime = ProviderHTTP.number(root["expires_in"]) else {
            throw ProviderIntegrationError.unreadableResponse
        }
        return ProviderCredentialEnvelope(
            provider: .codex,
            kind: .oauth,
            accessToken: accessToken,
            refreshToken: (root["refresh_token"] as? String) ?? prior?.refreshToken,
            expiresAt: now().addingTimeInterval(lifetime),
            accountID: Self.accountID(accessToken) ?? prior?.accountID
        )
    }

    private static func accountID(_ token: String) -> String? {
        guard let claims = jwtClaims(token),
              let auth = claims["https://api.openai.com/auth"] as? [String: Any] else { return nil }
        return auth["chatgpt_account_id"] as? String
    }

    private static func jwtClaims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var body = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        body += String(repeating: "=", count: (4 - body.count % 4) % 4)
        guard let data = Data(base64Encoded: body) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
