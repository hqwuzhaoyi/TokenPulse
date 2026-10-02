import Foundation
import XCTest
@testable import TokenPulse

final class MoonshotProviderTests: XCTestCase {
    private let body = #"{"code":0,"status":true,"data":{"available_balance":"-0.010000000000000001","voucher_balance":50,"cash_balance":"12.34567890123456789"}}"#

    func testSelectedRegionUsesOnlyItsHostCurrencyAndBearer() async throws {
        let collectedAt = Date(timeIntervalSince1970: 500)
        for region in ProviderRegion.allCases {
            let transport = MoonshotTestTransport([(200, body)])
            let credential = try ProviderAuthenticationController().credential(provider: .moonshot, apiKey: "fixture", region: region)
            let snapshot = try await ProviderQuotaClient(provider: .moonshot, transport: transport, now: { collectedAt })
                .quota(for: UUID(), credential: credential)
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests[0].url, region.moonshotEndpoint)
            XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
            XCTAssertEqual(requests[0].httpMethod, "GET")
            XCTAssertEqual(requests[0].cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(snapshot.windows[0].wallet?.currency, region.moonshotCurrency)
            XCTAssertEqual(snapshot.windows[0].wallet?.total, Decimal(string: "-0.010000000000000001"))
            XCTAssertEqual(snapshot.windows[0].wallet?.granted, 50)
            XCTAssertEqual(snapshot.windows[0].wallet?.toppedUp, Decimal(string: "12.34567890123456789"))
            XCTAssertEqual(snapshot.collectedAt, collectedAt)
            XCTAssertNotNil(snapshot.sourceCredentialFingerprint)
            XCTAssertNil(snapshot.walletAvailable)
            XCTAssertNil(snapshot.windows[0].resetsAt)
            XCTAssertNil(snapshot.windows[0].usedPercentage)
        }
    }

