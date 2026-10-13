import Foundation
import XCTest
@testable import TokenPulse

final class WindsurfProviderTests: XCTestCase {
    private let base64 = "CjcKBwgCEgNQcm8SBgiAvMPOBhoGCIDW4c8GUgIIAWABcER4VIgB4LPizwaQAYDB6M8GnQEAAIA/EAc="
    private func storage() -> [String: String] {
        ["devin_session_token": "fixture-session", "devin_auth1_token": "\"auth1_fixture\"",
         "devin_account_id": "fixture-account", "devin_primary_org_id": "fixture-org"]
    }
    private func encodedStatus(daily: UInt64?, weekly: UInt64?) -> Data {
        var status = Data()
        for (field, value) in [(UInt64(14), daily), (15, weekly)] {
            if let value { WindsurfProto.append(field << 3, to: &status); WindsurfProto.append(value, to: &status) }
        }
        var reply = Data(); WindsurfProto.bytes(status, field: 1, to: &reply); return reply
    }

    func testAllFourExactSameOriginStorageValuesAreRequiredAndOneJSONStringLayerIsUnwrapped() throws {
        let id = UUID()
        let credential = try WindsurfWebSession.credential(storage: storage(), accountID: id)
        XCTAssertEqual(credential.accessToken, "fixture-session")
        XCTAssertEqual(credential.accountID, "fixture-account")
        XCTAssertEqual(credential.metadata["auth1Token"], "auth1_fixture")
        XCTAssertEqual(credential.metadata["organizationID"], "fixture-org")
        XCTAssertEqual(credential.metadata["origin"], "https://windsurf.com")
        for key in WindsurfWebSession.storageKeys {
            var missing = storage(); missing[key] = nil
            XCTAssertThrowsError(try WindsurfWebSession.credential(storage: missing, accountID: id))
        }
        XCTAssertThrowsError(try WindsurfWebSession.credential(storage: storage(), accountID: id, origin: "https://app.devin.ai"))
        var unsafe = storage(); unsafe["devin_auth1_token"] = "auth1_\r\nInjected: value"
        XCTAssertThrowsError(try WindsurfWebSession.credential(storage: unsafe, accountID: id))
        XCTAssertEqual(Provider.windsurf.webLoginProfile?.storageKeys, WindsurfWebSession.storageKeys)
    }

