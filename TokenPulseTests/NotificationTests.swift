import XCTest
@testable import TokenPulse

final class NotificationTests: XCTestCase {
    @MainActor
    func testNotificationPermissionAlwaysReturnsVisibleFeedback() async throws {
        let suite = "com.tokenpulse.tests.permission.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for (status, grant, expected) in [
            (NotificationAuthorizationStatus.authorized, true, NotificationPermissionFeedback.enabled),
            (.denied, false, .denied),
            (.notDetermined, true, .enabled),
            (.notDetermined, false, .denied),
        ] {
            let adapter = PermissionTestAdapter(status: status, grant: grant)
            let runtime = NotificationRuntime(defaults: defaults, adapter: adapter)
            let feedback = await runtime.requestAuthorization()
            XCTAssertEqual(feedback, expected)
        }
    }

    @MainActor
    func testNotificationPermissionFailureIsNotSilentlyIgnored() async throws {
        let suite = "com.tokenpulse.tests.permission.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runtime = NotificationRuntime(defaults: defaults, adapter: PermissionTestAdapter(status: .notDetermined, grant: nil))
        let feedback = await runtime.requestAuthorization()
        XCTAssertEqual(feedback, .failed)
    }

    @MainActor
    func testGlobalNotificationSwitchSchedulesAndCancelsWithoutDiscardingAccountSettings() async throws {
        let suite = "com.tokenpulse.tests.notification-switch.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let adapter = RecordingNotificationAdapter()
        let runtime = NotificationRuntime(defaults: defaults, adapter: adapter)
        let account = SubscriptionAccount(name: "测试账号")
        let window = QuotaWindow(
            id: "short",
            name: "短周期",
            scope: nil,
            usedPercentage: 20,
            remainingCount: nil,
            totalCount: nil,
            resetsAt: Date().addingTimeInterval(3_600)
        )
        let state = AccountQuotaState(
            account: account,
            snapshot: QuotaSnapshot(accountID: account.id, windows: [window], collectedAt: Date())
        )
        let configuration = AccountConfiguration(account: account)

        XCTAssertFalse(runtime.isEnabled)
        let enabledFeedback = await runtime.setEnabled(
            true,
            configurations: [configuration],
            states: [state]
        )
        XCTAssertEqual(enabledFeedback, .enabled)
        XCTAssertTrue(runtime.isEnabled)
        let enabledOperations = await adapter.operations()
        XCTAssertTrue(enabledOperations.contains { operation in
            if case .schedule = operation { return true }
            return false
        })

        let disabledFeedback = await runtime.setEnabled(
            false,
            configurations: [configuration],
            states: [state]
        )
        XCTAssertEqual(disabledFeedback, .disabled)
        XCTAssertFalse(runtime.isEnabled)
        XCTAssertTrue(configuration.reminders.quotaAlertsEnabled)
        XCTAssertTrue(configuration.reminders.resetRemindersEnabled)
        let disabledOperations = await adapter.operations()
        XCTAssertTrue(disabledOperations.contains { operation in
            if case .cancel = operation { return true }
            return false
        })
    }
    private let planner = NotificationPlanner()
    private let accountID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let now = Date(timeIntervalSince1970: 1_000)

    func testSettingsDefaultAndCodableRoundTrip() throws {
        let settings = AccountReminderSettings()

        XCTAssertTrue(settings.quotaAlertsEnabled)
        XCTAssertTrue(settings.resetRemindersEnabled)
        XCTAssertEqual(settings.thresholds, [80, 95, 100])
        XCTAssertEqual(try JSONDecoder().decode(AccountReminderSettings.self, from: JSONEncoder().encode(settings)), settings)
    }

    func testInitialAndCrossedThresholdsNotifyOnlyHighestAndRecordLowerLevels() {
        let first = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: nil,
            newSnapshot: snapshot(windows: [window(id: "short", name: "短周期", used: 98, cycleID: "a")]),
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: ReminderLedger(),
            now: now
        )

        XCTAssertEqual(delivered(first.operations, kind: .quotaAlert).map(\.body), ["短周期达到95%"])

        let repeated = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: nil,
            newSnapshot: snapshot(windows: [window(id: "short", name: "短周期", used: 98, cycleID: "a")]),
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: first.ledger,
            now: now
        )
        XCTAssertTrue(delivered(repeated.operations, kind: .quotaAlert).isEmpty)

        let hundred = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: nil,
            newSnapshot: snapshot(windows: [window(id: "short", name: "短周期", used: 100, cycleID: "a")]),
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: repeated.ledger,
            now: now
        )
        XCTAssertEqual(delivered(hundred.operations, kind: .quotaAlert).map(\.body), ["短周期达到100%"])
    }

    func testMultipleWindowsAreCombinedPerAccountRefresh() {
        let result = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: nil,
            newSnapshot: snapshot(windows: [
                window(id: "short", name: "短周期", used: 96, cycleID: "a"),
                window(id: "weekly", name: "每周", used: 82, cycleID: "b"),
            ]),
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: ReminderLedger(),
            now: now
        )

        let notifications = delivered(result.operations, kind: .quotaAlert)
        XCTAssertEqual(notifications.count, 1)
        XCTAssertTrue(notifications[0].body.contains("短周期达到95%"))
        XCTAssertTrue(notifications[0].body.contains("每周达到80%"))
    }

    func testExplicitNewCycleAllowsThresholdAgain() {
        let firstSnapshot = snapshot(windows: [window(id: "short", name: "短周期", used: 90, cycleID: "a")])
        let first = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: nil,
            newSnapshot: firstSnapshot,
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: ReminderLedger(),
            now: now
        )
        let second = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: firstSnapshot,
            newSnapshot: snapshot(windows: [window(id: "short", name: "短周期", used: 90, cycleID: "b")]),
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: first.ledger,
            now: now
        )

        XCTAssertEqual(delivered(second.operations, kind: .quotaAlert).map(\.body), ["短周期达到80%"])
    }

    func testLedgerMergeSuppressesCrossDeviceDuplicate() {
        let refresh = snapshot(windows: [window(id: "short", name: "短周期", used: 90, cycleID: "a")])
        let phone = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: nil,
            newSnapshot: refresh,
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: ReminderLedger(),
            now: now
        )
        let merged = ReminderLedger().merging(phone.ledger)
        let watch = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: nil,
            newSnapshot: refresh,
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: merged,
            now: now
        )

        XCTAssertTrue(delivered(watch.operations, kind: .quotaAlert).isEmpty)
    }

    func testCustomThresholdsAndReminderSwitchesAreIndependent() {
        let resetAt = now.addingTimeInterval(100)
        let refresh = snapshot(windows: [
            window(id: "short", name: "短周期", used: 75, resetAt: resetAt, cycleID: "a"),
        ])
        let quotaOnly = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: nil,
            newSnapshot: refresh,
            settings: AccountReminderSettings(
                quotaAlertsEnabled: true,
                resetRemindersEnabled: false,
                thresholds: [70, 90]
            ),
            ledger: ReminderLedger(),
            now: now
        )
        XCTAssertEqual(delivered(quotaOnly.operations, kind: .quotaAlert).map(\.body), ["短周期达到70%"])
        XCTAssertTrue(scheduled(quotaOnly.operations).isEmpty)

        let resetOnly = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: nil,
            newSnapshot: refresh,
            settings: AccountReminderSettings(quotaAlertsEnabled: false, resetRemindersEnabled: true),
            ledger: ReminderLedger(),
            now: now
        )
        XCTAssertTrue(delivered(resetOnly.operations, kind: .quotaAlert).isEmpty)
        XCTAssertEqual(scheduled(resetOnly.operations).count, 1)
    }

    func testResetBoundaryStartsNewQuotaCycleWithoutUsingUsageDrop() {
        let oldReset = now.addingTimeInterval(100)
        let rescheduledReset = now.addingTimeInterval(200)
        let previous = snapshot(windows: [
            window(id: "short", name: "短周期", used: 90, resetAt: oldReset),
        ])
        let first = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: nil,
            newSnapshot: previous,
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: ReminderLedger(),
            now: now
        )
        let beforeReset = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: previous,
            newSnapshot: snapshot(
                collectedAt: now.addingTimeInterval(50),
                windows: [window(id: "short", name: "短周期", used: 85, resetAt: rescheduledReset)]
            ),
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: first.ledger,
            now: now.addingTimeInterval(50)
        )
        XCTAssertTrue(delivered(beforeReset.operations, kind: .quotaAlert).isEmpty)

        let afterOldReset = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: snapshot(
                collectedAt: now.addingTimeInterval(50),
                windows: [window(id: "short", name: "短周期", used: 85, resetAt: rescheduledReset)]
            ),
            newSnapshot: snapshot(
                collectedAt: now.addingTimeInterval(101),
                windows: [window(id: "short", name: "短周期", used: 85, resetAt: rescheduledReset)]
            ),
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: beforeReset.ledger,
            now: now.addingTimeInterval(101)
        )
        XCTAssertTrue(delivered(afterOldReset.operations, kind: .quotaAlert).isEmpty)

        let afterRescheduledReset = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: snapshot(
                collectedAt: now.addingTimeInterval(101),
                windows: [window(id: "short", name: "短周期", used: 85, resetAt: rescheduledReset)]
            ),
            newSnapshot: snapshot(
                collectedAt: now.addingTimeInterval(201),
                windows: [window(id: "short", name: "短周期", used: 85, resetAt: now.addingTimeInterval(1_000))]
            ),
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: afterOldReset.ledger,
            now: now.addingTimeInterval(201)
        )
        XCTAssertEqual(delivered(afterRescheduledReset.operations, kind: .quotaAlert).map(\.body), ["短周期达到80%"])
    }

    func testKnownResetSchedulesCombinedNotificationAndTimeChangeReplacesIt() {
        let firstReset = now.addingTimeInterval(100)
        let firstSnapshot = snapshot(windows: [
            window(id: "short", name: "短周期", used: 20, resetAt: firstReset),
            window(id: "weekly", name: "每周", used: 20, resetAt: firstReset),
        ])
        let first = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: nil,
            newSnapshot: firstSnapshot,
            settings: AccountReminderSettings(quotaAlertsEnabled: false),
            ledger: ReminderLedger(),
            now: now
        )

        XCTAssertEqual(scheduled(first.operations).count, 1)
        XCTAssertEqual(scheduled(first.operations)[0].0.body, "每周、短周期")

        let changedReset = now.addingTimeInterval(200)
        let changed = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: firstSnapshot,
            newSnapshot: snapshot(windows: [
                window(id: "short", name: "短周期", used: 20, resetAt: changedReset),
                window(id: "weekly", name: "每周", used: 20, resetAt: changedReset),
            ]),
            settings: AccountReminderSettings(quotaAlertsEnabled: false),
            ledger: first.ledger,
            now: now
        )

        XCTAssertEqual(cancelled(changed.operations).count, 1)
        XCTAssertEqual(scheduled(changed.operations).map(\.1), [changedReset])
    }

    func testSameResetTimeWindowChangeReplacesWithoutCancellingSharedIdentifier() {
        let resetAt = now.addingTimeInterval(100)
        let firstSnapshot = snapshot(windows: [
            window(id: "short", name: "短周期", used: 20, resetAt: resetAt),
        ])
        let first = planner.planSettingsChange(
            accountID: accountID,
            accountName: "测试账号",
            latestSnapshot: firstSnapshot,
            settings: AccountReminderSettings(),
            ledger: ReminderLedger(),
            now: now
        )
        let changed = planner.planSettingsChange(
            accountID: accountID,
            accountName: "测试账号",
            latestSnapshot: snapshot(windows: [
                window(id: "short", name: "短周期", used: 20, resetAt: resetAt),
                window(id: "weekly", name: "每周", used: 20, resetAt: resetAt),
            ]),
            settings: AccountReminderSettings(),
            ledger: first.ledger,
            now: now
        )

        XCTAssertEqual(scheduled(changed.operations).count, 1)
        XCTAssertEqual(scheduled(changed.operations)[0].0.body, "每周、短周期")
        XCTAssertTrue(cancelled(changed.operations).isEmpty)
        XCTAssertEqual(
            scheduled(changed.operations)[0].0.identifier,
            scheduled(first.operations)[0].0.identifier
        )
    }

    func testSettingsDisableCancelsAndEnableReschedulesResetOnly() {
        let resetAt = now.addingTimeInterval(100)
        let latest = snapshot(windows: [window(id: "short", name: "短周期", used: 99, resetAt: resetAt)])
        let initial = planner.planSettingsChange(
            accountID: accountID,
            accountName: "测试账号",
            latestSnapshot: latest,
            settings: AccountReminderSettings(),
            ledger: ReminderLedger(),
            now: now
        )
        let disabled = planner.planSettingsChange(
            accountID: accountID,
            accountName: "测试账号",
            latestSnapshot: latest,
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: initial.ledger,
            now: now
        )

        XCTAssertEqual(cancelled(disabled.operations).count, 1)
        XCTAssertTrue(delivered(disabled.operations, kind: .quotaAlert).isEmpty)

        let enabled = planner.planSettingsChange(
            accountID: accountID,
            accountName: "测试账号",
            latestSnapshot: latest,
            settings: AccountReminderSettings(),
            ledger: disabled.ledger,
            now: now
        )
        XCTAssertEqual(scheduled(enabled.operations).count, 1)
    }

    func testExpectedResetSuppressesConfirmationForSameOccurrence() {
        let oldReset = now.addingTimeInterval(100)
        let previous = snapshot(windows: [
            window(id: "short", name: "短周期", used: 90, resetAt: oldReset, cycleID: "cycle-a"),
        ])
        let scheduledResult = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: nil,
            newSnapshot: previous,
            settings: AccountReminderSettings(quotaAlertsEnabled: false),
            ledger: ReminderLedger(),
            now: now
        )
        let afterReset = Date(timeIntervalSince1970: oldReset.timeIntervalSince1970 + 1)
        let current = snapshot(
            collectedAt: afterReset,
            windows: [
                window(
                    id: "short",
                    name: "短周期",
                    used: 5,
                    resetAt: oldReset.addingTimeInterval(1_000),
                    cycleID: "cycle-b"
                ),
            ]
        )
        let confirmed = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: previous,
            newSnapshot: current,
            settings: AccountReminderSettings(quotaAlertsEnabled: false),
            ledger: scheduledResult.ledger,
            now: afterReset
        )

        XCTAssertTrue(delivered(confirmed.operations, kind: .confirmedReset).isEmpty)
    }

    func testCancelledFutureScheduleDoesNotSuppressLaterExplicitConfirmation() {
        let resetAt = now.addingTimeInterval(100)
        let previous = snapshot(windows: [
            window(id: "short", name: "短周期", used: 90, resetAt: resetAt, cycleID: "cycle-a"),
        ])
        let scheduledResult = planner.planSettingsChange(
            accountID: accountID,
            accountName: "测试账号",
            latestSnapshot: previous,
            settings: AccountReminderSettings(),
            ledger: ReminderLedger(),
            now: now
        )
        let cancelledResult = planner.planSettingsChange(
            accountID: accountID,
            accountName: "测试账号",
            latestSnapshot: previous,
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: scheduledResult.ledger,
            now: now
        )

        let result = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: previous,
            newSnapshot: snapshot(windows: [
                window(id: "short", name: "短周期", used: 5, cycleID: "cycle-b"),
            ]),
            settings: AccountReminderSettings(quotaAlertsEnabled: false),
            ledger: cancelledResult.ledger,
            now: now
        )

        XCTAssertEqual(delivered(result.operations, kind: .confirmedReset).map(\.body), ["短周期"])
    }

    func testUnknownResetRequiresExplicitCycleChangeAndNeverUsesUsageDrop() {
        let previous = snapshot(windows: [window(id: "short", name: "短周期", used: 90, cycleID: "a")])
        let initial = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: nil,
            newSnapshot: previous,
            settings: AccountReminderSettings(quotaAlertsEnabled: false),
            ledger: ReminderLedger(),
            now: now
        )
        let usageDrop = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: previous,
            newSnapshot: snapshot(windows: [window(id: "short", name: "短周期", used: 5, cycleID: "a")]),
            settings: AccountReminderSettings(quotaAlertsEnabled: false),
            ledger: initial.ledger,
            now: now
        )
        XCTAssertTrue(delivered(usageDrop.operations, kind: .confirmedReset).isEmpty)

        let explicitReset = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: previous,
            newSnapshot: snapshot(windows: [window(id: "short", name: "短周期", used: 5, cycleID: "b")]),
            settings: AccountReminderSettings(quotaAlertsEnabled: false),
            ledger: usageDrop.ledger,
            now: now
        )
        XCTAssertEqual(delivered(explicitReset.operations, kind: .confirmedReset).map(\.body), ["短周期"])
    }

    func testMultipleConfirmedResetsAreCombinedAndMergedLedgerSuppressesCrossDeviceDuplicate() {
        let previous = snapshot(windows: [
            window(id: "short", name: "短周期", used: 80, cycleID: "short-a"),
            window(id: "weekly", name: "每周", used: 80, cycleID: "week-a"),
        ])
        let current = snapshot(windows: [
            window(id: "short", name: "短周期", used: 5, cycleID: "short-b"),
            window(id: "weekly", name: "每周", used: 5, cycleID: "week-b"),
        ])
        let phone = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: previous,
            newSnapshot: current,
            settings: AccountReminderSettings(quotaAlertsEnabled: false),
            ledger: ReminderLedger(),
            now: now
        )

        let phoneNotifications = delivered(phone.operations, kind: .confirmedReset)
        XCTAssertEqual(phoneNotifications.count, 1)
        XCTAssertTrue(phoneNotifications[0].body.contains("短周期"))
        XCTAssertTrue(phoneNotifications[0].body.contains("每周"))

        let watch = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: previous,
            newSnapshot: current,
            settings: AccountReminderSettings(quotaAlertsEnabled: false),
            ledger: ReminderLedger().merging(phone.ledger),
            now: now
        )
        XCTAssertTrue(delivered(watch.operations, kind: .confirmedReset).isEmpty)
    }

    private func snapshot(collectedAt: Date? = nil, windows: [QuotaWindow]) -> QuotaSnapshot {
        QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: collectedAt ?? now)
    }

    private func window(id: String,
                        name: String,
                        used: Double,
                        resetAt: Date? = nil,
                        cycleID: String? = nil) -> QuotaWindow {
        QuotaWindow(
            id: id,
            name: name,
            scope: nil,
            usedPercentage: used,
            remainingCount: 100 - used,
            totalCount: 100,
            resetsAt: resetAt,
            cycleID: cycleID
        )
    }

    private func delivered(_ operations: [NotificationOperation],
                           kind: ReminderNotificationKind) -> [ReminderNotification] {
        operations.compactMap {
            guard case let .deliver(notification) = $0, notification.kind == kind else { return nil }
            return notification
        }
    }

    private func scheduled(_ operations: [NotificationOperation]) -> [(ReminderNotification, Date)] {
        operations.compactMap {
            guard case let .schedule(notification, date) = $0 else { return nil }
            return (notification, date)
        }
    }

    private func cancelled(_ operations: [NotificationOperation]) -> [[String]] {
        operations.compactMap {
            guard case let .cancel(identifiers) = $0 else { return nil }
            return identifiers
        }
    }
}

private struct PermissionTestAdapter: NotificationApplying {
    let status: NotificationAuthorizationStatus
    let grant: Bool?
    @MainActor func configure() {}
    func authorizationStatus() async -> NotificationAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool {
        guard let grant else { throw NotificationAdapterError.authorizationRequired }
        return grant
    }
    func apply(_ operations: [NotificationOperation]) async throws {}
}

private actor RecordingNotificationAdapter: NotificationApplying {
    private var recordedOperations: [NotificationOperation] = []

    @MainActor func configure() {}
    func authorizationStatus() async -> NotificationAuthorizationStatus { .authorized }
    func requestAuthorization() async throws -> Bool { true }
    func apply(_ operations: [NotificationOperation]) async throws {
        recordedOperations.append(contentsOf: operations)
    }
    func operations() -> [NotificationOperation] { recordedOperations }
}
