import Foundation
import Security
import XCTest
@testable import TokenPulse

final class NousPortalTests: XCTestCase {
    private let account = #"{"user":{"privy_did":"did:privy:alice"},"organisation":{"id":"org-a"},"subscription":{"plan":"Starter","monthly_credits":100,"credits_remaining":75,"current_period_end":"2026-11-01T00:00:00Z"},"purchased_credits_remaining":20,"paid_service_access":{"organisation_id":"org-a","subscription_credits_remaining":75,"purchased_credits_remaining":20,"total_usable_credits":95,"allowed":true}}"#
    private let tokens = #"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600,"token_type":"Bearer","scope":"inference:invoke"}"#
    private func deviceCode(_ code: String = UUID().uuidString) -> String {
        "{\"device_code\":\"\(code)\",\"user_code\":\"ABCD-EFGH\",\"verification_uri\":\"https://portal.nousresearch.com/device\",\"verification_uri_complete\":\"https://portal.nousresearch.com/device?user_code=ABCD-EFGH\",\"expires_in\":600,\"interval\":2}"
    }
    private func credential(_ id: UUID, device: String, access: String = "old-access", refresh: String = "old-refresh",
                            expiry: Double = 110, state: String = "active", subject: String = "did:privy:alice") throws -> ProviderCredentialEnvelope {
        var value = ProviderCredentialEnvelope(provider: .nousPortal, kind: .oauth, accessToken: access,
            refreshToken: refresh, expiresAt: Date(timeIntervalSince1970: expiry), accountID: subject,
            metadata: ["nousSessionFormat":"device-v1", "portal":NousPortalCredential.portal, "clientID":NousPortalCredential.clientID,
                       "credentialDistribution":"deviceLocal", "localAccountID":id.uuidString, "ownerDeviceID":device,
                       "organizationID":"org-a", "rotationState":state, "issuedTTL":"3600", "chainID":UUID().uuidString])
        value.metadata["sourceCredentialFingerprint"] = try NousPortalCredential.fingerprint(value)
        return value
    }

