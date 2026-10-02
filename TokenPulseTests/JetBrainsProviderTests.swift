import Foundation
import XCTest
@testable import TokenPulse

private final class JetBrainsRecords: DeviceOAuthRecordStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var data: [UUID: Data] = [:]
    private var writes = 0
    var writeCount: Int { lock.lock(); defer { lock.unlock() }; return writes }
    var failAt: Int? = nil
    func read(_ id: UUID) -> Data? { lock.lock(); defer { lock.unlock() }; return data[id] }
    func write(_ value: Data, for id: UUID) throws {
        lock.lock(); defer { lock.unlock() }; writes += 1
        if writes == failAt { throw URLError(.cannotWriteToFile) }
        data[id] = value
    }
}
private actor JetBrainsTransport: ProviderTransport {
    struct Reply: Sendable { let status: Int; let body: String; var finalURL: URL? = nil; var fail = false }
    var replies: [Reply]
    var requests: [URLRequest] = []
    var observe: (@Sendable (URLRequest) async throws -> Void)?
    init(_ replies: [Reply], observe: (@Sendable (URLRequest) async throws -> Void)? = nil) { self.replies = replies; self.observe = observe }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request); try await observe?(request)
        guard !replies.isEmpty else { throw URLError(.notConnectedToInternet) }
        let reply = replies.removeFirst()
        if reply.fail { throw URLError(.timedOut) }
        return (Data(reply.body.utf8), HTTPURLResponse(url: reply.finalURL ?? request.url!, statusCode: reply.status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!)
    }
    func received() -> [URLRequest] { requests }
}
private actor JetBrainsBarrier {
    private var waiting: CheckedContinuation<Void, Never>?
    private var startWaiting: CheckedContinuation<Void, Never>?
    private var started = false
    func pause() async {
        started = true; startWaiting?.resume(); startWaiting = nil
        await withCheckedContinuation { waiting = $0 }
    }
    func waitForStart() async {
        if started { return }; await withCheckedContinuation { startWaiting = $0 }
    }
    func release() { waiting?.resume(); waiting = nil }
}
private actor JetBrainsSynchronizedSecrets: CredentialStoring {
    var values: [UUID: String] = [:]
    func save(_ value: String, for id: UUID) { values[id] = value }
    func credential(for id: UUID) -> String? { values[id] }
    func deleteCredential(for id: UUID) { values.removeValue(forKey: id) }
}

