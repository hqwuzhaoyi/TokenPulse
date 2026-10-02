import Foundation
import XCTest
@testable import TokenPulse

final class PartialWalletTests: XCTestCase {
    func testPartialFailureRetainsOnlySameIdentityWalletAndItsOriginalTimestamp() {
        let id = UUID()
        let old = snapshot(id: id, identity: "A", time: 10, balance: 1)
        let failed = snapshot(id: id, identity: "A", time: 30, balance: 300, failure: .network)
        let merged = failed.retainingWalletAfterPartialFailure(from: old)
        XCTAssertEqual(merged.windows.last?.wallet?.total, 1)
        XCTAssertEqual(merged.windows.first?.usedPercentage, 95)
        XCTAssertEqual(merged.collectedAt, Date(timeIntervalSince1970: 30))
        XCTAssertEqual(merged.walletCollectedAt, Date(timeIntervalSince1970: 10))
        XCTAssertEqual(merged.walletFailure, .network)
        let changed = snapshot(id: id, identity: "B", time: 40, balance: nil, failure: .network)
            .retainingWalletAfterPartialFailure(from: old)
        XCTAssertFalse(changed.windows.contains { $0.wallet != nil })
        XCTAssertNil(changed.walletCollectedAt)
        XCTAssertFalse(failed.retainingWalletAfterPartialFailure(from: snapshot(id: UUID(), identity: "A", time: 10, balance: 1)).windows.contains { $0.wallet != nil })
    }

    func testPartialWalletCannotAlertOrRearmButNewQuotaCanAlert() {
        let id = UUID()
        let planner = NotificationPlanner()
        var old = snapshot(id: id, identity: "A", time: 10, balance: 1)
        old.windows.removeAll { $0.wallet == nil }
        let first = planner.planSuccessfulRefresh(accountID: id, accountName: "mixed", previousSnapshot: nil,
            newSnapshot: old, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: old.collectedAt)
        let partial = snapshot(id: id, identity: "A", time: 20, balance: 100, failure: .network)
        let second = planner.planSuccessfulRefresh(accountID: id, accountName: "mixed", previousSnapshot: old,
            newSnapshot: partial, settings: AccountReminderSettings(), ledger: first.ledger, now: partial.collectedAt)
        XCTAssertEqual(second.ledger.walletAlertState(accountID: id, currency: "USD"), first.ledger.walletAlertState(accountID: id, currency: "USD"))
        XCTAssertTrue(second.operations.contains { if case .deliver(let message) = $0 { return message.kind == .quotaAlert }; return false })
        XCTAssertFalse(second.operations.contains { if case .deliver(let message) = $0 { return message.kind == .walletAlert }; return false })
    }

    @MainActor
    func testRuntimePreservesWalletFailureMetadataBeforePlanning() async throws {
        let suite = "com.tokenpulse.tests.partial-notifications.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "notificationsEnabled")
        let adapter = PartialWalletAdapter()
        let runtime = NotificationRuntime(defaults: defaults, adapter: adapter)
        let account = SubscriptionAccount(name: "mixed", provider: .claude)
        var prior = snapshot(id: account.id, identity: "A", time: 10, balance: 1)
        prior.windows.removeAll { $0.wallet == nil }
        let priorState = AccountQuotaState(account: account, snapshot: prior, credentialIdentity: "A")
        try await runtime.fresh(state: priorState, previous: nil, settings: AccountReminderSettings())
        let partial = snapshot(id: account.id, identity: "A", time: 20, balance: 100, failure: .network)
        try await runtime.fresh(state: AccountQuotaState(account: account, snapshot: partial, credentialIdentity: "A"),
            previous: priorState, settings: AccountReminderSettings())
        XCTAssertTrue(runtime.ledger.walletAlertState(accountID: account.id, currency: "USD")?.isActive == true)
        let operations = await adapter.operations
        XCTAssertEqual(operations.filter { if case .deliver(let message) = $0 { return message.kind == .walletAlert }; return false }.count, 1)
    }

    func testWidgetPersistedStatusKeepsIndependentOldWalletTimeAndLegacyDecode() async throws {
        let suite = "com.tokenpulse.tests.partial-widget.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let account = SubscriptionAccount(name: "mixed", provider: .claude)
        let merged = snapshot(id: account.id, identity: "A", time: 30, balance: nil, failure: .network)
            .retainingWalletAfterPartialFailure(from: snapshot(id: account.id, identity: "A", time: 10, balance: 1))
        let store = WidgetSnapshotStore(defaults: UserDefaults(suiteName: suite))
        try await store.save(states: [AccountQuotaState(account: account, snapshot: merged)])
        let loaded = await store.load()
        let widget = try XCTUnwrap(loaded.first)
        XCTAssertEqual(widget.walletCollectedAt, Date(timeIntervalSince1970: 10))
        XCTAssertEqual(widget.collectedAt, Date(timeIntervalSince1970: 30))
        XCTAssertEqual(widget.walletFailure, .network)
        XCTAssertTrue(QuotaFormatting.walletCollectionStatus(failure: widget.walletFailure, collectedAt: widget.walletCollectedAt)?.contains("旧数据") == true)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(merged)) as? [String: Any])
        object.removeValue(forKey: "walletCollectedAt")
        object.removeValue(forKey: "walletFailure")
        let legacy = try JSONDecoder().decode(QuotaSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.walletCollectedAt)
        XCTAssertNil(legacy.walletFailure)
    }

    private func snapshot(id: UUID, identity: String, time: Double, balance: Decimal?, failure: RefreshFailure? = nil) -> QuotaSnapshot {
        let quota = QuotaWindow(id: "quota", name: "套餐", scope: nil, usedPercentage: 95,
                               remainingCount: nil, totalCount: nil, resetsAt: nil)
        let wallets = balance.map { [QuotaWindow(id: "wallet", name: "钱包", scope: nil, usedPercentage: nil,
            remainingCount: nil, totalCount: nil, resetsAt: nil, wallet: WalletBalance(currency: "USD", total: $0))] } ?? []
        return QuotaSnapshot(accountID: id, windows: [quota] + wallets, collectedAt: Date(timeIntervalSince1970: time),
            sourceCredentialFingerprint: identity, walletCollectedAt: balance == nil ? nil : Date(timeIntervalSince1970: time), walletFailure: failure)
    }
}

private actor PartialWalletAdapter: NotificationApplying {
    private(set) var operations: [NotificationOperation] = []
    @MainActor func configure() {}
    func requestAuthorization() -> Bool { true }
    func authorizationStatus() -> NotificationAuthorizationStatus { .authorized }
    func apply(_ operations: [NotificationOperation]) { self.operations += operations }
}
