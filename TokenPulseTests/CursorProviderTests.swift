import Foundation
import XCTest
import CryptoKit
import WebKit
@testable import TokenPulse

final class CursorProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1000)
    private let body = #"{"billingCycleEnd":"2026-11-01T00:00:00Z","membershipType":"pro_plus","individualUsage":{"plan":{"enabled":true,"used":12,"limit":2000,"remaining":1988,"autoPercentUsed":0.0267,"apiPercentUsed":18},"onDemand":{"enabled":true,"used":"123.456789","limit":2000,"remaining":"1876.543211"}}}"#

    private func token(user: String = "user_a", expiry: Any = 10_000) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["sub":"auth0|\(user)","exp":expiry], options: [.sortedKeys])
        let encoded = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJub25lIn0.\(encoded).fixture"
    }

    func testNativeNoncePKCERequestMatchesPinnedProtocolWithoutClientOrCallback() async throws {
        let transport = CursorTestTransport([.response(404, "{}"), .response(200, try JSONText(["accessToken":token(),"refreshToken":"discarded-fixture"]))])
        let auth = CursorAccountAuthenticator(transport: transport, now: { Date(timeIntervalSince1970: 1000) })
        let id = UUID()
        let attempt = auth.begin(accountID: id)
        let url = URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false)!
        let parameters = Dictionary(uniqueKeysWithValues: url.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "cursor.com")
        XCTAssertEqual(url.path, "/loginDeepControl")
        XCTAssertEqual(parameters["mode"], "login")
        XCTAssertEqual(parameters["redirectTarget"], "sand")
        XCTAssertEqual(parameters["supportsSelectedTeamLogin"], "true")
        XCTAssertEqual(Set(parameters.keys), ["mode", "redirectTarget", "supportsSelectedTeamLogin", "uuid", "challenge"])
        let verifier = try XCTUnwrap(attempt.codeVerifier)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(parameters["challenge"], challenge)
        XCTAssertNil(parameters["verifier"])
        XCTAssertEqual(verifier.count, 43)
        XCTAssertEqual(attempt.expiresAt, now.addingTimeInterval(300))
        let pending = try await auth.poll(attempt)
        XCTAssertEqual(pending, .pending(retryAfter: 2))
        guard case .completed(let encoded) = try await auth.poll(attempt) else { return XCTFail() }
        let credential = try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .cursor)
        XCTAssertNil(credential.refreshToken)
        XCTAssertEqual(credential.accountID, "user_a")
        XCTAssertEqual(credential.metadata["localAccountID"], id.uuidString)
        XCTAssertEqual(credential.expiresAt, Date(timeIntervalSince1970: 10_000))
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        let poll = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(poll.host, "api2.cursor.sh")
        XCTAssertEqual(poll.path, "/auth/poll")
        XCTAssertEqual(Set(poll.queryItems!.map(\.name)), ["uuid", "verifier"])
        XCTAssertFalse(requests[0].httpShouldHandleCookies)
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(ProviderAuthenticationController().loginConfiguration(for: .cursor).method, .webSession)
    }

    func testNativeExpiryRefusalMalformedTokenNetworkAndCancellationRemainDistinct() async throws {
        let now = self.now
        for (outcome, expected) in [
            (CursorTestTransport.Outcome.response(403, #"{"error":"denied"}"#), ProviderIntegrationError.invalidCredential),
            (.response(429, "{}"), .rateLimited), (.response(500, "{}"), .server),
            (.response(200, #"{"accessToken":"not-jwt","refreshToken":"fixture"}"#), .invalidCredential),
            (.response(200, #"{"accessToken":"fixture"}"#), .unreadableResponse),
            (.failure(.timedOut), .network)
        ] {
            let auth = CursorAccountAuthenticator(transport: CursorTestTransport([outcome]), now: { now })
            do { _ = try await auth.poll(auth.begin(accountID: UUID())); XCTFail() }
            catch { XCTAssertEqual(error as? ProviderIntegrationError, expected) }
        }
        let unused = CursorTestTransport([])
        let auth = CursorAccountAuthenticator(transport: unused, now: { now })
        let attempt = auth.begin(accountID: UUID())
        let expired = CursorAccountAuthenticator(transport: unused, now: { now.addingTimeInterval(300) })
        do { _ = try await expired.poll(attempt); XCTFail() }
        catch { XCTAssertEqual(error as? ProviderIntegrationError, .loginExpired) }
        let requests = await unused.requests
        XCTAssertTrue(requests.isEmpty)
        let cancelled = CursorAccountAuthenticator(transport: CursorTestTransport([.failure(.cancelled)]), now: { now })
        do { _ = try await cancelled.poll(cancelled.begin(accountID: UUID())); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testJWTExpiryAccountBindingFingerprintAndCookieHeaderAreStrict() throws {
        let id = UUID()
        let encoded = try CursorAccountSession.credential(accessToken: token(), accountID: id, now: now)
        let credential = try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .cursor)
        XCTAssertEqual(try CursorAccountSession.cookie(credential, accountID: id, now: now), "WorkosCursorSessionToken=user_a%3A%3A\(try token())")
        XCTAssertThrowsError(try CursorAccountSession.cookie(credential, accountID: UUID(), now: now))
        for expiry in [true, 1060, "10000", 1e20] as [Any] {
            XCTAssertThrowsError(try CursorAccountSession.credential(accessToken: token(expiry: expiry), accountID: id, now: now))
        }
        var changed = credential
        changed.accessToken = try token(user: "user_b")
        XCTAssertThrowsError(try CursorAccountSession.validate(changed, accountID: id, now: now))
        changed = credential
        changed.metadata["host"] = "evil.example"
        XCTAssertThrowsError(try CursorAccountSession.validate(changed, accountID: id, now: now))
        changed = credential
        changed.metadata["sourceCredentialFingerprint"] = "forged"
        XCTAssertThrowsError(try CursorAccountSession.validate(changed, accountID: id, now: now))
        XCTAssertThrowsError(try CursorAccountSession.credential(accessToken: token()+"\r\nCookie: bad", accountID: id, now: now))
        let escaping = try ProviderCredentialEnvelope.decode(CursorAccountSession.credential(accessToken: token(user: "id;evil=1"), accountID: id, now: now), expectedProvider: .cursor)
        XCTAssertTrue(try CursorAccountSession.cookie(escaping, accountID: id, now: now).contains("id%3Bevil%3D1%3A%3A"))
    }

    func testPoolsStaySeparateAndCentsCashDenominatorCannotJoinThem() throws {
        let snapshot = try CursorProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: now)
        XCTAssertEqual(snapshot.windows.map(\.id), ["cursor.cursorModels", "cursor.otherModels", "cursor.onDemand"])
        XCTAssertEqual(snapshot.windows.map(\.scope), ["Cursor Models", "Other Models", nil])
        XCTAssertEqual(snapshot.windows[0].usedPercentage, 0.0267)
        XCTAssertEqual(snapshot.windows[1].usedPercentage, 18)
        XCTAssertNil(snapshot.windows[0].totalCount)
        XCTAssertNil(snapshot.windows[1].remainingCount)
        XCTAssertEqual(snapshot.windows[2].exactCounts?.used, Decimal(string: "1.23456789"))
        XCTAssertEqual(snapshot.windows[2].exactCounts?.remaining, Decimal(string: "18.76543211"))
        XCTAssertEqual(snapshot.windows[2].exactCounts?.total, 20)
        XCTAssertEqual(snapshot.windows[2].unit, "USD 预算")
        XCTAssertTrue(snapshot.windows.allSatisfy { $0.wallet == nil && $0.period == .monthly })
        XCTAssertEqual(snapshot.providerPlanName, "pro_plus")
    }

    func testTeamFallbackMissingMetricsAndExplicitDisabledSpendStayDistinct() throws {
        let team = #"{"teamUsage":{"pooled":{"apiPercentUsed":99},"onDemand":{"enabled":false,"used":100,"limit":500}}}"#
        let snapshot = try CursorProviderClient.snapshot(Data(team.utf8), accountID: UUID(), collectedAt: now)
        XCTAssertEqual(snapshot.windows.map(\.id), ["cursor.otherModels"])
        XCTAssertNil(snapshot.windows[0].resetsAt)
        let fallback = #"{"individualUsage":{"plan":{"used":50,"limit":2000},"onDemand":{"enabled":true,"limit":1000}}}"#
        let cash = try CursorProviderClient.snapshot(Data(fallback.utf8), accountID: UUID(), collectedAt: now)
        XCTAssertEqual(cash.windows.map(\.id), ["cursor.planCash", "cursor.onDemand"])
        XCTAssertEqual(cash.windows[0].usedPercentage, 2.5)
        XCTAssertEqual(cash.windows[0].exactCounts?.total, 20)
        XCTAssertNil(cash.windows[1].usedPercentage)
        XCTAssertNil(cash.windows[1].exactCounts)
        XCTAssertEqual(cash.windows[1].totalCount, 10)
    }

    func testMalformedBooleanAndUnknownPercentagesNeverBecomeZero() {
        for body in [#"{"individualUsage":{"plan":{"autoPercentUsed":true}}}"#,
                     #"{"individualUsage":{"plan":{"autoPercentUsed":"NaN"}}}"#,
                     #"{"individualUsage":{"plan":{"enabled":1,"apiPercentUsed":0}}}"#,
                     #"{"individualUsage":{"onDemand":{"used":true,"limit":100}}}"#,
                     #"{"random":{"autoPercentUsed":50}}"#, "{}"] {
            XCTAssertThrowsError(try CursorProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: now))
        }
        XCTAssertThrowsError(try CursorProviderClient.snapshot(Data(#"{"individualUsage":{"plan":{"autoPercentUsed":-1}}}"#.utf8), accountID: UUID(), collectedAt: now))
    }

    func testQuotaUsesOnlyRestrictedCookieAndExpiryBlocksBeforeNetwork() async throws {
        let id = UUID(), now = self.now
        let encoded = try CursorAccountSession.credential(accessToken: token(), accountID: id, now: now)
        let transport = CursorTestTransport([.response(200, body)])
        let snapshot = try await ProviderQuotaClient(provider: .cursor, transport: transport, now: { now }).quota(for: id, credential: encoded)
        XCTAssertEqual(snapshot.sourceCredentialFingerprint, try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .cursor).metadata["sourceCredentialFingerprint"])
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://cursor.com/api/usage-summary")
        XCTAssertTrue(requests[0].value(forHTTPHeaderField: "Cookie")!.hasPrefix("WorkosCursorSessionToken="))
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertFalse(requests[0].httpShouldHandleCookies)
        XCTAssertEqual(requests[0].cachePolicy, .reloadIgnoringLocalCacheData)
        let unused = CursorTestTransport([])
        do { _ = try await ProviderQuotaClient(provider: .cursor, transport: unused, now: { Date(timeIntervalSince1970: 9940) }).quota(for: id, credential: encoded); XCTFail() }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let expiredRequests = await unused.requests
        XCTAssertTrue(expiredRequests.isEmpty)
    }

    func testHTTPErrorMappingAndNoCrossOriginCredentialRedirectPolicy() async throws {
        let id = UUID(), now = self.now
        let encoded = try CursorAccountSession.credential(accessToken: token(), accountID: id, now: now)
        for (status, expected) in [(401, RefreshFailure.invalidCredential), (403, .invalidCredential), (429, .rateLimited), (500, .server), (302, .server)] {
            let transport = CursorTestTransport([.response(status, "{}")])
            do { _ = try await ProviderQuotaClient(provider: .cursor, transport: transport, now: { now }).quota(for: id, credential: encoded); XCTFail() }
            catch { XCTAssertEqual(error as? RefreshFailure, expected) }
        }
        XCTAssertFalse(ProviderRedirectPolicy.permits(origin: nil, target: URL(string: "https://cursor.com/api/usage-summary")))
        XCTAssertFalse(ProviderRedirectPolicy.permits(origin: URL(string: "https://cursor.com/api/usage-summary"), target: URL(string: "https://evil.example/")))
    }

    func testWidgetsNotificationsAndDemoKeepBothModelPoolsAndExtraBudget() throws {
        let account = SubscriptionAccount(name: "fixture", provider: .cursor)
        let source = body.replacingOccurrences(of: "18}", with: "95}")
        let snapshot = try CursorProviderClient.snapshot(Data(source.utf8), accountID: account.id, collectedAt: now)
        let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows, collectedAt: now, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 3)
        XCTAssertEqual(widget.ringMetrics.count, 3)
        XCTAssertEqual(widget.displayMetrics[0].window?.usedPercentage, 0.0267)
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        let result = NotificationPlanner().planSuccessfulRefresh(accountID: account.id, accountName: account.name, previousSnapshot: nil, newSnapshot: snapshot,
            settings: AccountReminderSettings(), ledger: ReminderLedger(), now: now)
        let delivered = result.operations.compactMap { if case .deliver(let value) = $0 { return value }; return nil }
        XCTAssertEqual(delivered.map(\.kind), [.quotaAlert])
        XCTAssertTrue(delivered[0].body.contains("Other Models"))
        XCTAssertFalse(delivered[0].body.contains("Cursor Models"))
        XCTAssertEqual(result.operations.filter { if case .schedule = $0 { return true }; return false }.count, 1)
        XCTAssertEqual(DemoMode.snapshot(accountID: UUID(), provider: .cursor, now: now).windows.count, 3)
    }

    @MainActor
    func testIsolatedWebLoginCompletesOnlyAfterNativePollAndQuotaValidation() async throws {
        let now = self.now
        let reply = try JSONText(["accessToken":token(),"refreshToken":"unused"])
        let transport = CursorTestTransport([.response(404, "{}"), .response(200, reply)])
        var saved: [String] = [], queryIDs: [UUID] = []
        let id = UUID()
        let model = CursorSessionLoginModel(accountID: id, onCredential: { saved.append($0) },
            auth: .init(transport: transport, now: { now }), sleep: { _ in },
            query: { queriedID, _ in queryIDs.append(queriedID) }, loadPage: { _, _ in })
        let task = model.start()
        let container = try XCTUnwrap(model.container)
        XCTAssertFalse(container.webView.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(container.scope.accountID, id)
        await task.value
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(queryIDs, [id])
        XCTAssertTrue(container.closed)
        XCTAssertNil(model.container)
        let other = CursorSessionLoginModel(accountID: UUID(), onCredential: { _ in },
            auth: .init(transport: CursorTestTransport([]), now: { now }), sleep: { _ in throw CancellationError() }, loadPage: { _, _ in })
        let otherTask = other.start()
        let otherContainer = try XCTUnwrap(other.container)
        XCTAssertNotEqual(otherContainer.scope, container.scope)
        XCTAssertFalse(otherContainer.webView.configuration.websiteDataStore.isPersistent)
        await otherTask.value
        other.close()
    }

    @MainActor
    func testDismissalOrRestartDuringPollCannotStoreOldAccountCredential() async throws {
        let now = self.now
        for restart in [false, true] {
            let held = CursorHeldTransport(body: try JSONText(["accessToken":token(),"refreshToken":"unused"]))
            var saved: [String] = [], queried = 0
            let model = CursorSessionLoginModel(accountID: UUID(), onCredential: { saved.append($0) },
                auth: .init(transport: held, now: { now }), sleep: { _ in }, query: { _, _ in queried += 1 }, loadPage: { _, _ in })
            let oldTask = model.start()
            await held.waitForRequest()
            if restart { _ = model.start() } else { model.close() }
            await held.release()
            await oldTask.value
            XCTAssertTrue(oldTask.isCancelled)
            XCTAssertTrue(saved.isEmpty)
            XCTAssertEqual(queried, 0)
            model.close()
        }
    }

    @MainActor
    func testAccountsRestartReauthorizeSyncAndDeleteKeepSessionOwnership() async throws {
        let phoneSuite = "cursor.phone.tests.\(UUID().uuidString)", watchSuite = "cursor.watch.tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: phoneSuite)?.removePersistentDomain(forName: phoneSuite); UserDefaults(suiteName: watchSuite)?.removePersistentDomain(forName: watchSuite) }
        let now = self.now, firstID = UUID(), secondID = UUID()
        let credentials = CursorTestCredentials()
        let transport = CursorTestTransport([.response(200, body), .response(200, body), .response(401, "{}"), .response(401, "{}")])
        let client = ProviderQuotaClient(provider: .cursor, transport: transport, now: { now })
        let store = LocalAccountStateStore(suiteName: phoneSuite), config = LocalAccountConfigurationStore(suiteName: phoneSuite)
        let phone = QuotaMonitor(accountStore: store, credentialStore: credentials, quotaClient: client, configurationStore: config)
        await phone.start(refresh: false)
        let first = try CursorAccountSession.credential(accessToken: token(), accountID: firstID, now: now)
        let second = try CursorAccountSession.credential(accessToken: token(user: "user_b"), accountID: secondID, now: now)
        await phone.addAccount(name: "A", credential: first, provider: .cursor, accountID: firstID)
        await phone.addAccount(name: "B", credential: second, provider: .cursor, accountID: secondID)
        let old = try XCTUnwrap(phone.states.first)
        let other = try XCTUnwrap(phone.states.last)
        await phone.refresh(accountID: firstID)
        XCTAssertEqual(phone.states[0].snapshot, old.snapshot)
        XCTAssertEqual(phone.states[0].lastFailure, .invalidCredential)
        let restored = QuotaMonitor(accountStore: store, credentialStore: credentials, quotaClient: client, configurationStore: config)
        await restored.start(refresh: false)
        XCTAssertEqual(restored.states, phone.states)
        let watchTransport = CursorTestTransport([.response(200, body), .response(200, body)])
        let watchNow = now.addingTimeInterval(500)
        let watch = QuotaMonitor(accountStore: LocalAccountStateStore(suiteName: watchSuite), credentialStore: credentials,
            quotaClient: ProviderQuotaClient(provider: .cursor, transport: watchTransport, now: { watchNow }),
            configurationStore: LocalAccountConfigurationStore(suiteName: watchSuite))
        await watch.start(refresh: false)
        await watch.mergeSynchronized(configurations: restored.configurations, states: restored.states)
        await watch.refreshAll()
        XCTAssertTrue(watch.states.allSatisfy { $0.snapshot?.collectedAt == watchNow && $0.lastFailure == nil })
        let requests = await watchTransport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertNotEqual(requests[0].value(forHTTPHeaderField: "Cookie"), requests[1].value(forHTTPHeaderField: "Cookie"))
        let new = try CursorAccountSession.credential(accessToken: token(user: "user_c"), accountID: firstID, now: now)
        await restored.replaceCredential(new, accountID: firstID)
        XCTAssertNil(restored.states[0].snapshot)
        XCTAssertEqual(restored.states[1], other)
        let deleted = await restored.deleteAccount(accountID: firstID)
        XCTAssertTrue(deleted)
        let erased = await credentials.credential(for: firstID), kept = await credentials.credential(for: secondID)
        XCTAssertNil(erased)
        XCTAssertEqual(kept, second)
    }

    private func JSONText(_ object: [String: String]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}

private actor CursorTestTransport: ProviderTransport {
    enum Outcome: Sendable { case response(Int, String), failure(URLError.Code) }
    private var outcomes: [Outcome]
    private(set) var requests: [URLRequest] = []
    init(_ outcomes: [Outcome]) { self.outcomes = outcomes }
    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        guard !outcomes.isEmpty else { throw URLError(.badServerResponse) }
        switch outcomes.removeFirst() {
        case .response(let status, let body): return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        case .failure(let code): throw URLError(code)
        }
    }
}
private actor CursorHeldTransport: ProviderTransport {
    private let body: String
    private var requestStarted = false
    private var response: CheckedContinuation<Void, Never>?
    private var ready: CheckedContinuation<Void, Never>?
    init(body: String) { self.body = body }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        // A replacement run must not produce another credential while the old
        // request is deliberately held.
        if requestStarted { throw CancellationError() }
        requestStarted = true
        await withCheckedContinuation { response = $0; ready?.resume(); ready = nil }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func waitForRequest() async { if !requestStarted { await withCheckedContinuation { ready = $0 } } }
    func release() { response?.resume(); response = nil }
}
private actor CursorTestCredentials: CredentialStoring {
    private var values: [UUID: String] = [:]
    func save(_ credential: String, for accountID: UUID) { values[accountID] = credential }
    func credential(for accountID: UUID) -> String? { values[accountID] }
    func deleteCredential(for accountID: UUID) { values[accountID] = nil }
}