    func testActualControllerDeviceFlowUsesPublicClientAndVerifiesAccountBeforeCompletion() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let transport = NousTransport([.response(200, deviceCode()), .response(400, #"{"error":"authorization_pending"}"#),
            .response(400, #"{"error":"slow_down"}"#), .response(200, tokens), .response(200, account)])
        let controller = ProviderAuthenticationController(transport: transport, now: { now })
        XCTAssertEqual(controller.loginConfiguration(for: .nousPortal).method, .deviceCode)
        let session = try await controller.beginLogin(provider: .nousPortal, accountID: id)
        XCTAssertEqual(session.userCode, "ABCD-EFGH")
        XCTAssertEqual(session.metadata["localAccountID"], id.uuidString)
        XCTAssertEqual(session.expiresAt, Date(timeIntervalSince1970: 700))
        let pending = try await controller.continueLogin(session)
        let slower = try await controller.continueLogin(session)
        XCTAssertEqual(pending, .pending(retryAfter: 2))
        XCTAssertEqual(slower, .pending(retryAfter: 7))
        guard case .completed(let encoded) = try await controller.continueLogin(session) else { return XCTFail("Expected approved grant") }
        let result = try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .nousPortal)
        XCTAssertEqual(result.accountID, "did:privy:alice")
        XCTAssertEqual(result.metadata["organizationID"], "org-a")
        XCTAssertEqual(result.metadata["ownerDeviceID"], DeviceOAuthIdentity.id)
        XCTAssertEqual(result.refreshToken, "new-refresh")
        let requests = await transport.requests
        XCTAssertEqual(requests[0].url?.path, "/api/oauth/device/code")
        let form = String(data: requests[0].httpBody!, encoding: .utf8)!
        XCTAssertTrue(form.contains("client_id=hermes-cli"))
        XCTAssertTrue(form.contains("scope=inference%3Ainvoke"))
        XCTAssertEqual(requests.last?.url?.path, "/api/oauth/account")
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
    }

    func testDeviceCodeWAFIsRateLimitedRatherThanInvalidCredential() async throws {
        let transport = NousTransport([.response(403, "challenge", ["x-vercel-mitigated":"deny"])])
        do { _ = try await ProviderAuthenticationController(transport: transport).beginLogin(provider: .nousPortal, accountID: UUID()); XCTFail("Edge challenge") }
        catch { XCTAssertEqual(error as? ProviderIntegrationError, .rateLimited) }
    }

    func testApprovedGrantRetriesOnlyAccountGETAndNeverReturnsUnverifiedIdentity() async throws {
        let now = Date(timeIntervalSince1970: 100)
        for succeeds in [true, false] {
            let replies: [NousTransport.Reply] = [.response(200, deviceCode()), .response(200, tokens), .failure,
                .response(503, "{}"), .response(succeeds ? 200 : 503, succeeds ? account : "{}")]
            let transport = NousTransport(replies)
            let controller = ProviderAuthenticationController(transport: transport, now: { now })
            let session = try await controller.beginLogin(provider: .nousPortal, accountID: UUID())
            do {
                let progress = try await controller.continueLogin(session)
                XCTAssertTrue(succeeds)
                guard case .completed(let raw) = progress else { return XCTFail("Expected verified completion") }
                let envelope = try ProviderCredentialEnvelope.decode(raw, expectedProvider: .nousPortal)
                XCTAssertEqual(envelope.accountID, "did:privy:alice")
            } catch { XCTAssertFalse(succeeds); XCTAssertEqual(error as? ProviderIntegrationError, .loginExpired) }
            do { _ = try await controller.continueLogin(session); XCTFail("Consumed code must not be posted again") }
            catch { XCTAssertEqual(error as? ProviderIntegrationError, .loginExpired) }
            let requests = await transport.requests
            XCTAssertEqual(requests.filter { $0.url?.path == "/api/oauth/token" }.count, 1)
            XCTAssertEqual(requests.filter { $0.url?.path == "/api/oauth/account" }.count, 3)
            XCTAssertTrue(requests.filter { $0.url?.path == "/api/oauth/account" }.allSatisfy { $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer new-access" })
        }
    }

    @MainActor
    func testPhonePostGrantVerificationFailureStartsFreshAuthorizationOnNextAttempt() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let transport = NousTransport([.response(200, deviceCode()), .response(200, tokens),
            .response(503, "{}"), .response(503, "{}"), .response(503, "{}"),
            .response(200, deviceCode()), .response(200, tokens), .response(200, account)])
        let model = DeviceLoginModel(controller: ProviderAuthenticationController(transport: transport, now: { now }), sleep: { _ in })
        var completions = 0
        await model.authorize(provider: .nousPortal, accountID: id) { _ in completions += 1 }
        XCTAssertNil(model.session)
        XCTAssertEqual(completions, 0)
        await model.authorize(provider: .nousPortal, accountID: id) { _ in completions += 1 }
        XCTAssertEqual(completions, 1)
        let requests = await transport.requests
        XCTAssertEqual(requests.filter { $0.url?.path == "/api/oauth/device/code" }.count, 2)
        XCTAssertEqual(requests.filter { $0.url?.path == "/api/oauth/token" }.count, 2)
    }

    func testIndependentDeviceChainsAndRotationKeepSameVerifiedLogicalScope() throws {
        let id = UUID()
        let phone = try credential(id, device: "phone")
        let watch = try credential(id, device: "watch", access: "watch-access", refresh: "watch-refresh")
        XCTAssertEqual(phone.sourceCredentialIdentity, watch.sourceCredentialIdentity)
        let changed = try credential(id, device: "phone", subject: "did:privy:bob")
        XCTAssertNotEqual(phone.sourceCredentialIdentity, changed.sourceCredentialIdentity)
        XCTAssertThrowsError(try NousPortalCredential.validateLocal(phone, accountID: id, deviceID: "watch"))
        XCTAssertThrowsError(try NousPortalCredential.validateLocal(phone, accountID: UUID(), deviceID: "phone"))
    }

    func testRouterNeverSynchronizesNousSecretIncludingWrongProviderContext() async throws {
        let id = UUID(), synced = NousSpyCredentials()
        let vault = DeviceOAuthCredentialVault(records: NousMemoryRecords(), deviceID: "phone")
        let router = ProviderScopedCredentialStore(synchronized: synced, deviceOAuthVault: vault)
        let value = try credential(id, device: "phone").encoded()
        try await router.save(value, for: id, provider: .nousPortal)
        let local = try await router.credential(for: id, provider: .nousPortal)
        XCTAssertEqual(local, value)
        for provider in [Provider.codex, .claude, .miniMaxChina] {
            do { try await router.save(value, for: id, provider: provider); XCTFail("Must not demote a Nous secret to synced") }
            catch { XCTAssertEqual(error as? ProviderIntegrationError, .invalidCredentialData) }
        }
        let writes = await synced.writes, reads = await synced.reads
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(reads, 0)
        let query = KeychainDeviceOAuthRecords(service: "fixture-device-service").query(id)
        XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
        try await router.deleteCredential(for: id, provider: .nousPortal)
        let gone = try await router.credential(for: id, provider: .nousPortal)
        XCTAssertNil(gone)
    }

    func testVaultGenerationTombstonePreventsABAAfterDeleteAndReimport() async throws {
        let id = UUID(), vault = DeviceOAuthCredentialVault(records: NousMemoryRecords(), deviceID: "phone")
        try await vault.save("same-payload", for: id)
        let before = try await vault.version(for: id)
        try await vault.delete(for: id)
        try await vault.save("same-payload", for: id)
        let rejected = try await vault.compareAndSwap(expectedGeneration: before.generation, credential: "late-result", for: id)
        XCTAssertNil(rejected)
        let current = try await vault.version(for: id)
        XCTAssertEqual(current.credential, "same-payload")
        XCTAssertGreaterThan(current.generation, before.generation)
    }

    func testRefreshHeaderRotationIsPersistedBeforeQuotaFailure() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let vault = DeviceOAuthCredentialVault(records: NousMemoryRecords(), deviceID: "phone")
        try await vault.save(credential(id, device: "phone").encoded(), for: id)
        let transport = NousTransport([.response(200, tokens), .response(500, "{}")])
        do { _ = try await NousSessionCoordinator().quota(accountID: id, vault: vault, transport: transport, now: { now }); XCTFail("Quota failed") }
        catch { XCTAssertEqual(error as? RefreshFailure, .server) }
        let version = try await vault.version(for: id)
        let saved = try ProviderCredentialEnvelope.decode(XCTUnwrap(version.credential), expectedProvider: .nousPortal)
        XCTAssertEqual(saved.refreshToken, "new-refresh")
        XCTAssertEqual(saved.metadata["rotationState"], "active")
        let requests = await transport.requests
        XCTAssertEqual(requests[0].url?.path, "/api/oauth/token")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "x-nous-refresh-token"), "old-refresh")
        let form = String(data: requests[0].httpBody!, encoding: .utf8)!
        XCTAssertTrue(form.contains("grant_type=refresh_token"))
        XCTAssertFalse(form.contains("old-refresh"))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
    }

