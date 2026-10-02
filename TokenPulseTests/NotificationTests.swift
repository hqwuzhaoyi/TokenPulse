import XCTest
@testable import TokenPulse

final class NotificationTests: XCTestCase {
    func testUnrepresentableProviderResetCannotCreateASchedule() {
        let now = Date(timeIntervalSince1970: 100)
        let account = UUID()
        let window = QuotaWindow(id: "fixture", name: "额度", scope: nil,
                                 usedPercentage: 96, remainingCount: nil, totalCount: nil,
                                 resetsAt: Date(timeIntervalSince1970: 1e20))
        let snapshot = QuotaSnapshot(accountID: account, windows: [window], collectedAt: now)
        let result = NotificationPlanner().planSuccessfulRefresh(
            accountID: account, accountName: "Fixture", previousSnapshot: nil, newSnapshot: snapshot,
            settings: AccountReminderSettings(), ledger: ReminderLedger(), now: now)
        XCTAssertFalse(result.operations.contains {
            if case .schedule = $0 { return true }
            return false
        })
        XCTAssertTrue(result.operations.contains {
            if case .deliver(let notification) = $0 { return notification.kind == .quotaAlert }
            return false
        })
    }

    @MainActor
    func testRemovingAccountCancelsItsScheduledNotifications() async throws {
        let suite = "com.tokenpulse.tests.delete-notifications.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "notificationsEnabled")
        let adapter = RecordingNotificationAdapter()
        let runtime = NotificationRuntime(defaults: defaults, adapter: adapter)
        let account = SubscriptionAccount(name: "Deleted")
        let kept = SubscriptionAccount(name: "Kept")
        let window = QuotaWindow(id: "weekly", name: "每周", scope: nil, usedPercentage: 20,
                                 remainingCount: nil, totalCount: nil, resetsAt: Date().addingTimeInterval(3_600))
        let states = [account, kept].map {
            AccountQuotaState(account: $0, snapshot: QuotaSnapshot(accountID: $0.id, windows: [window], collectedAt: Date()))
        }
        try await runtime.settingsChanged(configurations: [account, kept].map { AccountConfiguration(account: $0) }, states: states)
        let deletedSchedules = runtime.ledger.pendingSchedules(accountID: account.id).map(\.notificationID)
        XCTAssertFalse(deletedSchedules.isEmpty)

        try await runtime.settingsChanged(configurations: [AccountConfiguration(account: kept)], states: [states[1]])

        let operations = await adapter.operations()
        XCTAssertTrue(operations.contains(.cancel(identifiers: deletedSchedules)))
        XCTAssertTrue(runtime.ledger.pendingSchedules(accountID: account.id).isEmpty)
        XCTAssertFalse(runtime.ledger.pendingSchedules(accountID: kept.id).isEmpty)
        let restored = NotificationRuntime(defaults: defaults, adapter: adapter)
        XCTAssertTrue(restored.ledger.pendingSchedules(accountID: account.id).isEmpty)
    }

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
    func testCodexAuxiliaryModelQuotaDoesNotTriggerAccountReminders() async throws {
        let suite = "com.tokenpulse.tests.codex-auxiliary.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "notificationsEnabled")
        let adapter = RecordingNotificationAdapter()
        let runtime = NotificationRuntime(defaults: defaults, adapter: adapter)
        let account = SubscriptionAccount(name: "Pro 账号", provider: .codex)
        let weekly = QuotaWindow(
            id: "codex.primary_window", name: "每周额度", scope: nil,
            usedPercentage: 20, remainingCount: nil, totalCount: nil,
            resetsAt: Date().addingTimeInterval(3_600)
        )
        let spark = QuotaWindow(
            id: "codex_bengalfox.primary_window", name: "5 小时额度",
            scope: "GPT-5.3-Codex-Spark", usedPercentage: 90,
            remainingCount: nil, totalCount: nil,
            resetsAt: Date().addingTimeInterval(1_800)
        )
        let snapshot = QuotaSnapshot(
            accountID: account.id, windows: [weekly, spark], collectedAt: Date(),
            subscriptionPlan: .pro
        )

        try await runtime.fresh(
            state: AccountQuotaState(account: account, snapshot: snapshot),
            previous: nil,
            settings: AccountReminderSettings()
        )

        let operations = await adapter.operations()
        XCTAssertFalse(operations.contains {
            if case .deliver(let notification) = $0, notification.kind == .quotaAlert { return true }
            return false
        })
        XCTAssertEqual(operations.compactMap {
            if case .schedule(let notification, _) = $0 { return notification.body }
            return nil
        }, ["每周额度"])
    }

