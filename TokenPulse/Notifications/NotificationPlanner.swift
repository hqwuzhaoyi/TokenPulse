import Foundation

struct NotificationPlanner: Sendable {
    func planSuccessfulRefresh(accountID: UUID,
                               accountName: String,
                               previousSnapshot: QuotaSnapshot?,
                               newSnapshot: QuotaSnapshot,
                               settings: AccountReminderSettings,
                               ledger: ReminderLedger,
                               now: Date) -> NotificationPlanningResult {
        var ledger = ledger
        var operations: [NotificationOperation] = []
        var quotaMessages: [String] = []
        var confirmedResetWindows: [String] = []
        let previousWindows = Dictionary(uniqueKeysWithValues: (previousSnapshot?.windows ?? []).map { ($0.id, $0) })

        for window in newSnapshot.windows {
            let previousWindow = previousWindows[window.id]
            let cycle = resolveCycle(
                accountID: accountID,
                previousWindow: previousWindow,
                currentWindow: window,
                collectedAt: newSnapshot.collectedAt,
                ledger: ledger
            )

            if cycle.didReset, let occurrence = cycle.resetOccurrence {
                let alreadyExpected = ledger.hasExpectedReset(occurrence)
                let alreadyConfirmed = ledger.hasConfirmedReset(occurrence)
                ledger.recordConfirmedReset(occurrence)
                if settings.resetRemindersEnabled && !alreadyExpected && !alreadyConfirmed {
                    confirmedResetWindows.append(window.name)
                }
            }

            ledger.setCycleState(WindowCycleState(
                accountID: accountID,
                windowID: window.id,
                identity: cycle.identity,
                resetAt: window.resetsAt,
                observedAt: newSnapshot.collectedAt
            ))

            guard settings.quotaAlertsEnabled,
                  !window.isUnlimited,
                  let reportedPercentage = window.usedPercentage else { continue }
            let usedPercentage = window.isExhausted == true ? 100 : reportedPercentage

            let reachedThresholds = normalizedThresholds(settings.thresholds)
                .filter { $0 <= usedPercentage }
            let newThresholds = reachedThresholds.filter {
                !ledger.containsQuotaAlert(
                    accountID: accountID,
                    windowID: window.id,
                    cycle: cycle.identity,
                    threshold: $0
                )
            }
            guard let highest = newThresholds.max() else { continue }

            for threshold in reachedThresholds {
                ledger.recordQuotaAlert(
                    accountID: accountID,
                    windowID: window.id,
                    cycle: cycle.identity,
                    threshold: threshold
                )
            }
            quotaMessages.append("\(window.name)达到\(format(highest))%")
        }

        if !quotaMessages.isEmpty {
            operations.append(.deliver(ReminderNotification(
                identifier: "quota.\(accountID.uuidString).\(milliseconds(newSnapshot.collectedAt))",
                title: "\(accountName)额度告警",
                body: quotaMessages.joined(separator: "；"),
                kind: .quotaAlert
            )))
        }

        if !confirmedResetWindows.isEmpty {
            operations.append(.deliver(ReminderNotification(
                identifier: "reset.confirmed.\(accountID.uuidString).\(milliseconds(newSnapshot.collectedAt))",
                title: "\(accountName)额度已确认重置",
                body: confirmedResetWindows.joined(separator: "、"),
                kind: .confirmedReset
            )))
        }

        operations.append(contentsOf: reconcileResetSchedules(
            accountID: accountID,
            accountName: accountName,
            snapshot: newSnapshot,
            settings: settings,
            ledger: &ledger,
            now: now
        ))

        return NotificationPlanningResult(operations: operations, ledger: ledger)
    }

    func planSettingsChange(accountID: UUID,
                            accountName: String,
                            latestSnapshot: QuotaSnapshot?,
                            settings: AccountReminderSettings,
                            ledger: ReminderLedger,
                            now: Date) -> NotificationPlanningResult {
        var ledger = ledger
        let operations = reconcileResetSchedules(
            accountID: accountID,
            accountName: accountName,
            snapshot: latestSnapshot,
            settings: settings,
            ledger: &ledger,
            now: now
        )
        return NotificationPlanningResult(operations: operations, ledger: ledger)
    }