    func testAmbiguousRefreshPersistsUncertainAndNeverReplaysOnRestart() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let records = NousMemoryRecords()
        let vault = DeviceOAuthCredentialVault(records: records, deviceID: "phone")
        try await vault.save(credential(id, device: "phone").encoded(), for: id)
        let transport = NousTransport([.failure, .response(200, account)])
        do { _ = try await NousSessionCoordinator().quota(accountID: id, vault: vault, transport: transport, now: { now }); XCTFail("Unknown result") }
        catch { XCTAssertEqual(error as? RefreshFailure, .network) }
        let saved = try await vault.version(for: id)
        XCTAssertEqual(try ProviderCredentialEnvelope.decode(XCTUnwrap(saved.credential), expectedProvider: .nousPortal).metadata["rotationState"], "uncertain")
        let restarted = DeviceOAuthCredentialVault(records: records, deviceID: "phone")
        _ = try await NousSessionCoordinator().quota(accountID: id, vault: restarted, transport: transport, now: { now })
        let expired = Date(timeIntervalSince1970: 200)
        do { _ = try await NousSessionCoordinator().quota(accountID: id, vault: restarted, transport: transport, now: { expired }); XCTFail("Needs new authorization") }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let terminal = try await restarted.version(for: id)
        let terminalEnvelope = try ProviderCredentialEnvelope.decode(XCTUnwrap(terminal.credential), expectedProvider: .nousPortal)
        XCTAssertEqual(terminalEnvelope.metadata["rotationState"], "terminal")
        XCTAssertNil(terminalEnvelope.refreshToken)
        XCTAssertGreaterThan(terminal.generation, saved.generation)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/oauth/token", "/api/oauth/account"])
    }

    func testPersistedPendingOnlyUsesStillValidAccessAndNotItsOldRefresh() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let vault = DeviceOAuthCredentialVault(records: NousMemoryRecords(), deviceID: "phone")
        try await vault.save(credential(id, device: "phone", expiry: 110, state: "pending").encoded(), for: id)
        let transport = NousTransport([.response(200, account)])
        _ = try await NousSessionCoordinator().quota(accountID: id, vault: vault, transport: transport, now: { now })
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].httpMethod, "GET")
    }

    func testExpiredPendingChainClearsRefreshWithGenerationCASWithoutHTTP() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 200)
        let vault = DeviceOAuthCredentialVault(records: NousMemoryRecords(), deviceID: "phone")
        try await vault.save(credential(id, device: "phone", state: "pending").encoded(), for: id)
        let before = try await vault.version(for: id)
        let transport = NousTransport([])
        do { _ = try await NousSessionCoordinator().quota(accountID: id, vault: vault, transport: transport, now: { now }); XCTFail("Expired chain") }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let after = try await vault.version(for: id)
        let envelope = try ProviderCredentialEnvelope.decode(XCTUnwrap(after.credential), expectedProvider: .nousPortal)
        XCTAssertEqual(after.generation, before.generation + 1)
        XCTAssertNil(envelope.refreshToken)
        XCTAssertEqual(envelope.metadata["rotationState"], "terminal")
        let rejected = try await vault.compareAndSwap(expectedGeneration: before.generation, credential: before.credential, for: id)
        XCTAssertNil(rejected)
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testWAFRejectionDoesNotClearOrConsumeTheCredential() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let vault = DeviceOAuthCredentialVault(records: NousMemoryRecords(), deviceID: "phone")
        try await vault.save(credential(id, device: "phone").encoded(), for: id)
        let transport = NousTransport([.response(403, "challenge", ["x-vercel-mitigated":"deny"])])
        do { _ = try await NousSessionCoordinator().quota(accountID: id, vault: vault, transport: transport, now: { now }); XCTFail("WAF rejected") }
        catch { XCTAssertEqual(error as? RefreshFailure, .rateLimited) }
        let saved = try await vault.version(for: id)
        let envelope = try ProviderCredentialEnvelope.decode(XCTUnwrap(saved.credential), expectedProvider: .nousPortal)
        XCTAssertEqual(envelope.refreshToken, "old-refresh")
        XCTAssertEqual(envelope.metadata["rotationState"], "active")
    }

    func testTerminalReuseCannotReplayRefreshOrQueryTheRevokedChain() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let vault = DeviceOAuthCredentialVault(records: NousMemoryRecords(), deviceID: "phone")
        try await vault.save(credential(id, device: "phone").encoded(), for: id)
        let transport = NousTransport([.response(400, #"{"error":"refresh_token_reused"}"#)])
        let owner = NousSessionCoordinator()
        for _ in 0..<2 {
            do { _ = try await owner.quota(accountID: id, vault: vault, transport: transport, now: { now }); XCTFail("Reauthorization required") }
            catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        }
        let saved = try await vault.version(for: id)
        let envelope = try ProviderCredentialEnvelope.decode(XCTUnwrap(saved.credential), expectedProvider: .nousPortal)
        XCTAssertNil(envelope.refreshToken)
        XCTAssertEqual(envelope.metadata["rotationState"], "terminal")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testLateRefreshSuccessAndErrorCannotOverwriteReauthorizationOrDeletion() async throws {
        for error in [false, true] {
            for deleted in [false, true] {
                let id = UUID(), now = Date(timeIntervalSince1970: 100)
                let vault = DeviceOAuthCredentialVault(records: NousMemoryRecords(), deviceID: "phone")
                try await vault.save(credential(id, device: "phone").encoded(), for: id)
                let transport = NousHeldTransport(path: "/api/oauth/token")
                let owner = NousSessionCoordinator()
                let task = Task { try await owner.quota(accountID: id, vault: vault, transport: transport, now: { now }) }
                await transport.waitForRequest()
                let pending = try await vault.version(for: id)
                XCTAssertEqual(try ProviderCredentialEnvelope.decode(XCTUnwrap(pending.credential), expectedProvider: .nousPortal).metadata["rotationState"], "pending")
                if deleted { try await vault.delete(for: id) }
                let replacement = try credential(id, device: "phone", access: "relogin-access", refresh: "relogin-refresh", expiry: 5000).encoded()
                try await vault.save(replacement, for: id)
                await transport.release(status: error ? 401 : 200, json: error ? #"{"error":"invalid_grant"}"# : tokens)
                do { _ = try await task.value; XCTFail("Late result must be discarded") }
                catch { XCTAssertTrue(error is CancellationError) }
                let latest = try await vault.version(for: id)
                XCTAssertEqual(latest.credential, replacement)
            }
        }
    }

    func testLateAccount401CannotQuarantineAReplacementChain() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let vault = DeviceOAuthCredentialVault(records: NousMemoryRecords(), deviceID: "phone")
        try await vault.save(credential(id, device: "phone", expiry: 5000).encoded(), for: id)
        let transport = NousHeldTransport(path: "/api/oauth/account")
        let task = Task { try await NousSessionCoordinator().quota(accountID: id, vault: vault, transport: transport, now: { now }) }
        await transport.waitForRequest()
        let replacement = try credential(id, device: "phone", access: "replacement", refresh: "replacement-refresh", expiry: 5000).encoded()
        try await vault.save(replacement, for: id)
        await transport.release(status: 401, json: "{}")
        do { _ = try await task.value; XCTFail("Old 401") } catch { XCTAssertTrue(error is CancellationError) }
        let latest = try await vault.version(for: id)
        XCTAssertEqual(latest.credential, replacement)
    }

    func testEveryAccountReplyVerifiesActualUserAndConsistentOrganization() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let transport = NousTransport([.response(200, account.replacingOccurrences(of: "did:privy:alice", with: "did:privy:bob"))])
        let value = try credential(id, device: "phone", expiry: 5000)
        do { _ = try await NousPortalProviderClient(transport: transport, now: { now }, deviceID: "phone").quota(accountID: id, credential: value); XCTFail("Wrong server subject") }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let conflicting = account.replacingOccurrences(of: #""organisation_id":"org-a""#, with: #""organisation_id":"org-b""#)
        XCTAssertThrowsError(try NousPortalProviderClient.remoteIdentity(Data(conflicting.utf8))) {
            XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
        }
        XCTAssertThrowsError(try NousPortalProviderClient.snapshot(Data(conflicting.utf8), accountID: id, collectedAt: now))
    }

    func testCreditsNeverBecomeMoneyOrDoubleCountedPoolsAndMissingCountsRemainUnknown() throws {
        let snapshot = try NousPortalProviderClient.snapshot(Data(account.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(snapshot.windows.map(\.id), ["nous.subscription", "nous.purchased", "nous.total"])
        XCTAssertEqual(snapshot.windows[0].exactCounts?.used, 25)
        XCTAssertEqual(snapshot.windows[0].exactCounts?.remaining, 75)
        XCTAssertEqual(snapshot.windows[1].exactCounts?.remaining, 20)
        XCTAssertNil(snapshot.windows[1].usedPercentage)
        XCTAssertEqual(snapshot.windows[2].wallet?.total, 95)
        XCTAssertEqual(snapshot.windows[2].wallet?.isMonetary, false)
        let partial = try NousPortalProviderClient.snapshot(Data(#"{"subscription":{"monthly_credits":100}}"#.utf8), accountID: UUID(), collectedAt: Date())
        XCTAssertNil(partial.windows[0].usedPercentage)
        XCTAssertNil(partial.windows[0].exactCounts?.remaining)
        XCTAssertNil(partial.windows[0].resetsAt)
        XCTAssertNil(partial.windows[0].resetSemantics)
        XCTAssertEqual(partial.windows[0].period, .monthly)
        for raw in [#"{"purchased_credits_remaining":true}"#, #"{"purchased_credits_remaining":"nan"}"#, #"{}"#] {
            XCTAssertThrowsError(try NousPortalProviderClient.snapshot(Data(raw.utf8), accountID: UUID(), collectedAt: Date()))
        }
    }

    func testRolloverUnrepresentableDifferenceAndExplicitZeroPartialAmountsRemainKnown() throws {
        for raw in [#"{"subscription":{"monthly_credits":100,"credits_remaining":150}}"#,
                    #"{"subscription":{"monthly_credits":"100000000000000000","credits_remaining":"0.0000000000000000000001"}}"#] {
            let snapshot = try NousPortalProviderClient.snapshot(Data(raw.utf8), accountID: UUID(), collectedAt: Date())
            XCTAssertNil(snapshot.windows[0].exactCounts?.used)
            XCTAssertNil(snapshot.windows[0].usedPercentage)
            XCTAssertNotNil(snapshot.windows[0].exactCounts?.remaining)
            XCTAssertNotNil(snapshot.windows[0].exactCounts?.total)
        }
        for (raw, remaining) in [(#"{"subscription":{"credits_remaining":0}}"#, true),
                                 (#"{"subscription":{"monthly_credits":0}}"#, false)] {
            let window = try XCTUnwrap(NousPortalProviderClient.snapshot(Data(raw.utf8), accountID: UUID(), collectedAt: Date()).windows.first)
            XCTAssertEqual(remaining ? window.exactCounts?.remaining : window.exactCounts?.total, 0)
            XCTAssertNil(remaining ? window.exactCounts?.total : window.exactCounts?.remaining)
            XCTAssertNil(window.usedPercentage)
            XCTAssertNil(window.isExhausted)
            XCTAssertNil(window.resetsAt)
            XCTAssertNil(window.resetSemantics)
        }
    }

    func testActualAccountQuotaClientUsesScopedVaultAndDoesNotDoubleSaveRotatedTokens() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let vault = DeviceOAuthCredentialVault(records: NousMemoryRecords(), deviceID: "phone")
        let synced = NousSpyCredentials()
        let router = ProviderScopedCredentialStore(synchronized: synced, deviceOAuthVault: vault)
        let initial = try credential(id, device: "phone").encoded()
        try await router.save(initial, for: id, provider: .nousPortal)
        let transport = NousTransport([.response(200, tokens), .response(200, account)])
        let snapshot = try await AccountQuotaClient(provider: .nousPortal, credentialStore: router, transport: transport, now: { now })
            .quota(for: id, credential: initial)
        XCTAssertEqual(snapshot.accountID, id)
        let latest = try await vault.version(for: id)
        XCTAssertEqual(latest.generation, 3) // initial save, pending reservation, rotated result; no generic extra save.
        let writes = await synced.writes
        XCTAssertEqual(writes, 0)
    }

    @MainActor
    func testWatchModelRejectsDifferentRemoteScopeAndCancellationDoesNotCompleteOrQueryAfterPoll() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let transport = NousTransport([.response(200, deviceCode()), .response(200, tokens), .response(200, account)])
        let model = NousDeviceLoginModel(controller: ProviderAuthenticationController(transport: transport, now: { now }), sleep: { _ in })
        var callbacks = 0
        let task = model.start(accountID: id, expectedIdentity: "another-user-scope") { _ in callbacks += 1 }
        await task.value
        XCTAssertEqual(callbacks, 0)
        XCTAssertNotNil(model.message)
        let held = NousHeldTransport(path: "/api/oauth/token", immediate: [.response(200, deviceCode())])
        let cancelled = NousDeviceLoginModel(controller: ProviderAuthenticationController(transport: held, now: { now }), sleep: { _ in })
        let work = cancelled.start(accountID: id, expectedIdentity: "unused") { _ in callbacks += 1 }
        await held.waitForRequest()
        cancelled.cancel()
        await held.release(status: 200, json: tokens)
        await work.value
        XCTAssertEqual(callbacks, 0)
        let requests = await held.requests
        XCTAssertFalse(requests.contains { $0.url?.path == "/api/oauth/account" })
    }

    @MainActor
    func testWatchGrantCannotReplaceAfterPhoneChangesTheConfiguredBinding() async throws {
        let id = UUID()
        let synced = NousSpyCredentials()
        let vault = DeviceOAuthCredentialVault(records: NousMemoryRecords(), deviceID: "watch")
        let router = ProviderScopedCredentialStore(synchronized: synced, deviceOAuthVault: vault)
        let states = NousMemoryAccountState()
        let client = NousCountingQuota()
        let monitor = QuotaMonitor(accountStore: states, credentialStore: router, quotaClient: client)
        await monitor.start(refresh: false)
        let alice = try credential(id, device: "watch", expiry: 5000)
        await monitor.addAccount(name: "Nous", credential: try alice.encoded(), provider: .nousPortal, accountID: id)
        let oldIdentity = try XCTUnwrap(alice.sourceCredentialIdentity)
        let initialQueries = await client.queries
        XCTAssertNotNil(monitor.states.first?.snapshot)
        let bob = try credential(id, device: "phone", expiry: 5000, subject: "did:privy:bob")
        var changed = try XCTUnwrap(monitor.configuration(for: id))
        changed.credentialIdentity = bob.sourceCredentialIdentity
        changed.modifiedAt = .distantFuture
        await monitor.mergeSynchronized(configurations: [changed], states: [])
        let before = try await vault.version(for: id)
        await monitor.replaceCredential(try alice.encoded(), accountID: id, expectedIdentity: oldIdentity)
        let after = try await vault.version(for: id)
        XCTAssertEqual(after, before)
        XCTAssertEqual(monitor.configuration(for: id)?.credentialIdentity, bob.sourceCredentialIdentity)
        await monitor.refresh(accountID: id)
        let latestQueries = await client.queries
        XCTAssertEqual(latestQueries, initialQueries) // Pre-query binding check rejects the old Watch vault.
        XCTAssertEqual(monitor.states.first?.lastFailure, .invalidCredential)
        XCTAssertNil(monitor.states.first?.snapshot)
    }

    func testDistinctPhoneAndWatchGrantsUseSameConfigIdentityAndIndependentDirectQueries() async throws {
        let id = UUID(), now = Date(timeIntervalSince1970: 100)
        let phone = try credential(id, device: "phone", expiry: 5000)
        let watch = try credential(id, device: "watch", access: "watch-only-access", refresh: "watch-only-refresh", expiry: 5000)
        let pVault = DeviceOAuthCredentialVault(records: NousMemoryRecords(), deviceID: "phone")
        let wVault = DeviceOAuthCredentialVault(records: NousMemoryRecords(), deviceID: "watch")
        try await pVault.save(phone.encoded(), for: id)
        try await wVault.save(watch.encoded(), for: id)
        let pTransport = NousTransport([.response(200, account)])
        let wTransport = NousTransport([.response(200, account)])
        let pResult = try await NousSessionCoordinator().quota(accountID: id, vault: pVault, transport: pTransport, now: { now })
        let wResult = try await NousSessionCoordinator().quota(accountID: id, vault: wVault, transport: wTransport, now: { now })
        XCTAssertEqual(pResult.sourceCredentialFingerprint, wResult.sourceCredentialFingerprint)
        let pRequests = await pTransport.requests, wRequests = await wTransport.requests
        XCTAssertEqual(pRequests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer old-access")
        XCTAssertEqual(wRequests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer watch-only-access")
    }

    func testDemoRealWidgetInterfaceAndNousIconAreRegistered() throws {
        let account = try XCTUnwrap(DemoMode.accounts().first { $0.provider == .nousPortal })
        let snapshot = DemoMode.snapshot(accountID: account.id, provider: .nousPortal)
        let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows, collectedAt: snapshot.collectedAt, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 3)
        XCTAssertEqual(Provider.nousPortal.iconAssetName, "ProviderNousPortal")
        XCTAssertEqual(Provider.nousPortal.balancePresentation, .mixed)
        XCTAssertFalse(Provider.nousPortal.hasMonetaryWallet)
    }
}

private final class NousMemoryRecords: DeviceOAuthRecordStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: Data] = [:]
    func read(_ accountID: UUID) -> Data? { lock.withLock { values[accountID] } }
    func write(_ data: Data, for accountID: UUID) { lock.withLock { values[accountID] = data } }
}
private actor NousSpyCredentials: CredentialStoring {
    private(set) var writes = 0
    private(set) var reads = 0
    func save(_ credential: String, for accountID: UUID) { writes += 1 }
    func credential(for accountID: UUID) -> String? { reads += 1; return nil }
    func deleteCredential(for accountID: UUID) {}
}
private actor NousTransport: ProviderTransport {
    enum Reply: Sendable { case response(Int, String, [String:String] = [:]), failure }
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        switch replies.removeFirst() {
        case .failure: throw URLError(.timedOut)
        case .response(let status, let json, let headers):
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
        }
    }
}
private actor NousHeldTransport: ProviderTransport {
    let path: String
    private var immediate: [NousTransport.Reply]
    private(set) var requests: [URLRequest] = []
    private var pending: CheckedContinuation<(Data, URLResponse), any Error>?
    private var waiter: CheckedContinuation<Void, Never>?
    private var pendingURL: URL?
    init(path: String, immediate: [NousTransport.Reply] = []) { self.path = path; self.immediate = immediate }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if request.url?.path == path {
            pendingURL = request.url
            return try await withCheckedThrowingContinuation { pending = $0; waiter?.resume(); waiter = nil }
        }
        guard !immediate.isEmpty else { throw URLError(.badServerResponse) }
        switch immediate.removeFirst() {
        case .failure: throw URLError(.timedOut)
        case .response(let status, let json, let headers): return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
        }
    }
    func waitForRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release(status: Int, json: String) {
        let response = HTTPURLResponse(url: pendingURL!, statusCode: status, httpVersion: nil, headerFields: nil)!
        pending?.resume(returning: (Data(json.utf8), response)); pending = nil
    }
}

private actor NousMemoryAccountState: AccountStateStoring {
    private var states: [AccountQuotaState] = []
    func load() -> [AccountQuotaState] { states }
    func save(_ states: [AccountQuotaState]) { self.states = states }
}
private actor NousCountingQuota: QuotaQuerying {
    private(set) var queries = 0
    func quota(for accountID: UUID, credential: String) throws -> QuotaSnapshot {
        queries += 1
        let envelope = try ProviderCredentialEnvelope.decode(credential, expectedProvider: .nousPortal)
        return QuotaSnapshot(accountID: accountID, windows: [QuotaWindow(id: "quota", name: "Quota", scope: nil, usedPercentage: 25, remainingCount: 75, totalCount: 100, resetsAt: nil)], collectedAt: Date(), sourceCredentialFingerprint: envelope.sourceCredentialIdentity)
    }
}
