import Foundation
import CryptoKit
import XCTest
@testable import TokenPulse

final class GoogleNativeOAuthTests: XCTestCase {
    func testProviderProjectValidationPrecedesNativeSessionAndRetainsProviderRules() throws {
        let instant = Date(timeIntervalSince1970: 1000)
        let auth = GoogleNativeOAuth(clientID: "123-test.apps.googleusercontent.com", transport: GoogleFixtureTransport([]), now: { instant })
        for (provider, validator) in [(Provider.antigravity, AntigravityProviderClient.validateConfiguredProject), (.gemini, GeminiProviderClient.validateConfiguredProject)] as [(Provider, @Sendable (String?) throws -> String?)] {
            XCTAssertThrowsError(try GoogleNativeOAuth(clientID: "invalid-client", transport: GoogleFixtureTransport([]), now: { instant }).begin(provider: provider, configuredProject: "my project!", validateProject: validator)) {
                guard case ProviderIntegrationError.unsupportedLogin(let message) = $0 else { return XCTFail("Expected project input feedback") }
                XCTAssertEqual(message, L10n.text("项目 ID 格式无效，请输入 Cloud 项目 ID；留空则使用已激活项目。"))
            }
            let prepared = try auth.begin(provider: provider, configuredProject: "  valid-project \n", validateProject: validator)
            XCTAssertEqual(prepared.project, "valid-project")
            XCTAssertEqual(prepared.session.provider, provider)
            XCTAssertNil(try auth.begin(provider: provider, configuredProject: " \n", validateProject: validator).project)
        }
        // Preserve each provider's existing accepted project syntax rather than imposing one UI whitelist.
        XCTAssertEqual(try auth.begin(provider: .antigravity, configuredProject: "project_alias", validateProject: AntigravityProviderClient.validateConfiguredProject).project, "project_alias")
        XCTAssertThrowsError(try auth.begin(provider: .gemini, configuredProject: "project_alias", validateProject: GeminiProviderClient.validateConfiguredProject))
    }
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

    func testPermanentUserinfoFailuresAndExhaustedRetriesRemainClassified() async throws {
        let instant = now
        for (status, expected) in [(429, RefreshFailure.rateLimited), (503, .server), (401, .invalidCredential)] {
            let replies = [(200, token)] + Array(repeating: (status, "{}"), count: status == 401 ? 1 : 3)
            let transport = GoogleFixtureTransport(replies)
            let auth = GoogleNativeOAuth(clientID: client, transport: transport, now: { instant }, sleep: { _ in })
            let session = try auth.begin(provider: .codex)
            do { _ = try await auth.exchange(callback: callback(session), session: session); XCTFail() }
            catch { XCTAssertEqual(error as? RefreshFailure, expected) }
            let requests = await transport.requests
            XCTAssertEqual(requests.filter { $0.httpMethod == "POST" }.count, 1)
            XCTAssertEqual(requests.count, status == 401 ? 2 : 4)
        }
    }