    @MainActor
    func testCodexPlanChangeDoesNotReportAResetWhenPrimaryWindowChangesPeriod() async throws {
        let suite = "com.tokenpulse.tests.codex-plan-change.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "notificationsEnabled")
        let adapter = RecordingNotificationAdapter()
        let runtime = NotificationRuntime(defaults: defaults, adapter: adapter)
        let account = SubscriptionAccount(name: "Codex", provider: .codex)
        let future = Date().addingTimeInterval(3_600).timeIntervalSince1970
        let plusWindows = CodexProviderClient.windows([
            "rate_limit": [
                "primary_window": [
                    "used_percent": 20,
                    "limit_window_seconds": 5 * 3_600,
                    "reset_at": future,
                ],
            ],
        ])
        let proWindows = CodexProviderClient.windows([
            "rate_limit": [
                "primary_window": [
                    "used_percent": 20,
                    "limit_window_seconds": 7 * 86_400,
                    "reset_at": future + 3_600,
                ],
            ],
        ])
        let previous = AccountQuotaState(
            account: account,
            snapshot: QuotaSnapshot(accountID: account.id, windows: plusWindows, collectedAt: Date(), subscriptionPlan: .plus)
        )
        let current = AccountQuotaState(
            account: account,
            snapshot: QuotaSnapshot(accountID: account.id, windows: proWindows, collectedAt: Date(), subscriptionPlan: .pro)
        )

        try await runtime.fresh(
            state: current,
            previous: previous,
            settings: AccountReminderSettings(quotaAlertsEnabled: false)
        )

        let operations = await adapter.operations()
        XCTAssertFalse(operations.contains {
            if case .deliver(let notification) = $0, notification.kind == .confirmedReset { return true }
            return false
        })
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

    func testUnusedWindowDoesNotScheduleResetReminder() {
        let result = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: nil,
            newSnapshot: snapshot(windows: [
                window(id: "short", name: "5 小时额度", used: 0, resetAt: now.addingTimeInterval(1_000)),
            ]),
            settings: AccountReminderSettings(quotaAlertsEnabled: false),
            ledger: ReminderLedger(),
            now: now
        )

        XCTAssertTrue(scheduled(result.operations).isEmpty)
    }

