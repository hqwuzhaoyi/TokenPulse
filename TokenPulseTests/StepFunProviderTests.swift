import Foundation
import XCTest
import WebKit
@testable import TokenPulse

final class StepFunProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let tokenBody = #"{"status":1,"plan_family":2,"five_hour_usage_left_rate":0,"five_hour_usage_reset_time":"0","weekly_usage_left_rate":0,"weekly_usage_reset_time":"0","plan_credit_rate_limit":{"subscription_credit_left_rate":0.9999462,"topup_credit_left_rate":0,"credit_buckets":[{"type":1,"credit_total":"1600000000","credit_residual":"1599913834","expire_at":"1791187256","next_reset_at":"0"}]}}"#

    func testTokenPlanSumsOnlyCreditsAndExpiryDoesNotCreateAReset() throws {
        let windows = try StepFunProviderClient.windows(ProviderHTTP.json(Data(tokenBody.utf8)), now: now)
        let window = try XCTUnwrap(windows.first)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(window.id, "stepfun.credits")
        XCTAssertEqual(window.period, .other)
        XCTAssertEqual(window.unit, "积分")
        XCTAssertEqual(window.totalCount, 1_600_000_000)
        XCTAssertEqual(window.remainingCount, 1_599_913_834)
        XCTAssertEqual(try XCTUnwrap(window.usedPercentage), 0.005385375, accuracy: 0.0000001)
        XCTAssertNil(window.resetsAt)
        XCTAssertNil(window.wallet)
        XCTAssertEqual(window.expiresAt, Date(timeIntervalSince1970: 1_791_187_256))
        XCTAssertFalse(window.needsUpdate(at: Date(timeIntervalSince1970: 1_792_000_000)))
    }

    func testBucketsSumSubscriptionAndPacksButKeepExpirySeparateFromMonthlyRefill() throws {
        let root = try json(#"{"status":1,"plan_credit_rate_limit":{"credit_buckets":[{"credit_total":"100","credit_residual":"20","expire_at":"1790000010","next_reset_at":"1790000020"},{"credit_total":"200","credit_residual":"100","expire_at":"1790000010","next_reset_at":"0"},{"credit_total":"50","credit_residual":"0","expire_at":"1790000001","next_reset_at":"0"}]}}"#)
        let window = try XCTUnwrap(StepFunProviderClient.windows(root, now: now).first)
        XCTAssertEqual(window.totalCount, 350)
        XCTAssertEqual(window.remainingCount, 120)
        XCTAssertEqual(window.expiresAt, now.addingTimeInterval(10))
        XCTAssertEqual(window.resetsAt, now.addingTimeInterval(20))
        XCTAssertEqual(QuotaFormatting.nextEventLabel(window), "最早积分到期")
        XCTAssertEqual(QuotaFormatting.nextEventDate(window), now.addingTimeInterval(10))
        XCTAssertEqual(window.isExhausted, false)
    }

    func testCodingPlanUsesFractionsLeftAndRequiresAReportedResetInsteadOfPlanFamily() throws {
        let root = try json(#"{"status":1,"plan_family":2,"five_hour_usage_left_rate":0.25,"five_hour_usage_reset_time":"1790000010","weekly_usage_left_rate":0,"weekly_usage_reset_time":"1790000020000","plan_credit_rate_limit":{"subscription_credit_left_rate":0.75}}"#)
        let windows = try StepFunProviderClient.windows(root, now: now)
        XCTAssertEqual(windows.map(\.id), ["stepfun.5h", "stepfun.weekly"])
        XCTAssertEqual(windows.map(\.period), [.fiveHour, .weekly])
        XCTAssertEqual(windows.map(\.usedPercentage), [75, 100])
        XCTAssertEqual(windows.map(\.isExhausted), [false, true])
        XCTAssertEqual(windows.map(\.resetsAt), [now.addingTimeInterval(10), now.addingTimeInterval(20)])
        XCTAssertTrue(windows.allSatisfy { $0.totalCount == nil && $0.remainingCount == nil && $0.unit == nil && $0.expiresAt == nil })
    }

    func testFractionFallbackDoesNotAddSubscriptionAndPackOrInventAmounts() throws {
        let root = try json(#"{"status":1,"plan_credit_rate_limit":{"subscription_credit_left_rate":0.25,"topup_credit_left_rate":0.75}}"#)
        let window = try XCTUnwrap(StepFunProviderClient.windows(root, now: now).first)
        XCTAssertEqual(window.usedPercentage, 75)
        XCTAssertNil(window.totalCount)
        XCTAssertNil(window.remainingCount)
        XCTAssertNil(window.resetsAt)
        XCTAssertEqual(QuotaFormatting.usage(window), "75% 已用")
        let topUpOnly = try json(#"{"status":1,"plan_credit_rate_limit":{"subscription_credit_left_rate":0,"topup_credit_left_rate":0.75}}"#)
        XCTAssertEqual(try StepFunProviderClient.windows(topUpOnly, now: now).first?.usedPercentage, 25)
        XCTAssertTrue(try StepFunProviderClient.windows(["status": 1], now: now).isEmpty)
    }

    func testInvalidBucketsBooleanNumbersAndMissingRatesDoNotBecomeZero() throws {
        for body in [
            #"{"status":true}"#,
            #"{"status":1,"five_hour_usage_reset_time":"1790000010","five_hour_usage_left_rate":false}"#,
            #"{"status":1,"plan_credit_rate_limit":{"credit_buckets":[{"credit_total":"100","credit_residual":"101"}]}}"#,
            #"{"status":1,"plan_credit_rate_limit":{"credit_buckets":[{"credit_total":"100","credit_residual":"20"},{"credit_total":true,"credit_residual":0}]}}"#,
            #"{"status":1,"plan_credit_rate_limit":{"credit_buckets":[{"credit_total":"100"}]}}"#,
        ] {
            XCTAssertThrowsError(try StepFunProviderClient.windows(json(body), now: now)) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
        XCTAssertNil(StepFunProviderClient.timestamp(true))
        XCTAssertNil(StepFunProviderClient.timestamp("0"))
        XCTAssertNil(StepFunProviderClient.timestamp("nan"))
        let exhausted = try StepFunProviderClient.windows(json(#"{"status":1,"plan_credit_rate_limit":{"credit_buckets":[{"credit_total":"100","credit_residual":"0","expire_at":"1790000010"}]}}"#), now: now)
        XCTAssertEqual(exhausted.first?.isExhausted, true)
        XCTAssertEqual(exhausted.first?.usedPercentage, 100)
        XCTAssertNil(exhausted.first?.expiresAt)
    }

    func testCookieAllowlistAndRegionalAccountBindingSupportAStandaloneDeviceRequest() async throws {
        for site in StepFunSite.allCases {
            let id = UUID()
            let credential = try session(site: site, id: id)
            let transport = StepFunTransportStub([.response(200, tokenBody)])
            let result = try await ProviderQuotaClient(provider: .stepFun, transport: transport, now: { self.now })
                .quotaResult(for: id, credential: credential)
            XCTAssertEqual(result.snapshot.accountID, id)
            XCTAssertNil(result.updatedCredential)
            let requests = await transport.requests()
            let request = try XCTUnwrap(requests.first)
            XCTAssertEqual(request.url, site.endpoint("QueryStepPlanRateLimit"))
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.httpBody, Data("{}".utf8))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "Oasis-Token=fixture-token; Oasis-Webid=fixture-device; INGRESSCOOKIE=fixture-route")
            XCTAssertEqual(request.value(forHTTPHeaderField: "oasis-webid"), "fixture-device")
            XCTAssertEqual(request.value(forHTTPHeaderField: "oasis-appid"), "10300")
            XCTAssertEqual(request.value(forHTTPHeaderField: "oasis-platform"), "web")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), site.origin)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), site.usageURL.absoluteString)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testWrongSiteAccountDeviceAndExpiredSessionsNeverSendRequests() async throws {
        let id = UUID()
        let transport = StepFunTransportStub([])
        let client = ProviderQuotaClient(provider: .stepFun, transport: transport, now: { self.now })
        let encoded = try session(site: .china, id: id)
        let base = try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .stepFun)
        for mutation in ["account", "site", "host", "webID", "expiry", "kind", "missing-device", "unsafe-header"] {
            var credential = base
            switch mutation {
            case "account": credential.metadata["localAccountID"] = UUID().uuidString
            case "site": credential.metadata["site"] = "international"
            case "host": credential.metadata["host"] = "platform.stepfun.ai"
            case "webID": credential.metadata["webID"] = "another-device"
            case "expiry": credential.expiresAt = now
            case "kind": credential = .init(provider: .stepFun, kind: .apiKey, accessToken: "fixture-key")
            case "missing-device": credential.accessToken = "Oasis-Token=opaque-token"
            default: credential.accessToken += "\r\nInjected=value"
            }
            do {
                _ = try await client.quota(for: id, credential: credential.encoded())
                XCTFail("Expected invalid credential for \(mutation)")
            } catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential, mutation) }
        }
        let requests = await transport.requests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testJWTDeviceClaimIsReadWithoutGuessingAndConflictingCookieFails() throws {
        let payload = Data(#"{"device_id":"jwt-device"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let jwt = "fixture.\(payload).signature"
        for token in [jwt, "opaque...\(jwt)"] {
            XCTAssertEqual(try StepFunSession.webID(["Oasis-Token": token]), "jwt-device")
            XCTAssertThrowsError(try StepFunSession.webID(["Oasis-Token": token, "Oasis-Webid": "different-device"]))
        }
        XCTAssertThrowsError(try StepFunSession.webID(["Oasis-Token": "opaque"]))
        XCTAssertThrowsError(try StepFunSession.values(in: "Oasis-Token=x; analytics=unwanted"))
        XCTAssertThrowsError(try StepFunSession.values(in: "Oasis-Token=x; Oasis-Token=y"))
    }

    func testCookieDomainPathAndExpirySelectionRejectsOtherSitesAndUnrelatedNames() throws {
        let id = UUID()
        let valid = [cookie("Oasis-Token", "fixture", domain: ".stepfun.com"),
                     cookie("Oasis-Webid", "device", domain: "platform.stepfun.com"),
                     cookie("tracking", "private", domain: "platform.stepfun.com"),
                     cookie("Oasis-Token", "wrong-site", domain: "platform.stepfun.ai")]
        let envelope = try ProviderCredentialEnvelope.decode(StepFunSession.credential(cookies: valid, site: .china, accountID: id, now: now), expectedProvider: .stepFun)
        XCTAssertEqual(envelope.accessToken, "Oasis-Token=fixture; Oasis-Webid=device")
        for invalid in [
            [cookie("Oasis-Token", "fixture", domain: "evil.stepfun.com"), valid[1]],
            [cookie("Oasis-Token", "fixture", domain: "platform.stepfun.com", path: "/account"), valid[1]],
            [cookie("Oasis-Token", "fixture", domain: "platform.stepfun.com", expires: now), valid[1]],
            valid + [cookie("Oasis-Token", "ambiguous", domain: "platform.stepfun.com")],
        ] {
            XCTAssertThrowsError(try StepFunSession.credential(cookies: invalid, site: .china, accountID: id, now: now))
        }
    }

    func testFailuresAndNoPlanAreDistinctAndAuthenticationConfigurationRemainsCompatible() async throws {
        let id = UUID()
        let encoded = try session(site: .china, id: id)
        for (status, body, expected) in [(401, "{}", RefreshFailure.invalidCredential), (403, "{}", .invalidCredential),
                                         (429, "{}", .rateLimited), (500, "{}", .server),
                                         (200, "bad-json", .unreadableResponse),
                                         (200, #"{"status":0,"desc":"auth token expired"}"#, .invalidCredential),
                                         (200, #"{"status":0,"message":"unexpected reply"}"#, .unreadableResponse)] {
            do {
                _ = try await ProviderQuotaClient(provider: .stepFun, transport: StepFunTransportStub([.response(status, body)]), now: { self.now })
                    .quota(for: id, credential: encoded)
                XCTFail("Expected failure")
            } catch { XCTAssertEqual(error as? RefreshFailure, expected) }
        }
        let snapshot = try await ProviderQuotaClient(provider: .stepFun, transport: StepFunTransportStub([.response(200, #"{"status":1}"#)]), now: { self.now })
            .quota(for: id, credential: encoded)
        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertEqual(snapshot.collectedAt, now)
        XCTAssertEqual(ProviderAuthenticationController().loginConfiguration(for: .stepFun).method, .webSession)
        XCTAssertEqual(ProviderAuthenticationController().loginConfiguration(for: .claude).method, .webSession)
        XCTAssertTrue(ProviderRedirectPolicy.permits(origin: StepFunSite.china.usageURL, target: StepFunSite.china.endpoint("x")))
        XCTAssertFalse(ProviderRedirectPolicy.permits(origin: StepFunSite.china.usageURL, target: StepFunSite.international.usageURL))
        XCTAssertFalse(ProviderRedirectPolicy.permits(origin: StepFunSite.china.usageURL, target: URL(string: "http://platform.stepfun.com/x")))
    }

    func testCreditExpiryDoesNotScheduleResetAndCodingResetUsesExistingRules() throws {
        let id = UUID()
        let credits = try StepFunProviderClient.windows(json(tokenBody), now: now)
        let snapshot = QuotaSnapshot(accountID: id, windows: credits, collectedAt: now)
        let result = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "StepFun",
            previousSnapshot: nil, newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: now)
        XCTAssertFalse(result.operations.contains { if case .schedule = $0 { return true }; return false })
        let coding = try StepFunProviderClient.windows(json(#"{"status":1,"five_hour_usage_left_rate":0,"five_hour_usage_reset_time":"1790000010"}"#), now: now)
        let codingResult = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "StepFun",
            previousSnapshot: nil, newSnapshot: QuotaSnapshot(accountID: id, windows: coding, collectedAt: now),
            settings: AccountReminderSettings(), ledger: ReminderLedger(), now: now)
        XCTAssertTrue(codingResult.operations.contains { if case .schedule = $0 { return true }; return false })
        XCTAssertTrue(codingResult.operations.contains { if case .deliver(let notification) = $0 { return notification.kind == .quotaAlert }; return false })
    }

    @MainActor
    func testEphemeralWebContainersAreIsolatedByProviderAccountAndRegion() async throws {
        let first = WebSessionContainer(scope: .init(provider: .stepFun, accountID: UUID(), host: StepFunSite.china.host))
        let second = WebSessionContainer(scope: .init(provider: .stepFun, accountID: UUID(), host: StepFunSite.china.host))
        let international = WebSessionContainer(scope: .init(provider: .stepFun, accountID: first.scope.accountID, host: StepFunSite.international.host))
        let claude = WebSessionContainer(scope: .init(provider: .claude, accountID: first.scope.accountID, host: "claude.ai"))
        let store = first.webView.configuration.websiteDataStore.httpCookieStore
        await withCheckedContinuation { continuation in
            store.setCookie(cookie("Oasis-Token", "fixture", domain: StepFunSite.china.host)) { continuation.resume() }
        }
        for container in [second, international, claude] {
            XCTAssertFalse(container.webView.configuration.websiteDataStore.isPersistent)
            XCTAssertNotEqual(container.scope, first.scope)
            let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
                container.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
            }
            XCTAssertTrue(cookies.isEmpty)
            container.close()
            XCTAssertTrue(container.closed)
        }
        first.close()
        XCTAssertTrue(first.closed)
    }

    func testDemoAndWidgetsUseCreditsOrCodingMetricsWithoutWalletOrExpiryReset() throws {
        let accounts = DemoMode.accounts().filter { $0.provider == .stepFun }
        XCTAssertEqual(accounts.count, 2)
        let token = DemoMode.snapshot(accountID: accounts[0].id, provider: .stepFun, now: now)
        let coding = DemoMode.snapshot(accountID: accounts[1].id, provider: .stepFun, now: now)
        XCTAssertEqual(token.windows.first?.unit, "积分")
        XCTAssertNil(token.windows.first?.wallet)
        XCTAssertNil(token.windows.first?.resetsAt)
        XCTAssertEqual(coding.windows.map(\.period), [.fiveHour, .weekly])
        for (account, snapshot) in [(accounts[0], token), (accounts[1], coding)] {
            let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows, collectedAt: now, lastFailure: nil)
            XCTAssertEqual(widget.displayMetrics.count, snapshot.windows.count)
            XCTAssertEqual(widget.ringMetrics.count, snapshot.windows.count)
            XCTAssertFalse(widget.supportsManualResetCount)
        }
        XCTAssertEqual(Provider.stepFun.iconAssetName, "ProviderStepFun")
    }

    @MainActor
    func testNoPlanClearsCachedPlanAndFailureKeepsOriginalCollectionTimeWithoutCloud() async throws {
        let id = UUID()
        let store = StepFunMemoryStore()
        let transport = StepFunTransportStub([.response(200, tokenBody), .failure(.timedOut),
                                              .response(200, #"{"status":1}"#), .response(500, "{}")])
        let client = ProviderQuotaClient(provider: .stepFun, transport: transport, now: { self.now })
        let monitor = QuotaMonitor(accountStore: store, credentialStore: store, quotaClient: client)
        await monitor.start(refresh: false)
        await monitor.addAccount(name: "First", credential: try session(site: .china, id: id), provider: .stepFun, accountID: id)
        let initial = try XCTUnwrap(monitor.states.first?.snapshot)
        await monitor.refresh(accountID: id)
        XCTAssertEqual(monitor.states.first?.snapshot, initial)
        XCTAssertEqual(monitor.states.first?.lastFailure, .network)
        await monitor.refresh(accountID: id)
        XCTAssertTrue(monitor.states.first?.snapshot?.windows.isEmpty == true)
        XCTAssertNil(monitor.states.first?.lastFailure)
        await monitor.refresh(accountID: id)
        XCTAssertTrue(monitor.states.first?.snapshot?.windows.isEmpty == true)
        XCTAssertEqual(monitor.states.first?.lastFailure, .server)
        let restored = QuotaMonitor(accountStore: store, credentialStore: store, quotaClient: client)
        await restored.start(refresh: false)
        XCTAssertTrue(restored.states.first?.snapshot?.windows.isEmpty == true)
        let deleted = await restored.deleteAccount(accountID: id)
        XCTAssertTrue(deleted)
        let saved = try await store.credential(for: id)
        XCTAssertNil(saved)
    }

    func testClaudeCookieExtractionKeepsEitherSessionVariantAndDropsUnrelatedCookies() throws {
        for name in ["sessionKey", "sessionKeyV3"] {
            let selected = try WebSessionCookiePolicy.select(
                [cookie(name, "fixture", domain: ".claude.ai"), cookie("analytics", "private", domain: "claude.ai")],
                names: ["sessionKey", "sessionKeyV3"], requiredNames: [],
                requiredAnyNames: ["sessionKey", "sessionKeyV3"], domains: ["claude.ai"], path: "/api/bootstrap", now: now)
            XCTAssertEqual(selected.header, "\(name)=fixture")
        }
    }

    private func json(_ text: String) throws -> [String: Any] { try ProviderHTTP.json(Data(text.utf8)) }
    private func cookie(_ name: String, _ value: String, domain: String, path: String = "/", expires: Date? = nil) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path, .secure: "TRUE"]
        if let expires { properties[.expires] = expires }
        return HTTPCookie(properties: properties)!
    }
    private func session(site: StepFunSite, id: UUID) throws -> String {
        try StepFunSession.credential(cookies: [cookie("Oasis-Token", "fixture-token", domain: site.host),
                                               cookie("Oasis-Webid", "fixture-device", domain: site.host),
                                               cookie("INGRESSCOOKIE", "fixture-route", domain: site.host),
                                               cookie("analytics", "unwanted", domain: site.host)],
                                      site: site, accountID: id, now: now)
    }
}

private actor StepFunTransportStub: ProviderTransport {
    enum Outcome: Sendable { case response(Int, String), failure(URLError.Code) }
    private var outcomes: [Outcome]
    private var received: [URLRequest] = []
    init(_ outcomes: [Outcome]) { self.outcomes = outcomes }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        received.append(request)
        guard !outcomes.isEmpty else { throw URLError(.badServerResponse) }
        switch outcomes.removeFirst() {
        case .failure(let code): throw URLError(code)
        case .response(let code, let body):
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
        }
    }
    func requests() -> [URLRequest] { received }
}

private actor StepFunMemoryStore: AccountStateStoring, CredentialStoring {
    private var states: [AccountQuotaState] = []
    private var credentials: [UUID: String] = [:]
    func load() -> [AccountQuotaState] { states }
    func save(_ states: [AccountQuotaState]) { self.states = states }
    func save(_ credential: String, for accountID: UUID) { credentials[accountID] = credential }
    func credential(for accountID: UUID) -> String? { credentials[accountID] }
    func deleteCredential(for accountID: UUID) { credentials[accountID] = nil }
}
