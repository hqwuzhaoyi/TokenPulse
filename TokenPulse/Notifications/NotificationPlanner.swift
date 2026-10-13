import Foundation

struct NotificationPlanner: Sendable {
    func planSuccessfulRefresh(accountID: UUID,
                               accountName: String,
                               provider: Provider? = nil,
                               previousSnapshot: QuotaSnapshot?,
                               newSnapshot: QuotaSnapshot,
                               settings: AccountReminderSettings,
                               ledger: ReminderLedger,
                               now: Date, locale: Locale = .autoupdatingCurrent) -> NotificationPlanningResult {
        var ledger = ledger
        var operations: [NotificationOperation] = []
        var quotaMessages: [String] = []
        var confirmedResetWindows: [String] = []
        let previousWindows = Dictionary(uniqueKeysWithValues: (previousSnapshot?.windows ?? []).map { ($0.id, $0) })
        let quotaIsFresh = ledger.quotaObservedAt(accountID: accountID).map { newSnapshot.collectedAt > $0 } ?? true

        for window in newSnapshot.windows where window.wallet == nil && quotaIsFresh {
            if let existing = ledger.cycleState(accountID: accountID, windowID: window.id),
               newSnapshot.collectedAt <= existing.observedAt { continue }
            let previousWindow = previousWindows[window.id]
            let cycle = resolveCycle(
                accountID: accountID,
                previousWindow: previousWindow,
                previousCollectedAt: previousSnapshot?.collectedAt,
                currentWindow: window,
                collectedAt: newSnapshot.collectedAt,
                ledger: ledger,
                minimumThreshold: normalizedThresholds(settings.thresholds).first
            )

            if cycle.didReset, let occurrence = cycle.resetOccurrence {
                let expectedResetWasDue: Bool
                if case .expectedAt(let expectedAt) = occurrence.identity {
                    expectedResetWasDue = expectedAt <= now
                } else {
                    expectedResetWasDue = false
                }
                let alreadyExpected = ledger.hasExpectedReset(occurrence) && expectedResetWasDue
                let alreadyConfirmed = ledger.hasConfirmedReset(occurrence)
                ledger.recordConfirmedReset(occurrence)
                if cycle.shouldNotifyReset,
                   settings.resetRemindersEnabled,
                   !alreadyExpected,
                   !alreadyConfirmed {
                    confirmedResetWindows.append(L10n.windowDisplayName(window, provider: provider))
                }
            }

            let observation = cycleObservation(window, previous: ledger.cycleState(accountID: accountID, windowID: window.id))
            ledger.setCycleState(WindowCycleState(
                accountID: accountID,
                windowID: window.id,
                identity: cycle.identity,
                resetAt: window.resetsAt,
                usedPercentage: observation.percentage,
                observedAt: newSnapshot.collectedAt,
                exactCounts: observation.counts
            ))

            guard settings.quotaAlertsEnabled, !window.isUnlimited else { continue }
            let reachedThresholds = reachedQuotaThresholds(window, thresholds: normalizedThresholds(settings.thresholds))
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
            quotaMessages.append(L10n.format("%@达到%@", L10n.windowDisplayName(window, provider: provider),
                                            (highest / 100).formatted(.percent.precision(.fractionLength(0...2)).locale(locale))))
        }

        if !quotaMessages.isEmpty {
            operations.append(.deliver(ReminderNotification(
                identifier: "quota.\(accountID.uuidString).\(milliseconds(newSnapshot.collectedAt))",
                title: L10n.format("%@额度告警", accountName),
                body: quotaMessages.joined(separator: L10n.text("；")),
                kind: .quotaAlert
            )))
        }

        let walletMessages = walletMessages(
            accountID: accountID, snapshot: newSnapshot, settings: settings, ledger: &ledger, locale: locale
        )
        if !walletMessages.isEmpty {
            operations.append(.deliver(ReminderNotification(
                identifier: "wallet.\(accountID.uuidString).\(milliseconds(newSnapshot.collectedAt))",
                title: L10n.format("%@钱包余额提醒", accountName),
                body: walletMessages.joined(separator: L10n.text("；")),
                kind: .walletAlert
            )))
        }

        if !confirmedResetWindows.isEmpty {
            operations.append(.deliver(ReminderNotification(
                identifier: "reset.confirmed.\(accountID.uuidString).\(milliseconds(newSnapshot.collectedAt))",
                title: L10n.format("%@额度已重置", accountName),
                body: confirmedResetWindows.joined(separator: L10n.text("、")),
                kind: .confirmedReset
            )))
        }

        if quotaIsFresh {
            operations.append(contentsOf: reconcileResetSchedules(
                accountID: accountID,
                accountName: accountName,
                provider: provider,
                snapshot: newSnapshot,
                settings: settings,
                ledger: &ledger,
                now: now
            ))
            // Empty successful frames also advance the clock, so old frames
            // cannot resurrect windows or plans removed by newer observations.
            ledger.recordQuotaObservation(newSnapshot.collectedAt, accountID: accountID)
        }

        return NotificationPlanningResult(operations: operations, ledger: ledger)
    }