final class JetBrainsProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let quota = #"{"current":{"license":"opaque-platform-license","current":{"amount":"200000"},"maximum":1000000,"until":9000000,"tariffQuota":{"current":"200000","maximum":{"amount":1000000},"available":"800000"},"topUpQuota":{"current":100000,"maximum":500000,"available":400000}}}"#
    private let refill = #"{"current":{"last":1000000,"next":86400000}}"#
    private func transfer(refresh: String = "fixture-rt", license: String = "chosen-license", version: Int = 1,
                          environment: String = "prod", accepted: String = "true") -> String {
        let text = "{\"version\":\(version),\"refresh_token\":\"\(refresh)\",\"environment\":\"\(environment)\",\"ai_access\":{\"type\":\"license\",\"license_id\":\"\(license)\"},\"eap_tos_accepted\":\(accepted)}"
        return "central-" + Data(text.utf8).base64EncodedString()
    }
    private func idToken(subject: String = "same-subject", expiry: Double = 5_000) -> String {
        let text = "{\"sub\":\"\(subject)\",\"jba_login\":\"display-login\",\"exp\":\(expiry)}"
        return "fixture." + Data(text.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_") + ".signature"
    }
    private func oauth(refresh: String? = "rotated-rt", subject: String = "same-subject", expiry: Double = 5_000) -> JetBrainsTransport.Reply {
        let optional = refresh.map { ",\"refresh_token\":\"\($0)\"" } ?? ""
        return .init(status: 200, body: "{\"access_token\":\"jba-access\",\"id_token\":\"\(idToken(subject: subject, expiry: expiry))\"\(optional)}")
    }
    private func successful(_ oauth: JetBrainsTransport.Reply? = nil) -> [JetBrainsTransport.Reply] {
        [oauth ?? self.oauth(), .init(status: 201, body: "{}"), .init(status: 200, body: #"{"token":"ai-jwt","expiresAt":3600000}"#),
         .init(status: 200, body: quota), .init(status: 200, body: refill)]
    }
    private func vault(_ records: JetBrainsRecords = JetBrainsRecords(), device: String = UUID().uuidString) -> DeviceOAuthCredentialVault {
        DeviceOAuthCredentialVault(records: records, deviceID: device, now: { Date(timeIntervalSince1970: 1_000) })
    }
    private func envelope(_ vault: DeviceOAuthCredentialVault, _ id: UUID) async throws -> ProviderCredentialEnvelope {
        let active = try await vault.version(for: id)
        let candidateID = JetBrainsCredential.candidateRecordID(accountID: id, marker: try JetBrainsTokenTransfer.decode(transfer()).grantMarker)
        let candidate = try await vault.version(for: candidateID)
        return try ProviderCredentialEnvelope.decode(XCTUnwrap(active.credential ?? candidate.credential), expectedProvider: .jetBrainsAI)
    }

    private func activate(_ receipt: String, store: DeviceOAuthCredentialVault, id: UUID) async throws {
        try await ProviderScopedCredentialStore(synchronized: JetBrainsSynchronizedSecrets(), deviceOAuthVault: store)
            .save(receipt, for: id, provider: .jetBrainsAI)
    }

    func testTransferRejectsUnsupportedVersionEnvironmentEnterpriseMissingLicenseAndWrongBool() throws {
        XCTAssertEqual(try JetBrainsTokenTransfer.decode(transfer()).ai_access.license_id, "chosen-license")
        for bad in [transfer(version: 2), transfer(environment: "staging"), transfer(environment: "ides"), transfer(license: ""),
                    transfer(accepted: "1"), transfer(accepted: "false"), "ai-jwt", "central-@@@"] {
            XCTAssertThrowsError(try JetBrainsTokenTransfer.decode(bad))
        }
    }
    func testGrantMarkerUsesOnlyActualRefreshNotJSONWrapperLicenseOrFormatting() throws {
        let first = try JetBrainsTokenTransfer.decode(transfer()), second = try JetBrainsTokenTransfer.decode(transfer(license: "another"))
        XCTAssertEqual(first.grantMarker, second.grantMarker)
        XCTAssertNotEqual(first.grantMarker, try JetBrainsTokenTransfer.decode(transfer(refresh: "different")).grantMarker)
        XCTAssertFalse(first.grantMarker.contains("fixture-rt"))
    }
    func testQuotaUsesExactNonMoneyCreditsAndRefillMillisDoesNotUseUntilOrDuplicateTotal() throws {
        let result = try JetBrainsQuotaParser.snapshot(Data(quota.utf8), refill: Data(refill.utf8), accountID: UUID(), collectedAt: now)
        XCTAssertEqual(result.windows.count, 2)
        XCTAssertEqual(result.windows[0].exactCounts, .init(used: 2, remaining: 8, total: 10))
        XCTAssertEqual(result.windows[0].usedPercentage, 20)
        XCTAssertEqual(result.windows[0].resetsAt, Date(timeIntervalSince1970: 86_400))
        XCTAssertEqual(result.windows[0].cycleID, "1000000")
        XCTAssertNil(result.windows[1].resetsAt); XCTAssertNil(result.windows[1].expiresAt)
        XCTAssertEqual(result.windows[1].resetSemantics, .nonResettingAllowance)
        XCTAssertTrue(result.windows.allSatisfy { $0.wallet == nil && $0.unit == "AI credits" })
    }
    func testMissingAmountDenominatorStaysUnknownAndBooleansDoNotBecomeZero() throws {
        let partial = #"{"current":{"tariffQuota":{"current":"123456.789"}}}"#
        let window = try JetBrainsQuotaParser.snapshot(Data(partial.utf8), refill: Data(refill.utf8), accountID: UUID(), collectedAt: now).windows[0]
        XCTAssertEqual(window.exactCounts?.used, Decimal(string: "1.23456789"))
        XCTAssertNil(window.usedPercentage); XCTAssertNil(window.totalCount); XCTAssertNil(window.remainingCount)
        for amount in ["true", "-1", #"{"amount":false}"#] {
            let data = Data("{\"current\":{\"current\":\(amount)}}".utf8)
            XCTAssertThrowsError(try JetBrainsQuotaParser.snapshot(data, refill: Data(refill.utf8), accountID: UUID(), collectedAt: now))
        }
        XCTAssertThrowsError(try JetBrainsQuotaParser.snapshot(Data(quota.utf8), refill: Data(#"{"current":{"last":9,"next":8}}"#.utf8), accountID: UUID(), collectedAt: now))
    }
    func testServerMintIdentityUsesSubjectBeforeDisplayLoginAndRejectsInvalidLifetime() throws {
        XCTAssertEqual(try JetBrainsCredential.identity(idToken()).0, "sub:same-subject")
        XCTAssertThrowsError(try JetBrainsCredential.identity("not-a-jwt"))
        XCTAssertThrowsError(try JetBrainsCredential.identity(idToken(subject: "")))
        XCTAssertThrowsError(try JetBrainsCredential.identity(idToken(expiry: -1)))
    }
    func testMintExpiryRejectsPresentNonpositiveStaleOrOverflowAndOnlyMissingUsesKnownDefault() throws {
        for milliseconds: Int64 in [-1, 0, 999_999, Int64.max] {
            XCTAssertThrowsError(try JetBrainsProviderClient.mintExpiry(.init(token: "fixture", expiresAt: milliseconds), now: now))
        }
        XCTAssertEqual(try JetBrainsProviderClient.mintExpiry(.init(token: "fixture", expiresAt: nil), now: now), now.addingTimeInterval(86_400))
        XCTAssertEqual(try JetBrainsProviderClient.mintExpiry(.init(token: "fixture", expiresAt: 3_600_123), now: now), Date(timeIntervalSince1970: 3_600.123))
    }
    func testInitialImportExactRoutesPublicClientAndCheckpointBeforeSigning() async throws {
        let id = UUID(), store = vault(), coordinator = JetBrainsSessionCoordinator()
        let candidateID = JetBrainsCredential.candidateRecordID(accountID: id, marker: try JetBrainsTokenTransfer.decode(transfer()).grantMarker)
        let transport = JetBrainsTransport(successful(), observe: { request in
            let saved = try await store.version(for: candidateID)
            let envelope = try ProviderCredentialEnvelope.decode(XCTUnwrap(saved.credential), expectedProvider: .jetBrainsAI)
            if request.url?.path == "/oauth2/token" { XCTAssertEqual(envelope.metadata["stage"], "oauthPending") }
            if request.url?.path == "/auth/jetbrains-jwt/register" {
                XCTAssertEqual(envelope.refreshToken, "rotated-rt"); XCTAssertEqual(envelope.metadata["stage"], "jbaReady")
            }
        })
        let value = try await coordinator.importTransfer(transfer(), accountID: id, vault: store, transport: transport, now: { Date(timeIntervalSince1970: 1_000) })
        let beforeSave = try await store.version(for: id); XCTAssertNil(beforeSave.credential)
        try await activate(value, store: store, id: id)
        let saved = try ProviderCredentialEnvelope.decode(value, expectedProvider: .jetBrainsAI)
        XCTAssertEqual(saved.refreshToken, "rotated-rt"); XCTAssertEqual(saved.expiresAt, Date(timeIntervalSince1970: 3_600))
        XCTAssertEqual(saved.accountID, "sub:same-subject"); XCTAssertEqual(saved.metadata["stage"], "ready")
        let requests = await transport.received()
        XCTAssertEqual(requests.map { $0.url!.path }, ["/oauth2/token", "/auth/jetbrains-jwt/register", "/auth/jetbrains-jwt/provide-access/license/v2", "/user/v5/quota/get", "/user/v5/quota/metadata/refill"])
        let form = String(decoding: requests[0].httpBody!, as: UTF8.self)
        XCTAssertTrue(form.contains("client_id=central-cli")); XCTAssertTrue(form.contains("grant_type=refresh_token"))
        XCTAssertFalse(form.contains("secret")); XCTAssertFalse(form.contains("redirect_uri")); XCTAssertFalse(form.contains("code_verifier"))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer jba-access")
        XCTAssertEqual(requests[1].httpBody, Data("{}".utf8))
        XCTAssertEqual(requests[2].httpBody, Data(#"{"licenseId":"chosen-license"}"#.utf8))
        XCTAssertNil(requests[3].httpBody); XCTAssertEqual(requests[3].value(forHTTPHeaderField: "Grazie-Authenticate-JWT"), "ai-jwt")
        XCTAssertNil(requests[3].value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(requests.allSatisfy { !$0.httpShouldHandleCookies && $0.httpMethod == "POST" })
    }
    func testNoRefreshReplacementPreservesOriginalWithoutPromisingMultiDeviceSafety() async throws {
        let id = UUID(), store = vault()
        _ = try await JetBrainsSessionCoordinator().importTransfer(transfer(), accountID: id, vault: store,
            transport: JetBrainsTransport(successful(oauth(refresh: nil))), now: { Date(timeIntervalSince1970: 1_000) })
        let observed = try await envelope(store, id)
        XCTAssertEqual(observed.refreshToken, "fixture-rt")
    }
    func testRegisterFailureResumeUsesPersistedNewJBAWithoutReplayingExportRefresh() async throws {
        let id = UUID(), records = JetBrainsRecords(), store = vault(records), coordinator = JetBrainsSessionCoordinator()
        let failed = JetBrainsTransport([oauth(), .init(status: 500, body: "{}")])
        do { _ = try await coordinator.importTransfer(transfer(), accountID: id, vault: store, transport: failed, now: { Date(timeIntervalSince1970: 1_000) }); XCTFail("unexpected success") } catch {}
        let saved = try await envelope(store, id)
        XCTAssertEqual(saved.refreshToken, "rotated-rt"); XCTAssertEqual(saved.metadata["stage"], "jbaReady")
        let resumed = JetBrainsTransport(Array(successful().dropFirst()))
        _ = try await JetBrainsSessionCoordinator().importTransfer(transfer(), accountID: id, vault: vault(records, device: store.deviceID), transport: resumed, now: { Date(timeIntervalSince1970: 1_000) })
        let requests = await resumed.received(); XCTAssertFalse(requests.contains { $0.url!.path == "/oauth2/token" })
    }
    func testQuotaFailureDoesNotRollBackRotatedRefreshAndNextQueryDoesNotRemint() async throws {
        let id = UUID(), store = vault(), coordinator = JetBrainsSessionCoordinator()
        let bad = JetBrainsTransport(Array(successful().prefix(3)) + [.init(status: 500, body: "{}")])
        do { _ = try await coordinator.importTransfer(transfer(), accountID: id, vault: store, transport: bad, now: { Date(timeIntervalSince1970: 1_000) }); XCTFail("unexpected success") } catch {}
        let observed = try await envelope(store, id)
        XCTAssertEqual(observed.refreshToken, "rotated-rt")
        let good = JetBrainsTransport(Array(successful().suffix(2)))
        let receipt = try await coordinator.importTransfer(transfer(), accountID: id, vault: store, transport: good, now: { Date(timeIntervalSince1970: 1_000) })
        try await activate(receipt, store: store, id: id)
        let requests = await good.received(); XCTAssertEqual(requests.count, 2)
    }
    func testUncertainPOSTCannotBeReplayedBySameExportOrNewAccountUUIDEvenAfterDeletion() async throws {
        let id = UUID(), store = vault(), coordinator = JetBrainsSessionCoordinator()
        let timeout = JetBrainsTransport([.init(status: 0, body: "", fail: true)])
        do { _ = try await coordinator.importTransfer(transfer(), accountID: id, vault: store, transport: timeout, now: { Date(timeIntervalSince1970: 1_000) }); XCTFail("unexpected success") } catch {}
        let observed = try await envelope(store, id)
        XCTAssertEqual(observed.metadata["stage"], "uncertain")
        for retryID in [id, UUID()] {
            let transport = JetBrainsTransport(successful())
            do { _ = try await coordinator.importTransfer(transfer(license: retryID == id ? "chosen-license" : "changed-wrapper"), accountID: retryID, vault: store, transport: transport, now: { Date(timeIntervalSince1970: 1_000) }); XCTFail("replayed") } catch {}
            let requests = await transport.received(); XCTAssertTrue(requests.isEmpty)
        }
        try await coordinator.cancelImport(accountID: id, vault: store, attemptID: UUID(uuidString: (try await envelope(store, id)).metadata["importAttemptID"]!)!)
        let afterDelete = JetBrainsTransport(successful())
        do { _ = try await coordinator.importTransfer(transfer(), accountID: UUID(), vault: store, transport: afterDelete, now: { Date(timeIntervalSince1970: 1_000) }); XCTFail("replayed after delete") } catch {}
        let requests = await afterDelete.received(); XCTAssertTrue(requests.isEmpty)
    }
    func testPendingCheckpointFailureSendsNoPOSTAndNewRTCheckpointFailureSealsOldLineage() async throws {
        for failure in [2, 3] {
            let records = JetBrainsRecords(); records.failAt = failure
            let store = vault(records), id = UUID(), transport = JetBrainsTransport(successful())
            do { _ = try await JetBrainsSessionCoordinator().importTransfer(transfer(), accountID: id, vault: store, transport: transport, now: { Date(timeIntervalSince1970: 1_000) }); XCTFail("write failure accepted") } catch {}
            let requests = await transport.received(); XCTAssertEqual(requests.count, failure == 2 ? 0 : 1)
            let retry = JetBrainsTransport(successful())
            do { _ = try await JetBrainsSessionCoordinator().importTransfer(transfer(), accountID: id, vault: store, transport: retry, now: { Date(timeIntervalSince1970: 1_000) }); XCTFail("unsafe retry") } catch {}
            let retryRequests = await retry.received(); XCTAssertTrue(retryRequests.isEmpty)
        }
    }
    func testIdentityParseFailureStillCheckpointsNewRefreshAndCannotRefreshOldExportAgain() async throws {
        let id = UUID(), store = vault(), coordinator = JetBrainsSessionCoordinator()
        let transport = JetBrainsTransport([.init(status: 200, body: #"{"access_token":"jba-access","id_token":"malformed","refresh_token":"rotated-rt"}"#)])
        do { _ = try await coordinator.importTransfer(transfer(), accountID: id, vault: store, transport: transport, now: { Date(timeIntervalSince1970: 1_000) }); XCTFail("unexpected identity") } catch {}
        let saved = try await envelope(store, id)
        XCTAssertEqual(saved.refreshToken, "rotated-rt"); XCTAssertEqual(saved.metadata["stage"], "identityPending")
        let retry = JetBrainsTransport(successful())
        do { _ = try await coordinator.importTransfer(transfer(), accountID: id, vault: store, transport: retry, now: { Date(timeIntervalSince1970: 1_000) }); XCTFail("unsafe identity retry") } catch {}
        let requests = await retry.received(); XCTAssertTrue(requests.isEmpty)
    }
    func testEachDeviceIndependentGrantHasSameLogicalScopeButWrongDeviceEnvelopeIsRejected() async throws {
        let id = UUID(), phone = vault(device: "phone"), watch = vault(device: "watch")
        let first = try await JetBrainsSessionCoordinator().importTransfer(transfer(), accountID: id, vault: phone, transport: JetBrainsTransport(successful()), now: { Date(timeIntervalSince1970: 1_000) })
        let credential = try ProviderCredentialEnvelope.decode(first, expectedProvider: .jetBrainsAI), identity = try JetBrainsCredential.fingerprint(credential)
        let second = try await JetBrainsSessionCoordinator().importTransfer(transfer(refresh: "independent-watch-grant"), accountID: id, vault: watch,
            expectedIdentity: identity, transport: JetBrainsTransport(successful(oauth(refresh: "watch-rt"))), now: { Date(timeIntervalSince1970: 1_000) })
        let watchCredential = try ProviderCredentialEnvelope.decode(second, expectedProvider: .jetBrainsAI)
        XCTAssertEqual(try JetBrainsCredential.fingerprint(watchCredential), identity)
        XCTAssertNotEqual(watchCredential.metadata["grantMarker"], credential.metadata["grantMarker"])
        XCTAssertThrowsError(try JetBrainsCredential.validateLocal(credential, accountID: id, deviceID: "watch"))
    }
    func testWatchExpectedScopeMismatchPersistsLockAndNeverSignsOrQueriesWrongAccount() async throws {
        let id = UUID(), store = vault(), transport = JetBrainsTransport([oauth()]), coordinator = JetBrainsSessionCoordinator()
        do { _ = try await coordinator.importTransfer(transfer(), accountID: id, vault: store, expectedIdentity: "expected-other",
            transport: transport, now: { Date(timeIntervalSince1970: 1_000) }); XCTFail("wrong scope accepted") } catch {}
        let saved = try await envelope(store, id); XCTAssertEqual(saved.metadata["expectedIdentity"], "expected-other")
        let retry = JetBrainsTransport(successful())
        do { _ = try await coordinator.quota(accountID: id, vault: store, transport: retry, now: { Date(timeIntervalSince1970: 1_000) }); XCTFail("lost expected scope") } catch {}
        let requests = await retry.received(); XCTAssertTrue(requests.isEmpty)
    }
    func testAIRefreshFailureFallsBackToRegisterUsingValidJBAWithoutConsumingRefreshToken() async throws {
        let id = UUID(), store = vault(), coordinator = JetBrainsSessionCoordinator()
        let seed = try await coordinator.importTransfer(transfer(), accountID: id, vault: store, transport: JetBrainsTransport(successful()), now: { Date(timeIntervalSince1970: 1_000) })
        try await activate(seed, store: store, id: id)
        let fallback = JetBrainsTransport([.init(status: 401, body: "{}"), .init(status: 201, body: "{}"),
            .init(status: 200, body: #"{"token":"renewed-ai"}"#), .init(status: 200, body: quota), .init(status: 200, body: refill)])
        _ = try await coordinator.quota(accountID: id, vault: store, transport: fallback, now: { Date(timeIntervalSince1970: 3_601) })
        let requests = await fallback.received()
        XCTAssertTrue(requests[0].url!.path.hasSuffix("/jwt/refresh/v3")); XCTAssertFalse(requests.contains { $0.url!.path == "/oauth2/token" })
        let observed = try await envelope(store, id)
        XCTAssertEqual(observed.refreshToken, "rotated-rt")
    }
    func testExpiredJBAUsesCheckpointRefreshAndKeepsBoundIdentity() async throws {
        let id = UUID(), store = vault(), coordinator = JetBrainsSessionCoordinator()
        let seed = try await coordinator.importTransfer(transfer(), accountID: id, vault: store, transport: JetBrainsTransport(successful()), now: { Date(timeIntervalSince1970: 1_000) })
        try await activate(seed, store: store, id: id)
        let transport = JetBrainsTransport(successful(oauth(refresh: "next-rt", expiry: 10_000)).map { reply in
            reply.body.contains("expiresAt") ? .init(status: 200, body: #"{"token":"next-ai","expiresAt":9000000}"#) : reply
        })
        _ = try await coordinator.quota(accountID: id, vault: store, transport: transport, now: { Date(timeIntervalSince1970: 5_001) })
        let requests = await transport.received()
        XCTAssertTrue(String(decoding: requests[0].httpBody!, as: UTF8.self).contains("refresh_token=rotated-rt"))
        let observed = try await envelope(store, id)
        XCTAssertEqual(observed.refreshToken, "next-rt")
    }
    func testCrossOriginMintResponseAndChangedServerSubjectNeverOverwriteLogicalScope() async throws {
        let id = UUID(), store = vault(), coordinator = JetBrainsSessionCoordinator()
        let seed = try await coordinator.importTransfer(transfer(), accountID: id, vault: store, transport: JetBrainsTransport(successful()), now: { Date(timeIntervalSince1970: 1_000) })
        try await activate(seed, store: store, id: id)
        let changed = JetBrainsTransport([oauth(subject: "different", expiry: 10_000)])
        do { _ = try await coordinator.quota(accountID: id, vault: store, transport: changed, now: { Date(timeIntervalSince1970: 5_001) }); XCTFail("scope changed") } catch {}
        let observed = try await envelope(store, id)
        XCTAssertEqual(observed.accountID, "sub:same-subject")
        let unrelated = JetBrainsTransport([.init(status: 200, body: "{}", finalURL: URL(string: "https://other.invalid/token")!)])
        do { _ = try await JetBrainsSessionCoordinator().importTransfer(transfer(refresh: "fresh-grant"), accountID: UUID(), vault: store,
            transport: unrelated, now: { Date(timeIntervalSince1970: 1_000) }); XCTFail("redirect accepted") } catch {}
    }

    func testConcurrentActiveQueriesShareOneReadWithoutConsumingAnotherRefresh() async throws {
        let id = UUID(), store = vault(), coordinator = JetBrainsSessionCoordinator(), gate = JetBrainsBarrier()
        let receipt = try await coordinator.importTransfer(transfer(), accountID: id, vault: store, transport: JetBrainsTransport(successful()), now: { Date(timeIntervalSince1970: 1_000) })
        try await activate(receipt, store: store, id: id)
        let transport = JetBrainsTransport(Array(successful().suffix(2)), observe: { request in
            if request.url!.path == "/user/v5/quota/get" { await gate.pause() }
        })
        let first = Task { try await coordinator.quota(accountID: id, vault: store, transport: transport, now: { Date(timeIntervalSince1970: 1_000) }) }
        await gate.waitForStart()
        let second = Task { try await coordinator.quota(accountID: id, vault: store, transport: transport, now: { Date(timeIntervalSince1970: 1_000) }) }
        await Task.yield(); await gate.release()
        _ = try await first.value; let snapshot = try await second.value
        XCTAssertEqual(snapshot.windows.count, 2)
        let requests = await transport.received(); XCTAssertEqual(requests.count, 2)
    }
    func testCancellationTombstoneRejectsLateMintAndPreservesSpentMarkerAcrossNewUUID() async throws {
        let id = UUID(), store = vault(), coordinator = JetBrainsSessionCoordinator(), gate = JetBrainsBarrier()
        let transport = JetBrainsTransport(successful(), observe: { request in
            if request.url!.path == "/oauth2/token" { await gate.pause() }
        })
        let input = transfer()
        let importing = Task { try await coordinator.importTransfer(input, accountID: id, vault: store, transport: transport, now: { Date(timeIntervalSince1970: 1_000) }) }
        await gate.waitForStart(); try await coordinator.cancelImport(accountID: id, vault: store, attemptID: UUID(uuidString: (try await envelope(store, id)).metadata["importAttemptID"]!)!); await gate.release()
        do { _ = try await importing.value; XCTFail("late import revived") } catch {}
        let version = try await store.version(for: id); XCTAssertNil(version.credential)
        let retry = JetBrainsTransport(successful())
        do { _ = try await coordinator.importTransfer(input, accountID: UUID(), vault: store, transport: retry, now: { Date(timeIntervalSince1970: 1_000) }); XCTFail("spent marker forgotten") } catch {}
        let requests = await retry.received(); XCTAssertTrue(requests.isEmpty)
    }
    func testInvalidInputCancellationDoesNotDeleteAnExistingReadyGrant() async throws {
        let id = UUID(), store = vault(), coordinator = JetBrainsSessionCoordinator()
        _ = try await coordinator.importTransfer(transfer(), accountID: id, vault: store,
            transport: JetBrainsTransport(successful()), now: { Date(timeIntervalSince1970: 1_000) })
        let before = try await store.version(for: id), invalidAttempt = UUID()
        do { _ = try await coordinator.importTransfer("central-@@@", accountID: id, vault: store, attemptID: invalidAttempt,
            transport: JetBrainsTransport([]), now: { Date(timeIntervalSince1970: 1_000) }); XCTFail("invalid input accepted") } catch {}
        try await coordinator.cancelImport(accountID: id, vault: store, attemptID: invalidAttempt)
        let after = try await store.version(for: id); XCTAssertEqual(after, before)
    }
    func testDelayedOldPageCleanupCannotDeleteANewerImportLease() async throws {
        let id = UUID(), store = vault(), coordinator = JetBrainsSessionCoordinator(), oldLease = UUID(), newLease = UUID()
        let oldPrepared = try await coordinator.importTransfer(transfer(), accountID: id, vault: store, attemptID: oldLease,
            transport: JetBrainsTransport(successful()), now: { Date(timeIntervalSince1970: 1_000) })
        try await activate(oldPrepared, store: store, id: id)
        let newPrepared = try await coordinator.importTransfer(transfer(refresh: "new-independent-export"), accountID: id, vault: store, attemptID: newLease,
            transport: JetBrainsTransport(successful(oauth(refresh: "new-ready-rt"))), now: { Date(timeIntervalSince1970: 1_000) })
        try await activate(newPrepared, store: store, id: id)
        let before = try await store.version(for: id)
        try await coordinator.cancelImport(accountID: id, vault: store, attemptID: oldLease)
        let after = try await store.version(for: id); XCTAssertEqual(after, before)
        let saved = try await envelope(store, id); XCTAssertEqual(saved.refreshToken, "new-ready-rt")
    }
    func testActualScopedStoreHandoffAcknowledgesLatestRotationWithoutRollingItBackOrSyncing() async throws {
        let id = UUID(), local = vault(), shared = JetBrainsSynchronizedSecrets()
        let router = ProviderScopedCredentialStore(synchronized: shared, deviceOAuthVault: local)
        let bootstrap = try await JetBrainsSessionCoordinator().importTransfer(transfer(), accountID: id, vault: local,
            transport: JetBrainsTransport(successful()), now: { Date(timeIntervalSince1970: 1_000) })
        try await router.save(bootstrap, for: id, provider: .jetBrainsAI)
        var newer = try await envelope(local, id)
        newer.accessToken = "newer-ai"; newer.refreshToken = "newer-rt"; newer.expiresAt = Date(timeIntervalSince1970: 9_000)
        try await local.save(newer.encoded(), for: id)
        let before = try await local.version(for: id)
        try await router.save(bootstrap, for: id, provider: .jetBrainsAI)
        try await router.save(bootstrap, for: id) // Unscoped API also routes by actual provider without ISO-date decoding errors.
        let after = try await local.version(for: id); XCTAssertEqual(after, before)
        let synchronized = await shared.credential(for: id); XCTAssertNil(synchronized)
    }
    func testStaleBootstrapHandoffCannotResurrectDeletedVaultOrReplaceAnotherGrant() async throws {
        let id = UUID(), local = vault(), router = ProviderScopedCredentialStore(synchronized: JetBrainsSynchronizedSecrets(), deviceOAuthVault: local)
        let bootstrap = try await JetBrainsSessionCoordinator().importTransfer(transfer(), accountID: id, vault: local,
            transport: JetBrainsTransport(successful()), now: { Date(timeIntervalSince1970: 1_000) })
        try await local.delete(for: id)
        do { try await router.save(bootstrap, for: id, provider: .jetBrainsAI); XCTFail("resurrected") } catch {}
        let tombstone = try await local.version(for: id); XCTAssertNil(tombstone.credential)
        let fresh = try await JetBrainsSessionCoordinator().importTransfer(transfer(refresh: "new-family"), accountID: id, vault: local,
            transport: JetBrainsTransport(successful()), now: { Date(timeIntervalSince1970: 1_000) })
        do { try await router.save(bootstrap, for: id, provider: .jetBrainsAI); XCTFail("replaced another grant") } catch {}
        try await router.save(fresh, for: id, provider: .jetBrainsAI)
        let saved = try await envelope(local, id); XCTAssertEqual(saved.metadata["grantMarker"], try ProviderCredentialEnvelope.decode(fresh, expectedProvider: .jetBrainsAI).metadata["grantMarker"])
    }
    func testFreshCandidateFailuresAndCancellationPreserveExistingReadyAuthorization() async throws {
        for failedPhase in 0..<4 {
            let id = UUID(), local = vault(), coordinator = JetBrainsSessionCoordinator()
            let original = try await coordinator.importTransfer(transfer(), accountID: id, vault: local,
                transport: JetBrainsTransport(successful()), now: { Date(timeIntervalSince1970: 1_000) })
            try await activate(original, store: local, id: id)
            let before = try await local.version(for: id), lease = UUID()
            var replies = Array(successful().prefix(failedPhase))
            replies.append(.init(status: failedPhase == 0 ? 0 : 500, body: "{}", fail: failedPhase == 0))
            let input = transfer(refresh: "fresh-phase-\(failedPhase)")
            do { _ = try await coordinator.importTransfer(input, accountID: id, vault: local, attemptID: lease,
                transport: JetBrainsTransport(replies), now: { Date(timeIntervalSince1970: 1_000) }); XCTFail("failed candidate accepted") } catch {}
            let afterFailure = try await local.version(for: id); XCTAssertEqual(afterFailure, before)
            try await coordinator.cancelImport(accountID: id, vault: local, attemptID: lease)
            let afterCancel = try await local.version(for: id); XCTAssertEqual(afterCancel, before)
        }
    }
    func testCandidateReceiptRequiresRealSaveAndStaleBaselineCannotReplaceNewerActive() async throws {
        let id = UUID(), local = vault(), coordinator = JetBrainsSessionCoordinator()
        let initial = try await coordinator.importTransfer(transfer(), accountID: id, vault: local,
            transport: JetBrainsTransport(successful()), now: { Date(timeIntervalSince1970: 1_000) })
        try await activate(initial, store: local, id: id)
        let before = try await local.version(for: id), input = transfer(refresh: "candidate-fresh")
        let receipt = try await coordinator.importTransfer(input, accountID: id, vault: local,
            transport: JetBrainsTransport(successful()), now: { Date(timeIntervalSince1970: 1_000) })
        let afterPrepare = try await local.version(for: id); XCTAssertEqual(afterPrepare, before)
        var updated = try await envelope(local, id); updated.refreshToken = "active-rotated-after-prepare"
        try await local.save(updated.encoded(), for: id)
        let newer = try await local.version(for: id)
        do { try await activate(receipt, store: local, id: id); XCTFail("stale baseline activated") } catch {}
        let afterRejection = try await local.version(for: id); XCTAssertEqual(afterRejection, newer)
        let refreshedReceipt = try await coordinator.importTransfer(input, accountID: id, vault: local,
            transport: JetBrainsTransport(Array(successful().suffix(2))), now: { Date(timeIntervalSince1970: 1_000) })
        try await activate(refreshedReceipt, store: local, id: id)
        let adopted = try await envelope(local, id)
        XCTAssertEqual(adopted.metadata["grantMarker"], try JetBrainsTokenTransfer.decode(input).grantMarker)
        XCTAssertNil(adopted.metadata["candidateRecordID"])
        let candidateID = JetBrainsCredential.candidateRecordID(accountID: id, marker: try JetBrainsTokenTransfer.decode(input).grantMarker)
        let cleared = try await local.version(for: candidateID); XCTAssertNil(cleared.credential)
    }
    func testDeletedActiveDuringCandidatePrepareCannotBeResurrectedByLateReceipt() async throws {
        let id = UUID(), local = vault(), coordinator = JetBrainsSessionCoordinator(), gate = JetBrainsBarrier()
        let initial = try await coordinator.importTransfer(transfer(), accountID: id, vault: local,
            transport: JetBrainsTransport(successful()), now: { Date(timeIntervalSince1970: 1_000) })
        try await activate(initial, store: local, id: id)
        let input = transfer(refresh: "new-delayed"), lease = UUID()
        let transport = JetBrainsTransport(successful(), observe: { request in
            if request.url!.path == "/oauth2/token" { await gate.pause() }
        })
        let preparing = Task { try await coordinator.importTransfer(input, accountID: id, vault: local, attemptID: lease,
            transport: transport, now: { Date(timeIntervalSince1970: 1_000) }) }
        await gate.waitForStart(); try await local.delete(for: id); await gate.release()
        let receipt = try await preparing.value
        do { try await activate(receipt, store: local, id: id); XCTFail("late receipt revived deleted account") } catch {}
        let deleted = try await local.version(for: id); XCTAssertNil(deleted.credential)
        try await coordinator.cancelImport(accountID: id, vault: local, attemptID: lease)
    }
    func testActiveQuotaDoesNotJoinDifferentGrantCandidateAndSameGrantCancelDoesNotDeleteActive() async throws {
        let id = UUID(), local = vault(), coordinator = JetBrainsSessionCoordinator(), gate = JetBrainsBarrier()
        let initial = try await coordinator.importTransfer(transfer(), accountID: id, vault: local,
            transport: JetBrainsTransport(successful()), now: { Date(timeIntervalSince1970: 1_000) })
        try await activate(initial, store: local, id: id)
        let before = try await local.version(for: id), input = transfer(refresh: "other-grant", license: "other-license"), lease = UUID()
        let transport = JetBrainsTransport(successful(), observe: { request in
            if request.url!.path == "/oauth2/token" { await gate.pause() }
        })
        let preparing = Task { try await coordinator.importTransfer(input, accountID: id, vault: local, attemptID: lease,
            transport: transport, now: { Date(timeIntervalSince1970: 1_000) }) }
        await gate.waitForStart()
        let snapshot = try await coordinator.quota(accountID: id, vault: local, transport: JetBrainsTransport(Array(successful().suffix(2))), now: { Date(timeIntervalSince1970: 1_000) })
        let old = try ProviderCredentialEnvelope.decode(XCTUnwrap(before.credential), expectedProvider: .jetBrainsAI)
        XCTAssertEqual(snapshot.sourceCredentialFingerprint, try JetBrainsCredential.fingerprint(old))
        await gate.release(); _ = try await preparing.value
        try await coordinator.cancelImport(accountID: id, vault: local, attemptID: lease)
        let after = try await local.version(for: id); XCTAssertEqual(after, before)
        let sameLease = UUID()
        _ = try await coordinator.importTransfer(transfer(), accountID: id, vault: local, attemptID: sameLease,
            transport: JetBrainsTransport(Array(successful().suffix(2))), now: { Date(timeIntervalSince1970: 1_000) })
        try await coordinator.cancelImport(accountID: id, vault: local, attemptID: sameLease)
        let same = try await local.version(for: id); XCTAssertEqual(same, before)
    }
    func testResumedCandidateClaimsNewLeaseBeforeAwaitSoOldCleanupCannotDeleteIt() async throws {
        let id = UUID(), local = vault(), coordinator = JetBrainsSessionCoordinator(), firstLease = UUID(), secondLease = UUID(), gate = JetBrainsBarrier()
        _ = try await coordinator.importTransfer(transfer(), accountID: id, vault: local, attemptID: firstLease,
            transport: JetBrainsTransport(successful()), now: { Date(timeIntervalSince1970: 1_000) })
        let transport = JetBrainsTransport(Array(successful().suffix(2)), observe: { request in
            if request.url!.path == "/user/v5/quota/get" { await gate.pause() }
        })
        let input = transfer()
        let resumed = Task { try await coordinator.importTransfer(input, accountID: id, vault: local, attemptID: secondLease,
            transport: transport, now: { Date(timeIntervalSince1970: 1_000) }) }
        await gate.waitForStart()
        try await coordinator.cancelImport(accountID: id, vault: local, attemptID: firstLease)
        await gate.release(); let receipt = try await resumed.value
        try await activate(receipt, store: local, id: id)
        let active = try await local.version(for: id); XCTAssertNotNil(active.credential)
    }
    func testActivationWriteFailureKeepsCandidateSealedAndReceiptRetriesWithoutNativeRefresh() async throws {
        let id = UUID(), records = JetBrainsRecords(), local = vault(records), coordinator = JetBrainsSessionCoordinator()
        let transport = JetBrainsTransport(successful())
        let receipt = try await coordinator.importTransfer(transfer(), accountID: id, vault: local, transport: transport, now: { Date(timeIntervalSince1970: 1_000) })
        records.failAt = records.writeCount + 2 // Claim candidate succeeds; writing active fails.
        do { try await activate(receipt, store: local, id: id); XCTFail("failed write accepted") } catch {}
        let stillEmpty = try await local.version(for: id); XCTAssertNil(stillEmpty.credential)
        let retryTransport = JetBrainsTransport(successful())
        do { _ = try await coordinator.importTransfer(transfer(), accountID: id, vault: local, transport: retryTransport, now: { Date(timeIntervalSince1970: 1_000) }); XCTFail("sealed candidate refreshed") } catch {}
        let requests = await retryTransport.received(); XCTAssertTrue(requests.isEmpty)
        records.failAt = nil
        try await activate(receipt, store: local, id: id)
        let active = try await local.version(for: id); XCTAssertNotNil(active.credential)
        let originalRequests = await transport.received(); XCTAssertEqual(originalRequests.count, 5)
    }
    func testUnsavedCandidateExpiresWithoutBecomingActiveAndCannotReplayItsExport() async throws {
        let id = UUID(), local = vault(), coordinator = JetBrainsSessionCoordinator()
        _ = try await coordinator.importTransfer(transfer(), accountID: id, vault: local,
            transport: JetBrainsTransport(successful()), now: { Date(timeIntervalSince1970: 1_000) })
        let beforeSave = try await local.version(for: id); XCTAssertNil(beforeSave.credential)
        let expired = JetBrainsTransport(successful())
        do { _ = try await coordinator.importTransfer(transfer(), accountID: id, vault: local, transport: expired, now: { Date(timeIntervalSince1970: 4_601) }); XCTFail("expired candidate resumed") } catch {}
        let requests = await expired.received(); XCTAssertTrue(requests.isEmpty)
        let candidate = try await local.version(for: JetBrainsCredential.candidateRecordID(accountID: id, marker: try JetBrainsTokenTransfer.decode(transfer()).grantMarker))
        XCTAssertNil(candidate.credential)
        let replay = JetBrainsTransport(successful())
        do { _ = try await coordinator.importTransfer(transfer(), accountID: id, vault: local, transport: replay, now: { Date(timeIntervalSince1970: 4_602) }); XCTFail("expired export replayed") } catch {}
        let replayRequests = await replay.received(); XCTAssertTrue(replayRequests.isEmpty)
    }
    #if os(iOS)
    @MainActor
    func testActualAccountClientMonitorDeviceVaultRouterAndWidgetRegistration() async throws {
        let id = UUID(), local = vault(), synced = JetBrainsMonitorStore()
        let records = ProviderScopedCredentialStore(synchronized: synced, deviceOAuthVault: local)
        let value = try await JetBrainsSessionCoordinator().importTransfer(transfer(), accountID: id, vault: local,
            transport: JetBrainsTransport(successful()), now: { Date(timeIntervalSince1970: 1_000) })
        let client = AccountQuotaClient(provider: .jetBrainsAI, credentialStore: records,
            transport: JetBrainsTransport(Array(successful().suffix(2))), now: { Date(timeIntervalSince1970: 1_000) })
        let monitor = QuotaMonitor(accountStore: synced, credentialStore: records, quotaClient: client)
        await monitor.start(refresh: false)
        await monitor.addAccount(name: "JetBrains", credential: value, provider: .jetBrainsAI, accountID: id)
        let state = try XCTUnwrap(monitor.states.first), snapshot = try XCTUnwrap(state.snapshot)
        XCTAssertNil(state.lastFailure); XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.sourceCredentialFingerprint, state.credentialIdentity)
        let synchronizedSecret = await synced.credential(for: id); XCTAssertNil(synchronizedSecret)
        let widget = WidgetAccountSnapshot(account: state.account, windows: snapshot.windows, collectedAt: snapshot.collectedAt, lastFailure: state.lastFailure)
        XCTAssertEqual(widget.displayMetrics.count, 2)
        XCTAssertEqual(ProviderAuthenticationController().loginConfiguration(for: .jetBrainsAI).method, .webSession)
        XCTAssertEqual(Provider.jetBrainsAI.systemIconName, "terminal")
        XCTAssertTrue(Provider.jetBrainsAI.requiresDeviceLocalCredential)
        XCTAssertTrue(DemoMode.accounts().contains { $0.provider == .jetBrainsAI })
        let restored = QuotaMonitor(accountStore: synced, credentialStore: records, quotaClient: client)
        await restored.start(refresh: false); XCTAssertEqual(restored.states, monitor.states)
        let deleted = await restored.deleteAccount(accountID: id); XCTAssertTrue(deleted)
        let tombstone = try await local.version(for: id); XCTAssertNil(tombstone.credential)
    }
    #endif
}

#if os(iOS)
private actor JetBrainsMonitorStore: AccountStateStoring, CredentialStoring {
    private var states: [AccountQuotaState] = []
    private var values: [UUID: String] = [:]
    func load() -> [AccountQuotaState] { states }
    func save(_ states: [AccountQuotaState]) { self.states = states }
    func save(_ value: String, for id: UUID) { values[id] = value }
    func credential(for id: UUID) -> String? { values[id] }
    func deleteCredential(for id: UUID) { values.removeValue(forKey: id) }
}
#endif
