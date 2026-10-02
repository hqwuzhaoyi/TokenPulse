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

    func testClaudeSessionQueriesSelectedOrganizationAndParsesFableWindow() async throws {
        let transport = ProviderTransportStub([
            .response(200, #"""
            {"limits":[
              {"kind":"session","percent":25,"resets_at":"2026-09-08T12:00:00Z"},
              {"kind":"weekly_all","percent":40,"resets_at":"2026-09-14T00:00:00Z"},
              {"kind":"weekly_scoped","percent":50,"resets_at":null,"scope":{"model":{"display_name":"Fable"}}}
            ]}
            """#),
        ])
        let credential = try ProviderCredentialEnvelope(
            provider: .claude,
            kind: .session,
            accessToken: "sessionKey=test-session-value; sessionKeyV3=test-session-v3",
            metadata: ["cookieFormat": "restrictedHeader", "organizationID": "org-test"]
        ).encoded()

        let result = try await ProviderQuotaClient(provider: .claude, transport: transport)
            .quotaResult(for: UUID(), credential: credential)

        XCTAssertEqual(result.snapshot.windows.count, 3)
        XCTAssertEqual(result.snapshot.windows[0].usedPercentage, 25)
        XCTAssertEqual(result.snapshot.windows.map(\.period), [.fiveHour, .weekly, .weekly])
        XCTAssertEqual(result.snapshot.windows.map(\.displayName), ["5 小时额度", "每周额度", "Fable 每周额度"])
        XCTAssertNil(result.snapshot.windows[2].resetsAt)
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

final class RegionalProviderTests: XCTestCase {
    private let zhipuResponse = #"{"success":true,"code":200,"data":{"level":"lite","limits":[{"type":"CREDIT_LIMIT","unit":3,"number":5,"usage":2000,"remaining":2000},{"type":"CREDIT_LIMIT","unit":6,"number":1,"usage":10000,"remaining":2500,"nextResetTime":1789373585999}]}}"#
    private let miniMaxResponse = #"{"base_resp":{"status_code":0},"model_remains":[{"model_name":"general","current_interval_status":1,"current_interval_total_count":"1000","current_interval_usage_count":"960","current_interval_remaining_percent":"96","start_time":1760000000000,"end_time":1760018000000,"current_weekly_status":1,"current_weekly_total_count":4000,"current_weekly_usage_count":3000,"weekly_end_time":1760600000000}]}"#

    func testZhipuQueriesOnlyMainlandWithProviderBoundKeyAndReportedReset() async throws {
        let transport = ProviderTransportStub([.response(200, zhipuResponse)])
        let accountID = UUID()
        let collectedAt = Date(timeIntervalSince1970: 500)
        let credential = try ProviderAuthenticationController().credential(provider: .zhipu, apiKey: " mainland-fixture ")
        let result = try await ProviderQuotaClient(provider: .zhipu, transport: transport, now: { collectedAt })
            .quotaResult(for: accountID, credential: credential)
        let requests = await transport.requests()
        XCTAssertEqual(requests.map(\.url?.absoluteString), ["https://open.bigmodel.cn/api/monitor/usage/quota/limit"])
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer mainland-fixture")
        XCTAssertEqual(requests.first?.httpMethod, "GET")
        XCTAssertEqual(requests.first?.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(result.snapshot.accountID, accountID)
        XCTAssertEqual(result.snapshot.collectedAt, collectedAt)
        let short = try XCTUnwrap(result.snapshot.windows.first { $0.period == .fiveHour })
        let weekly = try XCTUnwrap(result.snapshot.windows.first { $0.period == .weekly })
        XCTAssertEqual(short.usedPercentage, 0)
        XCTAssertNil(short.resetsAt)
        XCTAssertEqual(weekly.usedPercentage, 75)
        XCTAssertEqual(weekly.resetsAt, Date(timeIntervalSince1970: 1789373585.999))
        XCTAssertTrue(result.snapshot.windows.allSatisfy { $0.id.hasPrefix("zhipu.") })
    }

    func testRegionMismatchesFailBeforeSendingAnyCredential() async throws {
        for (source, destination) in [(Provider.zai, Provider.zhipu), (.zhipu, .zai), (.miniMaxInternational, .zhipu)] {
            let credential = try ProviderAuthenticationController().credential(provider: source, apiKey: "fixture")
            let transport = ProviderTransportStub([])
            do {
                _ = try await ProviderQuotaClient(provider: destination, transport: transport)
                    .quota(for: UUID(), credential: credential)
                XCTFail("Region mismatch must fail")
            } catch { XCTAssertEqual(error as? ProviderIntegrationError, .invalidCredentialData) }
            let requests = await transport.requests()
            XCTAssertTrue(requests.isEmpty)
        }
        XCTAssertEqual(try ProviderAuthenticationController().credential(provider: .miniMaxChina, apiKey: " cn-fixture "), "cn-fixture")
        XCTAssertThrowsError(try ProviderCredentialEnvelope.decode("cn-fixture", expectedProvider: .miniMaxInternational))
    }

    func testZhipuEnvelopeFailuresKeepAuthenticationAndSubscriptionDistinct() async throws {
        let cases: [(String, RefreshFailure)] = [
            (#"{"success":false,"code":1000,"msg":"身份验证失败。"}"#, .invalidCredential),
            (#"{"success":false,"code":1001}"#, .invalidCredential),
            (#"{"success":false,"code":401}"#, .invalidCredential),
            (#"{"success":false,"code":429}"#, .rateLimited),
            (#"{"success":false,"code":500,"msg":"当前用户不存在coding plan"}"#, .subscriptionRequired),
            (#"{"success":false,"code":500,"msg":"service failure"}"#, .server),
            (#"{"success":true,"code":true,"data":{"limits":[]}}"#, .server),
        ]
        let credential = try ProviderAuthenticationController().credential(provider: .zhipu, apiKey: "fixture")
        for (body, expected) in cases {
            let transport = ProviderTransportStub([.response(200, body)])
            do {
                _ = try await ProviderQuotaClient(provider: .zhipu, transport: transport).quota(for: UUID(), credential: credential)
                XCTFail("Expected refusal")
            } catch { XCTAssertEqual(error as? RefreshFailure, expected) }
        }
    }

    func testZhipuRejectsUnknownOrMalformedDurationsAndPreservesMissingMetrics() {
        let limits: [[String: Any]] = [
            ["type": "CREDIT_LIMIT", "unit": 3, "number": 5],
            ["type": "CREDIT_LIMIT", "unit": 77, "number": 1, "percentage": 10],
            ["type": "CREDIT_LIMIT", "unit": 3, "number": 1.5, "percentage": 10],
            ["type": "CREDIT_LIMIT", "unit": true, "number": 5, "percentage": 10],
            ["type": "CREDIT_LIMIT", "unit": 3, "number": "inf", "percentage": 10],
            ["type": "CREDIT_LIMIT", "unit": 6, "number": 1, "usage": "NaN", "remaining": true, "percentage": "inf", "nextResetTime": 0],
            ["type": "UNKNOWN", "unit": 3, "number": 5, "percentage": 10],
        ]
        let windows = ZaiProviderClient.windows(limits, provider: .zhipu)
        XCTAssertEqual(windows.count, 2)
        XCTAssertTrue(windows.allSatisfy { $0.usedPercentage == nil && $0.remainingCount == nil && $0.totalCount == nil && $0.resetsAt == nil })
    }

    func testZhipuCountsTakePriorityAndMCPMarkerKeepsMonthlyIdentity() {
        let windows = ZaiProviderClient.windows([
            ["type": "CREDIT_LIMIT", "unit": 3, "number": 5, "usage": 1000, "remaining": 247, "percentage": 7],
            ["type": "CREDIT_LIMIT", "unit": 6, "number": 1, "usage": 1000, "remaining": 247, "currentValue": 600],
            ["type": "TIME_LIMIT", "unit": 5, "number": 1, "percentage": 10],
        ], provider: .zhipu)
        XCTAssertEqual(windows[0].usedPercentage ?? -1, 75.3, accuracy: 0.000001)
        XCTAssertEqual(windows[1].usedPercentage, 60)
        XCTAssertEqual(windows[2].period, .monthly)
        XCTAssertEqual(windows[2].scope, "MCP")
    }

    func testMiniMaxInternationalQueriesItsHostAndParsesCurrentAndLegacyShapes() async throws {
        for body in [miniMaxResponse, #"{"base_resp":{"status_code":"0"},"data":{"model_remains":[{"model_name":"general","current_weekly_total_count":"4000","current_weekly_usage_count":"3000"}]}}"#] {
            let transport = ProviderTransportStub([.response(200, body)])
            let credential = try ProviderAuthenticationController().credential(provider: .miniMaxInternational, apiKey: " international-fixture ")
            let result = try await ProviderQuotaClient(provider: .miniMaxInternational, transport: transport)
                .quotaResult(for: UUID(), credential: credential)
            let weekly = try XCTUnwrap(result.snapshot.windows.first { $0.period == .weekly })
            XCTAssertEqual(weekly.usedPercentage, 25)
            XCTAssertEqual(weekly.remainingCount, 3000)
            let requests = await transport.requests()
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests.first?.url?.absoluteString, "https://api.minimax.io/v1/token_plan/remains")
            XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer international-fixture")
            XCTAssertEqual(requests.first?.cachePolicy, .reloadIgnoringLocalCacheData)
        }
    }

    func testMiniMaxInternationalFallsBackOnlyFor404AndKeepsSameHost() async throws {
        let transport = ProviderTransportStub([.response(404, ""), .response(200, miniMaxResponse)])
        let credential = try ProviderAuthenticationController().credential(provider: .miniMaxInternational, apiKey: "fixture")
        let snapshot = try await ProviderQuotaClient(provider: .miniMaxInternational, transport: transport)
            .quota(for: UUID(), credential: credential)
        XCTAssertEqual(snapshot.windows.first { $0.period == .fiveHour }?.usedPercentage, 4)
        let requests = await transport.requests()
        XCTAssertEqual(requests.map(\.url?.absoluteString), ["https://api.minimax.io/v1/token_plan/remains", "https://api.minimax.io/v1/api/openplatform/coding_plan/remains"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture" })
    }

    func testMiniMaxInternationalNeverFallsBackForOtherFailures() async throws {
        let cases: [(ProviderTransportStub.Outcome, RefreshFailure)] = [
            (.response(401, ""), .invalidCredential), (.response(403, ""), .invalidCredential),
            (.response(429, ""), .rateLimited), (.response(500, ""), .server),
            (.failure(.notConnectedToInternet), .network),
            (.response(200, "bad json"), .unreadableResponse),
            (.response(200, #"{"base_resp":{"status_code":1004}}"#), .invalidCredential),
            (.response(200, #"{"base_resp":{"status_code":2045}}"#), .rateLimited),
            (.response(200, #"{"base_resp":{"status_code":true}}"#), .unreadableResponse),
            (.response(200, #"{"base_resp":{"status_code":0}}"#), .noQuotaWindows),
        ]
        let credential = try ProviderAuthenticationController().credential(provider: .miniMaxInternational, apiKey: "fixture")
        for (outcome, expected) in cases {
            let transport = ProviderTransportStub([outcome, .response(200, miniMaxResponse)])
            do {
                _ = try await ProviderQuotaClient(provider: .miniMaxInternational, transport: transport).quota(for: UUID(), credential: credential)
                XCTFail("Expected original failure")
            } catch { XCTAssertEqual(error as? RefreshFailure, expected) }
            let requests = await transport.requests()
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testMiniMaxInternationalCancellationDoesNotMakeFallbackRequest() async throws {
        let transport = ProviderTransportStub([.failure(.cancelled)])
        let credential = try ProviderAuthenticationController().credential(provider: .miniMaxInternational, apiKey: "fixture")
        do {
            _ = try await ProviderQuotaClient(provider: .miniMaxInternational, transport: transport).quota(for: UUID(), credential: credential)
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 1)
    }

    func testMiniMaxInternationalDropsOnlyExplicitlyUnallocatedPoolsAndNeverInventsMissingMetrics() throws {
        let data = Data(#"{"base_resp":{"status_code":0},"model_remains":[{"model_name":"general","current_interval_status":1,"current_interval_remaining_percent":"NaN","current_interval_total_count":true,"current_weekly_status":3,"current_weekly_total_count":0,"current_weekly_remaining_percent":100},{"model_name":"video","current_interval_status":3,"current_interval_total_count":0,"current_interval_remaining_percent":100,"current_weekly_status":3,"current_weekly_total_count":0,"current_weekly_remaining_percent":100},{"model_name":"audio","current_weekly_status":3,"current_weekly_total_count":0}] }"#.utf8)
        let snapshot = try MiniMaxQuotaClient.decode(data, accountID: UUID(), collectedAt: Date(), discardUnallocatedPools: true)
        XCTAssertEqual(snapshot.windows.count, 2)
        let general = try XCTUnwrap(snapshot.windows.first { $0.id == "general.interval" })
        XCTAssertNil(general.usedPercentage)
        XCTAssertNil(general.totalCount)
        XCTAssertNil(general.resetsAt)
        XCTAssertEqual(general.period, .other)
        XCTAssertTrue(snapshot.windows.contains { $0.id == "audio.weekly" })
        XCTAssertFalse(snapshot.windows.contains { $0.id.hasPrefix("video.") || $0.id == "general.weekly" })
    }

    func testRegionalWidgetMetricsRetainAllReturnedWindowsAndCollectionTime() throws {
        for provider in [Provider.zhipu, .miniMaxInternational] {
            let account = SubscriptionAccount(name: "fixture", provider: provider)
            let snapshot = DemoMode.snapshot(accountID: account.id, provider: provider, now: Date(timeIntervalSince1970: 100))
            let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows, collectedAt: snapshot.collectedAt, lastFailure: nil)
            XCTAssertEqual(widget.displayMetrics.map(\.window), snapshot.windows.map(Optional.some))
            XCTAssertEqual(widget.collectedAt, snapshot.collectedAt)
            XCTAssertEqual(widget.needsUpdate(at: Date(timeIntervalSince1970: 100)), false)
            XCTAssertEqual(widget.needsUpdate(at: .distantFuture), true)
            XCTAssertEqual(provider.iconAssetName, provider == .zhipu ? "ProviderZai" : "ProviderMiniMax")
        }
    }
}

extension RegionalProviderTests {
    @MainActor
    func testRegionalAccountsRestoreKeepCredentialsAndCacheIsolatedThenDeleteOnlyOneAccount() async throws {
        let suite = "com.tokenpulse.tests.regional.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = RegionalTestCredentialStore()
        let transport = RegionalTestTransport([zhipuResponse, zhipuResponse, zhipuResponse, miniMaxResponse, miniMaxResponse])
        let monitor = QuotaMonitor(accountStore: LocalAccountStateStore(suiteName: suite), credentialStore: credentials,
                                   quotaClient: MiniMaxQuotaClient(transport: transport),
                                   configurationStore: LocalAccountConfigurationStore(suiteName: suite),
                                   providerClient: { provider in
            if provider == .miniMaxChina { return MiniMaxQuotaClient(transport: transport) }
            return ProviderQuotaClient(provider: provider, transport: transport)
        })
        await monitor.start(refresh: false)
        let providers: [Provider] = [.zhipu, .zhipu, .zai, .miniMaxInternational, .miniMaxChina]
        for (index, provider) in providers.enumerated() {
            let credential = try ProviderAuthenticationController().credential(provider: provider, apiKey: "fixture-\(index)")
            await monitor.addAccount(name: "fixture-\(index)", credential: credential, provider: provider)
        }
        XCTAssertEqual(monitor.states.map(\.account.provider), providers)
        XCTAssertTrue(monitor.states.allSatisfy { $0.snapshot?.accountID == $0.id && $0.lastFailure == nil })
        let requests = await transport.requests()
        XCTAssertEqual(requests.map(\.url?.host), ["open.bigmodel.cn", "open.bigmodel.cn", "api.z.ai", "api.minimax.io", "api.minimaxi.com"])
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") }, providers.indices.map { "Bearer fixture-\($0)" })
        let original = try XCTUnwrap(monitor.states.first)
        // The stub now rejects every request. A failed refresh must retain its
        // previous collection time and leave all other account snapshots alone.
        let otherStates = Array(monitor.states.dropFirst())
        await monitor.refresh(accountID: original.id)
        XCTAssertEqual(monitor.states.first?.snapshot, original.snapshot)
        XCTAssertEqual(monitor.states.first?.lastFailure, .invalidCredential)
        XCTAssertEqual(Array(monitor.states.dropFirst()), otherStates)
        let restored = QuotaMonitor(accountStore: LocalAccountStateStore(suiteName: suite), credentialStore: credentials,
                                    quotaClient: MiniMaxQuotaClient(transport: transport),
                                    configurationStore: LocalAccountConfigurationStore(suiteName: suite))
        await restored.start(refresh: false)
        XCTAssertEqual(restored.states, monitor.states)
        XCTAssertEqual(restored.configurations.map(\.account.provider), providers)
        let firstCredential = await credentials.credential(for: original.id)
        XCTAssertEqual(try ProviderCredentialEnvelope.decode(try XCTUnwrap(firstCredential), expectedProvider: .zhipu).accessToken, "fixture-0")
        let didDelete = await restored.deleteAccount(accountID: original.id)
        XCTAssertTrue(didDelete)
        let deletedCredential = await credentials.credential(for: original.id)
        XCTAssertNil(deletedCredential)
        let secondCredential = await credentials.credential(for: otherStates[0].id)
        XCTAssertNotNil(secondCredential)
        XCTAssertEqual(restored.states.map(\.id), otherStates.map(\.id))
        let persistedConfigurations = try await LocalAccountConfigurationStore(suiteName: suite).load()
        XCTAssertNotNil(persistedConfigurations.first { $0.id == original.id && $0.deletedAt != nil })
    }

    @MainActor
    func testReceivingRegionalConfigurationCanRefreshWithoutPhoneMonitor() async throws {
        for provider in [Provider.zhipu, .miniMaxInternational] {
            let phoneSuite = "com.tokenpulse.tests.phone.\(UUID().uuidString)"
            let watchSuite = "com.tokenpulse.tests.watch.\(UUID().uuidString)"
            defer {
                UserDefaults(suiteName: phoneSuite)?.removePersistentDomain(forName: phoneSuite)
                UserDefaults(suiteName: watchSuite)?.removePersistentDomain(forName: watchSuite)
            }
            let credentials = RegionalTestCredentialStore()
            let body = provider == .zhipu ? zhipuResponse : miniMaxResponse
            let phoneTransport = RegionalTestTransport([body])
            var phone: QuotaMonitor? = QuotaMonitor(accountStore: LocalAccountStateStore(suiteName: phoneSuite), credentialStore: credentials,
                quotaClient: ProviderQuotaClient(provider: provider, transport: phoneTransport),
                configurationStore: LocalAccountConfigurationStore(suiteName: phoneSuite))
            await phone?.start(refresh: false)
            await phone?.addAccount(name: "fixture", credential: try ProviderAuthenticationController().credential(provider: provider, apiKey: "fixture"), provider: provider)
            let configurations = try XCTUnwrap(phone?.configurations)
            let states = try XCTUnwrap(phone?.states)
            phone = nil
            let watchTransport = RegionalTestTransport([body])
            let collectedAt = Date(timeIntervalSince1970: 999)
            let watch = QuotaMonitor(accountStore: LocalAccountStateStore(suiteName: watchSuite), credentialStore: credentials,
                quotaClient: ProviderQuotaClient(provider: provider, transport: watchTransport, now: { collectedAt }),
                configurationStore: LocalAccountConfigurationStore(suiteName: watchSuite))
            await watch.start(refresh: false)
            await watch.mergeSynchronized(configurations: configurations, states: states)
            await watch.refreshAll()
            let requests = await watchTransport.requests()
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests.first?.url?.host, provider == .zhipu ? "open.bigmodel.cn" : "api.minimax.io")
            XCTAssertEqual(watch.states.first?.snapshot?.collectedAt, collectedAt)
            XCTAssertNil(watch.states.first?.lastFailure)
        }
    }

    func testRegionalNotificationsDoNotConvertMissingUsageOrDueTimeIntoConfirmedRecovery() throws {
        let accountID = UUID()
        let now = Date(timeIntervalSince1970: 100)
        let unknown = QuotaWindow(id: "unknown", name: "未知额度", scope: nil, period: .weekly,
                                  usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: now.addingTimeInterval(50))
        let used = QuotaWindow(id: "used", name: "每周额度", scope: nil, period: .weekly,
                               usedPercentage: 95, remainingCount: 5, totalCount: 100, resetsAt: now.addingTimeInterval(50))
        let planner = NotificationPlanner()
        let snapshot = QuotaSnapshot(accountID: accountID, windows: [unknown, used], collectedAt: now)
        let first = planner.planSuccessfulRefresh(accountID: accountID, accountName: "fixture", previousSnapshot: nil,
                                             newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: now)
        let repeated = planner.planSuccessfulRefresh(accountID: accountID, accountName: "fixture", previousSnapshot: snapshot,
                                                newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: first.ledger, now: now.addingTimeInterval(100))
        let delivered = first.operations.compactMap { operation -> ReminderNotification? in
            if case let .deliver(notification) = operation { return notification }; return nil
        }
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered.first?.kind, .quotaAlert)
        XCTAssertFalse(delivered.first?.body.contains("未知额度") ?? true)
        XCTAssertFalse(repeated.operations.contains { operation in
            if case let .deliver(notification) = operation { return notification.kind == .confirmedReset || notification.kind == .quotaAlert }; return false
        })
    }
}

private actor RegionalTestCredentialStore: CredentialStoring {
    private var items: [UUID: String] = [:]
    func save(_ credential: String, for accountID: UUID) { items[accountID] = credential }
    func credential(for accountID: UUID) -> String? { items[accountID] }
    func deleteCredential(for accountID: UUID) { items[accountID] = nil }
}

private actor RegionalTestTransport: ProviderTransport, HTTPTransport {
    private var bodies: [String]
    private var receivedRequests: [URLRequest] = []
    init(_ bodies: [String]) { self.bodies = bodies }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        receivedRequests.append(request)
        let status = bodies.isEmpty ? 401 : 200
        let body = bodies.isEmpty ? "" : bodies.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    func requests() -> [URLRequest] { receivedRequests }
}
