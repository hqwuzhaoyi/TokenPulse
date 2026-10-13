import CryptoKit
import Foundation
import XCTest
@testable import TokenPulse

final class GrokBotProviderTests: XCTestCase {
    private let body = #"{"hasNonZeroIncludedLimit":true,"includedLimitZero":false,"usesPooledEnterpriseAllowance":false,"usagePercent":35,"grokPlanLabel":"Grok Bot Plan","currentPeriodStart":"2026-10-01T00:00:00Z"}"#
    private let absent = #"{"hasNonZeroIncludedLimit":false,"includedLimitZero":true,"usagePercent":0,"grokPlanLabel":"Upgrade"}"#

    func testCursorNonceAndPKCEFlowCreatesOnlyGrokBotBoundCredential() async throws {
        let now = Date(timeIntervalSince1970: 100), id = UUID(), token = try jwt()
        let transport = BotTransport([(404, "{}"), (200, "{\"accessToken\":\"\(token)\",\"refreshToken\":\"unused\"}")])
        let auth = CursorAccountAuthenticator(provider: .grokBot, transport: transport, now: { now })
        let attempt = auth.begin(accountID: id)
        XCTAssertEqual(attempt.provider, .grokBot)
        let url = try XCTUnwrap(URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false))
        let parameters = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let verifier = try XCTUnwrap(attempt.codeVerifier)
        let hash = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(parameters["challenge"], hash)
        XCTAssertNil(parameters["verifier"])
        XCTAssertEqual(parameters["redirectTarget"], "sand")
        let pending = try await auth.poll(attempt)
        XCTAssertEqual(pending, .pending(retryAfter: 2))
        guard case .completed(let encoded) = try await auth.poll(attempt) else { return XCTFail("Expected auth") }
        let envelope = try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .grokBot)
        XCTAssertEqual(envelope.metadata["localAccountID"], id.uuidString)
        XCTAssertNil(envelope.refreshToken)
        XCTAssertThrowsError(try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .cursor))
        let cursor = try ProviderCredentialEnvelope.decode(CursorAccountSession.credential(accessToken: token, accountID: id, now: now), expectedProvider: .cursor)
        XCTAssertNotEqual(envelope.metadata["sourceCredentialFingerprint"], cursor.metadata["sourceCredentialFingerprint"])
        XCTAssertThrowsError(try CursorAccountSession.cookie(cursor, expectedProvider: .grokBot, accountID: id, now: now))
    }

    func testReadOnlySandEndpointCookieOriginAndIndependentWeeklyWindow() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100), transport = BotTransport([(200, body)])
        let snapshot = try await ProviderQuotaClient(provider: .grokBot, transport: transport, now: { now }).quota(for: id,
            credential: CursorAccountSession.credential(accessToken: jwt(), provider: .grokBot, accountID: id, now: now))
        XCTAssertEqual(snapshot.accountID, id)
        XCTAssertEqual(snapshot.windows.map(\.id), ["grokBot.weekly"])
        XCTAssertEqual(snapshot.windows[0].period, .weekly)
        XCTAssertEqual(snapshot.windows[0].usedPercentage, 35)
        XCTAssertNil(snapshot.windows[0].resetsAt, "currentPeriodStart cannot become +7 days or Monday")
        XCTAssertNil(snapshot.windows[0].wallet)
        let requests = await transport.requests, request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://cursor.com/api/dashboard/get-sand-usage-status")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.httpBody, Data("{}".utf8))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://cursor.com")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Cookie")?.hasPrefix("WorkosCursorSessionToken=remote%3A%3A") == true)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testConfirmedAbsentAndPooledAreSuccessfulCategoricalStatesNotFakeZeroOrUnlimited() throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let missing = try GrokBotProviderClient.snapshot(Data(absent.utf8), accountID: id, collectedAt: now)
        XCTAssertTrue(missing.windows.isEmpty)
        XCTAssertNil(missing.isNoPlan, "DevPass PAYG/no-limit wording must not be reused")
        XCTAssertNotNil(missing.quotaStatusText)
        XCTAssertNil(missing.providerPlanName, "Upgrade marketing is not the account plan")
        let pooled = try GrokBotProviderClient.snapshot(Data(#"{"usesPooledEnterpriseAllowance":true,"hasNonZeroIncludedLimit":true}"#.utf8), accountID: id, collectedAt: now)
        XCTAssertTrue(pooled.quotaStatusText?.contains("组织共享") == true)
        let account = SubscriptionAccount(id: id, name: "Grok Bot", provider: .grokBot)
        let widget = WidgetAccountSnapshot(account: account, windows: [], collectedAt: now, lastFailure: nil, quotaStatusText: missing.quotaStatusText)
        XCTAssertEqual(widget.displayMetrics[0].valueText, missing.quotaStatusText)
        XCTAssertNil(widget.displayMetrics[0].ringFraction)
    }

    func testMissingEntitlementFlagsBooleanNumbersAndAbsentUsageNeverBecomeGreenRing() throws {
        for input in ["{}", #"{"usagePercent":0}"#, #"{"includedLimitZero":false,"usesPooledEnterpriseAllowance":false,"usagePercent":0}"#, #"{"hasNonZeroIncludedLimit":1,"usagePercent":0}"#, #"{"hasNonZeroIncludedLimit":true,"includedLimitZero":true,"usagePercent":0}"#, #"{"hasNonZeroIncludedLimit":true,"usagePercent":-1}"#] {
            XCTAssertThrowsError(try GrokBotProviderClient.snapshot(Data(input.utf8), accountID: UUID(), collectedAt: Date())) { XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse) }
        }
        XCTAssertThrowsError(try GrokBotProviderClient.snapshot(Data(#"{"hasNonZeroIncludedLimit":true}"#.utf8), accountID: UUID(), collectedAt: Date())) { XCTAssertEqual($0 as? RefreshFailure, .noQuotaWindows) }
        let zero = try GrokBotProviderClient.snapshot(Data(body.replacingOccurrences(of: "usagePercent\":35", with: "usagePercent\":0").utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(zero.windows[0].usedPercentage, 0, "Actual included zero is valid")
    }

    func testReportedResetOnlyDrivesAlertsAndCachedStatusDoesNotHideOtherWindows() throws {
        let now = Date(timeIntervalSince1970: 100), id = UUID()
        let input = body.replacingOccurrences(of: "usagePercent\":35", with: "usagePercent\":95")
            .replacingOccurrences(of: "\"currentPeriodStart\"", with: "\"nextResetTimestampUtc\"")
        let snapshot = try GrokBotProviderClient.snapshot(Data(input.utf8), accountID: id, collectedAt: now)
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
        let result = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "Bot", previousSnapshot: nil, newSnapshot: snapshot, settings: .init(), ledger: .init(), now: now)
        XCTAssertEqual(result.ledger.pendingSchedules(accountID: id).count, 1)
        XCTAssertTrue(result.operations.contains { if case .deliver(let n) = $0 { return n.kind == .quotaAlert }; return false })
        let widget = WidgetAccountSnapshot(account: SubscriptionAccount(id: id, name: "Bot", provider: .grokBot), windows: snapshot.windows, collectedAt: now,
            lastFailure: nil, quotaStatusText: "Static note")
        XCTAssertNotNil(widget.displayMetrics.first?.window)
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        XCTAssertNotNil(DemoMode.accounts().first { $0.provider == .grokBot })
        XCTAssertNotEqual(Provider.grokBot.iconAssetName, Provider.superGrok.iconAssetName)
    }

    func testWrongProviderAccountOrExpiredCredentialsStopBeforeNetworking() async throws {
        let now = Date(timeIntervalSince1970: 100), id = UUID(), transport = BotTransport([])
        let client = ProviderQuotaClient(provider: .grokBot, transport: transport, now: { now })
        let cursor = try CursorAccountSession.credential(accessToken: jwt(), accountID: id, now: now)
        do { _ = try await client.quota(for: id, credential: cursor); XCTFail("Cursor service credential is not Bot credential") }
        catch { XCTAssertEqual(error as? ProviderIntegrationError, .invalidCredentialData) }
        let bot = try CursorAccountSession.credential(accessToken: jwt(), provider: .grokBot, accountID: id, now: now)
        do { _ = try await client.quota(for: UUID(), credential: bot); XCTFail("Wrong UUID") }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let expired = ProviderQuotaClient(provider: .grokBot, transport: transport, now: { Date(timeIntervalSince1970: 20_000) })
        do { _ = try await expired.quota(for: id, credential: bot); XCTFail("Expired") }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    @MainActor
    func testAccountRestoreConfirmedAbsenceClearsOldQuotaReauthorizeAndDelete() async throws {
        let store = BotStore(), now = Date(timeIntervalSince1970: 100), id = UUID(), otherID = UUID()
        let transport = BotTransport([(200, body), (200, body), (401, "{}"), (200, absent), (200, body)])
        let client = ProviderQuotaClient(provider: .grokBot, transport: transport, now: { now })
        let monitor = QuotaMonitor(accountStore: store, credentialStore: store, quotaClient: client)
        await monitor.start(refresh: false)
        await monitor.addAccount(name: "First", credential: try CursorAccountSession.credential(accessToken: jwt(), provider: .grokBot, accountID: id, now: now), provider: .grokBot, accountID: id)
        await monitor.addAccount(name: "Second", credential: try CursorAccountSession.credential(accessToken: jwt(), provider: .grokBot, accountID: otherID, now: now), provider: .grokBot, accountID: otherID)
        let previous = try XCTUnwrap(monitor.states.first?.snapshot), other = try XCTUnwrap(monitor.states.last)
        let restored = QuotaMonitor(accountStore: store, credentialStore: store, quotaClient: client)
        await restored.start(refresh: false)
        XCTAssertEqual(restored.states, monitor.states)
        await restored.refresh(accountID: id)
        XCTAssertEqual(restored.states[0].snapshot, previous)
        await restored.refresh(accountID: id)
        XCTAssertTrue(restored.states[0].snapshot?.windows.isEmpty == true)
        XCTAssertNotNil(restored.states[0].snapshot?.quotaStatusText)
        XCTAssertNil(restored.states[0].lastFailure)
        await restored.replaceCredential(try CursorAccountSession.credential(accessToken: jwt(subject: "workos|other"), provider: .grokBot, accountID: id, now: now), accountID: id)
        XCTAssertNotNil(restored.states[0].snapshot?.windows.first)
        XCTAssertEqual(restored.states[1], other)
        let deleted = await restored.deleteAccount(accountID: id)
        XCTAssertTrue(deleted)
        let value = await store.credential(for: id)
        XCTAssertNil(value)
    }
    private func jwt(subject: String = "workos|remote") throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["sub": subject, "exp": 10_000])
        let payload = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "header.\(payload).signature"
    }
}
private actor BotTransport: ProviderTransport {
    private var replies: [(Int, String)]; private(set) var requests: [URLRequest] = []
    init(_ replies: [(Int, String)]) { self.replies = replies }
    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request); guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let (status, body) = replies.removeFirst(); return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
private actor BotStore: AccountStateStoring, CredentialStoring {
    private var states: [AccountQuotaState] = [], values: [UUID: String] = [:]
    func load() -> [AccountQuotaState] { states }; func save(_ states: [AccountQuotaState]) { self.states = states }
    func save(_ value: String, for accountID: UUID) { values[accountID] = value }; func credential(for accountID: UUID) -> String? { values[accountID] }
    func deleteCredential(for accountID: UUID) { values[accountID] = nil }
}
