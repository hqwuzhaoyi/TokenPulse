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

    private var nextObservationOffset: TimeInterval = 0
    private func snapshot(collectedAt: Date? = nil, windows: [QuotaWindow]) -> QuotaSnapshot {
        let observedAt = collectedAt ?? now.addingTimeInterval(nextObservationOffset)
        nextObservationOffset = max(nextObservationOffset, observedAt.timeIntervalSince(now) + 1)
        return QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: observedAt)
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
    private var failNext = false

    @MainActor func configure() {}
    func authorizationStatus() async -> NotificationAuthorizationStatus { .authorized }
    func requestAuthorization() async throws -> Bool { true }
    func apply(_ operations: [NotificationOperation]) async throws {
        guard !operations.isEmpty else { return }
        if failNext {
            failNext = false
            throw NotificationAdapterError.authorizationRequired
        }
        recordedOperations.append(contentsOf: operations)
    }
    func failNextApply() { failNext = true }
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

final class OrderedQuotaObservationTests: XCTestCase {
    private let id = UUID()
    private let planner = NotificationPlanner()
    private func snap(_ at: Double, cycle: String = "A", used: Double = 50, reset: Double = 1000, empty: Bool = false) -> QuotaSnapshot {
        .init(accountID: id, windows: empty ? [] : [.init(id: "w", name: "main", scope: nil, usedPercentage: used,
              remainingCount: nil, totalCount: nil, resetsAt: Date(timeIntervalSince1970: reset), cycleID: cycle)],
              collectedAt: Date(timeIntervalSince1970: at))
    }
    private func apply(_ snapshot: QuotaSnapshot, previous: QuotaSnapshot? = nil, ledger: ReminderLedger = ReminderLedger()) -> NotificationPlanningResult {
        planner.planSuccessfulRefresh(accountID: id, accountName: "X", previousSnapshot: previous, newSnapshot: snapshot,
                                       settings: AccountReminderSettings(), ledger: ledger, now: Date(timeIntervalSince1970: 400))
    }
    private func kinds(_ result: NotificationPlanningResult) -> [ReminderNotificationKind] {
        result.operations.compactMap { if case .deliver(let value) = $0 { return value.kind }; return nil }
    }
    func testStaleAndEqualProviderCyclesCannotRefireResetThresholdOrRollbackLedger() {
        let a = snap(100, used: 80), b = snap(200, cycle: "B", used: 20, reset: 2000)
        let first = apply(a), second = apply(b, previous: a, ledger: first.ledger)
        XCTAssertTrue(kinds(second).contains(.confirmedReset))
        for at in [150.0, 200.0] {
            let replay = apply(snap(at, used: 95), previous: b, ledger: second.ledger)
            XCTAssertTrue(replay.operations.isEmpty)
            XCTAssertEqual(replay.ledger, second.ledger)
        }
        let c = apply(snap(300, cycle: "C", used: 5, reset: 3000), previous: snap(150), ledger: second.ledger)
        XCTAssertTrue(kinds(c).contains(.confirmedReset), "The next genuine cycle must still reset")
        let upgraded = apply(snap(350, cycle: "C", used: 95, reset: 3000), ledger: c.ledger)
        XCTAssertTrue(kinds(upgraded).contains(.quotaAlert))
    }
    func testOldMissingWindowCannotCancelNewPlanAndFreshEmptyFramePreventsResurrection() {
        let first = apply(snap(100)), latest = apply(snap(200, cycle: "B", used: 20, reset: 2000), ledger: first.ledger)
        for at in [150.0, 200.0] {
            let stale = apply(snap(at, empty: true), ledger: latest.ledger)
            XCTAssertTrue(stale.operations.isEmpty)
            XCTAssertEqual(stale.ledger, latest.ledger)
        }
        let removed = apply(snap(250, empty: true), ledger: latest.ledger)
        XCTAssertTrue(removed.operations.contains { if case .cancel = $0 { return true }; return false })
        XCTAssertTrue(removed.ledger.pendingSchedules(accountID: id).isEmpty)
        XCTAssertEqual(removed.ledger.quotaObservedAt(accountID: id), Date(timeIntervalSince1970: 250))
        let resurrected = apply(snap(225, cycle: "B", used: 95, reset: 2500), ledger: removed.ledger)
        XCTAssertTrue(resurrected.operations.isEmpty)
        XCTAssertEqual(resurrected.ledger, removed.ledger)
    }
    func testStaleSettingsDataPreservesPlansButExplicitDisableAndLatestEnableStillWork() {
        let latestSnapshot = snap(200, used: 20, reset: 2000), latest = apply(latestSnapshot)
        for stale in [Optional(snap(150, empty: true)), nil] {
            let result = planner.planSettingsChange(accountID: id, accountName: "X", latestSnapshot: stale,
                settings: AccountReminderSettings(), ledger: latest.ledger, now: Date(timeIntervalSince1970: 400))
            XCTAssertTrue(result.operations.isEmpty)
            XCTAssertEqual(result.ledger, latest.ledger)
        }
        let disabled = planner.planSettingsChange(accountID: id, accountName: "X", latestSnapshot: snap(150),
            settings: AccountReminderSettings(resetRemindersEnabled: false), ledger: latest.ledger, now: Date(timeIntervalSince1970: 400))
        XCTAssertTrue(disabled.ledger.pendingSchedules(accountID: id).isEmpty)
        let enabled = planner.planSettingsChange(accountID: id, accountName: "X", latestSnapshot: latestSnapshot,
            settings: AccountReminderSettings(), ledger: disabled.ledger, now: Date(timeIntervalSince1970: 400))
        XCTAssertEqual(enabled.ledger.pendingSchedules(accountID: id).map(\.resetAt), [Date(timeIntervalSince1970: 2000)])
    }
    func testOlderPreviousSnapshotCannotManufactureResetOnFreshSameProviderCycle() {
        let a = snap(100), b = snap(200, cycle: "B", used: 20, reset: 2000)
        let first = apply(a), latest = apply(b, previous: a, ledger: first.ledger)
        let sameCycle = apply(snap(250, cycle: "B", used: 95, reset: 2000), previous: a, ledger: latest.ledger)
        XCTAssertFalse(kinds(sameCycle).contains(.confirmedReset))
        XCTAssertTrue(kinds(sameCycle).contains(.quotaAlert))
    }
    func testQuotaFenceDoesNotSuppressIndependentNewWalletObservation() {
        var ledger = apply(snap(200)).ledger
        ledger.setWalletAlertState(.init(accountID: id, currency: "USD", isActive: false, observedAt: Date(timeIntervalSince1970: 100)))
        var mixed = snap(150, used: 95)
        let wallet = QuotaWindow(id: "wallet", name: "wallet", scope: nil, usedPercentage: nil, remainingCount: nil, totalCount: nil,
                                 resetsAt: nil, wallet: .init(currency: "USD", total: 0))
        mixed = .init(accountID: id, windows: mixed.windows + [wallet], collectedAt: mixed.collectedAt)
        let result = apply(mixed, ledger: ledger)
        XCTAssertEqual(kinds(result), [.walletAlert])
        XCTAssertEqual(result.ledger.quotaObservedAt(accountID: id), Date(timeIntervalSince1970: 200))
        XCTAssertEqual(result.ledger.cycleState(accountID: id, windowID: "w"), ledger.cycleState(accountID: id, windowID: "w"))
        XCTAssertEqual(result.ledger.pendingSchedules(accountID: id), ledger.pendingSchedules(accountID: id))
    }
    func testQuotaFenceRoundTripLegacyFallbackAndNewestMergeAreAccountIsolated() throws {
        let latest = apply(snap(200)).ledger
        XCTAssertEqual(try JSONDecoder().decode(ReminderLedger.self, from: JSONEncoder().encode(latest)), latest)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(latest)) as? [String: Any])
        object.removeValue(forKey: "quotaObservationTimes")
        let legacy = try JSONDecoder().decode(ReminderLedger.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(legacy.quotaObservedAt(accountID: id), Date(timeIntervalSince1970: 200))
        var newer = latest; newer.recordQuotaObservation(Date(timeIntervalSince1970: 300), accountID: id)
        let otherID = UUID(); newer.recordQuotaObservation(Date(timeIntervalSince1970: 50), accountID: otherID)
        let merged = legacy.merging(newer)
        XCTAssertEqual(merged.quotaObservedAt(accountID: id), Date(timeIntervalSince1970: 300))
        XCTAssertEqual(merged.quotaObservedAt(accountID: otherID), Date(timeIntervalSince1970: 50))
        XCTAssertEqual(newer.merging(legacy).quotaObservedAt(accountID: id), Date(timeIntervalSince1970: 300))
    }
    func testCredentialReplacementClearsFenceAndIncompatibleMergeCannotBlockNewScope() {
        var old = ReminderLedger(); _ = old.bindCredentialIdentity("old", accountID: id)
        old = apply(snap(300), ledger: old).ledger
        var new = old; _ = new.bindCredentialIdentity("new", accountID: id)
        XCTAssertNil(new.quotaObservedAt(accountID: id))
        let merged = new.merging(old)
        XCTAssertNil(merged.quotaObservedAt(accountID: id))
        let refreshed = apply(snap(50, cycle: "new", used: 95), ledger: merged)
        XCTAssertTrue(kinds(refreshed).contains(.quotaAlert))
        XCTAssertEqual(refreshed.ledger.quotaObservedAt(accountID: id), Date(timeIntervalSince1970: 50))
    }
}

