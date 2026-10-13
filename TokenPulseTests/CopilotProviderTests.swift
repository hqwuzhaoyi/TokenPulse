import Foundation
import XCTest
@testable import TokenPulse

final class CopilotProviderTests: XCTestCase {
    func testUnusedPercentageOnlyWindowDoesNotBecomeAnUnissuedPool() throws {
        let root = try ProviderHTTP.json(Data(#"{"quota_snapshots":{"chat":{"percent_remaining":100}}}"#.utf8))
        let window = try XCTUnwrap(CopilotProviderClient.windows(root).first)
        XCTAssertEqual(window.usedPercentage, 0)
        XCTAssertNil(window.totalCount)
        XCTAssertNil(window.remainingCount)
    }

    func testNumericFlagsCannotBecomeUnlimitedOrPaidOverage() throws {
        for flag in ["has_quota", "unlimited", "overage_permitted"] {
            let data = Data("{\"quota_snapshots\":{\"chat\":{\"percent_remaining\":50,\"\(flag)\":1}}}".utf8)
            XCTAssertTrue(CopilotProviderClient.windows(try ProviderHTTP.json(data)).isEmpty, flag)
        }
        let valid = try ProviderHTTP.json(Data(#"{"quota_snapshots":{"chat":{"unlimited":true}}}"#.utf8))
        XCTAssertEqual(CopilotProviderClient.windows(valid).first?.isUnlimited, true)
    }

    private let now = Date(timeIntervalSince1970: 100)
    private let deviceReply = #"{"user_code":"TEST-CODE","device_code":"device-fixture","verification_uri":"https://github.com/login/device","verification_uri_complete":"https://github.com/login/device?user_code=TEST-CODE","expires_in":900,"interval":5}"#
    private let tokenReply = #"{"access_token":"oauth-fixture","token_type":"bearer","scope":"read:user"}"#
    private let quotaReply = #"{"copilot_plan":"free","quota_reset_date_utc":"2026-11-01T00:00:00.000Z","quota_snapshots":{"premium_interactions":{"has_quota":true,"entitlement":50,"remaining":40,"percent_remaining":80},"chat":{"has_quota":true,"entitlement":200,"remaining":100,"percent_remaining":50},"completions":{"has_quota":true,"entitlement":2000,"remaining":1600,"percent_remaining":80}}}"#

    func testDeviceRequestHasNarrowScopeAndNoCodeInBrowserURL() async throws {
        let transport = CopilotTransportStub([(200, deviceReply), (200, #"{"error":"authorization_pending"}"#), (200, tokenReply)])
        let controller = ProviderAuthenticationController(transport: transport, now: { Date(timeIntervalSince1970: 100) })
        XCTAssertEqual(controller.loginConfiguration(for: .copilot).method, .deviceCode)
        let session = try await controller.beginLogin(provider: .copilot)
        XCTAssertEqual(session.authorizationURL.absoluteString, "https://github.com/login/device")
        XCTAssertEqual(session.expiresAt, now.addingTimeInterval(900))
        let pending = try await controller.continueLogin(session)
        XCTAssertEqual(pending, .pending(retryAfter: 5))
        guard case .completed(let encoded) = try await controller.continueLogin(session) else { return XCTFail("Expected authorization") }
        let credential = try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .copilot)
        XCTAssertNil(credential.refreshToken)
        XCTAssertNil(credential.expiresAt)
        let requests = await transport.requests
        XCTAssertEqual(requests[0].url?.absoluteString, "https://github.com/login/device/code")
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Accept"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(requests[0].httpBody)) as? [String: String])
        XCTAssertEqual(body, ["client_id": "Iv1.b507a08c87ecfe98", "scope": "read:user"])
        let pollBody = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(requests[1].httpBody)) as? [String: String])
        XCTAssertEqual(pollBody, ["client_id": "Iv1.b507a08c87ecfe98", "device_code": "device-fixture", "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
        XCTAssertEqual(requests[1].url?.absoluteString, "https://github.com/login/oauth/access_token")
    }

    @MainActor
    func testModelRetainsSlowDownForFollowingPollsAndCompletesOnce() async throws {
        let transport = CopilotTransportStub([(200, deviceReply), (200, #"{"error":"slow_down"}"#),
                                             (200, #"{"error":"authorization_pending"}"#),
                                             (200, #"{"error":"slow_down"}"#), (200, tokenReply)])
        let sleeps = CopilotSleepRecorder()
        let model = DeviceLoginModel(controller: ProviderAuthenticationController(transport: transport), sleep: { await sleeps.record($0) })
        var completions = 0
        await model.authorize(provider: .copilot) { _ in completions += 1 }
        let intervals = await sleeps.intervals
        XCTAssertEqual(intervals, [5, 10, 10, 15])
        await model.authorize(provider: .copilot) { _ in completions += 1 }
        XCTAssertEqual(completions, 1)
        XCTAssertNil(model.message)
    }

    @MainActor
    func testCancellationDoesNotPublishCredentialAndDeniedFlowStartsFresh() async throws {
        let transport = CopilotTransportStub([(200, deviceReply), (200, #"{"error":"access_denied"}"#), (200, deviceReply), (200, tokenReply)])
        let cancelled = DeviceLoginModel(controller: ProviderAuthenticationController(transport: transport), sleep: { _ in throw CancellationError() })
        await cancelled.authorize(provider: .copilot) { _ in XCTFail("Cancelled authorization must not complete") }
        XCTAssertNil(cancelled.message)
        let before = await transport.requests
        XCTAssertEqual(before.count, 1, "Cancellation stops before sending the device code")
        // The cancelled model retains its session for an app background/foreground transition.
        await cancelled.authorize(provider: .copilot) { _ in XCTFail("Still cancelled") }
        // A separate attempt needs its own device response.
        let freshTransport = CopilotTransportStub([(200, deviceReply), (200, #"{"error":"access_denied"}"#), (200, deviceReply), (200, tokenReply)])
        let fresh = DeviceLoginModel(controller: ProviderAuthenticationController(transport: freshTransport), sleep: { _ in })
        await fresh.authorize(provider: .copilot) { _ in XCTFail("Denied authorization must not complete") }
        XCTAssertNil(fresh.session)
        XCTAssertNotNil(fresh.message)
        var completed = false
        await fresh.authorize(provider: .copilot) { _ in completed = true }
        XCTAssertTrue(completed)
    }

    @MainActor
    func testLocalizedDeviceCodeExpiryAndDenialRecoverWithoutChangingRequestIdentity() async throws {
        for language in ["zh-Hans", "en"] {
            for denied in [false, true] {
                try await L10n.withLanguage(language) {
                    let cancelledTransport = CopilotTransportStub([(200, deviceReply)])
                    let cancelled = DeviceLoginModel(controller: ProviderAuthenticationController(transport: cancelledTransport),
                                                     sleep: { _ in throw CancellationError() })
                    await cancelled.authorize(provider: .copilot) { _ in XCTFail("Cancelled sign-in must not save a credential") }
                    XCTAssertNil(cancelled.message)
                    XCTAssertEqual(cancelled.session?.userCode, "TEST-CODE")
                    let cancelledRequests = await cancelledTransport.requests
                    XCTAssertEqual(cancelledRequests.count, 1)
                    let failure = denied ? #"{"error":"access_denied"}"# : #"{"error":"expired_token"}"#
                    let transport = CopilotTransportStub([(200, deviceReply), (200, failure), (200, deviceReply), (200, tokenReply)])
                    let model = DeviceLoginModel(controller: ProviderAuthenticationController(transport: transport), sleep: { _ in })
                    var saved: [String] = []
                    await model.authorize(provider: .copilot) { saved.append($0) }
                    let expected: String
                    if language == "en" {
                        expected = denied ? "GitHub authorization was denied or is no longer valid. Please start again."
                            : "Authorization has expired. Please start again."
                    } else {
                        expected = denied ? "GitHub 授权已拒绝或失效，请重新开始。" : "授权已过期，请重新开始。"
                    }
                    XCTAssertEqual(model.message, expected)
                    XCTAssertNil(model.session)
                    XCTAssertTrue(saved.isEmpty)
                    await model.authorize(provider: .copilot) { saved.append($0) }
                    XCTAssertEqual(saved.count, 1)
                    XCTAssertNil(model.message)
                    XCTAssertEqual(model.session?.userCode, "TEST-CODE")
                    XCTAssertEqual(model.session?.authorizationURL.absoluteString, "https://github.com/login/device")
                    let credential = try ProviderCredentialEnvelope.decode(try XCTUnwrap(saved.first), expectedProvider: .copilot)
                    XCTAssertEqual(credential.accessToken, "oauth-fixture")
                    let requests = await transport.requests
                    XCTAssertEqual(requests.count, 4)
                    let bodies = try requests.map { request in
                        try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? NSDictionary)
                    }
                    let deviceBody: NSDictionary = ["client_id": "Iv1.b507a08c87ecfe98", "scope": "read:user"]
                    let pollBody: NSDictionary = ["client_id": "Iv1.b507a08c87ecfe98", "device_code": "device-fixture",
                                                  "grant_type": "urn:ietf:params:oauth:grant-type:device_code"]
                    // JSON object key order is unspecified; compare every key and value instead of encoded bytes.
                    XCTAssertEqual(bodies, [deviceBody, pollBody, deviceBody, pollBody])
                    XCTAssertEqual(requests.map(\.url?.absoluteString), [
                        "https://github.com/login/device/code", "https://github.com/login/oauth/access_token",
                        "https://github.com/login/device/code", "https://github.com/login/oauth/access_token",
                    ])
                    for request in requests {
                        XCTAssertEqual(request.httpMethod, "POST")
                        XCTAssertEqual(request.allHTTPHeaderFields, ["Accept": "application/json", "Content-Type": "application/json"])
                    }
                    XCTAssertEqual(model.session?.provider, .copilot)
                    XCTAssertEqual(model.session?.deviceCode, "device-fixture")
                    XCTAssertEqual(credential.metadata["client_id"], "Iv1.b507a08c87ecfe98")
                    XCTAssertEqual(credential.metadata["scope"], "read:user")
                }
            }
        }
    }

    func testExpiryAndVerificationURLValidationRejectBeforePolling() async throws {
        let transport = CopilotTransportStub([(200, deviceReply)])
        let session = try await ProviderAuthenticationController(transport: transport, now: { Date(timeIntervalSince1970: 100) }).beginLogin(provider: .copilot)
        do {
            _ = try await ProviderAuthenticationController(transport: transport, now: { Date(timeIntervalSince1970: 1000) }).continueLogin(session)
            XCTFail("Expired code")
        } catch { XCTAssertEqual(error as? ProviderIntegrationError, .loginExpired) }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        for url in ["https://github.com.evil.example/login/device", "http://github.com/login/device", "https://github.com/login/device?user_code=OTHER"] {
            let body = deviceReply.replacingOccurrences(of: "https://github.com/login/device\"", with: "\(url)\"")
            do {
                _ = try await ProviderAuthenticationController(transport: CopilotTransportStub([(200, body)])).beginLogin(provider: .copilot)
                XCTFail("Invalid verification URL")
            } catch { XCTAssertEqual(error as? ProviderIntegrationError, .unreadableResponse) }
        }
    }

    func testTokenDoesNotRefreshOfflineAndRejectsExcessScopeOrCrossProviderEnvelope() async throws {
        let transport = CopilotTransportStub([])
        let controller = ProviderAuthenticationController(transport: transport)
        let persisted = try credential("offline-fixture")
        let result = try await controller.refreshCredentialIfNeeded(provider: .copilot, credential: persisted)
        XCTAssertEqual(result.credential, persisted)
        XCTAssertFalse(result.changed)
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
        do {
            _ = try await ProviderQuotaClient(provider: .copilot, transport: transport).quota(for: UUID(), credential: ProviderCredentialEnvelope(provider: .codex, kind: .oauth, accessToken: "wrong-provider").encoded())
            XCTFail("Cross-provider credential")
        } catch { XCTAssertEqual(error as? ProviderIntegrationError, .invalidCredentialData) }
        let unsafe = CopilotTransportStub([(200, deviceReply), (200, tokenReply.replacingOccurrences(of: "read:user", with: "repo,read:user"))])
        let auth = ProviderAuthenticationController(transport: unsafe)
        let session = try await auth.beginLogin(provider: .copilot)
        do { _ = try await auth.continueLogin(session); XCTFail("Excessive token scope") }
        catch { XCTAssertEqual(error as? ProviderIntegrationError, .invalidCredential) }
    }

    func testOAuthServerExpiryDenialAndMalformedTokenRemainDistinct() async throws {
        for (status, body, expected) in [
            (200, #"{"error":"expired_token"}"#, ProviderIntegrationError.loginExpired),
            (200, #"{"error":"access_denied"}"#, .invalidCredential),
            (429, "{}", .rateLimited), (500, "{}", .server),
            (200, #"{"access_token":"fixture"}"#, .unreadableResponse),
        ] {
            let transport = CopilotTransportStub([(200, deviceReply), (status, body)])
            let controller = ProviderAuthenticationController(transport: transport)
            let session = try await controller.beginLogin(provider: .copilot)
            do { _ = try await controller.continueLogin(session); XCTFail("Expected \(expected)") }
            catch { XCTAssertEqual(error as? ProviderIntegrationError, expected) }
        }
    }

    func testQueryUsesEditorContractAndAccountReportedMonthlyReset() async throws {
        let transport = CopilotTransportStub([(200, quotaReply)])
        let id = UUID()
        let snapshot = try await ProviderQuotaClient(provider: .copilot, transport: transport, now: { Date(timeIntervalSince1970: 100) }).quota(for: id, credential: credential("fixture"))
        XCTAssertEqual(snapshot.accountID, id)
        XCTAssertEqual(snapshot.collectedAt, now)
        XCTAssertEqual(snapshot.providerPlanName, "Free")
        XCTAssertEqual(snapshot.windows.map(\.id), ["copilot.premium_interactions", "copilot.chat", "copilot.completions"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercentage), [20, 50, 20])
        XCTAssertEqual(snapshot.windows.map(\.totalCount), [50, 200, 2000])
        XCTAssertEqual(Set(snapshot.windows.compactMap(\.resetsAt)).count, 1)
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.period == .monthly && $0.cycleID == nil })
        let received = await transport.requests
        let request = try XCTUnwrap(received.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/copilot_internal/user")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token fixture")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Editor-Version"), "vscode/1.96.2")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Editor-Plugin-Version"), "copilot-chat/0.26.7")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Github-Api-Version"), "2025-04-01")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testUnissuedUnlimitedAndPaidOverageAreDistinctAndPreserveSpentLegacyLane() throws {
        let root = try ProviderHTTP.json(Data(#"{"quota_reset_date":"2026-11-01","quota_snapshots":{"premium_interactions":{"has_quota":false,"percent_remaining":0},"chat":{"unlimited":true,"percent_remaining":0},"completions":{"has_quota":true,"entitlement":2000,"remaining":0,"percent_remaining":0,"overage_permitted":true,"overage_count":12}}}"#.utf8))
        let windows = CopilotProviderClient.windows(root)
        XCTAssertEqual(windows.count, 2)
        XCTAssertTrue(windows[0].isUnlimited)
        XCTAssertNil(windows[0].usedPercentage)
        XCTAssertEqual(QuotaFormatting.usage(windows[0]), "无限")
        XCTAssertEqual(windows[1].isExhausted, false)
        XCTAssertEqual(windows[1].usedPercentage, 100)
        XCTAssertEqual(QuotaFormatting.usage(windows[1]), "超额付费 12 次")
        XCTAssertNotNil(windows[1].resetsAt)
        let legacy = CopilotProviderClient.windows(["quota_snapshots": [
            "chat": ["entitlement": 0, "remaining": 0, "percent_remaining": 100],
            "completions": ["entitlement": 0, "remaining": 0, "percent_remaining": 0],
        ]])
        XCTAssertEqual(legacy.map(\.id), ["copilot.completions"])
        XCTAssertEqual(legacy.first?.isExhausted, true)
    }

    func testMissingNumbersAreNotZeroAndNonFiniteOrBooleanMetricsAreRejected() throws {
        let windows = CopilotProviderClient.windows(["quota_snapshots": [
            "premium_interactions": ["has_quota": true, "entitlement": 50],
            "chat": ["percent_remaining": "nan", "remaining": -1, "entitlement": true],
            "completions": ["has_quota": true, "percent_remaining": 140],
        ]])
        XCTAssertEqual(windows.count, 2)
        XCTAssertNil(windows[0].usedPercentage)
        XCTAssertNil(windows[0].remainingCount)
        XCTAssertNil(windows[0].isExhausted)
        XCTAssertEqual(windows[1].usedPercentage, 0)
        XCTAssertNil(windows[1].resetsAt)
        let unknown = CopilotProviderClient.windows(["quota_snapshots": ["chat": ["percent_remaining": true]]])
        XCTAssertTrue(unknown.isEmpty)
    }

    func testHTTPAndMalformedResponsesFailWithoutInventingWindows() async throws {
        for (status, body, failure) in [(401, "{}", RefreshFailure.invalidCredential), (403, "{}", .invalidCredential), (429, "{}", .rateLimited), (500, "{}", .server), (200, "not json", .unreadableResponse), (200, "{}", .noQuotaWindows)] {
            do {
                _ = try await ProviderQuotaClient(provider: .copilot, transport: CopilotTransportStub([(status, body)])).quota(for: UUID(), credential: credential("fixture"))
                XCTFail("Expected \(failure)")
            } catch { XCTAssertEqual(error as? RefreshFailure, failure) }
        }
    }

    func testNotificationsUseIncludedQuotaThresholdsAndOneExpectedResetWithoutUnlimitedAlerts() throws {
        let windows = CopilotProviderClient.windows(["quota_reset_date": "2026-11-01", "quota_snapshots": [
            "chat": ["unlimited": true], "premium_interactions": ["percent_remaining": 5],
            "completions": ["percent_remaining": 0, "overage_permitted": true],
        ]])
        let id = UUID()
        let snapshot = QuotaSnapshot(accountID: id, windows: windows, collectedAt: now)
        let planner = NotificationPlanner()
        let first = planner.planSuccessfulRefresh(accountID: id, accountName: "Copilot", previousSnapshot: nil, newSnapshot: snapshot, settings: .init(), ledger: .init(), now: now)
        let delivered = first.operations.compactMap { if case .deliver(let value) = $0 { return value }; return nil }
        XCTAssertEqual(delivered.map(\.kind), [.quotaAlert])
        XCTAssertFalse(delivered[0].body.contains("Chat"))
        let completions = try XCTUnwrap(windows.first { $0.id == "copilot.completions" })
        XCTAssertTrue(delivered[0].body.contains(L10n.windowDisplayName(completions, provider: .copilot)))
        XCTAssertTrue(delivered[0].body.contains(1.0.formatted(.percent.precision(.fractionLength(0)))))
        let schedules = first.operations.compactMap { if case .schedule(let value, _) = $0 { return value }; return nil }
        XCTAssertEqual(schedules.map(\.kind), [.expectedReset])
        XCTAssertTrue(schedules[0].title.contains("预计"))
        let second = planner.planSuccessfulRefresh(accountID: id, accountName: "Copilot", previousSnapshot: snapshot, newSnapshot: snapshot, settings: .init(), ledger: first.ledger, now: now)
        XCTAssertTrue(second.operations.isEmpty)
    }

    func testWidgetsAndSnapshotCodingRetainAllThreeLanesAndOverageState() throws {
        let windows = CopilotProviderClient.windows(["quota_snapshots": [
            "premium_interactions": ["percent_remaining": 10], "chat": ["unlimited": true],
            "completions": ["percent_remaining": 0, "overage_permitted": true],
        ]])
        let account = SubscriptionAccount(name: "Copilot", provider: .copilot)
        let widget = WidgetAccountSnapshot(account: account, windows: windows, collectedAt: now, lastFailure: .network, providerPlanName: "Custom Plan")
        let restored = try JSONDecoder().decode(WidgetAccountSnapshot.self, from: JSONEncoder().encode(widget))
        XCTAssertEqual(restored, widget)
        XCTAssertEqual(restored.ringMetrics.count, 3)
        XCTAssertEqual(restored.displayMetrics.map(\.valueText), ["90%", "无限", "可超额付费"])
        XCTAssertNil(restored.ringMetrics[1].ringFraction)
        let old = #"{"id":"copilot.chat","name":"Chat","isUnlimited":false}"#
        let oldWindow = try JSONDecoder().decode(QuotaWindow.self, from: Data(old.utf8))
        XCTAssertNil(oldWindow.overagePermitted)
        XCTAssertNil(oldWindow.overageCount)
    }

    @MainActor
    func testTwoAccountsRestoreReauthorizeAndDeleteWithCloudDisabled() async throws {
        let suite = "copilot.local.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LocalAccountStateStore(suiteName: suite)
        let config = LocalAccountConfigurationStore(suiteName: suite)
        let credentials = SynchronizableCredentialStore(service: suite, accessGroup: nil, syncEnabled: false)
        let transport = CopilotTransportStub([(200, quotaReply), (200, quotaReply), (401, "{}"), (200, quotaReply), (200, quotaReply)])
        let client = ProviderQuotaClient(provider: .copilot, transport: transport)
        let monitor = QuotaMonitor(accountStore: store, credentialStore: credentials, quotaClient: client, configurationStore: config, providerClient: { _ in client })
        await monitor.addAccount(name: "Work", credential: try credential("work-fixture"), provider: .copilot)
        await monitor.addAccount(name: "Personal", credential: try credential("personal-fixture"), provider: .copilot)
        let first = try XCTUnwrap(monitor.states.first)
        let second = try XCTUnwrap(monitor.states.last)
        let restoredCredentials = SynchronizableCredentialStore(service: suite, accessGroup: nil, syncEnabled: false)
        defer { Task { try? await restoredCredentials.deleteCredential(for: first.id); try? await restoredCredentials.deleteCredential(for: second.id) } }
        let restored = QuotaMonitor(accountStore: store, credentialStore: restoredCredentials, quotaClient: client, configurationStore: config, providerClient: { _ in client })
        await restored.start(refresh: false)
        XCTAssertEqual(restored.states, monitor.states)
        await restored.refresh(accountID: first.id)
        XCTAssertEqual(restored.states[0].snapshot, first.snapshot)
        XCTAssertEqual(restored.states[0].lastFailure, .invalidCredential)
        await restored.replaceCredential(try credential("reauthorized-fixture"), accountID: first.id)
        XCTAssertNil(restored.states[0].lastFailure)
        XCTAssertEqual(restored.states[1], second)
        let deleted = await restored.deleteAccount(accountID: first.id)
        XCTAssertTrue(deleted)
        let deletedCredential = try await restoredCredentials.credential(for: first.id)
        let remainingCredential = try await restoredCredentials.credential(for: second.id)
        XCTAssertNil(deletedCredential)
        XCTAssertEqual(remainingCredential, try credential("personal-fixture"))
        await restored.refresh(accountID: second.id)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["token work-fixture", "token personal-fixture", "token work-fixture", "token reauthorized-fixture", "token personal-fixture"])
        try await restoredCredentials.deleteCredential(for: second.id)
    }

    private func credential(_ token: String) throws -> String {
        try ProviderCredentialEnvelope(provider: .copilot, kind: .oauth, accessToken: token).encoded()
    }
}

private actor CopilotTransportStub: ProviderTransport {
    private var replies: [(Int, String)]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [(Int, String)]) { self.replies = replies }
    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let (status, body) = replies.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private actor CopilotSleepRecorder {
    private(set) var intervals: [TimeInterval] = []
    func record(_ interval: TimeInterval) { intervals.append(interval) }
}
