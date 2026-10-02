import Foundation
import CryptoKit

/// Public native OAuth client supplied by the user. No borrowed CLI client or secret.
struct GoogleNativeOAuth: Sendable {
    static let scopes = ["https://www.googleapis.com/auth/cloud-platform", "https://www.googleapis.com/auth/userinfo.email", "https://www.googleapis.com/auth/userinfo.profile"]
    let clientID: String
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    var requestedScopes: [String] = Self.scopes
    var sleep: @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }

    static func headerSafe(_ value: String) -> Bool { !value.isEmpty && value.utf8.allSatisfy { $0 >= 33 && $0 <= 126 } }

    static func redirectURL(clientID: String) throws -> URL {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { throw ProviderIntegrationError.unsupportedLogin("请输入 Google 注册的 iOS OAuth Client ID") }
        let prefix = String(clientID.dropLast(suffix.count))
        guard !prefix.isEmpty, prefix.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }) else { throw ProviderIntegrationError.invalidCredentialData }
        return URL(string: "com.googleusercontent.apps.\(prefix):/oauth2redirect")!
    }

    func begin(provider: Provider) throws -> ProviderLoginSession {
        let callback = try Self.redirectURL(clientID: clientID)
        let verifier = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let state = UUID().uuidString
        var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        url.queryItems = ["client_id": clientID, "redirect_uri": callback.absoluteString, "response_type": "code", "scope": requestedScopes.joined(separator: " "), "code_challenge": challenge, "code_challenge_method": "S256", "state": state, "access_type": "offline", "prompt": "consent select_account"].map { URLQueryItem(name: $0.key, value: $0.value) }
        return .init(provider: provider, authorizationURL: url.url!, userCode: nil, deviceCode: nil, state: state, codeVerifier: verifier, callbackURL: callback, pollingInterval: nil, expiresAt: now().addingTimeInterval(600), metadata: ["clientID": clientID])
    }

    /// Validate user configuration before creating a browser authorization attempt.
    /// Project formats belong to the provider, not the shared Google client-ID rules.
    func begin(provider: Provider, configuredProject: String?,
               validateProject: @Sendable (String?) throws -> String?) throws -> (session: ProviderLoginSession, project: String?) {
        let project = try validateProject(configuredProject)
        return (try begin(provider: provider), project)
    }

    func callbackCode(_ callback: URL, session: ProviderLoginSession) throws -> String {
        guard session.metadata["clientID"] == clientID, session.callbackURL == (try Self.redirectURL(clientID: clientID)),
              let expires = session.expiresAt, expires > now(),
              let expected = session.callbackURL, callback.scheme == expected.scheme, callback.host == expected.host, callback.path == expected.path,
              callback.fragment == nil, let c = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { throw ProviderIntegrationError.invalidCallback }
        guard let state = session.state, !state.isEmpty else { throw ProviderIntegrationError.invalidCallback }
        let items = c.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count, items.first(where: { $0.name == "state" })?.value == state,
              items.first(where: { $0.name == "error" }) == nil,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw ProviderIntegrationError.invalidCallback }
        return code
    }

    func exchange(callback: URL, session: ProviderLoginSession) async throws -> ProviderCredentialEnvelope {
        let code = try callbackCode(callback, session: session)
        guard let verifier = session.codeVerifier, let redirect = session.callbackURL else { throw ProviderIntegrationError.invalidCallback }
        var envelope = try await token(values: ["grant_type": "authorization_code", "code": code, "code_verifier": verifier, "redirect_uri": redirect.absoluteString, "client_id": clientID], provider: session.provider, previous: nil)
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(envelope.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpShouldHandleCookies = false; request.timeoutInterval = 20
        envelope.accountID = try await userInfoSubject(request)
        return envelope
    }

    func refresh(_ envelope: ProviderCredentialEnvelope) async throws -> ProviderCredentialEnvelope {
        guard envelope.kind == .oauth, envelope.metadata["clientID"] == clientID,
              let historicalScopes = envelope.metadata["grantedScopes"], !historicalScopes.isEmpty,
              Set(historicalScopes.split(separator: " ").map(String.init)).isSuperset(of: requestedScopes),
              let refresh = envelope.refreshToken, !refresh.isEmpty else { throw RefreshFailure.invalidCredential }
        return try await token(values: ["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID], provider: envelope.provider, previous: envelope)
    }

    /// Only the idempotent GET is retried. The authorization code POST above is never replayed.
    private func userInfoSubject(_ request: URLRequest) async throws -> String {
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let data: Data, response: HTTPURLResponse
            do {
                (data, response) = try await ProviderHTTP.send(request, transport: transport)
            } catch {
                guard attempt < 2, error as? ProviderIntegrationError == .network else { throw error }
                try await sleep(TimeInterval(attempt + 1))
                continue
            }
            try Task.checkCancellation()
            try Self.validateResponseOrigin(response, request: request)
            if response.statusCode == 429 || (500...599).contains(response.statusCode) {
                if attempt < 2, let delay = Self.userInfoRetryDelay(response, attempt: attempt, now: now()) {
                    try await sleep(delay)
                    continue
                }
            }
            if let failure = ProviderHTTP.queryFailure(status: response.statusCode) { throw failure }
            struct User: Decodable { let id: String }
            guard let user = try? JSONDecoder().decode(User.self, from: data), !user.id.isEmpty else { throw RefreshFailure.unreadableResponse }
            return user.id
        }
        throw RefreshFailure.server
    }

    /// At most two retries, each waiting no more than five seconds. Longer server
    /// cooldowns fail promptly rather than retrying before Retry-After permits it.
    static func userInfoRetryDelay(_ response: HTTPURLResponse, attempt: Int, now: Date) -> TimeInterval? {
        let fallback = TimeInterval(attempt + 1)
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return fallback }
        let delay: TimeInterval
        if raw.utf8.allSatisfy({ (48...57).contains($0) }) {
            guard let number = Double(raw), number.isFinite else { return nil }
            delay = number
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"; formatter.isLenient = false
            guard let date = formatter.date(from: raw) else { return fallback }
            delay = max(0, date.timeIntervalSince(now))
        }
        return delay.isFinite && delay <= 5 ? delay : nil
    }

    static func validateResponseOrigin(_ response: HTTPURLResponse, request: URLRequest) throws {
        guard let actual = response.url, let expected = request.url, actual.scheme == "https", actual.host == expected.host, actual.port == expected.port else { throw RefreshFailure.invalidCredential }
    }

    private func token(values: [String: String], provider: Provider, previous: ProviderCredentialEnvelope?) async throws -> ProviderCredentialEnvelope {
        _ = try Self.redirectURL(clientID: clientID)
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"; request.httpShouldHandleCookies = false; request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = ProviderHTTP.formBody(values)
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        try Self.validateResponseOrigin(response, request: request)
        guard response.statusCode == 200 else {
            if response.statusCode == 400 || response.statusCode == 401 { throw RefreshFailure.invalidCredential }
            if response.statusCode == 429 { throw RefreshFailure.rateLimited }
            throw RefreshFailure.server
        }
        struct Token: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double; let token_type: String; let scope: String? }
        guard let reply = try? JSONDecoder().decode(Token.self, from: data), Self.headerSafe(reply.access_token), reply.token_type.lowercased() == "bearer",
              reply.expires_in.isFinite, reply.expires_in > 0, reply.expires_in <= 31_536_000 else { throw RefreshFailure.unreadableResponse }
        // RFC 6749 §5.1 permits omission when the granted scope equals the request.
        let granted = reply.scope ?? previous?.metadata["grantedScopes"] ?? requestedScopes.joined(separator: " ")
        guard Set(granted.split(separator: " ").map(String.init)).isSuperset(of: requestedScopes) else { throw ProviderIntegrationError.unsupportedLogin("Google 未授予查询所需权限，请重新授权") }
        let refresh = reply.refresh_token ?? previous?.refreshToken
        guard let refresh, !refresh.isEmpty else { throw ProviderIntegrationError.unsupportedLogin("Google 未返回离线刷新令牌，请重新同意授权") }
        guard Self.headerSafe(refresh) else { throw RefreshFailure.unreadableResponse }
        var envelope = previous ?? .init(provider: provider, kind: .oauth, accessToken: reply.access_token)
        envelope.accessToken = reply.access_token; envelope.refreshToken = refresh
        envelope.expiresAt = now().addingTimeInterval(reply.expires_in)
        envelope.metadata["clientID"] = clientID; envelope.metadata["grantedScopes"] = granted
        return envelope
    }
}
