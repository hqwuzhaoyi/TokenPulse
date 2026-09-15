import Foundation
import XCTest
@testable import TokenPulse

/// Wallet presentation tests shared by the iPhone widget, the Watch widget and the Watch app pages.
final class WalletPresentationTests: XCTestCase {
    private func walletWindow(_ currency: String, total: Decimal) -> QuotaWindow {
        QuotaWindow(
            id: "deepseek.wallet.\(currency)", name: "\(currency) 钱包", scope: nil,
            usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
            unit: currency,
            wallet: WalletBalance(currency: currency, total: total, granted: 1, toppedUp: total - 1)
        )
    }

    func testSelectedWalletCurrencyComesFromConfigurationAndReachesTheWidgetSnapshot() async throws {
        let suite = "com.tokenpulse.tests.wallet-presentation.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = WidgetSnapshotStore(defaults: UserDefaults(suiteName: suite), key: "wallet-presentation")
        let account = SubscriptionAccount(name: "DeepSeek 钱包", provider: .deepSeek)
        let state = AccountQuotaState(account: account, snapshot: QuotaSnapshot(
            accountID: account.id,
            windows: [walletWindow("CNY", total: 110), walletWindow("USD", total: 8)],
            collectedAt: Date(timeIntervalSince1970: 500)
        ))

        // No configuration yet: the first returned currency is the display fallback.
        try await store.save(states: [state])
        let fallbackSnapshots = await store.load()
        let fallback = try XCTUnwrap(fallbackSnapshots.first)
        XCTAssertNil(fallback.walletCurrency)
        XCTAssertEqual(fallback.displayMetrics.map { $0.window?.wallet?.currency }, ["CNY"])

        // Selecting USD in the account settings must republish the same account with USD.
        var configuration = AccountConfiguration(account: account)
        configuration.reminders.walletCurrency = "USD"
        try await store.save(states: [state], configurations: [configuration])
        let selectedSnapshots = await store.load()
        let selected = try XCTUnwrap(selectedSnapshots.first)
        XCTAssertEqual(selected.walletCurrency, "USD")
        XCTAssertEqual(selected.displayMetrics.map { $0.window?.wallet?.currency }, ["USD"])
        XCTAssertEqual(selected.displayMetrics.first?.valueText, "8 USD")
        XCTAssertEqual(selected.collectedAt, Date(timeIntervalSince1970: 500))
    }

    func testMissingSelectedCurrencyShowsNotProvidedWithoutAutoSwitching() async throws {
        let account = SubscriptionAccount(name: "DeepSeek 钱包", provider: .deepSeek)
        let snapshot = WidgetAccountSnapshot(
            account: account,
            windows: [walletWindow("CNY", total: 110)],
            collectedAt: Date(),
            lastFailure: nil,
            walletCurrency: "USD"
        )
        let metric = try XCTUnwrap(snapshot.displayMetrics.first)
        XCTAssertEqual(metric.title, "USD")
        XCTAssertNil(metric.window)
        XCTAssertEqual(metric.valueText, "未提供")
        XCTAssertNil(metric.ringFraction)
    }

    func testEmptyBalanceArrayKeepsUnavailableStatusWithoutFabricatingZero() {
        let account = SubscriptionAccount(name: "DeepSeek 钱包", provider: .deepSeek)
        for available in [true, false] {
            let snapshot = WidgetAccountSnapshot(
                account: account, windows: [], collectedAt: Date(), lastFailure: nil,
                walletCurrency: "CNY", walletAvailable: available
            )
            // The selected currency is still shown as "未提供" rather than dropped or zeroed.
            XCTAssertEqual(snapshot.displayMetrics.map(\.valueText), ["未提供"])
            XCTAssertNil(snapshot.displayMetrics.first?.window)
            XCTAssertNil(snapshot.displayMetrics.first?.ringFraction)
            XCTAssertEqual(snapshot.walletAvailable, available)
        }
    }

