import Foundation
import XCTest
@testable import TokenPulse

final class WalletTests: XCTestCase {
    private let accountID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    func testDeepSeekPreservesExactMoneyAndSeparateCurrenciesWithoutQuotaOrReset() throws {
        let data = Data(#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.000000000000000001","granted_balance":"10.000000000000000001","topped_up_balance":"100.00"},{"currency":"USD","total_balance":"-0.01","granted_balance":"0","topped_up_balance":"-0.01"}]}"#.utf8)
        let snapshot = try DeepSeekProviderClient.snapshot(data, accountID: accountID, collectedAt: Date())
        XCTAssertEqual(snapshot.walletAvailable, true)
        XCTAssertEqual(snapshot.windows.compactMap(\.wallet).map(\.currency), ["CNY", "USD"])
        XCTAssertEqual(snapshot.windows[0].wallet?.total, Decimal(string: "110.000000000000000001"))
        XCTAssertEqual(snapshot.windows[0].wallet?.granted, Decimal(string: "10.000000000000000001"))
        XCTAssertEqual(snapshot.windows[0].wallet?.toppedUp, 100)
        XCTAssertEqual(snapshot.windows[1].wallet?.total, Decimal(string: "-0.01"))
        for window in snapshot.windows {
            XCTAssertNil(window.usedPercentage)
            XCTAssertNil(window.totalCount)
            XCTAssertNil(window.remainingCount)
            XCTAssertNil(window.resetsAt)
        }
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }

    func testDeepSeekRejectsMalformedMoneyAndSchemaInsteadOfDisplayingZero() throws {
        for amount in ["NaN", "1.2oops", "1,000", "", " 2", "2\n", "1e2",
                       "123456789012345678901234567890123456789"] {
            let row: [String: String] = ["currency": "CNY", "total_balance": amount,
                                        "granted_balance": "0", "topped_up_balance": "0"]
            let data = try JSONSerialization.data(withJSONObject: ["is_available": true, "balance_infos": [row]])
            XCTAssertThrowsError(try DeepSeekProviderClient.snapshot(data, accountID: accountID, collectedAt: Date())) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse, amount)
            }
        }
        for body in [
            #"{"is_available":true,"balance_infos":[{"currency":"EUR","total_balance":"1","granted_balance":"0","topped_up_balance":"1"}]}"#,
            #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":1,"granted_balance":"0","topped_up_balance":"1"}]}"#,
            #"{"is_available":1,"balance_infos":[]}"#,
            #"{"balance_infos":[]}"#,
            #"{"is_available":false}"#,
            #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"1","granted_balance":"0","topped_up_balance":"1"},{"currency":"CNY","total_balance":"2","granted_balance":"0","topped_up_balance":"2"}]}"#,
        ] {
            XCTAssertThrowsError(try DeepSeekProviderClient.snapshot(Data(body.utf8), accountID: accountID, collectedAt: Date()))
        }
    }

    func testDeepSeekAuthenticatedQueryKeepsAvailabilityWithEmptyBalances() async throws {
        let transport = WalletTransport(status: 200, body: #"{"is_available":false,"balance_infos":[]}"#)
        let client = DeepSeekProviderClient(transport: transport, now: { Date(timeIntervalSince1970: 100) })
        let credential = ProviderCredentialEnvelope(provider: .deepSeek, kind: .apiKey, accessToken: "test-key")
        let result = try await client.quota(accountID: accountID, credential: credential)
        XCTAssertEqual(result.snapshot.accountID, accountID)
        XCTAssertEqual(result.snapshot.collectedAt, Date(timeIntervalSince1970: 100))
        XCTAssertTrue(result.snapshot.windows.isEmpty)
        XCTAssertEqual(result.snapshot.walletAvailable, false)
        let request = await transport.request()
        XCTAssertEqual(request?.url?.absoluteString, "https://api.deepseek.com/user/balance")
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertTrue(request?.url?.query == nil)
    }

    func testDeepSeekQueryMapsFailuresWithoutManufacturingWalletState() async throws {
        for (status, expected) in [(401, RefreshFailure.invalidCredential), (429, .rateLimited), (503, .server)] {
            let client = DeepSeekProviderClient(transport: WalletTransport(status: status, body: "{}"), now: { Date() })
            do {
                _ = try await client.quota(accountID: accountID, credential: ProviderCredentialEnvelope(
                    provider: .deepSeek, kind: .apiKey, accessToken: "test-key"
                ))
                XCTFail("Expected query failure")
            } catch {
                XCTAssertEqual(error as? RefreshFailure, expected)
            }
        }
    }

    @MainActor
    func testNotificationRuntimePreservesUnavailableWithoutWalletWindowsAndPersistsDeduplication() async throws {
        let suite = "com.tokenpulse.tests.wallet-runtime.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "notificationsEnabled")
        let adapter = WalletNotificationAdapter()
        let runtime = NotificationRuntime(defaults: defaults, adapter: adapter)
        let account = SubscriptionAccount(id: accountID, name: "DeepSeek", provider: .deepSeek)
        let state = AccountQuotaState(account: account, snapshot: QuotaSnapshot(
            accountID: accountID, windows: [], collectedAt: Date(), walletAvailable: false
        ))
        try await runtime.fresh(state: state, previous: nil, settings: AccountReminderSettings(walletCurrency: "USD"))
        let restored = NotificationRuntime(defaults: defaults, adapter: adapter)
        try await restored.fresh(state: state, previous: nil, settings: AccountReminderSettings(walletCurrency: "USD"))
        let notifications = await adapter.notifications()
        XCTAssertEqual(notifications.map(\.kind), [.walletAlert])
        XCTAssertEqual(notifications.map(\.body), ["余额不足，无法调用 API"])
    }

    func testWalletFirstLowAndUnavailableCombineAndRecoveryRearms() {
        let first = plan(total: 10, available: false, time: 100)
        let alerts = deliveries(first)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.kind, .walletAlert)
        XCTAssertTrue(alerts.first?.body.contains("CNY") == true)
        XCTAssertTrue(alerts.first?.body.contains("无法调用 API") == true)
        let repeated = plan(total: 9, available: false, time: 110, ledger: first.ledger)
        XCTAssertTrue(repeated.operations.isEmpty)
        let restored = plan(total: 11, available: true, time: 120, ledger: repeated.ledger)
        XCTAssertTrue(restored.operations.isEmpty)
        let lowAgain = plan(total: 10, available: false, time: 130, ledger: restored.ledger)
        XCTAssertEqual(deliveries(lowAgain).count, 1)
    }

    func testOnlySelectedCurrencyAlertsAndMissingCurrencyDoesNotBecomeZero() {
        let usdSettings = AccountReminderSettings(walletCurrency: "USD")
        let missing = plan(total: 0, available: true, time: 100, settings: usdSettings)
        XCTAssertTrue(missing.operations.isEmpty)
        let unavailable = plan(total: nil, available: false, time: 110, settings: usdSettings, ledger: missing.ledger)
        XCTAssertEqual(deliveries(unavailable).map(\.body), ["余额不足，无法调用 API"])
        let settings = AccountReminderSettings(walletCurrency: "CNY", walletThresholds: ["CNY": 5])
        XCTAssertTrue(plan(total: 6, available: true, time: 100, settings: settings).operations.isEmpty)
        XCTAssertEqual(deliveries(plan(total: 5, available: true, time: 100, settings: settings)).count, 1)
    }

    func testOutOfOrderRecoveryCannotRearmAndRemoteLatestObservationWins() throws {
        let low = plan(total: 1, available: false, time: 100)
        let staleHigh = plan(total: 20, available: true, time: 90, ledger: low.ledger)
        XCTAssertEqual(staleHigh.ledger, low.ledger)
        XCTAssertTrue(plan(total: 1, available: false, time: 110, ledger: staleHigh.ledger).operations.isEmpty)

        let recovered = plan(total: 20, available: true, time: 120, ledger: low.ledger)
        let merged = low.ledger.merging(recovered.ledger)
        XCTAssertEqual(merged, recovered.ledger)
        XCTAssertEqual(recovered.ledger.merging(low.ledger), recovered.ledger)
        XCTAssertEqual(deliveries(plan(total: 1, available: false, time: 130, ledger: merged)).count, 1)
        XCTAssertEqual(try JSONDecoder().decode(ReminderLedger.self, from: JSONEncoder().encode(merged)), merged)
    }

    func testAvailabilityRecoveryDoesNotRearmStillLowBalanceAndViceVersa() {
        let first = plan(total: 1, available: false, time: 100)
        let available = plan(total: 1, available: true, time: 110, ledger: first.ledger)
        XCTAssertTrue(available.operations.isEmpty)
        let unavailableAgain = plan(total: 1, available: false, time: 120, ledger: available.ledger)
        XCTAssertEqual(deliveries(unavailableAgain).map(\.body), ["余额不足，无法调用 API"])
        let replenished = plan(total: 20, available: false, time: 130, ledger: unavailableAgain.ledger)
        let lowAgain = plan(total: 1, available: false, time: 140, ledger: replenished.ledger)
        XCTAssertEqual(deliveries(lowAgain).count, 1)
        XCTAssertFalse(deliveries(lowAgain)[0].body.contains("无法调用 API"))
    }

    func testDisabledWalletAlertCanNotifyAfterEnablingOnNextSuccessfulObservation() {
        let disabled = plan(total: 0, available: false, time: 100,
                            settings: AccountReminderSettings(quotaAlertsEnabled: false))
        XCTAssertTrue(disabled.operations.isEmpty)
        XCTAssertEqual(deliveries(plan(total: 0, available: false, time: 110, ledger: disabled.ledger)).count, 1)
    }

    func testExistingSettingsAndLedgerDecodeWithWalletDefaults() throws {
        let settings = try JSONDecoder().decode(AccountReminderSettings.self, from: Data(
            #"{"quotaAlertsEnabled":true,"resetRemindersEnabled":true,"thresholds":[80,95,100]}"#.utf8
        ))
        XCTAssertNil(settings.walletCurrency)
        XCTAssertEqual(settings.walletThreshold(for: "CNY"), 10)
        XCTAssertEqual(settings.walletThreshold(for: "USD"), 2)
        let ledger = try JSONDecoder().decode(ReminderLedger.self, from: Data(
            #"{"quotaAlerts":[],"expectedResets":[],"confirmedResets":[],"windowCycles":[],"pendingResetSchedules":[]}"#.utf8
        ))
        XCTAssertNil(ledger.walletAlertState(accountID: accountID, currency: "CNY"))
    }

    func testDeepSeekAPIKeyCredentialIsEncodedAsAKeyEnvelope() throws {
        let controller = ProviderAuthenticationController()
        let encoded = try controller.credential(provider: .deepSeek, apiKey: "  sk-test-key\n")
        let envelope = try ProviderCredentialEnvelope.decode(encoded, expectedProvider: .deepSeek)
        XCTAssertEqual(envelope.kind, .apiKey)
        XCTAssertEqual(envelope.accessToken, "sk-test-key")
        XCTAssertEqual(envelope.refreshToken, nil)
        XCTAssertEqual(controller.loginConfiguration(for: .deepSeek).method, .apiKey)
        XCTAssertEqual(controller.loginConfiguration(for: .deepSeek).credentialLabel, "DeepSeek API Key")
    }

    @MainActor
    func testTwoDeepSeekAccountsKeepCredentialsPreferencesAndBalancesIsolatedAcrossRestart() async throws {
        let suite = "com.tokenpulse.tests.wallet-accounts.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = WalletCredentialStore()
        let client = WalletStubClient(totals: ["key-a": 110, "key-b": 20])
        let monitor = QuotaMonitor(
            accountStore: LocalAccountStateStore(suiteName: suite),
            credentialStore: credentials,
            quotaClient: client,
            configurationStore: LocalAccountConfigurationStore(suiteName: suite),
            providerClient: { _ in client }
        )
        await monitor.start(refresh: false)
        await monitor.addAccount(name: "钱包 A", credential: "key-a", provider: .deepSeek)
        await monitor.addAccount(name: "钱包 B", credential: "key-b", provider: .deepSeek)
        let first = try XCTUnwrap(monitor.states.first { $0.account.name == "钱包 A" })
        let second = try XCTUnwrap(monitor.states.first { $0.account.name == "钱包 B" })
        XCTAssertEqual(first.snapshot?.windows.first?.wallet?.total, 110)
        XCTAssertEqual(second.snapshot?.windows.first?.wallet?.total, 20)
        let settings = AccountReminderSettings(walletCurrency: "USD", walletThresholds: ["USD": 3])
        await monitor.updateReminders(settings, accountID: second.id)

        let restored = QuotaMonitor(
            accountStore: LocalAccountStateStore(suiteName: suite),
            credentialStore: credentials,
            quotaClient: client,
            configurationStore: LocalAccountConfigurationStore(suiteName: suite),
            providerClient: { _ in client }
        )
        await restored.start(refresh: false)
        let firstCredential = try await credentials.credential(for: first.id)
        let secondCredential = try await credentials.credential(for: second.id)
        XCTAssertEqual(restored.states.count, 2)
        XCTAssertEqual(firstCredential, "key-a")
        XCTAssertEqual(secondCredential, "key-b")
        XCTAssertEqual(restored.configuration(for: second.id)?.reminders, settings)
        XCTAssertEqual(restored.states.first { $0.id == first.id }?.snapshot?.windows.first?.wallet?.total, 110)
        XCTAssertEqual(restored.states.first { $0.id == second.id }?.snapshot?.windows.first?.wallet?.total, 20)
    }

    func testWalletWindowsNeverEnterQuotaPercentageOrResetReminders() {
        let date = Date(timeIntervalSince1970: 100)
        // Defensive payload: even a wallet window carrying a percentage and a reset time must stay out
        // of the package-quota and reset pipelines.
        let wallet = QuotaWindow(
            id: "deepseek.wallet.CNY", name: "CNY 钱包", scope: nil,
            usedPercentage: 100, remainingCount: nil, totalCount: nil,
            resetsAt: date.addingTimeInterval(3_600),
            wallet: WalletBalance(currency: "CNY", total: 100, granted: 0, toppedUp: 100)
        )
        let result = NotificationPlanner().planSuccessfulRefresh(
            accountID: accountID, accountName: "DeepSeek", previousSnapshot: nil,
            newSnapshot: QuotaSnapshot(accountID: accountID, windows: [wallet], collectedAt: date,
                                       walletAvailable: true),
            settings: AccountReminderSettings(walletCurrency: "CNY", walletThresholds: ["CNY": 1]),
            ledger: ReminderLedger(), now: date
        )
        XCTAssertTrue(result.operations.isEmpty)
    }

    private func plan(total: Decimal?, available: Bool, time: TimeInterval,
                       settings: AccountReminderSettings = AccountReminderSettings(),
                       ledger: ReminderLedger = ReminderLedger()) -> NotificationPlanningResult {
        let windows = total.map { value in
            [QuotaWindow(id: "deepseek.wallet.CNY", name: "CNY 钱包", scope: nil,
                         usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                         wallet: WalletBalance(currency: "CNY", total: value, granted: 0, toppedUp: value))]
        } ?? []
        let date = Date(timeIntervalSince1970: time)
        return NotificationPlanner().planSuccessfulRefresh(
            accountID: accountID, accountName: "DeepSeek", previousSnapshot: nil,
            newSnapshot: QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: date,
                                       walletAvailable: available),
            settings: settings, ledger: ledger, now: date
        )
    }

    private func deliveries(_ result: NotificationPlanningResult) -> [ReminderNotification] {
        result.operations.compactMap {
            if case .deliver(let notification) = $0 { return notification }
            return nil
        }
    }
}

