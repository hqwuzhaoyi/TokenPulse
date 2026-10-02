import Foundation
import CryptoKit

/// Public native OAuth client supplied by the user. No borrowed CLI client or secret.
struct GoogleNativeOAuth: Sendable {
    static let scopes = ["https://www.googleapis.com/auth/cloud-platform", "https://www.googleapis.com/auth/userinfo.email", "https://www.googleapis.com/auth/userinfo.profile"]
    let clientID: String
    let transport: any ProviderTransport
    let now: @Sendable () -> Date
    var requestedScopes: [String] = Self.scopes

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

    func callbackCode(_ callback: URL, session: ProviderLoginSession) throws -> String {
        guard session.metadata["clientID"] == clientID, session.callbackURL == (try Self.redirectURL(clientID: clientID)),
              let expires = session.expiresAt, expires > now(),
              let expected = session.callbackURL, callback.scheme == expected.scheme, callback.host == expected.host, callback.path == expected.path,
              callback.fragment == nil, let c = URLComponents(url: callback, resolvingAgainstBaseURL: false) else { throw ProviderIntegrationError.invalidCallback }
        let items = c.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count, items.first(where: { $0.name == "state" })?.value == session.state,
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
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        guard response.statusCode == 200 else { throw RefreshFailure.invalidCredential }
        struct User: Decodable { let id: String }
        guard let user = try? JSONDecoder().decode(User.self, from: data), !user.id.isEmpty else { throw RefreshFailure.unreadableResponse }
        envelope.accountID = user.id
        return envelope
    }

    func refresh(_ envelope: ProviderCredentialEnvelope) async throws -> ProviderCredentialEnvelope {
        guard envelope.kind == .oauth, envelope.metadata["clientID"] == clientID, let refresh = envelope.refreshToken, !refresh.isEmpty else { throw RefreshFailure.invalidCredential }
        return try await token(values: ["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID], provider: envelope.provider, previous: envelope)
    }

    private func token(values: [String: String], provider: Provider, previous: ProviderCredentialEnvelope?) async throws -> ProviderCredentialEnvelope {
        _ = try Self.redirectURL(clientID: clientID)
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"; request.httpShouldHandleCookies = false; request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = ProviderHTTP.formBody(values)
        let (data, response) = try await ProviderHTTP.send(request, transport: transport)
        guard response.statusCode == 200 else {
            if response.statusCode == 400 || response.statusCode == 401 { throw RefreshFailure.invalidCredential }
            if response.statusCode == 429 { throw RefreshFailure.rateLimited }
            throw RefreshFailure.server
        }
        struct Token: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double; let token_type: String; let scope: String? }
        guard let reply = try? JSONDecoder().decode(Token.self, from: data), !reply.access_token.isEmpty, reply.token_type.lowercased() == "bearer",
              reply.expires_in.isFinite, reply.expires_in > 0, reply.expires_in <= 31_536_000 else { throw RefreshFailure.unreadableResponse }
        let granted = reply.scope ?? previous?.metadata["grantedScopes"]
        guard let granted, Set(granted.split(separator: " ").map(String.init)).isSuperset(of: requestedScopes) else { throw ProviderIntegrationError.unsupportedLogin("Google 未授予查询所需权限，请重新授权") }
        let refresh = reply.refresh_token ?? previous?.refreshToken
        guard let refresh, !refresh.isEmpty else { throw ProviderIntegrationError.unsupportedLogin("Google 未返回离线刷新令牌，请重新同意授权") }
        var envelope = previous ?? .init(provider: provider, kind: .oauth, accessToken: reply.access_token)
        envelope.accessToken = reply.access_token; envelope.refreshToken = refresh
        envelope.expiresAt = now().addingTimeInterval(reply.expires_in)
        envelope.metadata["clientID"] = clientID; envelope.metadata["grantedScopes"] = granted
        return envelope
    }
}
