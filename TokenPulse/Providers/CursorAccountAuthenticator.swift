import Foundation
import CryptoKit
import CoreFoundation

/// Cursor's nonce/PKCE sign-in, pinned to Pulse CursorWebLogin; this is not OAuth.
/// The protocol is independent of an editor installation and may be reused by a
/// later Cursor-account provider after that provider passes real-account gates.
struct CursorAccountAuthenticator: Sendable {
    let transport: any ProviderTransport
    let now: @Sendable () -> Date

    func begin(accountID: UUID) -> ProviderLoginSession {
        let verifier = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }.base64URL
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let nonce = UUID().uuidString.lowercased()
        var components = URLComponents(string: "https://cursor.com/loginDeepControl")!
        components.queryItems = [
            .init(name: "challenge", value: challenge), .init(name: "uuid", value: nonce),
            .init(name: "mode", value: "login"), .init(name: "redirectTarget", value: "sand"),
            .init(name: "supportsSelectedTeamLogin", value: "true")
        ]
        return .init(provider: .cursor, authorizationURL: components.url!, userCode: nil, deviceCode: nil,
                     state: nonce, codeVerifier: verifier, callbackURL: nil, pollingInterval: 2,
                     expiresAt: now().addingTimeInterval(300), metadata: ["localAccountID": accountID.uuidString])
    }

    func poll(_ session: ProviderLoginSession) async throws -> ProviderLoginProgress {
        guard session.provider == .cursor, session.expiresAt.map({ $0 > now() }) == true else { throw ProviderIntegrationError.loginExpired }
        guard let nonce = session.state, UUID(uuidString: nonce) != nil,
              let verifier = session.codeVerifier, verifier.count == 43,
              verifier.unicodeScalars.allSatisfy({ CursorAccountSession.tokenCharacters.contains($0) }),
              let account = session.metadata["localAccountID"].flatMap(UUID.init(uuidString:)) else { throw ProviderIntegrationError.invalidCredentialData }
        var components = URLComponents(string: "https://api2.cursor.sh/auth/poll")!
        components.queryItems = [.init(name: "uuid", value: nonce), .init(name: "verifier", value: verifier)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await ProviderHTTP.send(request, transport: transport)
            if response.statusCode == 404 { return .pending(retryAfter: 2) }
            if response.statusCode == 403 { throw ProviderIntegrationError.invalidCredential }
            if response.statusCode == 429 { throw ProviderIntegrationError.rateLimited }
            if let failure = ProviderHTTP.integrationFailure(status: response.statusCode) { throw failure }
            let root = try ProviderHTTP.json(data)
            guard let access = root["accessToken"] as? String,
                  let refresh = root["refreshToken"] as? String, !refresh.isEmpty else { throw ProviderIntegrationError.unreadableResponse }
            // Refresh is returned by the native protocol, but no supported
            // refresh exchange is known. Store only the query's access token.
            return .completed(credential: try CursorAccountSession.credential(accessToken: access, accountID: account, now: now()))
        } catch let error as RefreshFailure {
            if error == .invalidCredential { throw ProviderIntegrationError.invalidCredential }
            throw error
        }
    }
}

/// Build exactly one allowlisted Cookie from the server-issued access JWT.
/// No Safari, WebKit cookie jar, editor database or unrelated cookie is read.
enum CursorAccountSession {
    static let tokenCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    private struct Claims { let account: String; let expiresAt: Date }

    private static func claims(_ token: String, now: Date) throws -> Claims {
        guard token.utf8.count <= 32_768 else { throw RefreshFailure.invalidCredential }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(tokenCharacters.contains) }) else { throw RefreshFailure.invalidCredential }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload), let root = try? ProviderHTTP.json(data),
              let subject = root["sub"] as? String,
              let account = subject.split(separator: "|").last.map(String.init), !account.isEmpty, account.utf8.count <= 1024,
              let exp = root["exp"] as? NSNumber, CFGetTypeID(exp) != CFBooleanGetTypeID(),
              exp.doubleValue.isFinite, Int64(exactly: (exp.doubleValue * 1000).rounded()) != nil else { throw RefreshFailure.invalidCredential }
        let expiry = Date(timeIntervalSince1970: exp.doubleValue)
        guard expiry.timeIntervalSince(now) > 60 else { throw RefreshFailure.invalidCredential }
        return .init(account: account, expiresAt: expiry)
    }

    private static func fingerprint(_ credential: ProviderCredentialEnvelope) -> String? {
        guard let account = credential.accountID, let localID = credential.metadata["localAccountID"],
              let bytes = try? JSONEncoder().encode(["cursor", localID, account, credential.accessToken]) else { return nil }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func credential(accessToken: String, accountID: UUID, now: Date) throws -> String {
        let claims = try claims(accessToken, now: now)
        var envelope = ProviderCredentialEnvelope(provider: .cursor, kind: .session, accessToken: accessToken,
            expiresAt: claims.expiresAt, accountID: claims.account,
            metadata: ["localAccountID": accountID.uuidString, "host": "cursor.com", "authFlow": "loginDeepControl"])
        envelope.metadata["sourceCredentialFingerprint"] = fingerprint(envelope)
        return try envelope.encoded()
    }

    static func validate(_ credential: ProviderCredentialEnvelope, accountID: UUID, now: Date) throws {
        let claims = try claims(credential.accessToken, now: now)
        guard credential.provider == .cursor, credential.kind == .session,
              credential.accountID == claims.account,
              credential.metadata["localAccountID"] == accountID.uuidString,
              credential.metadata["host"] == "cursor.com", credential.metadata["authFlow"] == "loginDeepControl",
              credential.expiresAt.map({ abs($0.timeIntervalSince(claims.expiresAt)) < 1 }) == true,
              credential.metadata["sourceCredentialFingerprint"] == fingerprint(credential) else { throw RefreshFailure.invalidCredential }
    }

    static func cookie(_ credential: ProviderCredentialEnvelope, accountID: UUID, now: Date) throws -> String {
        try validate(credential, accountID: accountID, now: now)
        let allowed = tokenCharacters.union(CharacterSet(charactersIn: ".~"))
        guard let account = credential.accountID?.addingPercentEncoding(withAllowedCharacters: allowed) else { throw RefreshFailure.invalidCredential }
        return "WorkosCursorSessionToken=\(account)%3A%3A\(credential.accessToken)"
    }
}

private extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