    func testWalletMetricsNeverExposeUsagePercentageOrResetTimeline() {
        let zero = WalletBalance(currency: "USD", total: 0, granted: 0, toppedUp: 0)
        let window = QuotaWindow(
            id: "deepseek.wallet.USD", name: "USD 钱包", scope: nil,
            usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil, wallet: zero
        )
        let metric = WidgetQuotaMetric(id: "wallet.USD", title: "USD", window: window)
        XCTAssertEqual(metric.valueText, "0 USD")
        XCTAssertNil(metric.ringFraction)
        XCTAssertNil(window.usedPercentage)
        XCTAssertNil(window.resetsAt)
        XCTAssertEqual(QuotaFormatting.money(zero.total, currency: "USD"), "0 USD")
    }

    func testWalletRefreshFailureKeepsPreviousBalanceAndCollectedAtOnlyForThatAccount() async throws {
        let suite = "com.tokenpulse.tests.wallet-failure.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = WidgetSnapshotStore(defaults: UserDefaults(suiteName: suite), key: "wallet-failure")
        let failing = SubscriptionAccount(name: "钱包 A", provider: .deepSeek)
        let healthy = SubscriptionAccount(name: "钱包 B", provider: .deepSeek)
        let oldDate = Date(timeIntervalSince1970: 100)
        let states = [
            AccountQuotaState(
                account: failing,
                snapshot: QuotaSnapshot(accountID: failing.id, windows: [walletWindow("CNY", total: 50)],
                                        collectedAt: oldDate),
                lastFailure: .network
            ),
            AccountQuotaState(
                account: healthy,
                snapshot: QuotaSnapshot(accountID: healthy.id, windows: [walletWindow("CNY", total: 20)],
                                        collectedAt: Date(timeIntervalSince1970: 200)),
                lastFailure: nil
            ),
        ]
        try await store.save(states: states)
        let loaded = await store.load()
        let failingSnapshot = try XCTUnwrap(loaded.first { $0.id == failing.id })
        XCTAssertEqual(failingSnapshot.lastFailure, .network)
        XCTAssertEqual(failingSnapshot.collectedAt, oldDate)
        XCTAssertEqual(failingSnapshot.displayMetrics.first?.valueText, "50 CNY")
        let healthySnapshot = try XCTUnwrap(loaded.first { $0.id == healthy.id })
        XCTAssertNil(healthySnapshot.lastFailure)
        XCTAssertEqual(healthySnapshot.displayMetrics.first?.valueText, "20 CNY")
    }

    func testQoderWidgetItemSelectionKeepsBudgetsSeparate() {
        let account = SubscriptionAccount(name: "Qoder", provider: .qoderInternational)
        let personal = QuotaWindow(id: "qoder.userQuota", name: "个人额度", scope: nil,
                                   usedPercentage: 25, remainingCount: 750, totalCount: 1_000, resetsAt: nil)
        let organization = QuotaWindow(id: "qoder.orgResourcePackage", name: "组织资源包", scope: nil,
                                       usedPercentage: 50, remainingCount: 100, totalCount: 200, resetsAt: nil)
        let snapshot = WidgetAccountSnapshot(account: account, windows: [personal, organization],
                                             collectedAt: Date(), lastFailure: nil)

        XCTAssertEqual(snapshot.selectingQoderItem("personal").windows.map(\.id), ["qoder.userQuota"])
        XCTAssertEqual(snapshot.selectingQoderItem("organization").windows.map(\.id),
                       ["qoder.orgResourcePackage"])
        XCTAssertEqual(snapshot.selectingQoderItem(nil).windows.map(\.id),
                       ["qoder.userQuota", "qoder.orgResourcePackage"])
        XCTAssertEqual(snapshot.selectingQoderItem("organization").displayMetrics.map { $0.window?.id },
                       ["qoder.orgResourcePackage"])
    }
}