    func testMovingUnusedOpenCodeRollingResetDoesNotConfirmReset() throws {
        let firstCollectedAt = Date(timeIntervalSince1970: 1_000)
        let secondCollectedAt = firstCollectedAt.addingTimeInterval(120)
        let firstWindows = try OpenCodeGoProviderClient.windows(Data(
            #"{"usage":{"rolling":{"status":"ok","percent":0,"resetsAt":"1970-01-01T05:16:40Z"}}}"#.utf8
        ))
        let secondWindows = try OpenCodeGoProviderClient.windows(Data(
            #"{"usage":{"rolling":{"status":"ok","percent":0,"resetsAt":"1970-01-01T05:18:40Z"}}}"#.utf8
        ))
        let firstSnapshot = QuotaSnapshot(
            accountID: accountID,
            windows: firstWindows,
            collectedAt: firstCollectedAt
        )
        let first = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "OpenCode Go",
            previousSnapshot: nil,
            newSnapshot: firstSnapshot,
            settings: AccountReminderSettings(quotaAlertsEnabled: false),
            ledger: ReminderLedger(),
            now: firstCollectedAt
        )
        let second = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "OpenCode Go",
            previousSnapshot: firstSnapshot,
            newSnapshot: QuotaSnapshot(
                accountID: accountID,
                windows: secondWindows,
                collectedAt: secondCollectedAt
            ),
            settings: AccountReminderSettings(quotaAlertsEnabled: false),
            ledger: first.ledger,
            now: secondCollectedAt
        )

        XCTAssertTrue(scheduled(first.operations).isEmpty)
        XCTAssertTrue(delivered(second.operations, kind: .confirmedReset).isEmpty)
    }

    func testMovingCodexResetTimeDoesNotRearmQuotaOrConfirmReset() {
        let firstCollectedAt = Date(timeIntervalSince1970: 1_000)
        let secondCollectedAt = firstCollectedAt.addingTimeInterval(60)
        let firstWindows = CodexProviderClient.windows([
            "rate_limit": [
                "primary_window": [
                    "used_percent": 90,
                    "limit_window_seconds": 5 * 3_600,
                    "reset_at": firstCollectedAt.addingTimeInterval(1_000).timeIntervalSince1970,
                ],
            ],
        ])
        let secondWindows = CodexProviderClient.windows([
            "rate_limit": [
                "primary_window": [
                    "used_percent": 90,
                    "limit_window_seconds": 5 * 3_600,
                    "reset_at": secondCollectedAt.addingTimeInterval(1_000).timeIntervalSince1970,
                ],
            ],
        ])
        let firstSnapshot = QuotaSnapshot(
            accountID: accountID,
            windows: firstWindows,
            collectedAt: firstCollectedAt,
            subscriptionPlan: .plus
        )
        let first = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "Codex Plus",
            previousSnapshot: nil,
            newSnapshot: firstSnapshot,
            settings: AccountReminderSettings(),
            ledger: ReminderLedger(),
            now: firstCollectedAt
        )
        let second = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "Codex Plus",
            previousSnapshot: firstSnapshot,
            newSnapshot: QuotaSnapshot(
                accountID: accountID,
                windows: secondWindows,
                collectedAt: secondCollectedAt,
                subscriptionPlan: .plus
            ),
            settings: AccountReminderSettings(),
            ledger: first.ledger,
            now: secondCollectedAt
        )

        XCTAssertEqual(delivered(first.operations, kind: .quotaAlert).count, 1)
        XCTAssertTrue(delivered(second.operations, kind: .quotaAlert).isEmpty)
        XCTAssertTrue(delivered(second.operations, kind: .confirmedReset).isEmpty)
    }

    func testProviderExhaustedStatusTriggersHighestQuotaAlert() {
        let exhausted = QuotaWindow(
            id: "rolling", name: "5 小时额度", scope: nil, period: .fiveHour,
            isExhausted: true, usedPercentage: 60,
            remainingCount: nil, totalCount: nil, resetsAt: nil
        )
        let result = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "OpenCode Go",
            previousSnapshot: nil,
            newSnapshot: snapshot(windows: [exhausted]),
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: ReminderLedger(),
            now: now
        )

        XCTAssertEqual(delivered(result.operations, kind: .quotaAlert).map(\.body), ["5 小时额度达到100%"])
    }

    func testScopedQuotaNotificationIncludesProviderDisplayName() {
        let fable = QuotaWindow(
            id: "claude.weekly_scoped.Fable",
            name: "每周额度",
            scope: "Fable",
            period: .weekly,
            usedPercentage: 82,
            remainingCount: nil,
            totalCount: nil,
            resetsAt: nil,
            cycleID: "fable-week"
        )
        let result = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "Claude",
            previousSnapshot: nil,
            newSnapshot: snapshot(windows: [fable]),
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: ReminderLedger(),
            now: now
        )

        XCTAssertEqual(
            delivered(result.operations, kind: .quotaAlert).map(\.body),
            ["Fable 每周额度达到80%"]
        )
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

    func testResetBoundaryAdvanceOverSixtySecondsStartsNewQuotaCycleImmediately() {
        let oldReset = now.addingTimeInterval(100)
        let rescheduledReset = oldReset.addingTimeInterval(61)
        let previous = snapshot(windows: [
            window(id: "short", name: "短周期", used: 90, resetAt: oldReset),
        ])
        let first = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: nil,
            newSnapshot: previous,
            settings: AccountReminderSettings(),
            ledger: ReminderLedger(),
            now: now
        )
        let advanced = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: previous,
            newSnapshot: snapshot(
                collectedAt: now.addingTimeInterval(50),
                windows: [window(id: "short", name: "短周期", used: 85, resetAt: rescheduledReset)]
            ),
            settings: AccountReminderSettings(),
            ledger: first.ledger,
            now: now.addingTimeInterval(50)
        )
        XCTAssertEqual(delivered(advanced.operations, kind: .quotaAlert).map(\.body), ["短周期达到80%"])
        XCTAssertEqual(delivered(advanced.operations, kind: .confirmedReset).map(\.body), ["短周期"])
    }

    func testResetBoundaryAdvanceOfExactlySixtySecondsDoesNotStartNewQuotaCycle() {
        let oldReset = now.addingTimeInterval(100)
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
        let advanced = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: previous,
            newSnapshot: snapshot(
                collectedAt: now.addingTimeInterval(50),
                windows: [window(id: "short", name: "短周期", used: 85, resetAt: oldReset.addingTimeInterval(60))]
            ),
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: first.ledger,
            now: now.addingTimeInterval(50)
        )

        XCTAssertTrue(delivered(advanced.operations, kind: .quotaAlert).isEmpty)
    }

    func testUsageDropOfFortyWithoutResetAtRearmsThresholdForNextCrossing() {
        let previous = snapshot(windows: [window(id: "short", name: "短周期", used: 90)])
        let first = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: nil,
            newSnapshot: previous,
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: ReminderLedger(),
            now: now
        )
        let droppedSnapshot = snapshot(
            collectedAt: now.addingTimeInterval(50),
            windows: [window(id: "short", name: "短周期", used: 50)]
        )
        let dropped = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: previous,
            newSnapshot: droppedSnapshot,
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: first.ledger,
            now: now.addingTimeInterval(50)
        )
        let crossedAgain = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: droppedSnapshot,
            newSnapshot: snapshot(
                collectedAt: now.addingTimeInterval(100),
                windows: [window(id: "short", name: "短周期", used: 90)]
            ),
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: dropped.ledger,
            now: now.addingTimeInterval(100)
        )

        XCTAssertEqual(delivered(crossedAgain.operations, kind: .quotaAlert).map(\.body), ["短周期达到80%"])
    }

    func testUsageDropBelowFortyWithoutResetAtDoesNotRearmThreshold() {
        let previous = snapshot(windows: [window(id: "short", name: "短周期", used: 90)])
        let first = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: nil,
            newSnapshot: previous,
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: ReminderLedger(),
            now: now
        )
        let droppedSnapshot = snapshot(
            collectedAt: now.addingTimeInterval(50),
            windows: [window(id: "short", name: "短周期", used: 51)]
        )
        let dropped = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: previous,
            newSnapshot: droppedSnapshot,
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: first.ledger,
            now: now.addingTimeInterval(50)
        )
        let crossedAgain = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: droppedSnapshot,
            newSnapshot: snapshot(
                collectedAt: now.addingTimeInterval(100),
                windows: [window(id: "short", name: "短周期", used: 90)]
            ),
            settings: AccountReminderSettings(resetRemindersEnabled: false),
            ledger: dropped.ledger,
            now: now.addingTimeInterval(100)
        )

        XCTAssertTrue(delivered(crossedAgain.operations, kind: .quotaAlert).isEmpty)
    }

    func testMergedTurnoverDoesNotRearmAgainFromAnOlderLocalSnapshot() {
        let previous = snapshot(windows: [window(id: "short", name: "短周期", used: 90)])
        let settings = AccountReminderSettings(
            resetRemindersEnabled: false,
            thresholds: [40, 80]
        )
        let initial = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: nil,
            newSnapshot: previous,
            settings: settings,
            ledger: ReminderLedger(),
            now: now
        )
        let phone = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: previous,
            newSnapshot: snapshot(
                collectedAt: now.addingTimeInterval(100),
                windows: [window(id: "short", name: "短周期", used: 50)]
            ),
            settings: settings,
            ledger: initial.ledger,
            now: now.addingTimeInterval(100)
        )
        let watch = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: previous,
            newSnapshot: snapshot(
                collectedAt: now.addingTimeInterval(200),
                windows: [window(id: "short", name: "短周期", used: 50)]
            ),
            settings: settings,
            ledger: ReminderLedger().merging(phone.ledger),
            now: now.addingTimeInterval(200)
        )

        XCTAssertEqual(delivered(phone.operations, kind: .quotaAlert).map(\.body), ["短周期达到40%"])
        XCTAssertTrue(delivered(watch.operations, kind: .quotaAlert).isEmpty)
    }

    func testNewerMergedObservationStillDetectsALaterUsageDrop() {
        let previous = snapshot(windows: [window(id: "short", name: "短周期", used: 90)])
        let settings = AccountReminderSettings(resetRemindersEnabled: false)
        let initial = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: nil,
            newSnapshot: previous,
            settings: settings,
            ledger: ReminderLedger(),
            now: now
        )
        let remote = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: previous,
            newSnapshot: snapshot(
                collectedAt: now.addingTimeInterval(100),
                windows: [window(id: "short", name: "短周期", used: 90)]
            ),
            settings: settings,
            ledger: initial.ledger,
            now: now.addingTimeInterval(100)
        )
        let resetSnapshot = snapshot(
            collectedAt: now.addingTimeInterval(200),
            windows: [window(id: "short", name: "短周期", used: 0)]
        )
        let reset = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: previous,
            newSnapshot: resetSnapshot,
            settings: settings,
            ledger: ReminderLedger().merging(remote.ledger),
            now: now.addingTimeInterval(200)
        )
        let crossedAgain = planner.planSuccessfulRefresh(
            accountID: accountID,
            accountName: "测试账号",
            previousSnapshot: resetSnapshot,
            newSnapshot: snapshot(
                collectedAt: now.addingTimeInterval(300),
                windows: [window(id: "short", name: "短周期", used: 90)]
            ),
            settings: settings,
            ledger: reset.ledger,
            now: now.addingTimeInterval(300)
        )

        XCTAssertEqual(delivered(crossedAgain.operations, kind: .quotaAlert).map(\.body), ["短周期达到80%"])
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