    func planSettingsChange(accountID: UUID,
                            accountName: String,
                            provider: Provider? = nil,
                            latestSnapshot: QuotaSnapshot?,
                            settings: AccountReminderSettings,
                            ledger: ReminderLedger,
                            now: Date) -> NotificationPlanningResult {
        var ledger = ledger
        let operations = reconcileResetSchedules(
            accountID: accountID,
            accountName: accountName,
            provider: provider,
            snapshot: latestSnapshot,
            settings: settings,
            ledger: &ledger,
            now: now
        )
        if let snapshot = latestSnapshot,
           snapshot.collectedAt >= (ledger.quotaObservedAt(accountID: accountID) ?? .distantPast) {
            ledger.recordQuotaObservation(snapshot.collectedAt, accountID: accountID)
        }
        return NotificationPlanningResult(operations: operations, ledger: ledger)
    }

    private func walletMessages(accountID: UUID,
                                 snapshot: QuotaSnapshot,
                                 settings: AccountReminderSettings,
                                 ledger: inout ReminderLedger, locale: Locale) -> [String] {
        // A retained wallet is historical data: neither alert nor rearm its state from a failed collection.
        guard snapshot.walletFailure == nil else { return [] }
        var messages: [String] = []
        let wallets = snapshot.windows.compactMap(\.wallet).filter(\.isMonetary)
        let currency = settings.walletCurrency ?? wallets.first?.currency
        if let wallet = wallets.first(where: { $0.currency == currency }),
           observeWalletAlert(accountID: accountID, currency: wallet.currency,
                              active: wallet.total <= settings.walletThreshold(for: wallet.currency),
                              enabled: settings.effectiveWalletAlertsEnabled, observedAt: snapshot.collectedAt,
                              ledger: &ledger) {
            messages.append(L10n.format("可用余额 %@，已达到低余额阈值",
                                        QuotaFormatting.money(wallet.total, currency: wallet.currency, locale: locale)))
        }
        if !wallets.isEmpty || !snapshot.windows.contains(where: { $0.wallet?.isMonetary == false }),
           let available = snapshot.walletAvailable,
           observeWalletAlert(accountID: accountID, currency: nil, active: !available,
                              enabled: settings.effectiveWalletAlertsEnabled, observedAt: snapshot.collectedAt,
                              ledger: &ledger) {
            messages.append(L10n.text("余额不足，无法调用 API"))
        }
        return messages
    }

    private func observeWalletAlert(accountID: UUID,
                                    currency: String?,
                                    active: Bool,
                                    enabled: Bool,
                                    observedAt: Date,
                                    ledger: inout ReminderLedger) -> Bool {
        let previous = ledger.walletAlertState(accountID: accountID, currency: currency)
        if let previous, observedAt <= previous.observedAt { return false }
        let shouldAlert = enabled && active && previous?.isActive != true
        ledger.setWalletAlertState(WalletAlertState(
            accountID: accountID,
            currency: currency,
            isActive: active && (shouldAlert || previous?.isActive == true),
            observedAt: observedAt
        ))
        return shouldAlert
    }