extension NotificationTests {
    func testBilingualNotificationsPreserveAccountModelsCurrencyAndRegionalAmounts() throws {
        let observation = Date(timeIntervalSince1970: 100)
        let reset = observation.addingTimeInterval(3600)
        let userName = "工作 🌙 / Claude API Key"
        let quota = QuotaWindow(id: "claude.weekly_scoped.Fable", name: "每周额度", scope: "Fable",
                                period: .weekly, usedPercentage: 96, remainingCount: nil, totalCount: nil,
                                resetsAt: reset, cycleID: "weekly-original")
        let wallet = QuotaWindow(id: "custom.wallet", name: "USD", scope: nil,
                                 usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                                 wallet: WalletBalance(currency: "USD", total: Decimal(string: "1.23456789")!))
        let snapshot = QuotaSnapshot(accountID: accountID, windows: [quota, wallet], collectedAt: observation)
        for language in ["zh-Hans", "en"] {
            for region in ["en_US", "en_DE"] {
                L10n.withLanguage(language) {
                    let result = planner.planSuccessfulRefresh(accountID: accountID, accountName: userName, provider: .claude,
                        previousSnapshot: nil, newSnapshot: snapshot, settings: AccountReminderSettings(),
                        ledger: ReminderLedger(), now: observation, locale: Locale(identifier: region))
                    let quotas = delivered(result.operations, kind: .quotaAlert)
                    XCTAssertEqual(quotas.map(\.title), [language == "en" ? "\(userName) Quota Alert" : "\(userName)额度告警"])
                    XCTAssertTrue(quotas[0].body.contains(language == "en" ? "Fable Weekly Quota" : "Fable 每周额度"))
                    XCTAssertTrue(quotas[0].body.contains("95"))
                    let wallets = delivered(result.operations, kind: .walletAlert)
                    XCTAssertEqual(wallets.map(\.title), [language == "en" ? "\(userName) Wallet Balance Alert" : "\(userName)钱包余额提醒"])
                    XCTAssertTrue(wallets[0].body.contains(region == "en_DE" ? "1,23456789 USD" : "1.23456789 USD"))
                    XCTAssertEqual(scheduled(result.operations).map(\.1), [reset])
                    XCTAssertEqual(scheduled(result.operations)[0].0.kind, .expectedReset)
                    XCTAssertTrue(result.ledger.containsQuotaAlert(accountID: accountID, windowID: quota.id,
                                                                  cycle: .provider("weekly-original"), threshold: 95))
                    XCTAssertEqual(snapshot.windows[0].name, "每周额度")
                    XCTAssertEqual(snapshot.windows[0].scope, "Fable")
                    XCTAssertEqual(snapshot.windows[1].wallet?.currency, "USD")
                }
            }
        }
    }

