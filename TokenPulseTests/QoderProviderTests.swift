import CryptoKit
import Foundation
import XCTest
@testable import TokenPulse

final class QoderProviderTests: XCTestCase {
    func testDeviceLoginUsesPKCEAndPollsTheSameNonceUntilCompleted() async throws {
        let transport = QoderTransportStub([
            .response(202, "{}"), .response(404, "{}"),
            .response(200, #"{"token":"fixture-access","refresh_token":"fixture-refresh","user_id":"fixture-user","expires_at":"2026-10-15T00:00:00.000Z","expires_in":2591999998}"#),
        ])
        let controller = ProviderAuthenticationController(transport: transport, now: { Date(timeIntervalSince1970: 100) })
        XCTAssertEqual(controller.loginConfiguration(for: .qoderInternational).method, .deviceCode)
        let session = try await controller.beginLogin(provider: .qoderInternational)
        let verifier = try XCTUnwrap(session.codeVerifier)
        let query = try XCTUnwrap(URLComponents(url: session.authorizationURL, resolvingAgainstBaseURL: false)?.queryItems)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(verifier.count, 43)
        XCTAssertEqual(session.authorizationURL.host, "qoder.com")
        XCTAssertEqual(query.first { $0.name == "challenge" }?.value, challenge)
        XCTAssertEqual(query.first { $0.name == "challenge_method" }?.value, "S256")
        XCTAssertEqual(query.first { $0.name == "nonce" }?.value, session.state)
        XCTAssertEqual(query.first { $0.name == "machine_id" }?.value, session.metadata["machineID"])
        XCTAssertFalse(session.authorizationURL.absoluteString.contains(verifier))
        XCTAssertNil(session.userCode)
        XCTAssertEqual(session.expiresAt, Date(timeIntervalSince1970: 280))

        let first = try await controller.continueLogin(session)
        let second = try await controller.continueLogin(session)
        XCTAssertEqual(first, .pending(retryAfter: 2))
        XCTAssertEqual(second, .pending(retryAfter: 2))
        guard case .completed(let encoded) = try await controller.continueLogin(session) else {
            return XCTFail("Expected completed device login")
        }
        let credential = try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .qoderInternational)
        XCTAssertEqual(credential.accessToken, "fixture-access")
        XCTAssertEqual(credential.refreshToken, "fixture-refresh")
        XCTAssertEqual(credential.accountID, "fixture-user")
        XCTAssertEqual(credential.expiresAt, ISO8601DateFormatter().date(from: "2026-10-15T00:00:00Z"))
        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 3)
        for request in requests {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.host, "openapi.qoder.sh")
            XCTAssertEqual(request.url?.path, "/api/v1/deviceToken/poll")
            XCTAssertNotEqual(request.url?.host, "center.qoder.sh")
            let pollQuery = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(pollQuery?.first { $0.name == "nonce" }?.value, session.state)
            XCTAssertEqual(pollQuery?.first { $0.name == "verifier" }?.value, verifier)
            XCTAssertEqual(pollQuery?.first { $0.name == "challenge_method" }?.value, "S256")
        }
    }

    func testExpiredLoginDoesNotPollAndMismatchedChallengeIsRejected() async throws {
        let transport = QoderTransportStub([.response(200, #"{"token":"fixture-token","code_challenge":"wrong"}"#)])
        let authenticator = QoderProviderAuthenticator(transport: transport, now: { Date(timeIntervalSince1970: 100) })
        let session = try authenticator.begin()
        let expired = QoderProviderAuthenticator(transport: transport, now: { Date(timeIntervalSince1970: 280) })
        do {
            _ = try await expired.poll(session)
            XCTFail("Expired login must fail")
        } catch { XCTAssertEqual(error as? ProviderIntegrationError, .loginExpired) }
        let expiredRequests = await transport.requests()
        XCTAssertTrue(expiredRequests.isEmpty)
        do {
            _ = try await authenticator.poll(session)
            XCTFail("Mismatched PKCE must fail")
        } catch { XCTAssertEqual(error as? ProviderIntegrationError, .invalidCallback) }
    }

    func testPollNetworkErrorIsRetryableOnTheSameSession() async throws {
        let transport = QoderTransportStub([
            .failure(.networkConnectionLost),
            .response(200, #"{"token":"fixture-access","user_id":"fixture-user"}"#),
        ])
        let authenticator = QoderProviderAuthenticator(transport: transport, now: { Date(timeIntervalSince1970: 100) })
        let session = try authenticator.begin()
        do {
            _ = try await authenticator.poll(session)
            XCTFail("Network loss must surface as a retryable login error")
        } catch { XCTAssertEqual(error as? ProviderIntegrationError, .network) }
        guard case .completed(let encoded) = try await authenticator.poll(session) else {
            return XCTFail("The same PKCE session must resume after a transient disconnect")
        }
        XCTAssertEqual(try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .qoderInternational).accessToken,
                       "fixture-access")
        let requests = await transport.requests()
        XCTAssertEqual(Set(requests.map { $0.url?.path }), ["/api/v1/deviceToken/poll"])
        XCTAssertEqual(requests.count, 2)
    }

    func testPollIgnoresExpiresInAndRejectsEmptyToken() async throws {
        let transport = QoderTransportStub([
            .response(200, #"{"token":"fixture-access","expires_in":2591999998}"#),
            .response(200, #"{"token":"  "}"#),
        ])
        let authenticator = QoderProviderAuthenticator(transport: transport, now: { Date(timeIntervalSince1970: 100) })
        let session = try authenticator.begin()
        guard case .completed(let encoded) = try await authenticator.poll(session) else {
            return XCTFail("Expected completed login")
        }
        XCTAssertNil(try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .qoderInternational).expiresAt)
        do {
            _ = try await authenticator.poll(session)
            XCTFail("Empty token must fail")
        } catch { XCTAssertEqual(error as? ProviderIntegrationError, .unreadableResponse) }
    }

    func testExpiryRequiresReauthenticationWithoutCallingUnsupportedRefreshEndpoint() async throws {
        let transport = QoderTransportStub([])
        let controller = ProviderAuthenticationController(transport: transport, now: { Date(timeIntervalSince1970: 100) })
        for expiresAt in [Date(timeIntervalSince1970: 101), nil] {
            let original = try ProviderCredentialEnvelope(provider: .qoderInternational, kind: .oauth,
                                                          accessToken: "fixture", refreshToken: "fixture-refresh",
                                                          expiresAt: expiresAt).encoded()
            let result = try await controller.refreshCredentialIfNeeded(provider: .qoderInternational, credential: original)
            XCTAssertEqual(result, .init(credential: original, changed: false))
        }
        let expired = try ProviderCredentialEnvelope(provider: .qoderInternational, kind: .oauth,
                                                     accessToken: "fixture", refreshToken: "fixture-refresh",
                                                     expiresAt: Date(timeIntervalSince1970: 100)).encoded()
        do {
            _ = try await controller.refreshCredentialIfNeeded(provider: .qoderInternational, credential: expired)
            XCTFail("Expired credentials require login")
        } catch { XCTAssertEqual(error as? ProviderIntegrationError, .invalidCredential) }
        let refreshRequests = await transport.requests()
        XCTAssertTrue(refreshRequests.isEmpty)
        XCTAssertEqual(QoderProviderAuthenticator.expiry("1781594470000"), Date(timeIntervalSince1970: 1781594470))
        XCTAssertNil(QoderProviderAuthenticator.expiry(true))
        XCTAssertNil(QoderProviderAuthenticator.expiry("invalid"))
        XCTAssertNil(QoderProviderAuthenticator.expiry(0))
    }

    func testQuotaKeepsPersonalAndOrganizationIndependentAndExpiryIsNotReset() async throws {
        let transport = QoderTransportStub([.response(200, #"{"userQuota":{"total":1000,"used":250,"remaining":750,"percentage":0.25,"unit":"credits"},"orgResourcePackage":{"total":200,"used":100,"remaining":100,"unit":"credits"},"totalUsagePercentage":0.9,"isQuotaExceeded":true,"expiresAt":1781594470000}"#)])
        let credential = try ProviderCredentialEnvelope(provider: .qoderInternational, kind: .oauth, accessToken: "fixture").encoded()
        let accountID = UUID()
        let result = try await ProviderQuotaClient(provider: .qoderInternational, transport: transport,
                                                   now: { Date(timeIntervalSince1970: 100) })
            .quotaResult(for: accountID, credential: credential)
        XCTAssertEqual(result.snapshot.accountID, accountID)
        XCTAssertEqual(result.snapshot.windows.map(\.id), ["qoder.userQuota", "qoder.orgResourcePackage"])
        XCTAssertEqual(result.snapshot.windows.map(\.name), ["个人额度", "组织资源包"])
        XCTAssertEqual(result.snapshot.windows.map(\.usedPercentage), [25, 50])
        XCTAssertEqual(result.snapshot.windows.map(\.remainingCount), [750, 100])
        XCTAssertEqual(result.snapshot.windows.map(\.unit), ["credits", "credits"])
        XCTAssertTrue(result.snapshot.windows.allSatisfy { $0.resetsAt == nil && $0.cycleID == nil && $0.scope == nil })
        XCTAssertEqual(result.snapshot.windows.first?.expiresAt, Date(timeIntervalSince1970: 1781594470))
        XCTAssertNil(result.snapshot.windows.last?.expiresAt)
        XCTAssertEqual(result.snapshot.quotaExceeded, true)
        XCTAssertEqual(result.snapshot.windows.map(\.isExhausted), [false, false])
        let quotaRequests = await transport.requests()
        let request = try XCTUnwrap(quotaRequests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://openapi.qoder.sh/api/v2/quota/usage")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(result.updatedCredential)
    }

    func testMissingMetricsAndBooleanNumbersDoNotBecomeZeroOrCombinedPercentages() throws {
        let root = try ProviderHTTP.json(Data(#"{"userQuota":{"total":true,"used":1,"remaining":false,"percentage":0.25},"orgResourcePackage":{"total":100,"used":0,"remaining":100},"totalUsagePercentage":0.8}"#.utf8))
        let windows = QoderProviderClient.windows(root)
        XCTAssertEqual(windows.map(\.id), ["qoder.orgResourcePackage"])
        XCTAssertEqual(windows[0].usedPercentage, 0)
        XCTAssertEqual(windows[0].remainingCount, 100)
        XCTAssertEqual(windows[0].totalCount, 100)
        XCTAssertTrue(QoderProviderClient.windows([:]).isEmpty)
        XCTAssertTrue(QoderProviderClient.windows(["orgResourcePackage": ["unit": "credits"]]).isEmpty)
        XCTAssertTrue(QoderProviderClient.windows(["userQuota": ["percentage": 0.25]]).isEmpty)
        XCTAssertEqual(QoderProviderClient.windows(["orgResourcePackage": ["remaining": 1200]]).map(\.remainingCount), [1200])
        XCTAssertNil(QoderProviderClient.windows(["orgResourcePackage": ["remaining": 1200]]).first?.usedPercentage)
    }

    func testCombinedExhaustionUsesOnlyExplicitBooleanAndNeverChangesBucketStatus() async throws {
        for (flag, expected) in [("true", Optional(true)), ("false", Optional(false)), ("1", nil), ("0", nil), ("null", nil)] {
            let body = "{\"userQuota\":{\"remaining\":0,\"total\":10,\"used\":10},\"isQuotaExceeded\":\(flag)}"
            let transport = QoderTransportStub([.response(200, body)])
            let credential = try ProviderCredentialEnvelope(provider: .qoderInternational, kind: .oauth, accessToken: "fixture").encoded()
            let result = try await ProviderQuotaClient(provider: .qoderInternational, transport: transport)
                .quotaResult(for: UUID(), credential: credential)
            XCTAssertEqual(result.snapshot.quotaExceeded, expected, flag)
            XCTAssertEqual(result.snapshot.windows.first?.remainingCount, 0)
            XCTAssertEqual(result.snapshot.windows.first?.isExhausted, true)
            XCTAssertEqual(result.snapshot.windows.first?.usedPercentage, 100)
            XCTAssertNil(result.snapshot.windows.first?.resetsAt)
        }
    }

    func testQuotaErrorsUseSharedFailureMapping() async throws {
        for (status, body, expected) in [(401, "{}", RefreshFailure.invalidCredential),
                                         (403, "{}", .invalidCredential), (429, "{}", .rateLimited),
                                         (500, "{}", .server), (200, "not-json", .unreadableResponse),
                                         (200, "{}", .noQuotaWindows)] {
            let transport = QoderTransportStub([.response(status, body)])
            let credential = try ProviderCredentialEnvelope(provider: .qoderInternational, kind: .oauth, accessToken: "fixture").encoded()
            do {
                _ = try await ProviderQuotaClient(provider: .qoderInternational, transport: transport)
                    .quotaResult(for: UUID(), credential: credential)
                XCTFail("Expected failure for HTTP \(status)")
            } catch { XCTAssertEqual(error as? RefreshFailure, expected) }
        }
        let network = QoderTransportStub([.failure(.timedOut)])
        let credential = try ProviderCredentialEnvelope(provider: .qoderInternational, kind: .oauth, accessToken: "fixture").encoded()
        do {
            _ = try await ProviderQuotaClient(provider: .qoderInternational, transport: network)
                .quotaResult(for: UUID(), credential: credential)
            XCTFail("Expected network failure")
        } catch { XCTAssertEqual(error as? RefreshFailure, .network) }
        let networkRequests = await network.requests()
        XCTAssertEqual(try XCTUnwrap(networkRequests.first?.url?.path), "/api/v2/quota/usage")
    }
}

private actor QoderTransportStub: ProviderTransport {
    enum Outcome: Sendable {
        case response(Int, String)
        case failure(URLError.Code)
    }

    private var outcomes: [Outcome]
    private var receivedRequests: [URLRequest] = []

    init(_ outcomes: [Outcome]) { self.outcomes = outcomes }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        receivedRequests.append(request)
        guard !outcomes.isEmpty else { throw URLError(.badServerResponse) }
        switch outcomes.removeFirst() {
        case .failure(let code): throw URLError(code)
        case .response(let status, let body):
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    func requests() -> [URLRequest] { receivedRequests }
}