    func testRegionIsMandatoryAndKeyIsNotRetriedInOtherRegion() async throws {
        XCTAssertThrowsError(try ProviderAuthenticationController().credential(provider: .moonshot, apiKey: "fixture"))
        for (status, expected) in [(401, RefreshFailure.invalidCredential), (403, .invalidCredential), (429, .rateLimited), (500, .server)] {
            let transport = MoonshotTestTransport([(status, "{}"), (200, body)])
            let credential = try ProviderAuthenticationController().credential(provider: .moonshot, apiKey: "fixture", region: .china)
            do { _ = try await ProviderQuotaClient(provider: .moonshot, transport: transport).quota(for: UUID(), credential: credential); XCTFail() }
            catch { XCTAssertEqual(error as? RefreshFailure, expected) }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(requests[0].url?.host, "api.moonshot.cn")
        }
        let transport = MoonshotTestTransport([])
        let invalid = try ProviderCredentialEnvelope(provider: .moonshot, kind: .apiKey, accessToken: "fixture", metadata: ["region":"unknown"]).encoded()
        do { _ = try await ProviderQuotaClient(provider: .moonshot, transport: transport).quota(for: UUID(), credential: invalid); XCTFail() }
        catch { XCTAssertEqual(error as? RefreshFailure, .invalidCredential) }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testStrictEnvelopeAndMissingBalancesNeverBecomeZero() {
        for body in ["{}", #"{"code":0,"status":true,"data":{}}"#,
                     #"{"code":true,"status":true,"data":{"available_balance":1}}"#,
                     #"{"code":0,"status":1,"data":{"available_balance":1}}"#,
                     #"{"code":0,"status":true,"data":{"available_balance":true}}"#,
                     #"{"code":0,"status":true,"data":{"available_balance":"NaN"}}"#,
                     #"{"code":0,"status":true,"data":{"available_balance":1,"cash_balance":"bad"}}"#] {
            XCTAssertThrowsError(try MoonshotProviderClient.snapshot(Data(body.utf8), accountID: UUID(), region: .china, collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
        XCTAssertThrowsError(try MoonshotProviderClient.snapshot(Data(#"{"code":1,"status":false}"#.utf8), accountID: UUID(), region: .china, collectedAt: Date())) {
            XCTAssertEqual($0 as? RefreshFailure, .server)
        }
    }

    func testZeroAndOptionalBreakdownStayExactAcrossCodingAndWidgets() throws {
        let account = SubscriptionAccount(name: "fixture", provider: .moonshot)
        let snapshot = try MoonshotProviderClient.snapshot(Data(#"{"code":0,"status":true,"data":{"available_balance":0}}"#.utf8), accountID: account.id, region: .international, collectedAt: Date(timeIntervalSince1970: 100))
        let wallet = try XCTUnwrap(snapshot.windows[0].wallet)
        XCTAssertEqual(wallet.total, 0)
        XCTAssertNil(wallet.granted)
        XCTAssertNil(wallet.toppedUp)
        XCTAssertEqual(QuotaFormatting.balance(wallet.granted, wallet: wallet), "未提供")
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows, collectedAt: snapshot.collectedAt, lastFailure: nil)
        XCTAssertTrue(widget.displayMetrics[0].valueText.hasSuffix(" USD"))
        XCTAssertNil(widget.displayMetrics[0].ringFraction)
        XCTAssertFalse(widget.needsUpdate(at: .distantFuture))
        XCTAssertNotEqual(Provider.moonshot.iconAssetName, Provider.kimiCode.iconAssetName)
    }

    func testIdentityChangesWithRegionOrKeyAndCannotBeOverriddenByMetadata() throws {
        let auth = ProviderAuthenticationController()
        let encoded = try auth.credential(provider: .moonshot, apiKey: "a", region: .china)
        var a = try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .moonshot)
        let b = try ProviderCredentialEnvelope.decode(auth.credential(provider: .moonshot, apiKey: "b", region: .china), expectedProvider: .moonshot)
        let international = try ProviderCredentialEnvelope.decode(auth.credential(provider: .moonshot, apiKey: "a", region: .international), expectedProvider: .moonshot)
        XCTAssertNotEqual(a.sourceCredentialIdentity, b.sourceCredentialIdentity)
        XCTAssertNotEqual(a.sourceCredentialIdentity, international.sourceCredentialIdentity)
        a.metadata["sourceCredentialFingerprint"] = "forged"
        XCTAssertEqual(a.sourceCredentialIdentity, try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .moonshot).sourceCredentialIdentity)
    }

    @MainActor
    func testAccountRestartRegionChangeClearsOldCacheAndSyncMismatchBlocksBeforeNetwork() async throws {
        let suite = "moonshot.tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let credentials = MoonshotTestCredentials()
        let transport = MoonshotTestTransport([(200, body), (200, body), (401, "{}")])
        let now = Date(timeIntervalSince1970: 500)
        let client = ProviderQuotaClient(provider: .moonshot, transport: transport, now: { now })
        let store = LocalAccountStateStore(suiteName: suite)
        let configurations = LocalAccountConfigurationStore(suiteName: suite)
        let monitor = QuotaMonitor(accountStore: store, credentialStore: credentials, quotaClient: client, configurationStore: configurations)
        await monitor.start(refresh: false)
        let auth = ProviderAuthenticationController()
        let china = try auth.credential(provider: .moonshot, apiKey: "cn-fixture", region: .china)
        let international = try auth.credential(provider: .moonshot, apiKey: "intl-fixture", region: .international)
        await monitor.addAccount(name: "A", credential: china, provider: .moonshot)
        await monitor.addAccount(name: "B", credential: china, provider: .moonshot)
        let a = try XCTUnwrap(monitor.states.first)
        let b = try XCTUnwrap(monitor.states.last)
        var settings = monitor.configuration(for: a.id)!.reminders
        settings.walletCurrency = "CNY"
        await monitor.updateReminders(settings, accountID: a.id)
        await monitor.replaceCredential(international, accountID: a.id)
        XCTAssertNil(monitor.states[0].snapshot, "Failure after switching region cannot retain old CNY balance")
        XCTAssertEqual(monitor.states[0].lastFailure, .invalidCredential)
        XCTAssertEqual(monitor.configuration(for: a.id)?.providerRegion, .international)
        XCTAssertNil(monitor.configuration(for: a.id)?.reminders.walletCurrency)
        XCTAssertEqual(monitor.states[1], b)
        let restored = QuotaMonitor(accountStore: store, credentialStore: credentials, quotaClient: client, configurationStore: configurations)
        await restored.start(refresh: false)
        XCTAssertEqual(restored.states, monitor.states)
        XCTAssertEqual(restored.configuration(for: a.id)?.providerRegion, .international)
        // Simulate separate iCloud configuration and old Keychain arrival.
        await credentials.save(china, for: a.id)
        await restored.refresh(accountID: a.id)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3, "Old-region Key must not be queried against incoming configuration")
        let didDelete = await restored.deleteAccount(accountID: a.id)
        XCTAssertTrue(didDelete)
        let deleted = await credentials.credential(for: a.id)
        let kept = await credentials.credential(for: b.id)
        XCTAssertNil(deleted)
        XCTAssertEqual(kept, china)
    }

    @MainActor
    func testIndependentClientAndLowBalanceLedgerResetWithRegionIdentity() async throws {
        let suite = "moonshot.notification.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "notificationsEnabled")
        let adapter = MoonshotTestNotifications()
        let notifications = NotificationRuntime(defaults: defaults, adapter: adapter)
        let account = SubscriptionAccount(name: "fixture", provider: .moonshot)
        for region in ProviderRegion.allCases {
            let credential = try ProviderAuthenticationController().credential(provider: .moonshot, apiKey: "fixture", region: region)
            let transport = MoonshotTestTransport([(200, body)])
            let client = ProviderQuotaClient(provider: .moonshot, transport: transport)
            let snapshot = try await client.quota(for: account.id, credential: credential)
            let state = AccountQuotaState(account: account, snapshot: snapshot,
                                          credentialIdentity: snapshot.sourceCredentialFingerprint)
            try await notifications.fresh(state: state, previous: nil, settings: AccountReminderSettings())
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
        let operations = await adapter.operations
        let delivered = operations.compactMap { if case .deliver(let value) = $0 { return value }; return nil }
        XCTAssertEqual(delivered.count, 2, "Region identity change clears old low-balance deduplication")
        XCTAssertTrue(delivered.allSatisfy { $0.kind == .walletAlert })
        XCTAssertFalse(operations.contains { if case .schedule = $0 { return true }; return false })
    }
}

private actor MoonshotTestTransport: ProviderTransport {
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

private actor MoonshotTestCredentials: CredentialStoring {
    private var items: [UUID: String] = [:]
    func save(_ credential: String, for accountID: UUID) { items[accountID] = credential }
    func credential(for accountID: UUID) -> String? { items[accountID] }
    func deleteCredential(for accountID: UUID) { items[accountID] = nil }
}

private actor MoonshotTestNotifications: NotificationApplying {
    private(set) var operations: [NotificationOperation] = []
    @MainActor func configure() {}
    func requestAuthorization() async throws -> Bool { true }
    func authorizationStatus() async -> NotificationAuthorizationStatus { .authorized }
    func apply(_ operations: [NotificationOperation]) { self.operations += operations }
}