    private func resolveCycle(accountID: UUID,
                              previousWindow: QuotaWindow?,
                              previousCollectedAt: Date?,
                              currentWindow: QuotaWindow,
                              collectedAt: Date,
                              ledger: ReminderLedger,
                              minimumThreshold: Double?) -> CycleResolution {
        let existing = ledger.cycleState(accountID: accountID, windowID: currentWindow.id)
        let previousWindow = existing.map { state in
            previousCollectedAt.map { $0 > state.observedAt } == true ? previousWindow : nil
        } ?? previousWindow

        if currentWindow.resetSemantics != nil {
            let previousCounts: DecimalQuotaCounts?
            let previousUsed: Double?
            if let existing, previousCollectedAt.map({ existing.observedAt >= $0 }) ?? true {
                previousCounts = existing.exactCounts
                previousUsed = existing.usedPercentage
            } else {
                previousCounts = previousWindow?.isExhausted == true ? nil : previousWindow?.exactCounts
                previousUsed = previousWindow?.isExhausted == true ? 100 : previousWindow?.usedPercentage
            }
            let restored = minimumThreshold.map { threshold in
                let wasReached = thresholdReached(counts: previousCounts, percentage: previousUsed, threshold: threshold)
                let isReached = currentWindow.isExhausted == true ? true
                    : thresholdReached(counts: currentWindow.exactCounts, percentage: currentWindow.usedPercentage, threshold: threshold)
                return wasReached == true && isReached == false
            } ?? false
            // This is only alert rearming after recovery. It is not a provider reset observation.
            return CycleResolution(identity: restored ? .inferred(collectedAt) : existing?.identity ?? .unidentified,
                                   didReset: false, resetOccurrence: nil, shouldNotifyReset: false)
        }

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
            return CycleResolution(
                identity: identity,
                didReset: didReset,
                resetOccurrence: occurrence,
                shouldNotifyReset: true
            )
        }

        let previousResetAt = existing?.resetAt ?? previousWindow?.resetsAt
        let resetBoundaryAdvanced = previousResetAt.flatMap { previousResetAt in
            currentWindow.resetsAt.map { $0.timeIntervalSince(previousResetAt) > 60 }
        } ?? false
        let previousUsedPercentage: Double?
        if let existing,
           previousCollectedAt.map({ existing.observedAt >= $0 }) ?? true {
            previousUsedPercentage = existing.usedPercentage
        } else {
            previousUsedPercentage = previousWindow?.usedPercentage
        }
        let usageDropped = previousUsedPercentage.flatMap { previousUsed in
            currentWindow.usedPercentage.map { previousUsed - $0 >= 40 }
        } ?? false
        if resetBoundaryAdvanced || usageDropped {
            let previousIdentity = existing?.identity
                ?? previousResetAt.map(ReminderCycleIdentity.resetBoundary)
                ?? .unidentified
            return CycleResolution(
                identity: .inferred(collectedAt),
                didReset: true,
                resetOccurrence: ResetOccurrenceRecord(
                    accountID: accountID,
                    windowID: currentWindow.id,
                    identity: resetBoundaryAdvanced
                        ? previousResetAt.map(ResetOccurrenceIdentity.expectedAt) ?? .inferred(collectedAt)
                        : .inferred(collectedAt)
                ),
                shouldNotifyReset: ledger.containsQuotaAlert(
                    accountID: accountID,
                    windowID: currentWindow.id,
                    cycle: previousIdentity
                )
            )
        }