final class PreciseQuotaThresholdTests: XCTestCase {
    private let accountID = UUID()

    func testLargeExactCountersDoNotAlertOneUnitBefore80_95Or100AndDoAlertAtBoundary() {
        let limit = Decimal(string: "100000000000000000")!
        for threshold in [80.0, 95.0, 100.0] {
            let boundary = Decimal(threshold) * limit / 100
            // Deliberately use the rounded display percentage at both observations.
            let before = plan(used: boundary - 1, total: limit, reported: threshold, thresholds: [threshold], time: 100)
            XCTAssertTrue(alerts(before).isEmpty, "Below \(threshold)% must not alert")
            XCTAssertFalse(before.ledger.containsQuotaAlert(accountID: accountID, windowID: "exact", cycle: .provider("stable"), threshold: threshold))
            let reached = plan(used: boundary, total: limit, reported: threshold, thresholds: [threshold], time: 101, ledger: before.ledger)
            XCTAssertEqual(alerts(reached).count, 1)
            XCTAssertTrue(reached.ledger.containsQuotaAlert(accountID: accountID, windowID: "exact", cycle: .provider("stable"), threshold: threshold))
            let repeated = plan(used: boundary, total: limit, reported: threshold, thresholds: [threshold], time: 102, ledger: reached.ledger)
            XCTAssertTrue(alerts(repeated).isEmpty)
        }
    }

