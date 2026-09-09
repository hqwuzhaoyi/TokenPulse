import Foundation
import XCTest
@testable import TokenPulse

final class ProviderTests: XCTestCase {
    func testCodexUsesAvailableResetCountRatherThanCreditListOrEarnedCount() async throws {
        for count in [0, 3] {
            let body = """
            {"rate_limit":{"secondary_window":{"used_percent":25,"limit_window_seconds":604800}},
             "rate_limit_reset_credits":{"available_count":\(count),"total_earned_count":50,"credits":[{"id":"fixture"}]}}
            """
            let transport = ProviderTransportStub([.response(200, body)])
            let credential = try ProviderCredentialEnvelope(provider: .codex, kind: .oauth, accessToken: "fixture-token").encoded()
            let result = try await ProviderQuotaClient(provider: .codex, transport: transport)
                .quotaResult(for: UUID(), credential: credential)
            XCTAssertEqual(result.snapshot.remainingResetCount, count)
            let restored = try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(result.snapshot))
            XCTAssertEqual(restored.remainingResetCount, count)
            let requests = await transport.requests()
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests.first?.url?.path, "/backend-api/wham/usage")
            XCTAssertEqual(requests.first?.httpMethod, "GET")
        }
    }

    func testCodexMissingOrInvalidResetCountRemainsUnknown() async throws {
        for summary in ["null", "{}", "{\"available_count\":-1}", "{\"available_count\":1.5}", "{\"available_count\":true}"] {
            let body = """
            {"rate_limit":{"secondary_window":{"used_percent":25,"limit_window_seconds":604800}},"rate_limit_reset_credits":\(summary)}
            """
            let transport = ProviderTransportStub([.response(200, body)])
            let credential = try ProviderCredentialEnvelope(provider: .codex, kind: .oauth, accessToken: "fixture-token").encoded()
            let result = try await ProviderQuotaClient(provider: .codex, transport: transport)
                .quotaResult(for: UUID(), credential: credential)
            XCTAssertNil(result.snapshot.remainingResetCount)
            XCTAssertEqual(result.snapshot.windows.first?.usedPercentage, 25)
        }
    }

    func testSuperGrokReadsPublishedPercentageFromCreditsRPCWhenProxyOmitsIt() async throws {
        let transport = ProviderTransportStub([
            .response(200, #"{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-09-01T00:00:00Z","end":"2026-09-08T00:00:00Z"}}}"#),
            .binary(Data([0, 0, 0, 0, 7, 10, 5, 13, 0, 0, 22, 66])),
        ])
        let credential = try ProviderCredentialEnvelope(provider: .superGrok, kind: .oauth, accessToken: "fixture-token").encoded()
        let result = try await ProviderQuotaClient(provider: .superGrok, transport: transport)
            .quotaResult(for: UUID(), credential: credential)
        XCTAssertEqual(result.snapshot.windows.first?.usedPercentage, 37.5)
        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.url?.path, "/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig")
        XCTAssertEqual(requests.last?.httpMethod, "POST")
    }

    func testSuperGrokDoesNotTurnMissingOrMalformedRPCUsageIntoZero() async throws {
        for body in [Data([0, 0, 0, 0, 2, 10, 0]), Data([0, 0, 0, 0, 7, 10]) ] {
            let transport = ProviderTransportStub([.response(200, #"{"config":{}}"#), .binary(body)])
            let credential = try ProviderCredentialEnvelope(provider: .superGrok, kind: .oauth, accessToken: "fixture-token").encoded()
            let result = try await ProviderQuotaClient(provider: .superGrok, transport: transport)
                .quotaResult(for: UUID(), credential: credential)
            XCTAssertNil(result.snapshot.windows.first?.usedPercentage)
        }
    }

    func testSuperGrokAcceptsExplicitZeroUsageFromCreditsRPC() async throws {
        let transport = ProviderTransportStub([
            .response(200, #"{"config":{}}"#),
            .binary(Data([0, 0, 0, 0, 7, 10, 5, 13, 0, 0, 0, 0])),
        ])
        let credential = try ProviderCredentialEnvelope(provider: .superGrok, kind: .oauth, accessToken: "fixture-token").encoded()
        let result = try await ProviderQuotaClient(provider: .superGrok, transport: transport)
            .quotaResult(for: UUID(), credential: credential)
        XCTAssertEqual(result.snapshot.windows.first?.usedPercentage, 0)
    }

    @MainActor
    func testDeviceLoginRecoversNetworkInterruptionWithoutReplacingUserCode() async throws {
        let transport = ProviderTransportStub([
            .response(200, #"{"user_code":"TEST-CODE","device_auth_id":"device-test","interval":1}"#),
            .response(403, "{}"),
            .failure(.networkConnectionLost),
            .response(200, #"{"authorization_code":"test-code","code_verifier":"test-verifier"}"#),
            .response(200, #"{"access_token":"test-access","refresh_token":"test-refresh","expires_in":3600}"#),
        ])
        let model = DeviceLoginModel(controller: ProviderAuthenticationController(transport: transport), sleep: { _ in })
        var credential: String?

        await model.authorize(provider: .codex) { credential = $0 }

        XCTAssertNotNil(credential, "Returning from browser authorization must continue the same device login after a transient disconnect")
        XCTAssertNil(model.message)
        XCTAssertEqual(model.session?.userCode, "TEST-CODE")
        let requests = await transport.requests()
        XCTAssertEqual(requests.filter { $0.url?.path.hasSuffix("usercode") == true }.count, 1)
        XCTAssertEqual(requests.count, 5)
    }

    @MainActor
    func testDeviceLoginResumesSameSessionAfterBackgroundCancellation() async throws {
        let transport = ProviderTransportStub([
            .response(200, #"{"user_code":"TEST-CODE","device_auth_id":"device-test","interval":1}"#),
            .failure(.cancelled),
            .response(200, #"{"authorization_code":"test-code","code_verifier":"test-verifier"}"#),
            .response(200, #"{"access_token":"test-access","refresh_token":"test-refresh","expires_in":3600}"#),
        ])
        let model = DeviceLoginModel(controller: ProviderAuthenticationController(transport: transport), sleep: { _ in })
        var completions = 0
        await model.authorize(provider: .codex) { _ in completions += 1 }
        XCTAssertEqual(completions, 0)
        XCTAssertNil(model.message)
        await model.authorize(provider: .codex) { _ in completions += 1 }
        XCTAssertEqual(completions, 1)
        await model.authorize(provider: .codex) { _ in completions += 1 }
        XCTAssertEqual(completions, 1, "A later active event must not deliver the credential twice")
        XCTAssertNil(model.message)
        let requests = await transport.requests()
        XCTAssertEqual(requests.filter { $0.url?.path.hasSuffix("usercode") == true }.count, 1)
        XCTAssertEqual(requests.count, 4)
    }

    @MainActor
    func testDeviceLoginDoesNotRetryPermanentServerFailure() async {
        let transport = ProviderTransportStub([
            .response(200, #"{"user_code":"TEST-CODE","device_auth_id":"device-test","interval":1}"#),
            .response(500, "{}"),
        ])
        let model = DeviceLoginModel(controller: ProviderAuthenticationController(transport: transport), sleep: { _ in })
        await model.authorize(provider: .codex) { _ in XCTFail("Login must not succeed") }
        XCTAssertNotNil(model.message)
        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 2)
    }

    @MainActor
    func testPersistentNetworkFailureStopsAndRetryPreservesAuthorizationCode() async {
        let transport = ProviderTransportStub([
            .response(200, #"{"user_code":"TEST-CODE","device_auth_id":"device-test","interval":1}"#),
            .failure(.networkConnectionLost), .failure(.timedOut), .failure(.notConnectedToInternet),
            .response(200, #"{"authorization_code":"test-code","code_verifier":"test-verifier"}"#),
            .response(200, #"{"access_token":"test-access","refresh_token":"test-refresh","expires_in":3600}"#),
        ])
        let model = DeviceLoginModel(controller: ProviderAuthenticationController(transport: transport), sleep: { _ in })
        var completions = 0
        await model.authorize(provider: .codex) { _ in completions += 1 }
        XCTAssertEqual(completions, 0)
        XCTAssertNotNil(model.message)
        XCTAssertEqual(model.session?.userCode, "TEST-CODE")
        XCTAssertFalse(model.reconnecting)
        let beforeRetry = await transport.requests()
        XCTAssertEqual(beforeRetry.count, 4)
        await model.authorize(provider: .codex) { _ in completions += 1 }
        XCTAssertEqual(completions, 1)
        XCTAssertNil(model.message)
        let requests = await transport.requests()
        XCTAssertEqual(requests.filter { $0.url?.path.hasSuffix("usercode") == true }.count, 1)
    }

    func testDirectKeyEncodingPreservesMiniMaxAndWrapsOtherKeyProviders() throws {
        let controller = ProviderAuthenticationController()
        XCTAssertEqual(try controller.credential(provider: .miniMaxChina, apiKey: "  minimax-test-key  "), "minimax-test-key")
        for (provider, key) in [(Provider.zai, "zai-test-key"), (.openCodeGo, "opencode-test-key")] {
            let encoded = try controller.credential(provider: provider, apiKey: "  \(key)  ")
            XCTAssertEqual(
                try ProviderCredentialEnvelope.decode(encoded, expectedProvider: provider).accessToken,
                key
            )
        }
    }

    func testClaudeSessionQueriesSelectedOrganizationAndParsesWindows() async throws {
        let transport = ProviderTransportStub([
            .response(200, #"{"limits":[{"kind":"session","percent":25,"resets_at":"2026-09-08T12:00:00Z"},{"kind":"weekly_scoped","percent":50,"scope":{"model":{"display_name":"Sonnet"}}}]}"#),
        ])
        let credential = try ProviderCredentialEnvelope(
            provider: .claude,
            kind: .session,
            accessToken: "sessionKey=test-session-value; sessionKeyV3=test-session-v3",
            metadata: ["cookieFormat": "restrictedHeader", "organizationID": "org-test"]
        ).encoded()

        let result = try await ProviderQuotaClient(provider: .claude, transport: transport)
            .quotaResult(for: UUID(), credential: credential)

        XCTAssertEqual(result.snapshot.windows.count, 2)
        XCTAssertEqual(result.snapshot.windows[0].usedPercentage, 25)
        XCTAssertEqual(result.snapshot.windows[1].scope, "Sonnet")
        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://claude.ai/api/organizations/org-test/usage")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Cookie"),
            "sessionKey=test-session-value; sessionKeyV3=test-session-v3"
        )
    }

    func testCodexQueriesWhamWithAccountHeaderAndKeepsMissingMetricsNil() async throws {
        let transport = ProviderTransportStub([
            .response(200, #"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":20,"limit_window_seconds":18000,"reset_at":1780000000},"secondary_window":{"limit_window_seconds":604800}}}"#),
        ])
        let credential = try ProviderCredentialEnvelope(
            provider: .codex,
            kind: .oauth,
            accessToken: "test-access-token",
            accountID: "account-test"
        ).encoded()

        let result = try await ProviderQuotaClient(provider: .codex, transport: transport)
            .quotaResult(for: UUID(), credential: credential)

        XCTAssertEqual(result.snapshot.subscriptionPlan, .plus)
        XCTAssertEqual(result.snapshot.windows.map(\.name), ["5 小时额度", "每周额度"])
        XCTAssertEqual(result.snapshot.windows.map(\.period), [.fiveHour, .weekly])
        XCTAssertNil(result.snapshot.windows[1].usedPercentage)
        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "account-test")
    }

    func testCodexProKeepsWeeklyAccountQuotaAndSeparateSparkQuota() async throws {
        let transport = ProviderTransportStub([
            .response(200, #"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":77,"limit_window_seconds":604800,"reset_at":1780000000}},"additional_rate_limits":[{"limit_name":"GPT-5.3-Codex-Spark","metered_feature":"codex_bengalfox","rate_limit":{"primary_window":{"used_percent":12,"limit_window_seconds":18000,"reset_at":1779990000},"secondary_window":{"used_percent":1,"limit_window_seconds":604800,"reset_at":1780500000}}}]}"#),
        ])
        let credential = try ProviderCredentialEnvelope(
            provider: .codex,
            kind: .oauth,
            accessToken: "test-access-token"
        ).encoded()

        let result = try await ProviderQuotaClient(provider: .codex, transport: transport)
            .quotaResult(for: UUID(), credential: credential)

        XCTAssertEqual(result.snapshot.subscriptionPlan, .pro)
        XCTAssertEqual(result.snapshot.windows.map(\.period), [.weekly, .fiveHour, .weekly])
        XCTAssertEqual(result.snapshot.windows(for: .codex, surface: .summary).map(\.name), ["每周额度"])
        XCTAssertEqual(
            result.snapshot.windows(for: .codex, surface: .detail).map(\.scope),
            [nil, "GPT-5.3-Codex-Spark"]
        )
        XCTAssertEqual(result.snapshot.windows(for: .codex, surface: .detail).map(\.usedPercentage), [77, 12])
    }

    func testZaiQueriesInternationalCodingPlanAndParsesCounts() async throws {
        let transport = ProviderTransportStub([
            .response(200, #"{"success":true,"code":200,"data":{"limits":[{"type":"TOKENS_LIMIT","unit":3,"number":5,"usage":1000,"remaining":750,"percentage":25,"nextResetTime":1780000000000}]}}"#),
        ])
        let credential = try ProviderCredentialEnvelope(
            provider: .zai,
            kind: .apiKey,
            accessToken: "test-zai-key"
        ).encoded()

        let result = try await ProviderQuotaClient(provider: .zai, transport: transport)
            .quotaResult(for: UUID(), credential: credential)

        let window = try XCTUnwrap(result.snapshot.windows.first)
        XCTAssertEqual(window.name, "5 小时额度")
        XCTAssertEqual(window.period, .fiveHour)
        XCTAssertEqual(window.usedPercentage, 25)
        XCTAssertEqual(window.remainingCount, 750)
        XCTAssertEqual(window.totalCount, 1000)
        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.z.ai/api/monitor/usage/quota/limit")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testOpenCodeGoQueriesUsageAndParsesReportedWindows() async throws {
        let transport = ProviderTransportStub([
            .response(200, #"{"usage":{"rolling":{"status":"ok","percent":25,"resetsAt":"2026-09-09T10:00:00.000Z"},"weekly":{"status":"rate-limited","percent":60,"resetsAt":"2026-09-12T10:00:00Z"},"monthly":{"status":"ok","resetsAt":"2026-10-01T00:00:00Z"}}}"#),
        ])
        let credential = try ProviderCredentialEnvelope(
            provider: .openCodeGo,
            kind: .apiKey,
            accessToken: "test-opencode-key"
        ).encoded()

        let result = try await ProviderQuotaClient(provider: .openCodeGo, transport: transport)
            .quotaResult(for: UUID(), credential: credential)

        XCTAssertEqual(result.snapshot.windows.map(\.period), [.fiveHour, .weekly])
        XCTAssertEqual(result.snapshot.windows.map(\.usedPercentage), [25, 60])
        XCTAssertEqual(result.snapshot.windows.map(\.isExhausted), [false, true])
        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://opencode.ai/zen/go/v1/usage")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-opencode-key")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testOpenCodeGoDistinguishesMissingSubscriptionFromInvalidKey() async throws {
        let credential = try ProviderCredentialEnvelope(
            provider: .openCodeGo,
            kind: .apiKey,
            accessToken: "test-opencode-key"
        ).encoded()

        for (status, expected) in [(401, RefreshFailure.invalidCredential), (403, .subscriptionRequired)] {
            let transport = ProviderTransportStub([.response(status, "{}")])
            do {
                _ = try await ProviderQuotaClient(provider: .openCodeGo, transport: transport)
                    .quotaResult(for: UUID(), credential: credential)
                XCTFail("Expected HTTP \(status) failure")
            } catch {
                XCTAssertEqual(error as? RefreshFailure, expected)
            }
        }
    }

    func testOpenCodeGoReportsUnreadableAndEmptyUsageSeparately() async throws {
        let credential = try ProviderCredentialEnvelope(
            provider: .openCodeGo,
            kind: .apiKey,
            accessToken: "test-opencode-key"
        ).encoded()
        for (body, expected) in [
            ("not-json", RefreshFailure.unreadableResponse),
            (#"{"usage":{}}"#, .noQuotaWindows),
        ] {
            let transport = ProviderTransportStub([.response(200, body)])
            do {
                _ = try await ProviderQuotaClient(provider: .openCodeGo, transport: transport)
                    .quotaResult(for: UUID(), credential: credential)
                XCTFail("Expected \(expected)")
            } catch {
                XCTAssertEqual(error as? RefreshFailure, expected)
            }
        }
    }

    func testSuperGrokKeepsWindowWhenPercentageAndTimeAreMissing() async throws {
        let transport = ProviderTransportStub([.response(200, #"{"config":{}}"#)])
        let credential = try ProviderCredentialEnvelope(
            provider: .superGrok,
            kind: .oauth,
            accessToken: "test-grok-token"
        ).encoded()

        let result = try await ProviderQuotaClient(provider: .superGrok, transport: transport)
            .quotaResult(for: UUID(), credential: credential)

        let window = try XCTUnwrap(result.snapshot.windows.first)
        XCTAssertEqual(window.name, "SuperGrok 套餐额度")
        XCTAssertNil(window.usedPercentage)
        XCTAssertNil(window.resetsAt)
        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://cli-chat-proxy.grok.com/v1/billing?format=credits")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-xai-token-auth"), "xai-grok-cli")
    }

    func testProviderHTTPFailuresRemainInvalidCredentialAndRateLimited() async throws {
        let credential = try ProviderCredentialEnvelope(
            provider: .zai,
            kind: .apiKey,
            accessToken: "test-zai-key"
        ).encoded()
        for (status, expected) in [(401, RefreshFailure.invalidCredential), (429, .rateLimited)] {
            let transport = ProviderTransportStub([.response(status, "{}")])
            do {
                _ = try await ProviderQuotaClient(provider: .zai, transport: transport)
                    .quotaResult(for: UUID(), credential: credential)
                XCTFail("Expected HTTP \(status) failure")
            } catch {
                XCTAssertEqual(error as? RefreshFailure, expected)
            }
        }
    }

    func testCodexDeviceLoginBeginsAndReportsPendingWithoutInventingCallback() async throws {
        let transport = ProviderTransportStub([
            .response(200, #"{"user_code":"ABCD-EFGH","device_auth_id":"device-test","interval":2}"#),
            .response(403, "{}"),
        ])
        let controller = ProviderAuthenticationController(transport: transport)

        let session = try await controller.beginLogin(provider: .codex)
        let progress = try await controller.continueLogin(session)

        XCTAssertEqual(session.authorizationURL.absoluteString, "https://auth.openai.com/codex/device")
        XCTAssertNil(session.callbackURL)
        XCTAssertEqual(progress, .pending(retryAfter: 2))
    }

    func testSuperGrokDeviceLoginReturnsOAuthCredential() async throws {
        let transport = ProviderTransportStub([
            .response(200, #"{"user_code":"GROK-CODE","device_code":"device-test","verification_uri":"https://auth.x.ai/activate","verification_uri_complete":"https://auth.x.ai/activate?code=GROK-CODE","interval":3,"expires_in":900}"#),
            .response(200, #"{"access_token":"test-new-access","refresh_token":"test-refresh","expires_in":3600}"#),
        ])
        let controller = ProviderAuthenticationController(transport: transport, now: { Date(timeIntervalSince1970: 100) })

        let session = try await controller.beginLogin(provider: .superGrok)
        let progress = try await controller.continueLogin(session)

        guard case .completed(let encoded) = progress else { return XCTFail("Expected completed login") }
        let credential = try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .superGrok)
        XCTAssertEqual(credential.accessToken, "test-new-access")
        XCTAssertEqual(credential.refreshToken, "test-refresh")
        XCTAssertEqual(credential.expiresAt, Date(timeIntervalSince1970: 3_700))
    }

    func testCodexRefreshExposesRotatedCredentialBeforeQuery() async throws {
        let transport = ProviderTransportStub([
            .response(200, #"{"access_token":"test-rotated-access","refresh_token":"test-rotated-refresh","expires_in":7200}"#),
        ])
        let old = try ProviderCredentialEnvelope(
            provider: .codex,
            kind: .oauth,
            accessToken: "test-old-access",
            refreshToken: "test-old-refresh",
            expiresAt: Date(timeIntervalSince1970: 90)
        ).encoded()
        let controller = ProviderAuthenticationController(
            transport: transport,
            now: { Date(timeIntervalSince1970: 100) }
        )

        let refreshed = try await controller.refreshCredentialIfNeeded(provider: .codex, credential: old)

        XCTAssertTrue(refreshed.changed)
        let credential = try ProviderCredentialEnvelope.decode(refreshed.credential, expectedProvider: .codex)
        XCTAssertEqual(credential.accessToken, "test-rotated-access")
        XCTAssertEqual(credential.refreshToken, "test-rotated-refresh")
    }
}

private actor ProviderTransportStub: ProviderTransport {
    enum Outcome: Sendable {
        case response(Int, String)
        case failure(URLError.Code)
        case binary(Data)
    }

    private var outcomes: [Outcome]
    private var receivedRequests: [URLRequest] = []

    init(_ outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        receivedRequests.append(request)
        guard !outcomes.isEmpty else { throw URLError(.badServerResponse) }
        switch outcomes.removeFirst() {
        case .binary(let data):
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                         headerFields: ["Content-Type": "application/grpc-web+proto", "grpc-status": "0"])!)
        case .failure(let code): throw URLError(code)
        case .response(let status, let body):
            return (
                Data(body.utf8),
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            )
        }
    }

    func requests() -> [URLRequest] { receivedRequests }
}
