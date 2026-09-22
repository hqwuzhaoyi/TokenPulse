import Foundation
import XCTest
@testable import TokenPulse

final class KimiCodeProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100)
    private let deviceReply = #"{"user_code":"KIMI-CODE","device_code":"device-test","verification_uri_complete":"https://www.kimi.com/oauth/device?user_code=KIMI-CODE","expires_in":1800,"interval":5}"#

    func testDeviceLoginUsesDomesticFormEndpointsAndCompletesOAuth() async throws {
        let transport = KimiTransportStub([
            (200, deviceReply), (400, #"{"error":"authorization_pending"}"#),
            (400, #"{"error":"slow_down"}"#),
            (200, #"{"access_token":"access-test","refresh_token":"refresh-test","expires_in":3600,"token_type":"Bearer","scope":"coding"}"#),
        ])
        let controller = ProviderAuthenticationController(transport: transport, now: { Date(timeIntervalSince1970: 100) })
        XCTAssertEqual(controller.loginConfiguration(for: .kimiCode).method, .deviceCode)
        let session = try await controller.beginLogin(provider: .kimiCode)
        XCTAssertEqual(session.userCode, "KIMI-CODE")
        XCTAssertEqual(session.authorizationURL.host, "www.kimi.com")
        XCTAssertEqual(session.expiresAt, now.addingTimeInterval(1800))
        XCTAssertNil(session.callbackURL)
        let pending = try await controller.continueLogin(session)
        XCTAssertEqual(pending, .pending(retryAfter: 5))
        let slowed = try await controller.continueLogin(session)
        XCTAssertEqual(slowed, .pending(retryAfter: 10))
        guard case .completed(let encoded) = try await controller.continueLogin(session) else {
            return XCTFail("Expected OAuth completion")
        }
        let credential = try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .kimiCode)
        XCTAssertEqual(credential.kind, .oauth)
        XCTAssertEqual(credential.accessToken, "access-test")
        XCTAssertEqual(credential.refreshToken, "refresh-test")
        XCTAssertEqual(credential.expiresAt, now.addingTimeInterval(3600))
        XCTAssertEqual(credential.metadata, ["token_type": "Bearer", "scope": "coding"])
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://auth.kimi.com/api/oauth/device_authorization")
        XCTAssertEqual(requests.first?.httpMethod, "POST")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(String(data: try XCTUnwrap(requests.first?.httpBody), encoding: .utf8),
                       "client_id=17e5f671-d194-4dfb-9706-5516cb48c098")
        XCTAssertEqual(requests.last?.url?.absoluteString, "https://auth.kimi.com/api/oauth/token")
        XCTAssertEqual(String(data: try XCTUnwrap(requests.last?.httpBody), encoding: .utf8),
                       "client_id=17e5f671-d194-4dfb-9706-5516cb48c098&device_code=device-test&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code")
    }

    func testQuotaClampsRatiosAndDoesNotDuplicateMonthlyCodeBreakdown() async throws {
        let transport = KimiTransportStub([(200, #"""
        {"usages":{
          "limit_5h":{"used_ratio":0.25,"reset_time":"2026-09-22T12:00:00Z"},
          "limit_7d":{"used_ratio":"1.2","reset_time":"2026-09-27T12:00:00.000Z"},
          "limit_month_total":{"used_ratio":-0.1},"limit_month_code":{"used_ratio":1}
        }}
        """#)])
        let accountID = UUID()
        let result = try await ProviderQuotaClient(provider: .kimiCode, transport: transport)
            .quotaResult(for: accountID, credential: credential())
        XCTAssertEqual(result.snapshot.accountID, accountID)
        XCTAssertEqual(result.snapshot.windows.map(\.period), [.fiveHour, .weekly, .monthly])
        XCTAssertEqual(result.snapshot.windows.map(\.usedPercentage), [25, 100, 0])
        XCTAssertEqual(Set(result.snapshot.windows.map(\.id)).count, 3)
        XCTAssertNotNil(result.snapshot.windows[0].resetsAt)
        XCTAssertNotNil(result.snapshot.windows[1].resetsAt)
        XCTAssertNil(result.snapshot.windows[2].resetsAt)
        let request = await transport.requests.first
        XCTAssertEqual(request?.url?.absoluteString, "https://api.kimi.com/coding/v1/usages")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer access-test")
        XCTAssertEqual(request?.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testWalletOnlyResponseRetainsBalanceWithOfficialFixedPointConversion() async throws {
        let transport = KimiTransportStub([(200, #"{"boosterWallet":{"balance":{"type":"BOOSTER","amount":"1200000000","amountLeft":100},"monthlyUsed":{"currency":"CNY","priceInCents":0}}}"#)])
        let result = try await ProviderQuotaClient(provider: .kimiCode, transport: transport)
            .quotaResult(for: UUID(), credential: credential())
        let window = try XCTUnwrap(result.snapshot.windows.first)
        XCTAssertEqual(window.totalCount, 12)
        XCTAssertEqual(window.remainingCount, 0.01)
        XCTAssertEqual(window.unit, "CNY")
        XCTAssertNil(window.usedPercentage)
        XCTAssertNil(window.resetsAt)
        XCTAssertNil(window.wallet, "Booster funding does not have granted/topped-up balances")
    }

    func testRefreshRotatesTokensFiveMinutesBeforeExpiryAndKeepsUnchangedCredentialOffline() async throws {
        let transport = KimiTransportStub([(200, #"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":7200}"#)])
        let controller = ProviderAuthenticationController(transport: transport, now: { Date(timeIntervalSince1970: 100) })
        let refreshed = try await controller.refreshCredentialIfNeeded(provider: .kimiCode, credential: credential(expiresAt: now.addingTimeInterval(180)))
        XCTAssertTrue(refreshed.changed)
        let value = try ProviderCredentialEnvelope.decode(refreshed.credential, expectedProvider: .kimiCode)
        XCTAssertEqual(value.accessToken, "new-access")
        XCTAssertEqual(value.refreshToken, "new-refresh")
        XCTAssertEqual(value.expiresAt, now.addingTimeInterval(7200))
        let unchanged = try await controller.refreshCredentialIfNeeded(provider: .kimiCode, credential: refreshed.credential)
        XCTAssertFalse(unchanged.changed)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(String(data: try XCTUnwrap(requests.first?.httpBody), encoding: .utf8),
                       "client_id=17e5f671-d194-4dfb-9706-5516cb48c098&grant_type=refresh_token&refresh_token=refresh-test")
    }

    func testRevokedRefreshTokenRequiresLogin() async throws {
        let transport = KimiTransportStub([(400, #"{"error":"invalid_grant"}"#)])
        let controller = ProviderAuthenticationController(transport: transport)
        do {
            _ = try await controller.refreshCredentialIfNeeded(provider: .kimiCode, credential: credential(expiresAt: now))
            XCTFail("Expected invalid credential")
        } catch {
            XCTAssertEqual(error as? ProviderIntegrationError, .invalidCredential)
        }
    }

    func testQuotaFailuresDistinguishInvalidCredentialsAndMissingUsage() async throws {
        for (status, body, expected) in [
            (401, "{}", RefreshFailure.invalidCredential), (429, "{}", .rateLimited),
            (500, "{}", .server), (200, "not-json", .unreadableResponse),
            (200, #"{"usages":{"limit_5h":{"reset_time":"2026-09-22T12:00:00Z"}}}"#, .noQuotaWindows),
        ] {
            let transport = KimiTransportStub([(status, body)])
            do {
                _ = try await ProviderQuotaClient(provider: .kimiCode, transport: transport)
                    .quotaResult(for: UUID(), credential: credential())
                XCTFail("Expected \(expected)")
            } catch {
                XCTAssertEqual(error as? RefreshFailure, expected)
            }
        }
    }

    func testExpiredSessionStopsPollingWithoutSendingDeviceCode() async throws {
        let transport = KimiTransportStub([(200, deviceReply)])
        let starter = ProviderAuthenticationController(transport: transport, now: { Date(timeIntervalSince1970: 100) })
        let session = try await starter.beginLogin(provider: .kimiCode)
        let expired = ProviderAuthenticationController(transport: transport, now: { Date(timeIntervalSince1970: 2000) })
        do {
            _ = try await expired.continueLogin(session)
            XCTFail("Expected expired login")
        } catch {
            XCTAssertEqual(error as? ProviderIntegrationError, .loginExpired)
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testDeviceAuthorizationRejectsUntrustedVerificationURL() async throws {
        let body = deviceReply.replacingOccurrences(of: "www.kimi.com", with: "untrusted.example")
        let controller = ProviderAuthenticationController(transport: KimiTransportStub([(200, body)]))
        do {
            _ = try await controller.beginLogin(provider: .kimiCode)
            XCTFail("Expected untrusted authorization URL to be rejected")
        } catch {
            XCTAssertEqual(error as? ProviderIntegrationError, .unreadableResponse)
        }
    }

    private func credential(expiresAt: Date? = nil) throws -> String {
        try ProviderCredentialEnvelope(provider: .kimiCode, kind: .oauth, accessToken: "access-test",
                                       refreshToken: "refresh-test", expiresAt: expiresAt).encoded()
    }
}

private actor KimiTransportStub: ProviderTransport {
    private var replies: [(Int, String)]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [(Int, String)]) { self.replies = replies }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let (status, body) = replies.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status,
                                              httpVersion: nil, headerFields: nil)!)
    }
}