    func testRepeatingFractionUsesDecimalBoundaryInsteadOfDisplayedDoubleAndZeroIsValid() {
        let third = plan(used: 1, total: 3, reported: 50, thresholds: [33, 34])
        XCTAssertEqual(alerts(third).map(\.body), ["精确额度达到33%"])
        XCTAssertTrue(third.ledger.containsQuotaAlert(accountID: accountID, windowID: "exact", cycle: .provider("stable"), threshold: 33))
        XCTAssertFalse(third.ledger.containsQuotaAlert(accountID: accountID, windowID: "exact", cycle: .provider("stable"), threshold: 34))
        XCTAssertEqual(alerts(plan(used: Decimal(string: "2.5"), total: 10, reported: nil, thresholds: [25])).count, 1)
        XCTAssertTrue(alerts(plan(used: 0, total: 10, reported: 100)).isEmpty)
    }

    func testExactExhaustionAndOverageReachAllConfiguredThresholdsEvenWithoutPercentage() {
        for used in [Decimal(10), Decimal(11)] {
            let result = plan(used: used, total: 10, reported: nil)
            XCTAssertEqual(alerts(result).map(\.body), ["精确额度达到100%"])
            for threshold in [80.0, 95.0, 100.0] {
                XCTAssertTrue(result.ledger.containsQuotaAlert(accountID: accountID, windowID: "exact", cycle: .provider("stable"), threshold: threshold))
            }
        }
    }

