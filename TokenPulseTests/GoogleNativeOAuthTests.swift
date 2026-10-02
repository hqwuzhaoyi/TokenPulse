import Foundation
import CryptoKit
import XCTest
@testable import TokenPulse

final class GoogleNativeOAuthTests: XCTestCase {
    private let client = "12345-test.apps.googleusercontent.com"
    private let now = Date(timeIntervalSince1970: 1000)
    private let token = #"{"access_token":"synthetic-access","refresh_token":"synthetic-refresh","expires_in":3600,"token_type":"Bearer"}"#

    func testPublicClientPKCEAndDynamicCallbackWithoutSecret() throws {
        let instant = now
        let auth = GoogleNativeOAuth(clientID: client, transport: GoogleFixtureTransport([]), now: { instant })
        let session = try auth.begin(provider: .codex)
        let values = Dictionary(uniqueKeysWithValues: try XCTUnwrap(URLComponents(url: session.authorizationURL, resolvingAgainstBaseURL: false)).queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(values["redirect_uri"], "com.googleusercontent.apps.12345-test:/oauth2redirect")
        XCTAssertEqual(values["client_id"], client)
        XCTAssertNil(values["client_secret"])
        XCTAssertNil(values["code_verifier"])
        XCTAssertEqual(values["code_challenge_method"], "S256")
        let verifier = try XCTUnwrap(session.codeVerifier)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(values["code_challenge"], challenge)
        for value in ["", "secret", "123 bad.apps.googleusercontent.com", "client.apps.googleusercontent.com/path"] { XCTAssertThrowsError(try GoogleNativeOAuth.redirectURL(clientID: value)) }
    }

    func testWrongStatePathHostDuplicateParametersAndExpiryRejectedBeforeHTTPS() throws {
        let instant = now, transport = GoogleFixtureTransport([])
        let auth = GoogleNativeOAuth(clientID: client, transport: transport, now: { instant })
        let session = try auth.begin(provider: .codex), callback = try XCTUnwrap(session.callbackURL)
        let state = try XCTUnwrap(session.state)
        for url in ["\(callback)?code=x&state=wrong", "\(callback)?code=x&state=\(state)&state=\(state)", "\(callback)?error=access_denied&state=\(state)", "\(callback)?code=x&state=\(state)#fragment", "\(callback.scheme!)://evil/oauth2redirect?code=x&state=\(state)", "\(callback.scheme!):/other?code=x&state=\(state)"] { XCTAssertThrowsError(try auth.callbackCode(URL(string: url)!, session: session)) }
        XCTAssertThrowsError(try GoogleNativeOAuth(clientID: client, transport: transport, now: { instant.addingTimeInterval(601) }).callbackCode(URL(string: "\(callback)?code=x&state=\(state)")!, session: session))
    }

    func testScopeOmittedMeansSameRequestedScopeAndUserinfoProvidesSubject() async throws {
        let instant = now, transport = GoogleFixtureTransport([(200, token), (200, #"{"id":"subject-1","email":"not-identity@example.invalid"}"#)])
        let auth = GoogleNativeOAuth(clientID: client, transport: transport, now: { instant })
        let session = try auth.begin(provider: .codex)
        let envelope = try await auth.exchange(callback: callback(session), session: session)
        XCTAssertEqual(envelope.accountID, "subject-1")
        XCTAssertEqual(envelope.metadata["grantedScopes"], GoogleNativeOAuth.scopes.joined(separator: " "))
        let requests = await transport.requests
        let form = String(data: try XCTUnwrap(requests.first?.httpBody), encoding: .utf8)!
        XCTAssertTrue(form.contains("code_verifier="))
        XCTAssertFalse(form.contains("client_secret"))
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-access")
    }

    func testExplicitReducedScopeAndHeaderInjectionRejected() async throws {
        let instant = now
        for reply in [token.dropLast() + #", "scope":"https://www.googleapis.com/auth/userinfo.email"}"#, token.replacingOccurrences(of: "synthetic-access", with: #"bad\r\nHeader"#)] {
            let auth = GoogleNativeOAuth(clientID: client, transport: GoogleFixtureTransport([(200, String(reply))]), now: { instant })
            let session = try auth.begin(provider: .codex)
            do { _ = try await auth.exchange(callback: callback(session), session: session); XCTFail("Expected invalid grant") } catch {}
        }
    }

    func testRefreshRetainsOrReplacesRefreshTokenAndIdentityMetadata() async throws {
        let instant = now
        let old = ProviderCredentialEnvelope(provider: .codex, kind: .oauth, accessToken: "old", refreshToken: "stable", expiresAt: instant, accountID: "subject", metadata: ["clientID": client, "grantedScopes": GoogleNativeOAuth.scopes.joined(separator: " "), "project": "actual-project"])
        for replacement in [nil, "rotated"] as [String?] {
            let reply = #"{"access_token":"new","expires_in":3600,"token_type":"Bearer""# + (replacement.map { ",\"refresh_token\":\"\($0)\"" } ?? "") + "}"
            let transport = GoogleFixtureTransport([(200, reply)])
            let updated = try await GoogleNativeOAuth(clientID: client, transport: transport, now: { instant }).refresh(old)
            XCTAssertEqual(updated.refreshToken, replacement ?? "stable")
            XCTAssertEqual(updated.accountID, old.accountID)
            XCTAssertEqual(updated.metadata["project"], "actual-project")
            let requests = await transport.requests
            XCTAssertFalse(String(data: try XCTUnwrap(requests.first?.httpBody), encoding: .utf8)!.contains("client_secret"))
        }
    }

    func testUserinfoTransientFailuresDoNotForceReauthentication() async throws {
        let instant = now
        for (status, expected) in [(429, RefreshFailure.rateLimited), (503, .server), (401, .invalidCredential)] {
            let auth = GoogleNativeOAuth(clientID: client, transport: GoogleFixtureTransport([(200, token), (status, "{}")]), now: { instant })
            let session = try auth.begin(provider: .codex)
            do { _ = try await auth.exchange(callback: callback(session), session: session); XCTFail() }
            catch { XCTAssertEqual(error as? RefreshFailure, expected) }
        }
    }
    private func callback(_ session: ProviderLoginSession) throws -> URL { URL(string: "\(try XCTUnwrap(session.callbackURL))?code=synthetic-code&state=\(try XCTUnwrap(session.state))")! }
}

private actor GoogleFixtureTransport: ProviderTransport {
    var requests: [URLRequest] = []
    var replies: [(Int, String)]
    init(_ replies: [(Int, String)]) { self.replies = replies }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw ProviderIntegrationError.server }
        let reply = replies.removeFirst()
        return (Data(reply.1.utf8), HTTPURLResponse(url: request.url!, statusCode: reply.0, httpVersion: nil, headerFields: nil)!)
    }
}
