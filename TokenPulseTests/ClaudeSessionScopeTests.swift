import Foundation
import XCTest
@testable import TokenPulse

final class ClaudeSessionScopeTests: XCTestCase {
    private let fixture = #"{"five_hour":{"utilization":25,"resets_at":"2026-10-03T00:00:00Z"},"seven_day":{"utilization":50,"resets_at":"2026-10-08T00:00:00Z"}}"#
    private func legacy(token: String = "fixture-one", organization: String = "org-one") -> ProviderCredentialEnvelope {
        ProviderCredentialEnvelope(provider: .claude, kind: .session, accessToken: "sessionKeyV3=\(token)",
                                   metadata: ["cookieFormat": "restrictedHeader", "organizationID": organization])
    }

    func testNewLoginCredentialsBindAccountAndSeparateOrganizationAndActualSession() throws {
        let id = UUID()
        let first = try ClaudeWebSession.credential(accountID: id, cookieHeader: "sessionKeyV3=fixture-one", organizationID: "org-one")
        XCTAssertEqual(first.metadata["localAccountID"], id.uuidString)
        XCTAssertEqual(first.metadata["origin"], "https://claude.ai")
        XCTAssertEqual(first.metadata["webSessionFormat"], "v1")
        XCTAssertEqual(first.sourceCredentialIdentity, first.metadata["sourceCredentialFingerprint"])
        let anotherAccount = try ClaudeWebSession.credential(accountID: UUID(), cookieHeader: first.accessToken, organizationID: "org-one")
        let anotherOrg = try ClaudeWebSession.credential(accountID: id, cookieHeader: first.accessToken, organizationID: "org-two")
        let anotherToken = try ClaudeWebSession.credential(accountID: id, cookieHeader: "sessionKeyV3=fixture-two", organizationID: "org-one")
        XCTAssertNotEqual(first.sourceCredentialIdentity, anotherAccount.sourceCredentialIdentity)
        XCTAssertNotEqual(first.sourceCredentialIdentity, anotherOrg.sourceCredentialIdentity)
        XCTAssertNotEqual(first.sourceCredentialIdentity, anotherToken.sourceCredentialIdentity)
    }

    func testLegacyIdentityIsStableFromActualCookiesAndOrgWithoutInventingLocalUUID() async throws {
        let original = legacy()
        XCTAssertNil(original.metadata["localAccountID"])
        XCTAssertNil(original.metadata["webSessionFormat"])
        XCTAssertNotNil(original.sourceCredentialIdentity)
        var forged = original
        forged.metadata["sourceCredentialFingerprint"] = "someone-elses-fingerprint"
        XCTAssertEqual(original.sourceCredentialIdentity, forged.sourceCredentialIdentity)
        XCTAssertNotEqual(original.sourceCredentialIdentity, legacy(token: "different").sourceCredentialIdentity)
        XCTAssertNotEqual(original.sourceCredentialIdentity, legacy(organization: "org-two").sourceCredentialIdentity)
        let decoded = try ProviderCredentialEnvelope.decode(original.encoded(), expectedProvider: .claude)
        XCTAssertEqual(original.sourceCredentialIdentity, decoded.sourceCredentialIdentity)
        let transport = ClaudeScopeTransport([.response(200, fixture)])
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let result = try await ProviderQuotaClient(provider: .claude, transport: transport, now: { now })
            .quotaResult(for: id, credential: original.encoded())
        XCTAssertEqual(result.snapshot.accountID, id)
        XCTAssertEqual(result.snapshot.sourceCredentialFingerprint, original.sourceCredentialIdentity)
        XCTAssertNil(result.updatedCredential) // No mid-query v1 migration can change monitor's latest-credential identity.
        XCTAssertNil(original.metadata["localAccountID"])
    }

    func testEquivalentLegacyCookieOrderHasSameActualIdentity() {
        var first = legacy(), second = legacy()
        first.accessToken = "sessionKeyV3=fixture-v3; sessionKey=fixture-v1"
        second.accessToken = "sessionKey=fixture-v1; sessionKeyV3=fixture-v3"
        XCTAssertNotNil(first.sourceCredentialIdentity)
        XCTAssertEqual(first.sourceCredentialIdentity, second.sourceCredentialIdentity)
    }