    func testInvalidOrIncompleteExactCountsFallBackToExistingReportedPercentage() {
        let cases: [(Decimal?, Decimal?)] = [(nil, 100), (90, nil), (-1, 100), (90, 0), (90, -1), (.nan, 100), (90, .nan)]
        for (used, total) in cases {
            let result = plan(used: used, total: total, reported: 90)
            XCTAssertEqual(alerts(result).map(\.body), ["精确额度达到80%"])
        }
    }

    func testExplicitExhaustionStillOverridesExactCountsAndUnlimitedStillSuppressesAlerts() {
        XCTAssertEqual(alerts(plan(used: 1, total: 100, reported: 60, exhausted: true)).map(\.body), ["精确额度达到100%"])
        XCTAssertTrue(alerts(plan(used: 100, total: 100, reported: 100, unlimited: true)).isEmpty)
        XCTAssertTrue(alerts(plan(used: 100, total: 100, reported: 100, enabled: false)).isEmpty)
    }

    func testLegacyWindowsWithoutExactCountsRetainThresholdAndExhaustionRules() {
        XCTAssertTrue(alerts(plan(used: nil, total: nil, reported: 79.9, includeExact: false)).isEmpty)
        XCTAssertEqual(alerts(plan(used: nil, total: nil, reported: 80, includeExact: false)).map(\.body), ["精确额度达到80%"])
        XCTAssertEqual(alerts(plan(used: nil, total: nil, reported: 60, exhausted: true, includeExact: false)).map(\.body), ["精确额度达到100%"])
        XCTAssertTrue(alerts(plan(used: nil, total: nil, reported: nil, exhausted: true, includeExact: false)).isEmpty)
    }

    func testContinuousAndLifetimeRecoveryRearmsOnlyOnceAtTheExactBoundaryWithoutResetNotice() {
        let limit = Decimal(string: "100000000000000000")!, boundary = limit * 80 / 100
        for semantics in [QuotaResetSemantics.continuousReplenishment, .nonResettingAllowance] {
            let first = plan(used: boundary, total: limit, reported: 80, thresholds: [80], resetSemantics: semantics)
            XCTAssertEqual(alerts(first).count, 1)
            let recovered = plan(used: boundary - 1, total: limit, reported: 80, thresholds: [80], time: 101,
                                 ledger: first.ledger, resetSemantics: semantics)
            XCTAssertTrue(recovered.operations.isEmpty)
            let cycle = recovered.ledger.cycleState(accountID: accountID, windowID: "exact")?.identity
            XCTAssertNotEqual(cycle, first.ledger.cycleState(accountID: accountID, windowID: "exact")?.identity)
            let furtherRecovery = plan(used: boundary - 2, total: limit, reported: 80, thresholds: [80], time: 102,
                                       ledger: recovered.ledger, resetSemantics: semantics)
            XCTAssertTrue(furtherRecovery.operations.isEmpty)
            XCTAssertEqual(furtherRecovery.ledger.cycleState(accountID: accountID, windowID: "exact")?.identity, cycle)
            let crossed = plan(used: boundary, total: limit, reported: 80, thresholds: [80], time: 103,
                               ledger: furtherRecovery.ledger, resetSemantics: semantics)
            XCTAssertEqual(alerts(crossed).count, 1)
            XCTAssertFalse(crossed.operations.contains {
                if case .deliver(let notification) = $0 { return notification.kind == .confirmedReset }; return false
            })
        }
    }

    func testRoundedPreviousDisplayBelowThresholdCannotRepeatedlyRearmAndMissingUsageKeepsExactObservation() {
        let limit = Decimal(string: "100000000000000000")!, boundary = limit * 80 / 100
        let first = plan(used: boundary - 1, total: limit, reported: 80, thresholds: [80], resetSemantics: .continuousReplenishment)
        let identity = first.ledger.cycleState(accountID: accountID, windowID: "exact")?.identity
        let lower = plan(used: boundary - 2, total: limit, reported: 80, thresholds: [80], time: 101,
                         ledger: first.ledger, resetSemantics: .continuousReplenishment)
        XCTAssertTrue(lower.operations.isEmpty)
        XCTAssertEqual(lower.ledger.cycleState(accountID: accountID, windowID: "exact")?.identity, identity)
        let unknown = plan(used: nil, total: limit, reported: nil, thresholds: [80], time: 102,
                           ledger: lower.ledger, resetSemantics: .continuousReplenishment)
        XCTAssertTrue(unknown.operations.isEmpty)
        XCTAssertEqual(unknown.ledger.cycleState(accountID: accountID, windowID: "exact")?.exactCounts,
                       lower.ledger.cycleState(accountID: accountID, windowID: "exact")?.exactCounts)
        let lowerAgain = plan(used: boundary - 3, total: limit, reported: 80, thresholds: [80], time: 103,
                              ledger: unknown.ledger, resetSemantics: .continuousReplenishment)
        XCTAssertEqual(lowerAgain.ledger.cycleState(accountID: accountID, windowID: "exact")?.identity, identity)
        XCTAssertTrue(lowerAgain.operations.isEmpty)
    }