    func testLanguageChangesReplaceOnlyFutureContentWithoutRearmingOrReplaying() throws {
        let observation = Date(timeIntervalSince1970: 100)
        let reset = observation.addingTimeInterval(3600)
        let quota = QuotaWindow(id: "claude.weekly", name: "每周额度", scope: nil, period: .weekly,
                                usedPercentage: 96, remainingCount: nil, totalCount: nil, resetsAt: reset, cycleID: "same-cycle")
        let snapshot = QuotaSnapshot(accountID: accountID, windows: [quota], collectedAt: observation)
        let initial = L10n.withLanguage("zh-Hans") {
            planner.planSuccessfulRefresh(accountID: accountID, accountName: "我的 API", provider: .claude,
                previousSnapshot: nil, newSnapshot: snapshot, settings: AccountReminderSettings(),
                ledger: ReminderLedger(), now: observation)
        }
        let original = try XCTUnwrap(scheduled(initial.operations).first)
        let translated = L10n.withLanguage("en") {
            planner.planSettingsChange(accountID: accountID, accountName: "我的 API", provider: .claude,
                latestSnapshot: snapshot, settings: AccountReminderSettings(), ledger: initial.ledger, now: observation)
        }
        let replacement = try XCTUnwrap(scheduled(translated.operations).first)
        XCTAssertEqual(replacement.0.identifier, original.0.identifier)
        XCTAssertEqual(replacement.1, original.1)
        XCTAssertEqual(replacement.0.title, "我的 API Quota Expected to Have Reset")
        XCTAssertEqual(replacement.0.body, "Weekly Quota")
        XCTAssertTrue(cancelled(translated.operations).isEmpty)
        XCTAssertEqual(translated.operations.count, 1)
        XCTAssertEqual(translated.ledger.pendingSchedules(accountID: accountID).map(\.windowIDs), [Set([quota.id])])
        let occurrence = ResetOccurrenceRecord(accountID: accountID, windowID: quota.id, identity: .expectedAt(reset))
        XCTAssertTrue(initial.ledger.hasExpectedReset(occurrence))
        XCTAssertTrue(translated.ledger.hasExpectedReset(occurrence))
        XCTAssertEqual(translated.ledger.quotaObservedAt(accountID: accountID), initial.ledger.quotaObservedAt(accountID: accountID))
        for threshold in [80.0, 95.0] {
            XCTAssertTrue(translated.ledger.containsQuotaAlert(accountID: accountID, windowID: quota.id,
                                                               cycle: .provider("same-cycle"), threshold: threshold))
        }
        let repeated = L10n.withLanguage("en") {
            planner.planSuccessfulRefresh(accountID: accountID, accountName: "我的 API", provider: .claude,
                previousSnapshot: snapshot, newSnapshot: snapshot, settings: AccountReminderSettings(),
                ledger: translated.ledger, now: observation)
        }
        XCTAssertTrue(repeated.operations.isEmpty)
        let afterDelivery = L10n.withLanguage("zh-Hans") {
            planner.planSettingsChange(accountID: accountID, accountName: "我的 API", provider: .claude,
                latestSnapshot: snapshot, settings: AccountReminderSettings(), ledger: translated.ledger,
                now: reset.addingTimeInterval(1))
        }
        XCTAssertTrue(scheduled(afterDelivery.operations).isEmpty)
        XCTAssertTrue(delivered(afterDelivery.operations, kind: .quotaAlert).isEmpty)
        XCTAssertTrue(delivered(afterDelivery.operations, kind: .confirmedReset).isEmpty)
        XCTAssertTrue(afterDelivery.ledger.hasExpectedReset(occurrence))
    }

