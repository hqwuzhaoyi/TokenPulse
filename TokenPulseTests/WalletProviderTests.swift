import Foundation
import XCTest
@testable import TokenPulse

final class WalletProviderTests: XCTestCase {
    func testPoeWidgetTitleRemainsPointsInsteadOfMonetaryWallet() throws {
        let account = SubscriptionAccount(name: "Poe", provider: .poe)
        let snapshot = try PoeProviderClient.snapshot(Data(#"{"current_point_balance":125000}"#.utf8),
                                                      accountID: account.id, collectedAt: Date())
        let widget = WidgetAccountSnapshot(account: account, windows: snapshot.windows,
                                           collectedAt: snapshot.collectedAt, lastFailure: nil)
        let metric = try XCTUnwrap(widget.displayMetrics.first)
        XCTAssertEqual(metric.displayTitle, "剩余 points")
        XCTAssertNil(metric.ringFraction)
    }

    private let collectedAt = Date(timeIntervalSince1970: 1_000)

    func testPoeNumericAndStringPointsKeepUnitsAndDoNotInventQuota() throws {
        for value in ["0", "125000", "12345.67890123456789", "\"12345.67890123456789\""] {
            let accountID = UUID()
            let snapshot = try PoeProviderClient.snapshot(Data("{\"current_point_balance\":\(value)}".utf8),
                                                          accountID: accountID, collectedAt: collectedAt)
            let window = try XCTUnwrap(snapshot.windows.first)
            let balance = try XCTUnwrap(window.wallet)
            XCTAssertEqual(snapshot.accountID, accountID)
            XCTAssertEqual(snapshot.collectedAt, collectedAt)
            XCTAssertEqual(balance.total, Decimal(string: value.replacingOccurrences(of: "\"", with: "")))
            XCTAssertEqual(balance.currency, "points")
            XCTAssertFalse(balance.isMonetary)
            XCTAssertNil(balance.granted)
            XCTAssertNil(balance.toppedUp)
            XCTAssertNil(window.usedPercentage)
            XCTAssertNil(window.totalCount)
            XCTAssertNil(window.remainingCount)
            XCTAssertNil(window.resetsAt)
            XCTAssertNil(snapshot.walletAvailable)
            let metric = WidgetQuotaMetric(id: window.id, title: window.name, window: window)
            XCTAssertTrue(metric.valueText.hasSuffix(" points"))
            XCTAssertNil(metric.ringFraction)
            XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        }
    }

    func testPoeMissingMalformedAndBooleanBalancesNeverBecomeZero() {
        for body in ["{}", "{\"current_point_balance\":null}", "{\"current_point_balance\":true}",
                     "{\"current_point_balance\":\"NaN\"}", "{\"current_point_balance\":\"1.2oops\"}",
                     "{\"current_point_balance\":\"\"}", "{\"current_point_balance\":{}}"] {
            XCTAssertThrowsError(try PoeProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: collectedAt)) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
    }

    func testVercelExactUSDAndMissingBreakdownRetainZeroAndNegativeBalance() throws {
        for text in ["0", "-0.01", "95.500000000000000001"] {
            let snapshot = try VercelAIGatewayProviderClient.snapshot(
                Data("{\"balance\":\"\(text)\",\"total_used\":\"99999999.99\"}".utf8),
                accountID: UUID(), collectedAt: collectedAt
            )
            let window = try XCTUnwrap(snapshot.windows.first)
            let wallet = try XCTUnwrap(window.wallet)
            XCTAssertEqual(wallet.total, Decimal(string: text))
            XCTAssertEqual(wallet.currency, "USD")
            XCTAssertTrue(wallet.isMonetary)
            XCTAssertNil(wallet.granted)
            XCTAssertNil(wallet.toppedUp)
            XCTAssertEqual(QuotaFormatting.balance(wallet.granted, wallet: wallet), "未提供")
            XCTAssertEqual(QuotaFormatting.balance(wallet.toppedUp, wallet: wallet), "未提供")
            XCTAssertNil(window.usedPercentage)
            XCTAssertNil(window.totalCount)
            XCTAssertNil(window.resetsAt)
            XCTAssertNil(snapshot.walletAvailable)
        }
    }

    func testVercelRequiresStrictDecimalStringBalanceAndIgnoresLifetimeSpend() throws {
        for body in ["{}", "{\"balance\":null}", "{\"balance\":1}", "{\"balance\":true}",
                     "{\"balance\":\"1,000\"}", "{\"balance\":\"1e2\"}", "{\"balance\":\" 1\"}",
                     "{\"balance\":\"123456789012345678901234567890123456789\"}"] {
            XCTAssertThrowsError(try VercelAIGatewayProviderClient.snapshot(Data(body.utf8), accountID: UUID(), collectedAt: collectedAt)) {
                XCTAssertEqual($0 as? RefreshFailure, .unreadableResponse)
            }
        }
        let withoutSpend = try VercelAIGatewayProviderClient.snapshot(Data("{\"balance\":\"5\"}".utf8),
                                                                    accountID: UUID(), collectedAt: collectedAt)
        XCTAssertEqual(withoutSpend.windows.first?.wallet?.total, 5)
    }

    func testExistingDeepSeekWalletArchiveKeepsAmountsAndDefaultsToMoney() throws {
        let old = Data("{\"currency\":\"CNY\",\"total\":110,\"granted\":10,\"toppedUp\":100}".utf8)
        let wallet = try JSONDecoder().decode(WalletBalance.self, from: old)
        XCTAssertEqual(wallet, WalletBalance(currency: "CNY", total: 110, granted: 10, toppedUp: 100))
        XCTAssertTrue(wallet.isMonetary)
        XCTAssertEqual(try JSONDecoder().decode(WalletBalance.self, from: JSONEncoder().encode(wallet)), wallet)
    }

    func testBothRequestsUseKeyEnvelopeBearerGETAndExpectedEndpoint() async throws {
        for (provider, endpoint, body, label) in contracts {
            let transport = ExpansionWalletTransport(body: body)
            let controller = ProviderAuthenticationController()
            let credential = try controller.credential(provider: provider, apiKey: "  fixture-key\n")
            XCTAssertEqual(controller.loginConfiguration(for: provider).method, .apiKey)
            XCTAssertEqual(controller.loginConfiguration(for: provider).credentialLabel, label)
            let accountID = UUID()
            let client = ProviderQuotaClient(provider: provider, transport: transport, now: { Date(timeIntervalSince1970: 1_000) })
            let result = try await client.quotaResult(for: accountID, credential: credential)
            XCTAssertEqual(result.snapshot.accountID, accountID)
            XCTAssertEqual(result.snapshot.collectedAt, collectedAt)
            XCTAssertNil(result.updatedCredential)
            let capturedRequest = await transport.lastRequest()
            let request = try XCTUnwrap(capturedRequest)
            XCTAssertEqual(request.url?.absoluteString, endpoint)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertNil(request.url?.query)
            XCTAssertNil(request.httpBody)
        }
    }

    func testBothProvidersMapUnauthorizedRateLimitAndServerFailures() async throws {
        for (provider, _, _, _) in contracts {
            let credential = try ProviderAuthenticationController().credential(provider: provider, apiKey: "fixture-key")
            for (status, expected) in [(401, RefreshFailure.invalidCredential), (403, .invalidCredential),
                                       (429, .rateLimited), (500, .server)] {
                let client = ProviderQuotaClient(provider: provider, transport: ExpansionWalletTransport(status: status, body: "{}"))
                do {
                    _ = try await client.quota(for: UUID(), credential: credential)
                    XCTFail("Expected failure")
                } catch { XCTAssertEqual(error as? RefreshFailure, expected) }
            }
        }
    }

    func testPoeNeverReceivesMoneyPercentageOrResetAlertsEvenWithDefensivePayload() {
        let window = QuotaWindow(id: "poe.points", name: "points", scope: nil, usedPercentage: 100,
                                 remainingCount: nil, totalCount: nil, resetsAt: collectedAt.addingTimeInterval(3_600),
                                 wallet: WalletBalance(currency: "points", total: 0, isMonetary: false))
        let accountID = UUID()
        let result = NotificationPlanner().planSuccessfulRefresh(
            accountID: accountID, accountName: "Poe", previousSnapshot: nil,
            newSnapshot: QuotaSnapshot(accountID: accountID, windows: [window], collectedAt: collectedAt, walletAvailable: false),
            settings: AccountReminderSettings(walletCurrency: "points", walletThresholds: ["points": 100]),
            ledger: ReminderLedger(), now: collectedAt
        )
        XCTAssertTrue(result.operations.isEmpty)
        XCTAssertNil(WidgetQuotaMetric(id: "points", title: "points", window: window).ringFraction)
    }

    func testVercelLowUSDUsesExistingThresholdDeduplicationAndRecovery() throws {
        let accountID = UUID()
        var ledger = ReminderLedger()
        for (index, text, expectedCount) in [(0, "2", 1), (1, "1", 0), (2, "3", 0), (3, "-0.01", 1)] {
            let date = collectedAt.addingTimeInterval(Double(index))
            let snapshot = try VercelAIGatewayProviderClient.snapshot(Data("{\"balance\":\"\(text)\"}".utf8),
                                                                    accountID: accountID, collectedAt: date)
            let result = NotificationPlanner().planSuccessfulRefresh(
                accountID: accountID, accountName: "Vercel", previousSnapshot: nil, newSnapshot: snapshot,
                settings: AccountReminderSettings(), ledger: ledger, now: date
            )
            ledger = result.ledger
            let notifications = result.operations.compactMap { operation -> ReminderNotification? in
                if case .deliver(let notification) = operation { return notification }
                return nil
            }
            XCTAssertEqual(notifications.count, expectedCount)
            XCTAssertTrue(notifications.allSatisfy { $0.kind == .walletAlert && $0.body.contains("USD") })
        }
    }

    @MainActor
    func testBothProvidersKeepAccountsCredentialsFailureDataAndLocalRestartIsolated() async throws {
        for (provider, _, body, _) in contracts {
            let suite = "com.tokenpulse.tests.wallet-expansion.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(false, forKey: "cloudSyncEnabled")
            let credentials = ExpansionWalletCredentials()
            let transport = ExpansionWalletTransport(body: body)
            let client = ProviderQuotaClient(provider: provider, transport: transport)
            func monitor() -> QuotaMonitor {
                QuotaMonitor(accountStore: LocalAccountStateStore(suiteName: suite), credentialStore: credentials,
                             quotaClient: client, configurationStore: LocalAccountConfigurationStore(suiteName: suite),
                             providerClient: { _ in client })
            }
            let firstMonitor = monitor()
            await firstMonitor.start(refresh: false)
            let controller = ProviderAuthenticationController()
            let keyA = try controller.credential(provider: provider, apiKey: "key-a")
            let keyB = try controller.credential(provider: provider, apiKey: "key-b")
            await firstMonitor.addAccount(name: "A", credential: keyA, provider: provider)
            await firstMonitor.addAccount(name: "B", credential: keyB, provider: provider)
            let a = try XCTUnwrap(firstMonitor.states.first { $0.account.name == "A" })
            let b = try XCTUnwrap(firstMonitor.states.first { $0.account.name == "B" })
            XCTAssertNotNil(a.snapshot)
            XCTAssertNotNil(b.snapshot)
            XCTAssertEqual(a.snapshot?.accountID, a.id)
            XCTAssertEqual(b.snapshot?.accountID, b.id)
            XCTAssertNotEqual(a.snapshot?.windows.first?.wallet?.total, b.snapshot?.windows.first?.wallet?.total)
            await transport.failKeyA()
            await firstMonitor.refresh(accountID: a.id)
            XCTAssertEqual(firstMonitor.states.first { $0.id == a.id }?.snapshot, a.snapshot)
            XCTAssertEqual(firstMonitor.states.first { $0.id == a.id }?.lastFailure, .invalidCredential)
            XCTAssertNil(firstMonitor.states.first { $0.id == b.id }?.lastFailure)
            let restored = monitor()
            await restored.start(refresh: false)
            let storedA = try await credentials.credential(for: a.id)
            let storedB = try await credentials.credential(for: b.id)
            XCTAssertEqual(storedA, keyA)
            XCTAssertEqual(storedB, keyB)
            XCTAssertEqual(restored.states.count, 2)
            let synced = try JSONDecoder().decode([AccountQuotaState].self, from: JSONEncoder().encode(restored.states))
            XCTAssertEqual(synced, restored.states)
            let widgetStore = WidgetSnapshotStore(defaults: UserDefaults(suiteName: suite), key: "expansion.widgets")
            try await widgetStore.save(states: restored.states)
            let widgets = await widgetStore.load()
            let widgetA = try XCTUnwrap(widgets.first { $0.id == a.id })
            XCTAssertEqual(widgetA.collectedAt, a.snapshot?.collectedAt)
            XCTAssertEqual(widgetA.lastFailure, .invalidCredential)
            let walletA = try XCTUnwrap(a.snapshot?.windows.first?.wallet)
            XCTAssertEqual(widgetA.displayMetrics.first?.valueText, QuotaFormatting.balance(walletA.total, wallet: walletA))
            XCTAssertNil(widgetA.displayMetrics.first?.ringFraction)
            let deleted = await restored.deleteAccount(accountID: a.id)
            XCTAssertTrue(deleted)
            let deletedCredential = try await credentials.credential(for: a.id)
            XCTAssertNil(deletedCredential)
            XCTAssertEqual(restored.states.map(\.id), [b.id])
        }
    }

    private var contracts: [(Provider, String, String, String)] {
        [(.poe, "https://api.poe.com/usage/current_balance", "{\"current_point_balance\":125000}", "Poe API Key"),
         (.vercelAIGateway, "https://ai-gateway.vercel.sh/v1/credits", "{\"balance\":\"95.50\",\"total_used\":\"4.50\"}", "AI Gateway API Key")]
    }
}

private actor ExpansionWalletTransport: ProviderTransport {
    let status: Int
    let body: String
    private var request: URLRequest?
    private var shouldFailKeyA = false
    init(status: Int = 200, body: String) { self.status = status; self.body = body }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        let status = shouldFailKeyA && request.value(forHTTPHeaderField: "Authorization") == "Bearer key-a" ? 401 : status
        let reply: String
        if request.value(forHTTPHeaderField: "Authorization") == "Bearer key-b" {
            reply = body.contains("current_point_balance") ? "{\"current_point_balance\":20}" : "{\"balance\":\"20\"}"
        } else { reply = body }
        return (Data(reply.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    func lastRequest() -> URLRequest? { request }
    func failKeyA() { shouldFailKeyA = true }
}

private actor ExpansionWalletCredentials: CredentialStoring {
    private var values: [UUID: String] = [:]
    func save(_ credential: String, for accountID: UUID) async throws { values[accountID] = credential }
    func credential(for accountID: UUID) async throws -> String? { values[accountID] }
    func deleteCredential(for accountID: UUID) async throws { values[accountID] = nil }
}

final class HybridWalletReminderTests: XCTestCase {
    func testLegacyWalletSettingDecodesAndExplicitWalletToggleRoundTrips() throws {
        let old = Data(#"{"quotaAlertsEnabled":false,"resetRemindersEnabled":true,"thresholds":[80]}"#.utf8)
        var settings = try JSONDecoder().decode(AccountReminderSettings.self, from: old)
        XCTAssertNil(settings.walletAlertsEnabled)
        XCTAssertFalse(settings.effectiveWalletAlertsEnabled)
        settings.walletAlertsEnabled = true
        XCTAssertEqual(try JSONDecoder().decode(AccountReminderSettings.self, from: JSONEncoder().encode(settings)), settings)
        XCTAssertTrue(settings.effectiveWalletAlertsEnabled)
    }

    func testQuotaAndMonetaryWalletTogglesAreIndependentAndNonMoneyNeverAlerts() {
        let accountID = UUID()
        let quota = QuotaWindow(id: "quota", name: "套餐", scope: nil, usedPercentage: 95,
                                remainingCount: nil, totalCount: nil, resetsAt: nil)
        let wallet = QuotaWindow(id: "wallet", name: "钱包", scope: nil, usedPercentage: nil,
                                 remainingCount: nil, totalCount: nil, resetsAt: nil,
                                 wallet: WalletBalance(currency: "USD", total: 1))
        let credits = QuotaWindow(id: "credits", name: "积分", scope: nil, usedPercentage: nil,
                                  remainingCount: nil, totalCount: nil, resetsAt: nil,
                                  wallet: WalletBalance(currency: "HC", total: 0, isMonetary: false))
        for (quotaEnabled, walletEnabled, expected) in [
            (false, false, Set<ReminderNotificationKind>()), (true, false, Set([.quotaAlert])),
            (false, true, Set([.walletAlert])), (true, true, Set([.quotaAlert, .walletAlert])),
        ] {
            let date = Date(timeIntervalSince1970: 100)
            let result = NotificationPlanner().planSuccessfulRefresh(
                accountID: accountID, accountName: "混合", previousSnapshot: nil,
                newSnapshot: QuotaSnapshot(accountID: accountID, windows: [quota, wallet, credits], collectedAt: date),
                settings: AccountReminderSettings(quotaAlertsEnabled: quotaEnabled, walletAlertsEnabled: walletEnabled),
                ledger: ReminderLedger(), now: date
            )
            let alerts = result.operations.compactMap { operation -> ReminderNotificationKind? in
                if case .deliver(let notification) = operation { return notification.kind }
                return nil
            }
            XCTAssertEqual(Set(alerts), expected)
            XCTAssertNil(result.ledger.walletAlertState(accountID: accountID, currency: "HC"))
        }
    }
}

extension HybridWalletReminderTests {
    @MainActor
    func testGlobalDisableOverridesExplicitWalletEnableWithoutChangingAccountPreferences() async throws {
        let suite = "com.tokenpulse.tests.hybrid-global.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "notificationsEnabled")
        let adapter = HybridWalletNotificationAdapter()
        let runtime = NotificationRuntime(defaults: defaults, adapter: adapter)
        let account = SubscriptionAccount(name: "混合", provider: .deepSeek)
        let snapshot = QuotaSnapshot(accountID: account.id, windows: [
            QuotaWindow(id: "quota", name: "套餐", scope: nil, usedPercentage: 95,
                        remainingCount: nil, totalCount: nil, resetsAt: nil),
            QuotaWindow(id: "wallet", name: "钱包", scope: nil, usedPercentage: nil,
                        remainingCount: nil, totalCount: nil, resetsAt: nil,
                        wallet: WalletBalance(currency: "USD", total: 1)),
        ], collectedAt: Date())
        let state = AccountQuotaState(account: account, snapshot: snapshot)
        let settings = AccountReminderSettings(walletAlertsEnabled: true)
        try await runtime.fresh(state: state, previous: nil, settings: settings)
        let disabled = await adapter.delivered
        XCTAssertTrue(disabled.isEmpty)
        var config = AccountConfiguration(account: account, reminders: settings)
        config.reminders.resetRemindersEnabled = false
        let feedback = await runtime.setEnabled(true, configurations: [config], states: [state])
        XCTAssertEqual(feedback, .enabled)
        let resumed = AccountQuotaState(account: account, snapshot: QuotaSnapshot(
            accountID: account.id, windows: snapshot.windows,
            collectedAt: snapshot.collectedAt.addingTimeInterval(1)))
        try await runtime.fresh(state: resumed, previous: state, settings: settings)
        let enabled = await adapter.delivered
        XCTAssertEqual(Set(enabled.map(\.kind)), Set([.quotaAlert, .walletAlert]))
        XCTAssertTrue(settings.effectiveWalletAlertsEnabled)
    }
}

private actor HybridWalletNotificationAdapter: NotificationApplying {
    private(set) var delivered: [ReminderNotification] = []
    @MainActor func configure() {}
    func authorizationStatus() async -> NotificationAuthorizationStatus { .authorized }
    func requestAuthorization() async throws -> Bool { true }
    func apply(_ operations: [NotificationOperation]) async throws {
        for operation in operations {
            if case .deliver(let notification) = operation { delivered.append(notification) }
        }
    }
}