    func testExplicitExhaustionRemainsAuthoritativeForTheNextRecoveryObservation() {
        let first = plan(used: 1, total: 100, reported: 60, thresholds: [80], exhausted: true, resetSemantics: .nonResettingAllowance)
        XCTAssertEqual(alerts(first).count, 1)
        XCTAssertEqual(first.ledger.cycleState(accountID: accountID, windowID: "exact")?.usedPercentage, 100)
        XCTAssertNil(first.ledger.cycleState(accountID: accountID, windowID: "exact")?.exactCounts)
        let recovered = plan(used: 1, total: 100, reported: 60, thresholds: [80], time: 101,
                             ledger: first.ledger, resetSemantics: .nonResettingAllowance)
        XCTAssertTrue(recovered.operations.isEmpty)
        XCTAssertNotEqual(recovered.ledger.cycleState(accountID: accountID, windowID: "exact")?.identity,
                          first.ledger.cycleState(accountID: accountID, windowID: "exact")?.identity)
        let crossed = plan(used: 80, total: 100, reported: 80, thresholds: [80], time: 102,
                           ledger: recovered.ledger, resetSemantics: .nonResettingAllowance)
        XCTAssertEqual(alerts(crossed).count, 1)
    }

    func testNewPercentageObservationReplacesOldExactCountersAndLegacyCycleStateDecodes() throws {
        let first = plan(used: 90, total: 100, reported: 90, thresholds: [80], resetSemantics: .nonResettingAllowance)
        let newer = plan(used: nil, total: nil, reported: 85, thresholds: [80], time: 101,
                         ledger: first.ledger, includeExact: false, resetSemantics: .nonResettingAllowance)
        let state = try XCTUnwrap(newer.ledger.cycleState(accountID: accountID, windowID: "exact"))
        XCTAssertNil(state.exactCounts)
        XCTAssertEqual(state.usedPercentage, 85)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object.removeValue(forKey: "exactCounts")
        let legacy = try JSONDecoder().decode(WindowCycleState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(legacy, state)
        let savedLedger = try JSONDecoder().decode(ReminderLedger.self, from: JSONEncoder().encode(first.ledger))
        XCTAssertEqual(savedLedger, first.ledger)
    }

    private func plan(used: Decimal?, total: Decimal?, reported: Double?, thresholds: [Double] = [80, 95, 100],
                      time: TimeInterval = 100, ledger: ReminderLedger = ReminderLedger(),
                      exhausted: Bool = false, unlimited: Bool = false, enabled: Bool = true,
                      includeExact: Bool = true, resetSemantics: QuotaResetSemantics? = nil) -> NotificationPlanningResult {
        let date = Date(timeIntervalSince1970: time)
        let window = QuotaWindow(id: "exact", name: "精确额度", scope: nil, isExhausted: exhausted,
                                 isUnlimited: unlimited, usedPercentage: reported, remainingCount: nil, totalCount: nil,
                                 resetsAt: nil, cycleID: "stable", exactCounts: includeExact ? DecimalQuotaCounts(used: used, total: total) : nil,
                                 resetSemantics: resetSemantics)
        return NotificationPlanner().planSuccessfulRefresh(accountID: accountID, accountName: "测试", previousSnapshot: nil,
                                                           newSnapshot: QuotaSnapshot(accountID: accountID, windows: [window], collectedAt: date),
                                                           settings: AccountReminderSettings(quotaAlertsEnabled: enabled, resetRemindersEnabled: false, thresholds: thresholds),
                                                           ledger: ledger, now: date)
    }
    private func alerts(_ result: NotificationPlanningResult) -> [ReminderNotification] {
        result.operations.compactMap {
            if case .deliver(let notification) = $0, notification.kind == .quotaAlert { return notification }; return nil
        }
    }
}