    func testDirectClientRejectsWrongProviderBoundAccountExpiryCookiesAndUnsafeOrganizationBeforeRequest() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let scoped = try ClaudeWebSession.credential(accountID: id, cookieHeader: "sessionKeyV3=fixture", organizationID: "org-one")
        let transport = ClaudeScopeTransport([])
        let client = ClaudeProviderClient(transport: transport, now: { now })
        var wrong = scoped; wrong.metadata["localAccountID"] = UUID().uuidString
        var expired = legacy(); expired.expiresAt = now
        var tracking = legacy(); tracking.accessToken += "; analytics=private"
        var injected = legacy(); injected.accessToken += "\r\nInjected: value"
        var traversal = legacy(); traversal.metadata["organizationID"] = "../other"
        var path = legacy(); path.metadata["organizationID"] = "org-one/usage?other=1"
        let wrongProvider = ProviderCredentialEnvelope(provider: .cursor, kind: .session, accessToken: scoped.accessToken, metadata: scoped.metadata)
        let wrongKind = ProviderCredentialEnvelope(provider: .claude, kind: .apiKey, accessToken: scoped.accessToken, metadata: scoped.metadata)
        for candidate in [wrong, expired, tracking, injected, traversal, path, wrongProvider, wrongKind] {
            do { _ = try await client.quota(accountID: id, credential: candidate); XCTFail("Invalid session must not be queried") }
            catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    @MainActor
    func testLegacyFirstRefreshBindsItsActualIdentityAndDoesNotFailNewOldFingerprintComparison() async throws {
        let store = ClaudeScopeMemory()
        let credential = try legacy().encoded()
        let transport = ClaudeScopeTransport([.response(200, fixture)])
        let monitor = QuotaMonitor(accountStore: store, credentialStore: store,
            quotaClient: ProviderQuotaClient(provider: .claude, transport: transport))
        await monitor.start(refresh: false)
        await monitor.addAccount(name: "Legacy Claude", credential: credential, provider: .claude)
        let state = try XCTUnwrap(monitor.states.first)
        XCTAssertNotNil(state.snapshot)
        XCTAssertNil(state.lastFailure)
        XCTAssertEqual(state.credentialIdentity, legacy().sourceCredentialIdentity)
        XCTAssertEqual(state.snapshot?.sourceCredentialFingerprint, state.credentialIdentity)
        XCTAssertEqual(monitor.configuration(for: state.id)?.credentialIdentity, state.credentialIdentity)
        let stillLegacy = await store.credential(for: state.id)
        XCTAssertEqual(stillLegacy, credential)
    }

    @MainActor
    func testRebindingFailedNewOrganizationClearsOldQuotaAndRejectsLaterOldScopedSync() async throws {
        let store = ClaudeScopeMemory()
        let id = UUID()
        let original = try legacy().encoded()
        let transport = ClaudeScopeTransport([.response(200, fixture), .failure])
        let monitor = QuotaMonitor(accountStore: store, credentialStore: store,
            quotaClient: ProviderQuotaClient(provider: .claude, transport: transport))
        await monitor.start(refresh: false)
        await monitor.addAccount(name: "Claude", credential: original, provider: .claude, accountID: id)
        var oldState = try XCTUnwrap(monitor.states.first)
        var oldConfig = try XCTUnwrap(monitor.configuration(for: id))
        let replacement = try ClaudeWebSession.credential(accountID: id, cookieHeader: "sessionKeyV3=fixture-new", organizationID: "org-two")
        await monitor.replaceCredential(try replacement.encoded(), accountID: id)
        XCTAssertNil(monitor.states[0].snapshot)
        XCTAssertEqual(monitor.states[0].lastFailure, .network)
        XCTAssertEqual(monitor.states[0].credentialIdentity, replacement.sourceCredentialIdentity)
        oldState.snapshot = QuotaSnapshot(accountID: id, windows: oldState.snapshot!.windows, collectedAt: .distantFuture,
                                         sourceCredentialFingerprint: oldState.credentialIdentity)
        oldConfig.modifiedAt = .distantPast
        await monitor.mergeSynchronized(configurations: [oldConfig], states: [oldState])
        XCTAssertNil(monitor.states[0].snapshot)
    }

    func testNewBoundSessionRequestReturnsMatchingSourceAndKeepsCookieAllowlist() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let credential = try ClaudeWebSession.credential(accountID: id, cookieHeader: "sessionKeyV3=fixture-v3; sessionKey=fixture-v1", organizationID: "org-one")
        let transport = ClaudeScopeTransport([.response(200, fixture)])
        let result = try await ProviderQuotaClient(provider: .claude, transport: transport, now: { now }).quotaResult(for: id, credential: credential.encoded())
        XCTAssertEqual(result.snapshot.sourceCredentialFingerprint, credential.sourceCredentialIdentity)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://claude.ai/api/organizations/org-one/usage")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "sessionKey=fixture-v1; sessionKeyV3=fixture-v3")
        XCTAssertFalse(request.httpShouldHandleCookies)
    }
}

private actor ClaudeScopeTransport: ProviderTransport {
    enum Reply: Sendable { case response(Int, String), failure }
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.timedOut) }
        switch replies.removeFirst() {
        case .failure: throw URLError(.timedOut)
        case .response(let status, let body): return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}
private actor ClaudeScopeMemory: AccountStateStoring, CredentialStoring {
    private var states: [AccountQuotaState] = []
    private var credentials: [UUID: String] = [:]
    func load() -> [AccountQuotaState] { states }
    func save(_ states: [AccountQuotaState]) { self.states = states }
    func save(_ credential: String, for accountID: UUID) { credentials[accountID] = credential }
    func credential(for accountID: UUID) -> String? { credentials[accountID] }
    func deleteCredential(for accountID: UUID) { credentials[accountID] = nil }
}