    func testOldLedgerWithoutRenderedContentMigratesOnlyItsFutureRequest() throws {
        let observation = Date(timeIntervalSince1970: 100)
        let reset = observation.addingTimeInterval(3600)
        let quota = QuotaWindow(id: "claude.weekly", name: "每周额度", scope: nil, period: .weekly,
                                usedPercentage: 80, remainingCount: nil, totalCount: nil, resetsAt: reset)
        let snapshot = QuotaSnapshot(accountID: accountID, windows: [quota], collectedAt: observation)
        let initial = L10n.withLanguage("zh-Hans") {
            planner.planSuccessfulRefresh(accountID: accountID, accountName: "用户原名", provider: .claude,
                previousSnapshot: nil, newSnapshot: snapshot, settings: AccountReminderSettings(),
                ledger: ReminderLedger(), now: observation)
        }
        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(initial.ledger)) as? [String: Any])
        var schedules = try XCTUnwrap(archive["pendingResetSchedules"] as? [[String: Any]])
        for index in schedules.indices {
            schedules[index].removeValue(forKey: "notification")
            schedules[index].removeValue(forKey: "notificationWindows")
        }
        archive["pendingResetSchedules"] = schedules
        let legacy = try JSONDecoder().decode(ReminderLedger.self, from: JSONSerialization.data(withJSONObject: archive))
        XCTAssertNil(legacy.pendingSchedules(accountID: accountID).first?.notification)
        let result = L10n.withLanguage("en") {
            planner.planSettingsChange(accountID: accountID, accountName: "用户原名", provider: .claude,
                latestSnapshot: snapshot, settings: AccountReminderSettings(), ledger: legacy, now: observation)
        }
        XCTAssertEqual(scheduled(result.operations).map { $0.0.identifier }, scheduled(initial.operations).map { $0.0.identifier })
        XCTAssertEqual(scheduled(result.operations).map(\.1), [reset])
        XCTAssertEqual(result.operations.count, 1)
        XCTAssertTrue(result.ledger.containsQuotaAlert(accountID: accountID, windowID: quota.id,
                                                       cycle: .resetBoundary(reset), threshold: 80))
        let reopened = try JSONDecoder().decode(ReminderLedger.self, from: JSONEncoder().encode(result.ledger))
        let repeated = L10n.withLanguage("en") {
            planner.planSettingsChange(accountID: accountID, accountName: "用户原名", provider: .claude,
                latestSnapshot: snapshot, settings: AccountReminderSettings(), ledger: reopened, now: observation)
        }
        XCTAssertTrue(repeated.operations.isEmpty)
    }

    func testPendingLanguageRemainsDeviceLocalAndOtherAccountsKeepTheirContent() throws {
        let observation = Date(timeIntervalSince1970: 100)
        let reset = observation.addingTimeInterval(3600)
        let otherID = UUID()
        let quota = QuotaWindow(id: "claude.weekly", name: "每周额度", scope: nil, period: .weekly,
                                usedPercentage: 20, remainingCount: nil, totalCount: nil, resetsAt: reset)
        let firstSnapshot = QuotaSnapshot(accountID: accountID, windows: [quota], collectedAt: observation)
        let otherSnapshot = QuotaSnapshot(accountID: otherID, windows: [quota], collectedAt: observation)
        let first = L10n.withLanguage("zh-Hans") {
            planner.planSettingsChange(accountID: accountID, accountName: "账户一", provider: .claude,
                latestSnapshot: firstSnapshot, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: observation)
        }
        let both = L10n.withLanguage("zh-Hans") {
            planner.planSettingsChange(accountID: otherID, accountName: "账户二", provider: .claude,
                latestSnapshot: otherSnapshot, settings: AccountReminderSettings(), ledger: first.ledger, now: observation)
        }
        let english = L10n.withLanguage("en") {
            planner.planSettingsChange(accountID: accountID, accountName: "账户一", provider: .claude,
                latestSnapshot: firstSnapshot, settings: AccountReminderSettings(), ledger: both.ledger, now: observation)
        }
        XCTAssertEqual(english.ledger.pendingSchedules(accountID: otherID), both.ledger.pendingSchedules(accountID: otherID))
        XCTAssertEqual(both.ledger.merging(english.ledger).pendingSchedules(accountID: accountID), both.ledger.pendingSchedules(accountID: accountID))
        XCTAssertEqual(english.ledger.merging(both.ledger).pendingSchedules(accountID: accountID), english.ledger.pendingSchedules(accountID: accountID))
    }

    func testBilingualConfirmedResetAndZeroOneManyWindowsRemainDistinct() {
        let observation = Date(timeIntervalSince1970: 100)
        for language in ["zh-Hans", "en"] {
            L10n.withLanguage(language) {
                for count in [0, 1, 2] {
                    let windows = (0..<count).map { index in
                        QuotaWindow(id: "claude.weekly.\(index)", name: "每周额度", scope: "Model-\(index)", period: .weekly,
                                    usedPercentage: 20, remainingCount: nil, totalCount: nil, resetsAt: nil, cycleID: "old")
                    }
                    let before = QuotaSnapshot(accountID: accountID, windows: windows, collectedAt: observation)
                    let initial = planner.planSuccessfulRefresh(accountID: accountID, accountName: "Custom 用户", provider: .claude,
                        previousSnapshot: nil, newSnapshot: before, settings: AccountReminderSettings(),
                        ledger: ReminderLedger(), now: observation)
                    let changed = windows.map {
                        QuotaWindow(id: $0.id, name: $0.name, scope: $0.scope, period: $0.period,
                                    usedPercentage: $0.usedPercentage, remainingCount: nil, totalCount: nil,
                                    resetsAt: nil, cycleID: "new")
                    }
                    let after = QuotaSnapshot(accountID: accountID, windows: changed, collectedAt: observation.addingTimeInterval(1))
                    let result = planner.planSuccessfulRefresh(accountID: accountID, accountName: "Custom 用户", provider: .claude,
                        previousSnapshot: before, newSnapshot: after, settings: AccountReminderSettings(), ledger: initial.ledger,
                        now: observation.addingTimeInterval(1))
                    let confirmations = delivered(result.operations, kind: .confirmedReset)
                    XCTAssertEqual(confirmations.count, count == 0 ? 0 : 1)
                    if let notification = confirmations.first {
                        XCTAssertEqual(notification.title, language == "en" ? "Custom 用户 Quota Reset Confirmed" : "Custom 用户额度已重置")
                        XCTAssertTrue(notification.body.contains(language == "en" ? "Model-0 Weekly Quota" : "Model-0 每周额度"))
                        if count == 2 { XCTAssertTrue(notification.body.contains(language == "en" ? ", " : "、")) }
                    }
                    XCTAssertTrue(scheduled(result.operations).isEmpty)
                }
            }
        }
    }

    @MainActor
    func testRuntimeLanguageReplacementFailureKeepsPersistedHistoryAndRetrySucceeds() async throws {
        let suite = "com.tokenpulse.tests.notification-language.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "notificationsEnabled")
        let adapter = RecordingNotificationAdapter()
        let runtime = NotificationRuntime(defaults: defaults, adapter: adapter)
        let account = SubscriptionAccount(name: "原始用户 🌙", provider: .claude)
        let observation = Date()
        let quota = QuotaWindow(id: "claude.weekly", name: "每周额度", scope: nil, period: .weekly,
                                usedPercentage: 96, remainingCount: nil, totalCount: nil,
                                resetsAt: observation.addingTimeInterval(3600), cycleID: "unchanged")
        let state = AccountQuotaState(account: account, snapshot: QuotaSnapshot(accountID: account.id, windows: [quota], collectedAt: observation))
        let configurations = [AccountConfiguration(account: account)]
        try await L10n.withLanguage("zh-Hans") { try await runtime.fresh(state: state, previous: nil, settings: configurations[0].reminders) }
        let prior = runtime.ledger
        let deliveries = await adapter.operations().filter { if case .deliver = $0 { return true }; return false }
        await adapter.failNextApply()
        do {
            try await L10n.withLanguage("en") { try await runtime.settingsChanged(configurations: configurations, states: [state]) }
            XCTFail("A failed replacement must remain retryable")
        } catch { XCTAssertEqual(error as? NotificationAdapterError, .authorizationRequired) }
        XCTAssertEqual(runtime.ledger, prior)
        let restored = NotificationRuntime(defaults: defaults, adapter: adapter)
        XCTAssertEqual(restored.ledger, prior)
        try await L10n.withLanguage("en") { try await restored.settingsChanged(configurations: configurations, states: [state]) }
        let pending = try XCTUnwrap(restored.ledger.pendingSchedules(accountID: account.id).first)
        XCTAssertEqual(pending.notificationID, prior.pendingSchedules(accountID: account.id).first?.notificationID)
        XCTAssertEqual(pending.resetAt, quota.resetsAt)
        XCTAssertEqual(pending.notification?.title, "原始用户 🌙 Quota Expected to Have Reset")
        XCTAssertEqual(pending.notification?.body, "Weekly Quota")
        let currentDeliveries = await adapter.operations().filter { if case .deliver = $0 { return true }; return false }
        XCTAssertEqual(currentDeliveries, deliveries)
        let count = await adapter.operations().count
        try await L10n.withLanguage("en") { try await restored.settingsChanged(configurations: configurations, states: [state]) }
        let afterRepeated = await adapter.operations().count
        XCTAssertEqual(afterRepeated, count)
    }

    @MainActor
    func testBilingualPermissionAndExplicitDemoNotificationUseDeviceLanguage() async throws {
        for language in ["zh-Hans", "en", "fr"] {
            try await L10n.withLanguage(language) {
                let suite = "com.tokenpulse.tests.demo-notification-language.\(UUID().uuidString)"
                let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let adapter = RecordingNotificationAdapter()
                let runtime = NotificationRuntime(defaults: defaults, adapter: adapter)
                let feedback = await runtime.sendDemoNotification()
                XCTAssertEqual(feedback, .enabled)
                XCTAssertTrue(feedback.message.contains(language == "zh-Hans" ? "通知权限已开启" : "Notification permissions are enabled"))
                let operations = await adapter.operations()
                let notification = try XCTUnwrap(delivered(operations, kind: .quotaAlert).first)
                XCTAssertEqual(notification.identifier, "tokenpulse.demo.preview")
                XCTAssertEqual(notification.title, language == "zh-Hans" ? "TokenPulse 演示提醒" : "TokenPulse Demo Reminder")
                XCTAssertTrue(notification.body.contains(language == "zh-Hans" ? "这是示例通知" : "This is a sample notification"))
            }
        }
    }
}