    private func resolveCycle(accountID: UUID,
                              previousWindow: QuotaWindow?,
                              currentWindow: QuotaWindow,
                              collectedAt: Date,
                              ledger: ReminderLedger) -> CycleResolution {
        let existing = ledger.cycleState(accountID: accountID, windowID: currentWindow.id)

        if let cycleID = currentWindow.cycleID {
            let identity = ReminderCycleIdentity.provider(cycleID)
            let previousCycleID = previousWindow?.cycleID
            let priorExplicitIdentity: ReminderCycleIdentity? = existing.flatMap {
                if case .provider = $0.identity { return $0.identity }
                return nil
            }
            let didReset = (previousCycleID != nil && previousCycleID != cycleID)
                || (priorExplicitIdentity != nil && priorExplicitIdentity != identity)
            let previousResetAt = existing?.resetAt ?? previousWindow?.resetsAt
            let occurrence = didReset
                ? ResetOccurrenceRecord(
                    accountID: accountID,
                    windowID: currentWindow.id,
                    identity: previousResetAt.map(ResetOccurrenceIdentity.expectedAt)
                        ?? .providerCycle(cycleID)
                )
                : nil
            return CycleResolution(identity: identity, didReset: didReset, resetOccurrence: occurrence)
        }

        let previousResetAt = existing?.resetAt ?? previousWindow?.resetsAt
        if let previousResetAt,
           collectedAt >= previousResetAt,
           let newResetAt = currentWindow.resetsAt,
           newResetAt > previousResetAt {
            return CycleResolution(
                identity: .resetBoundary(newResetAt),
                didReset: true,
                resetOccurrence: ResetOccurrenceRecord(
                    accountID: accountID,
                    windowID: currentWindow.id,
                    identity: .expectedAt(previousResetAt)
                )
            )
        }

        if let existing {
            return CycleResolution(identity: existing.identity, didReset: false, resetOccurrence: nil)
        }
        if let resetAt = currentWindow.resetsAt {
            return CycleResolution(identity: .resetBoundary(resetAt), didReset: false, resetOccurrence: nil)
        }
        return CycleResolution(identity: .unidentified, didReset: false, resetOccurrence: nil)
    }

    private func reconcileResetSchedules(accountID: UUID,
                                         accountName: String,
                                         snapshot: QuotaSnapshot?,
                                         settings: AccountReminderSettings,
                                         ledger: inout ReminderLedger,
                                         now: Date) -> [NotificationOperation] {
        let existing = ledger.pendingSchedules(accountID: accountID)
        let desired = desiredResetSchedules(
            accountID: accountID,
            snapshot: snapshot,
            enabled: settings.resetRemindersEnabled,
            now: now
        )
        guard scheduleSignatures(existing) != scheduleSignatures(desired) else { return [] }

        var operations: [NotificationOperation] = []
        for schedule in existing where schedule.resetAt > now {
            for windowID in schedule.windowIDs {
                ledger.removeExpectedReset(ResetOccurrenceRecord(
                    accountID: accountID,
                    windowID: windowID,
                    identity: .expectedAt(schedule.resetAt)
                ))
            }
        }
        ledger.replacePendingSchedules(accountID: accountID, with: desired)

        if let snapshot {
            let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.id, $0) })
            for schedule in desired.sorted(by: { $0.resetAt < $1.resetAt }) {
                let names = schedule.windowIDs.compactMap { windowsByID[$0]?.name }.sorted()
                let notification = ReminderNotification(
                    identifier: schedule.notificationID,
                    title: "\(accountName)额度预计已重置",
                    body: names.joined(separator: "、"),
                    kind: .expectedReset
                )
                operations.append(.schedule(notification, at: schedule.resetAt))
                for windowID in schedule.windowIDs {
                    ledger.recordExpectedReset(ResetOccurrenceRecord(
                        accountID: accountID,
                        windowID: windowID,
                        identity: .expectedAt(schedule.resetAt)
                    ))
                }
            }
        }
        let desiredIDs = Set(desired.map(\.notificationID))
        let obsoleteIDs = existing.map(\.notificationID).filter { !desiredIDs.contains($0) }.sorted()
        if !obsoleteIDs.isEmpty {
            operations.append(.cancel(identifiers: obsoleteIDs))
        }
        return operations
    }

    private func desiredResetSchedules(accountID: UUID,
                                       snapshot: QuotaSnapshot?,
                                       enabled: Bool,
                                       now: Date) -> [PendingResetSchedule] {
        guard enabled, let snapshot else { return [] }
        let candidates = snapshot.windows.compactMap { window -> (Date, String)? in
            guard !window.isUnlimited,
                  let usedPercentage = window.usedPercentage,
                  usedPercentage > 0,
                  let resetAt = window.resetsAt,
                  resetAt > now else { return nil }
            return (resetAt, window.id)
        }
        let grouped = Dictionary(grouping: candidates, by: \.0)
        return grouped.map { resetAt, values in
            PendingResetSchedule(
                accountID: accountID,
                notificationID: "reset.expected.\(accountID.uuidString).\(milliseconds(resetAt))",
                resetAt: resetAt,
                windowIDs: Set(values.map(\.1))
            )
        }
    }

    private func scheduleSignatures(_ schedules: [PendingResetSchedule]) -> [ScheduleSignature] {
        schedules.map { ScheduleSignature(resetAt: $0.resetAt, windowIDs: $0.windowIDs) }
            .sorted { lhs, rhs in
                if lhs.resetAt != rhs.resetAt { return lhs.resetAt < rhs.resetAt }
                return lhs.windowIDs.sorted().joined(separator: "\u{0}")
                    < rhs.windowIDs.sorted().joined(separator: "\u{0}")
            }
    }

    private func normalizedThresholds(_ thresholds: [Double]) -> [Double] {
        Array(Set(thresholds.filter { $0.isFinite && $0 > 0 && $0 <= 100 })).sorted()
    }

    private func format(_ threshold: Double) -> String {
        threshold.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}

private struct CycleResolution {
    let identity: ReminderCycleIdentity
    let didReset: Bool
    let resetOccurrence: ResetOccurrenceRecord?
}

private struct ScheduleSignature: Equatable {
    let resetAt: Date
    let windowIDs: Set<String>
}