        if let existing {
            return CycleResolution(
                identity: existing.identity,
                didReset: false,
                resetOccurrence: nil,
                shouldNotifyReset: false
            )
        }
        if let resetAt = currentWindow.resetsAt {
            return CycleResolution(
                identity: .resetBoundary(resetAt),
                didReset: false,
                resetOccurrence: nil,
                shouldNotifyReset: false
            )
        }
        return CycleResolution(
            identity: .unidentified,
            didReset: false,
            resetOccurrence: nil,
            shouldNotifyReset: false
        )
    }

    private func reconcileResetSchedules(accountID: UUID,
                                         accountName: String,
                                         provider: Provider?,
                                         snapshot: QuotaSnapshot?,
                                         settings: AccountReminderSettings,
                                         ledger: inout ReminderLedger,
                                         now: Date) -> [NotificationOperation] {
        // Settings may explicitly disable reminders, but stale/missing data
        // cannot remove or rearrange schedules established by a newer frame.
        let existing = ledger.pendingSchedules(accountID: accountID)
        if settings.resetRemindersEnabled, let latest = ledger.quotaObservedAt(accountID: accountID),
           snapshot.map({ $0.collectedAt >= latest }) != true {
            // Local pending display inputs can change language even when a remote observation
            // fences out older/missing quota data. They cannot alter the schedule itself.
            let updated = existing.map { schedule in
                guard schedule.resetAt > now else { return schedule }
                if let windows = schedule.notificationWindows, Set(windows.map(\.id)) == schedule.windowIDs {
                    return renderedSchedule(schedule, accountName: accountName, provider: provider, windows: windows)
                }
                // Legacy plans may lack every display input. Preserve their event identity,
                // and translate only an accurate account-level forecast instead of guessing names.
                var updated = schedule
                updated.notification = ReminderNotification(
                    identifier: schedule.notificationID,
                    title: L10n.format("%@额度预计已重置", accountName),
                    body: L10n.text("该账号额度预计已重置，请刷新确认。"),
                    kind: .expectedReset
                )
                return updated
            }
            let changed = zip(existing, updated).compactMap { old, new -> PendingResetSchedule? in
                old.notification != new.notification ? new : nil
            }
            guard !changed.isEmpty else { return [] }
            ledger.replacePendingSchedules(accountID: accountID, with: updated)
            return changed.sorted { $0.resetAt < $1.resetAt }.compactMap { schedule in
                schedule.notification.map { .schedule($0, at: schedule.resetAt) }
            }
        }
        let windowsByID = Dictionary(uniqueKeysWithValues: (snapshot?.windows ?? []).map { ($0.id, $0) })
        let desired = desiredResetSchedules(
            accountID: accountID,
            snapshot: snapshot,
            enabled: settings.resetRemindersEnabled,
            now: now
        ).map { schedule in
            renderedSchedule(schedule, accountName: accountName, provider: provider,
                             windows: schedule.windowIDs.compactMap { windowsByID[$0] })
        }
        // Content is device-local. Updating a future request must not touch occurrence history.
        if scheduleSignatures(existing) == scheduleSignatures(desired) {
            let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.notificationID, $0) })
            let changed = desired.filter { existingByID[$0.notificationID]?.notification != $0.notification }
            // An upgrade can add trusted display inputs without changing today's
            // rendered text. Persist those inputs for later offline language changes.
            if existing != desired { ledger.replacePendingSchedules(accountID: accountID, with: desired) }
            guard !changed.isEmpty else { return [] }
            return changed.sorted { $0.resetAt < $1.resetAt }.compactMap { schedule in
                schedule.notification.map { .schedule($0, at: schedule.resetAt) }
            }
        }

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

        if snapshot != nil {
            for schedule in desired.sorted(by: { $0.resetAt < $1.resetAt }) {
                if let notification = schedule.notification {
                    operations.append(.schedule(notification, at: schedule.resetAt))
                }
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

    private func renderedSchedule(_ schedule: PendingResetSchedule, accountName: String,
                                  provider: Provider?, windows: [QuotaWindow]) -> PendingResetSchedule {
        var result = schedule
        // Cache only name semantics. Usage, monetary values and reset observations stay in the snapshot.
        result.notificationWindows = windows.map {
            QuotaWindow(id: $0.id, name: $0.name, scope: $0.scope, period: $0.period,
                        usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil,
                        presentationLabel: $0.presentationLabel, presentationScope: $0.presentationScope)
        }.sorted { $0.id < $1.id }
        let names = windows.map { L10n.windowDisplayName($0, provider: provider) }.sorted()
        result.notification = ReminderNotification(
            identifier: schedule.notificationID,
            title: L10n.format("%@额度预计已重置", accountName),
            body: names.joined(separator: L10n.text("、")),
            kind: .expectedReset
        )
        return result
    }

    private func desiredResetSchedules(accountID: UUID,
                                       snapshot: QuotaSnapshot?,
                                       enabled: Bool,
                                       now: Date) -> [PendingResetSchedule] {
        guard enabled, let snapshot else { return [] }
        let candidates = snapshot.windows.compactMap { window -> (Date, String)? in
            guard window.wallet == nil,
                  window.resetSemantics == nil,
                  window.resetDatePrecision != .day,
                  !window.isUnlimited,
                  (window.usedPercentage.map { $0 > 0 } ?? window.exactCounts?.used.map { $0 > 0 } ?? false),
                  let resetAt = window.resetsAt,
                  Int64(exactly: (resetAt.timeIntervalSince1970 * 1000).rounded()) != nil,
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

    private func validExactCounts(_ counts: DecimalQuotaCounts?) -> DecimalQuotaCounts? {
        guard let counts, let used = counts.used, let total = counts.total,
              !used.isNaN, !total.isNaN, used >= 0, total > 0 else { return nil }
        return counts
    }

    /// nil means unknown, so a missing reading cannot count as recovery.
    private func thresholdReached(counts: DecimalQuotaCounts?, percentage: Double?, threshold: Double) -> Bool? {
        if let counts = validExactCounts(counts), var used = counts.used, var total = counts.total {
            if used >= total { return true }
            var fraction = Decimal()
            let division = NSDecimalDivide(&fraction, &used, &total, .down)
            guard division == .noError || division == .lossOfPrecision,
                  !fraction.isNaN, fraction >= 0, fraction <= 1 else { return nil }
            var scale = Decimal(100), usedPercentage = Decimal()
            let multiplication = NSDecimalMultiply(&usedPercentage, &fraction, &scale, .down)
            guard multiplication == .noError || multiplication == .lossOfPrecision,
                  !usedPercentage.isNaN else { return nil }
            let exactThreshold = Decimal(threshold)
            guard !exactThreshold.isNaN, exactThreshold > 0 else { return nil }
            return usedPercentage >= exactThreshold
        }
        guard let percentage, percentage.isFinite else { return nil }
        return percentage >= threshold
    }

    private func reachedQuotaThresholds(_ window: QuotaWindow, thresholds: [Double]) -> [Double] {
        // Preserve explicit exhaustion and the legacy percentage-only behavior,
        // including its missing-percentage handling.
        if window.isExhausted == true, window.usedPercentage != nil { return thresholds }
        if validExactCounts(window.exactCounts) != nil {
            if window.isExhausted == true { return thresholds }
            return thresholds.filter { thresholdReached(counts: window.exactCounts, percentage: nil, threshold: $0) == true }
        }
        guard let reported = window.usedPercentage else { return [] }
        return thresholds.filter { $0 <= reported }
    }

    private func cycleObservation(_ window: QuotaWindow, previous: WindowCycleState?)
        -> (percentage: Double?, counts: DecimalQuotaCounts?) {
        let counts = validExactCounts(window.exactCounts)
        guard window.resetSemantics != nil else { return (window.usedPercentage, counts) }
        // Store the provider's exhausted flag as the authoritative 100% reading,
        // without conflicting exact counters overriding it on the next refresh.
        if window.isExhausted == true { return (100, nil) }
        let knownUsed = window.exactCounts?.used.map { !$0.isNaN && $0 >= 0 } ?? false
        if knownUsed || window.usedPercentage?.isFinite == true {
            return (window.usedPercentage, counts)
        }
        return (previous?.usedPercentage, previous?.exactCounts)
    }

    private func normalizedThresholds(_ thresholds: [Double]) -> [Double] {
        Array(Set(thresholds.filter { $0.isFinite && $0 > 0 && $0 <= 100 })).sorted()
    }

    private func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}

private struct CycleResolution {
    let identity: ReminderCycleIdentity
    let didReset: Bool
    let resetOccurrence: ResetOccurrenceRecord?
    let shouldNotifyReset: Bool
}

private struct ScheduleSignature: Equatable {
    let resetAt: Date
    let windowIDs: Set<String>
}