extension NotificationTests {
    @MainActor
    func testActivationUpdatesCachedNotificationBeforeOfflineQueryAndKeepsLastQuota() async throws {
        let suite = "com.tokenpulse.tests.notification-activation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "notificationsEnabled")
        let account = SubscriptionAccount(name: "Offline 用户", provider: .claude)
        let quota = QuotaWindow(id: "claude.weekly", name: "每周额度", scope: nil, period: .weekly,
                                usedPercentage: 20, remainingCount: nil, totalCount: nil,
                                resetsAt: Date().addingTimeInterval(3600))
        let snapshot = QuotaSnapshot(accountID: account.id, windows: [quota], collectedAt: Date())
        let store = NotificationActivationStore(states: [AccountQuotaState(account: account, snapshot: snapshot)])
        let events = NotificationActivationEvents()
        let monitor = QuotaMonitor(accountStore: store, credentialStore: NotificationActivationCredentials(),
                                   quotaClient: NotificationActivationOfflineClient(events: events))
        await monitor.start(refresh: false)
        let adapter = RecordingNotificationAdapter()
        let notifications = NotificationRuntime(defaults: defaults, adapter: adapter)
        try await L10n.withLanguage("zh-Hans") {
            try await notifications.settingsChanged(configurations: monitor.configurations, states: monitor.states)
        }
        monitor.onActivation = {
            await events.append("activation")
            try? await notifications.settingsChanged(configurations: monitor.configurations, states: monitor.states)
        }
        await L10n.withLanguage("en") { await monitor.applicationDidBecomeActive() }
        let observedEvents = await events.values()
        XCTAssertEqual(observedEvents, ["activation", "query"])
        XCTAssertEqual(monitor.states.first?.snapshot, snapshot)
        XCTAssertEqual(monitor.states.first?.lastFailure, .network)
        let pending = try XCTUnwrap(notifications.ledger.pendingSchedules(accountID: account.id).first)
        XCTAssertEqual(pending.notification?.body, "Weekly Quota")
        XCTAssertEqual(pending.resetAt, quota.resetsAt)
    }
}