    func testPinnedProtobufFixtureReadsRemainingPercentAndStatedResets() throws {
        let data = try XCTUnwrap(Data(base64Encoded: base64))
        let result = try WindsurfProviderClient.snapshot(data, accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(result.providerPlanName, "Pro")
        XCTAssertEqual(result.windows.map(\.id), ["windsurf.daily", "windsurf.weekly"])
        XCTAssertEqual(result.windows.map(\.usedPercentage), [32, 16])
        XCTAssertTrue(result.windows.allSatisfy { $0.resetsAt != nil && $0.wallet == nil && $0.remainingCount == nil })
    }

    func testAbsentQuotaIsUnknownAndExplicitZeroIsExhausted() throws {
        let onlyWeekly = try WindsurfProviderClient.snapshot(encodedStatus(daily: nil, weekly: 84), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(onlyWeekly.windows.map(\.id), ["windsurf.weekly"])
        let spent = try WindsurfProviderClient.snapshot(encodedStatus(daily: 0, weekly: 100), accountID: UUID(), collectedAt: Date())
        XCTAssertEqual(spent.windows.map(\.usedPercentage), [100, 0])
        XCTAssertEqual(spent.windows.map(\.isExhausted), [true, false])
        XCTAssertThrowsError(try WindsurfProviderClient.snapshot(encodedStatus(daily: nil, weekly: nil), accountID: UUID(), collectedAt: Date())) {
            XCTAssertEqual($0 as? RefreshFailure, .noQuotaWindows)
        }
    }

    func testBoundedDecoderRejectsTruncationIllegalWireTypesOverflowAndOutOfRangePercentages() throws {
        let original = try XCTUnwrap(Data(base64Encoded: base64))
        for data in [Data(original.dropLast()), Data([0]), Data([0x0b]), Data([0x0a, 0x7f, 1]),
                     Data(repeating: 0xff, count: 10), Data([0x09, 1, 2]), Data([0x0d, 1, 2]),
                     encodedStatus(daily: 101, weekly: 84)] {
            XCTAssertThrowsError(try WindsurfProviderClient.snapshot(data, accountID: UUID(), collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
        var invalidPlan = Data([0x0a, 0x02, 0x12, 0x08]) // plan_info contains a truncated plan_name
        WindsurfProto.append(14 << 3, to: &invalidPlan); WindsurfProto.append(68, to: &invalidPlan)
        var reply = Data(); WindsurfProto.bytes(invalidPlan, field: 1, to: &reply)
        XCTAssertThrowsError(try WindsurfProviderClient.snapshot(reply, accountID: UUID(), collectedAt: Date()))
    }

    func testConnectRequestHasCompleteCredentialHeadersAndTwoBareProtobufFields() async throws {
        let id = UUID(), date = Date(timeIntervalSince1970: 100)
        let credential = try WindsurfWebSession.credential(storage: storage(), accountID: id)
        let transport = WindsurfTransport([.response(200, Data(base64Encoded: base64)!)])
        let result = try await ProviderQuotaClient(provider: .windsurf, transport: transport, now: { date }).quota(for: id, credential: credential.encoded())
        XCTAssertEqual(result.sourceCredentialFingerprint, try WebProviderSession.fingerprint(credential))
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://windsurf.com/_backend/exa.seat_management_pb.SeatManagementService/GetPlanStatus")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/proto")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Connect-Protocol-Version"), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-auth-token"), "fixture-session")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-devin-session-token"), "fixture-session")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-devin-auth1-token"), "auth1_fixture")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-devin-account-id"), "fixture-account")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-devin-primary-org-id"), "fixture-org")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        let fields = try WindsurfProto.fields(XCTUnwrap(request.httpBody))
        XCTAssertEqual(fields.map(\.number), [1, 2])
        XCTAssertEqual(fields[0].data, Data("fixture-session".utf8))
        XCTAssertEqual(fields[1].integer, 1)
    }

    func testAccountOrganizationAuth1AndExpiryMustMatchTheStoredFingerprint() async throws {
        let id = UUID()
        let original = try WindsurfWebSession.credential(storage: storage(), accountID: id)
        let transport = WindsurfTransport([])
        for item in ["localAccountID", "organizationID", "auth1Token", "origin", "expiry"] {
            var credential = original
            if item == "expiry" { credential.expiresAt = .distantPast }
            else { credential.metadata[item] = "changed" }
            do { _ = try await ProviderQuotaClient(provider: .windsurf, transport: transport).quota(for: id, credential: credential.encoded()); XCTFail("Invalid scope") }
            catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
        for (status, expected) in [(401, RefreshFailure.invalidCredential), (403, .invalidCredential), (302, .invalidCredential), (429, .rateLimited), (500, .server)] {
            do { _ = try await ProviderQuotaClient(provider: .windsurf, transport: WindsurfTransport([.response(status, Data())])).quota(for: id, credential: original.encoded()); XCTFail("Expected failure") }
            catch { XCTAssertEqual(error as? RefreshFailure, expected) }
        }
    }

    @MainActor
    func testFailurePreservesSnapshotAndDeletingCleansThisAccountOnly() async throws {
        let id = UUID()
        let credential = try WindsurfWebSession.credential(storage: storage(), accountID: id)
        let store = WindsurfMemoryStore()
        let transport = WindsurfTransport([.response(200, Data(base64Encoded: base64)!), .response(500, Data())])
        let monitor = QuotaMonitor(accountStore: store, credentialStore: store,
            quotaClient: ProviderQuotaClient(provider: .windsurf, transport: transport))
        await monitor.start(refresh: false)
        await monitor.addAccount(name: "Windsurf", credential: try credential.encoded(), provider: .windsurf, accountID: id)
        let previous = monitor.states.first?.snapshot
        await monitor.refresh(accountID: id)
        XCTAssertEqual(monitor.states.first?.snapshot, previous)
        XCTAssertEqual(monitor.states.first?.lastFailure, .server)
        let deleted = await monitor.deleteAccount(accountID: id)
        XCTAssertTrue(deleted)
        let saved = await store.credential(for: id)
        XCTAssertNil(saved)
    }

    func testDemoWidgetAndIconAreSeparateFromDevin() throws {
        let account = try XCTUnwrap(DemoMode.accounts().first { $0.provider == .windsurf })
        let demo = DemoMode.snapshot(accountID: account.id, provider: .windsurf)
        let widget = WidgetAccountSnapshot(account: account, windows: demo.windows, collectedAt: demo.collectedAt, lastFailure: nil)
        XCTAssertEqual(widget.displayMetrics.count, 2)
        XCTAssertEqual(Provider.windsurf.iconAssetName, "ProviderWindsurf")
        XCTAssertEqual(ProviderAuthenticationController().loginConfiguration(for: .windsurf).method, .webSession)
    }
}

private actor WindsurfTransport: ProviderTransport {
    enum Reply: Sendable { case response(Int, Data) }
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.timedOut) }
        switch replies.removeFirst() {
        case .response(let status, let body): return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}
private actor WindsurfMemoryStore: AccountStateStoring, CredentialStoring {
    private var states: [AccountQuotaState] = []
    private var credentials: [UUID: String] = [:]
    func load() -> [AccountQuotaState] { states }
    func save(_ states: [AccountQuotaState]) { self.states = states }
    func save(_ credential: String, for accountID: UUID) { credentials[accountID] = credential }
    func credential(for accountID: UUID) -> String? { credentials[accountID] }
    func deleteCredential(for accountID: UUID) { credentials[accountID] = nil }
}