private actor WalletCredentialStore: CredentialStoring {
    private var values: [UUID: String] = [:]
    func save(_ credential: String, for accountID: UUID) async throws { values[accountID] = credential }
    func credential(for accountID: UUID) async throws -> String? { values[accountID] }
    func deleteCredential(for accountID: UUID) async throws { values[accountID] = nil }
}

private actor WalletStubClient: QuotaQuerying {
    let totals: [String: Decimal]

    init(totals: [String: Decimal]) { self.totals = totals }

    func quota(for accountID: UUID, credential: String) async throws -> QuotaSnapshot {
        let total = totals[credential] ?? 0
        return QuotaSnapshot(
            accountID: accountID,
            windows: [QuotaWindow(id: "deepseek.wallet.CNY", name: "CNY 钱包", scope: nil,
                                  usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                                  wallet: WalletBalance(currency: "CNY", total: total, granted: 0, toppedUp: total))],
            collectedAt: Date(timeIntervalSince1970: 100), walletAvailable: true
        )
    }
}

private actor WalletTransport: ProviderTransport {
    let status: Int
    let body: String
    private var receivedRequest: URLRequest?

    init(status: Int, body: String) {
        self.status = status
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        receivedRequest = request
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status,
                                               httpVersion: nil, headerFields: nil)!)
    }

    func request() -> URLRequest? { receivedRequest }
}

private actor WalletNotificationAdapter: NotificationApplying {
    private var delivered: [ReminderNotification] = []

    @MainActor func configure() {}
    func authorizationStatus() async -> NotificationAuthorizationStatus { .authorized }
    func requestAuthorization() async throws -> Bool { true }
    func apply(_ operations: [NotificationOperation]) async throws {
        for operation in operations {
            if case .deliver(let notification) = operation { delivered.append(notification) }
        }
    }
    func notifications() -> [ReminderNotification] { delivered }
}