private actor NotificationActivationStore: AccountStateStoring {
    private var states: [AccountQuotaState]
    init(states: [AccountQuotaState]) { self.states = states }
    func load() -> [AccountQuotaState] { states }
    func save(_ states: [AccountQuotaState]) { self.states = states }
}

private struct NotificationActivationCredentials: CredentialStoring {
    func credential(for accountID: UUID) async throws -> String? { "fixture" }
    func save(_ credential: String, for accountID: UUID) async throws {}
    func deleteCredential(for accountID: UUID) async throws {}
}

private actor NotificationActivationEvents {
    private var events: [String] = []
    func append(_ event: String) { events.append(event) }
    func values() -> [String] { events }
}

private struct NotificationActivationOfflineClient: QuotaQuerying {
    let events: NotificationActivationEvents
    func quota(for accountID: UUID, credential: String) async throws -> QuotaSnapshot {
        await events.append("query")
        throw RefreshFailure.network
    }
}

extension NotificationTests {
    func testStaleOrMissingSnapshotStillTranslatesPendingContentWithoutChangingObservationFence() throws {
        let observation = Date(timeIntervalSince1970: 100)
        let reset = observation.addingTimeInterval(3600)
        let quota = QuotaWindow(id: "claude.weekly", name: "每周额度", scope: "Fable", period: .weekly,
                                usedPercentage: 96, remainingCount: nil, totalCount: nil, resetsAt: reset, cycleID: "local-cycle")
        let localSnapshot = QuotaSnapshot(accountID: accountID, windows: [quota], collectedAt: observation)
        let local = L10n.withLanguage("zh-Hans") {
            planner.planSuccessfulRefresh(accountID: accountID, accountName: "Offline 用户", provider: .claude,
                previousSnapshot: nil, newSnapshot: localSnapshot, settings: AccountReminderSettings(),
                ledger: ReminderLedger(), now: observation)
        }
        var fencedLedger = local.ledger
        let remoteObservation = observation.addingTimeInterval(10)
        fencedLedger.recordQuotaObservation(remoteObservation, accountID: accountID)
        for cachedSnapshot in [Optional(localSnapshot), nil] {
            let result = L10n.withLanguage("en") {
                planner.planSettingsChange(accountID: accountID, accountName: "Offline 用户", provider: .claude,
                    latestSnapshot: cachedSnapshot, settings: AccountReminderSettings(),
                    ledger: fencedLedger, now: observation)
            }
            XCTAssertEqual(result.operations.count, 1)
            let replacement = try XCTUnwrap(scheduled(result.operations).first)
            XCTAssertEqual(replacement.0.body, "Fable Weekly Quota")
            XCTAssertEqual(replacement.0.identifier, scheduled(local.operations).first?.0.identifier)
            XCTAssertEqual(replacement.1, reset)
            XCTAssertEqual(result.ledger.quotaObservedAt(accountID: accountID), remoteObservation)
            XCTAssertTrue(result.ledger.containsQuotaAlert(accountID: accountID, windowID: quota.id,
                                                           cycle: .provider("local-cycle"), threshold: 95))
            XCTAssertTrue(result.ledger.hasExpectedReset(.init(accountID: accountID, windowID: quota.id, identity: .expectedAt(reset))))
            let cachedInputs = try XCTUnwrap(result.ledger.pendingSchedules(accountID: accountID).first?.notificationWindows)
            XCTAssertNil(cachedInputs[0].usedPercentage)
            XCTAssertNil(cachedInputs[0].resetsAt)
            let repeated = L10n.withLanguage("en") {
                planner.planSettingsChange(accountID: accountID, accountName: "Offline 用户", provider: .claude,
                    latestSnapshot: cachedSnapshot, settings: AccountReminderSettings(),
                    ledger: result.ledger, now: observation)
            }
            XCTAssertTrue(repeated.operations.isEmpty)
        }
    }
}