    func testUserinfo503ThenSuccessRetainsGrantAndExchangesCodeOnlyOnce() async throws {
        let instant = now, transport = GoogleFixtureTransport([(200, token), (503, "{}"), (200, #"{"id":"subject-after-retry"}"#)])
        let waits = GoogleWaitRecorder()
        let auth = GoogleNativeOAuth(clientID: client, transport: transport, now: { instant }, sleep: { await waits.record($0) })
        let session = try auth.begin(provider: .codex)
        let envelope = try await auth.exchange(callback: callback(session), session: session)
        XCTAssertEqual(envelope.accountID, "subject-after-retry")
        XCTAssertEqual(envelope.refreshToken, "synthetic-refresh")
        let requests = await transport.requests, delays = await waits.delays
        XCTAssertEqual(requests.filter { $0.httpMethod == "POST" }.count, 1)
        XCTAssertEqual(requests.filter { $0.url?.path == "/oauth2/v2/userinfo" }.count, 2)
        XCTAssertEqual(delays, [1])
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), requests[2].value(forHTTPHeaderField: "Authorization"))
    }

    func testUserinfo429HonorsReasonableRetryAfterWithoutReplayingCode() async throws {
        let instant = now
        let transport = GoogleFixtureTransport(responses: [(200, token, [:]), (429, "{}", ["Retry-After": "2"]), (200, #"{"id":"subject"}"#, [:])])
        let waits = GoogleWaitRecorder()
        let auth = GoogleNativeOAuth(clientID: client, transport: transport, now: { instant }, sleep: { await waits.record($0) })
        let session = try auth.begin(provider: .codex)
        _ = try await auth.exchange(callback: callback(session), session: session)
        let requests = await transport.requests, delays = await waits.delays
        XCTAssertEqual(delays, [2])
        XCTAssertEqual(requests.filter { $0.httpMethod == "POST" }.count, 1)
    }

    func testLongRetryAfterFailsWithoutSleepingOrRetryingBeforeCooldown() async throws {
        let instant = now
        let transport = GoogleFixtureTransport(responses: [(200, token, [:]), (429, "{}", ["Retry-After": "3600"])])
        let waits = GoogleWaitRecorder()
        let auth = GoogleNativeOAuth(clientID: client, transport: transport, now: { instant }, sleep: { await waits.record($0) })
        let session = try auth.begin(provider: .codex)
        do { _ = try await auth.exchange(callback: callback(session), session: session); XCTFail() }
        catch { XCTAssertEqual(error as? RefreshFailure, .rateLimited) }
        let requests = await transport.requests, delays = await waits.delays
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(delays.isEmpty)
    }

    func testRetryAfterHTTPDateAndMalformedValueHaveBoundedDelay() throws {
        let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!
        for (header, expected) in [("Thu, 01 Jan 1970 00:16:42 GMT", 2.0), ("garbage", 1.0), ("0", 0.0)] {
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": header]))
            XCTAssertEqual(GoogleNativeOAuth.userInfoRetryDelay(response, attempt: 0, now: now), expected)
        }
        let huge = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": String(repeating: "9", count: 400)]))
        XCTAssertNil(GoogleNativeOAuth.userInfoRetryDelay(huge, attempt: 0, now: now))
    }

    func testRefreshRejectsMissingOrReducedHistoricalScopeBeforeAnyRequest() async throws {
        let instant = now, transport = GoogleFixtureTransport([])
        let auth = GoogleNativeOAuth(clientID: client, transport: transport, now: { instant })
        for scopes in [nil, "", "https://www.googleapis.com/auth/userinfo.email"] as [String?] {
            var envelope = ProviderCredentialEnvelope(provider: .codex, kind: .oauth, accessToken: "old", refreshToken: "stable", metadata: ["clientID": client])
            envelope.metadata["grantedScopes"] = scopes
            do { _ = try await auth.refresh(envelope); XCTFail() }
            catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    @MainActor
    func testUnexpectedTransportCancellationHasFeedbackButExplicitTaskCancellationIsSilent() {
        for (language, expected) in [("zh-Hans", "Google 授权请求意外中断，请重试"),
                                     ("en", "The Google authorization request was interrupted. Please try again.")] {
            L10n.withLanguage(language) {
                XCTAssertEqual(GoogleNativeOAuthLoginModel.failureMessage(CancellationError(), taskCancelled: false), expected)
                let sourceText = "Provider-specific 原文: account/organization Ω"
                XCTAssertEqual(GoogleNativeOAuthLoginModel.failureMessage(ProviderIntegrationError.unsupportedLogin(sourceText),
                                                                          taskCancelled: false), sourceText)
            }
        }
        XCTAssertNil(GoogleNativeOAuthLoginModel.failureMessage(CancellationError(), taskCancelled: true))
        XCTAssertNil(GoogleNativeOAuthLoginModel.failureMessage(RefreshFailure.network, taskCancelled: true))
    }
    private func callback(_ session: ProviderLoginSession) throws -> URL { URL(string: "\(try XCTUnwrap(session.callbackURL))?code=synthetic-code&state=\(try XCTUnwrap(session.state))")! }
}

private actor GoogleFixtureTransport: ProviderTransport {
    var requests: [URLRequest] = []
    var replies: [(Int, String, [String: String])]
    init(_ replies: [(Int, String)]) { self.replies = replies.map { ($0.0, $0.1, [:]) } }
    init(responses: [(Int, String, [String: String])]) { self.replies = responses }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw ProviderIntegrationError.server }
        let reply = replies.removeFirst()
        return (Data(reply.1.utf8), HTTPURLResponse(url: request.url!, statusCode: reply.0, httpVersion: nil, headerFields: reply.2)!)
    }
}

private actor GoogleWaitRecorder {
    var delays: [TimeInterval] = []
    func record(_ delay: TimeInterval) { delays.append(delay) }
}