extension NotificationTests {
    func testLegacyPendingWithoutSnapshotOrDisplayMetadataGetsOnlyALocalizedForecast() throws {
        let observation = Date(timeIntervalSince1970: 100)
        let future = observation.addingTimeInterval(3600)
        let past = observation.addingTimeInterval(-1)
        let windowID = "unknown.provider.opaque-window"
        let futurePlan = PendingResetSchedule(accountID: accountID, notificationID: "original-future-id",
                                               resetAt: future, windowIDs: [windowID])
        let pastPlan = PendingResetSchedule(accountID: accountID, notificationID: "already-due-id",
                                             resetAt: past, windowIDs: [windowID])
        let expectedFuture = ResetOccurrenceRecord(accountID: accountID, windowID: windowID, identity: .expectedAt(future))
        let confirmedPast = ResetOccurrenceRecord(accountID: accountID, windowID: windowID, identity: .expectedAt(past))
        var original = ReminderLedger()
        original.replacePendingSchedules(accountID: accountID, with: [futurePlan, pastPlan])
        original.recordExpectedReset(expectedFuture)
        original.recordConfirmedReset(confirmedPast)
        original.recordQuotaAlert(accountID: accountID, windowID: windowID, cycle: .provider("old-cycle"), threshold: 80)
        // This archive has neither new presentation field and may predate the observation fence.
        let legacy = try JSONDecoder().decode(ReminderLedger.self, from: JSONEncoder().encode(original))
        for hasObservationFence in [false, true] {
            var prior = legacy
            if hasObservationFence { prior.recordQuotaObservation(observation, accountID: accountID) }
            for language in ["zh-Hans", "en"] {
                let result = L10n.withLanguage(language) {
                    planner.planSettingsChange(accountID: accountID, accountName: "User 原名", provider: .claude,
                        latestSnapshot: nil, settings: AccountReminderSettings(), ledger: prior, now: observation)
                }
                XCTAssertEqual(result.operations.count, 1)
                if hasObservationFence {
                    let replacement = try XCTUnwrap(scheduled(result.operations).first)
                    XCTAssertEqual(replacement.0.identifier, "original-future-id")
                    XCTAssertEqual(replacement.1, future)
                    XCTAssertEqual(replacement.0.kind, .expectedReset)
                    XCTAssertEqual(replacement.0.title, language == "en" ? "User 原名 Quota Expected to Have Reset" : "User 原名额度预计已重置")
                    XCTAssertEqual(replacement.0.body, language == "en"
                                   ? "This account’s quota is expected to have reset. Refresh to confirm."
                                   : "该账号额度预计已重置，请刷新确认。")
                    XCTAssertEqual(result.ledger.pendingSchedules(accountID: accountID).map(\.windowIDs),
                                   [Set([windowID]), Set([windowID])])
                    XCTAssertEqual(result.ledger.pendingSchedules(accountID: accountID).last, pastPlan)
                } else {
                    // Missing data without a protected newer observation still cancels, in either language.
                    XCTAssertTrue(scheduled(result.operations).isEmpty)
                    XCTAssertEqual(cancelled(result.operations), [["already-due-id", "original-future-id"]])
                    XCTAssertTrue(result.ledger.pendingSchedules(accountID: accountID).isEmpty)
                }
                XCTAssertEqual(result.ledger.quotaObservedAt(accountID: accountID), prior.quotaObservedAt(accountID: accountID))
                XCTAssertEqual(result.ledger.hasExpectedReset(expectedFuture), hasObservationFence)
                XCTAssertTrue(result.ledger.hasConfirmedReset(confirmedPast))
                XCTAssertTrue(result.ledger.containsQuotaAlert(accountID: accountID, windowID: windowID,
                                                               cycle: .provider("old-cycle"), threshold: 80))
                let repeated = L10n.withLanguage(language) {
                    planner.planSettingsChange(accountID: accountID, accountName: "User 原名", provider: .claude,
                        latestSnapshot: nil, settings: AccountReminderSettings(), ledger: result.ledger, now: observation)
                }
                XCTAssertTrue(repeated.operations.isEmpty)
                let disabled = L10n.withLanguage(language) {
                    planner.planSettingsChange(accountID: accountID, accountName: "User 原名", provider: .claude,
                        latestSnapshot: nil, settings: AccountReminderSettings(resetRemindersEnabled: false),
                        ledger: result.ledger, now: observation)
                }
                XCTAssertTrue(scheduled(disabled.operations).isEmpty)
                XCTAssertTrue(disabled.ledger.pendingSchedules(accountID: accountID).isEmpty)
            }
        }
    }
}
