import Foundation
import XCTest
@testable import TokenPulse

final class ReplenishmentSemanticsTests: XCTestCase {
    func testPartialReplenishmentNeverSchedulesOrConfirmsResetAndRearmsOnlyBelowLowestThreshold() {
        let id = UUID()
        let planner = NotificationPlanner()
        let settings = AccountReminderSettings(thresholds: [30, 80, 100])
        var ledger = ReminderLedger()
        var previous: QuotaSnapshot?
        for (index, usage, shouldAlert) in [(0, 100.0, true), (1, 55.0, false), (2, 90.0, false),
                                          (3, 29.0, false), (4, 31.0, true), (5, 29.0, false),
                                          (6, 31.0, true)] {
            let time = Date(timeIntervalSince1970: Double(index + 1) * 100)
            let window = QuotaWindow(id: "continuous", name: "滚动额度", scope: nil, usedPercentage: usage,
                                     remainingCount: nil, totalCount: nil, resetsAt: time.addingTimeInterval(100),
                                     cycleID: "changing-\(index)", resetSemantics: .continuousReplenishment,
                                     nextReplenishmentAt: time.addingTimeInterval(10))
            let snapshot = QuotaSnapshot(accountID: id, windows: [window], collectedAt: time)
            let result = planner.planSuccessfulRefresh(accountID: id, accountName: "rolling", previousSnapshot: previous,
                newSnapshot: snapshot, settings: settings, ledger: ledger, now: time)
            XCTAssertEqual(result.operations.contains { if case .deliver(let message) = $0 { return message.kind == .quotaAlert }; return false }, shouldAlert)
            XCTAssertFalse(result.operations.contains { operation in
                if case .schedule = operation { return true }
                if case .deliver(let message) = operation { return message.kind == .confirmedReset || message.kind == .expectedReset }
                return false
            })
            ledger = result.ledger
            previous = snapshot
        }
    }

    func testReplenishmentObservationIsStableAcrossRelaunchMissingValuesAndOutOfOrderReplies() throws {
        let id = UUID()
        let settings = AccountReminderSettings(thresholds: [80])
        let planner = NotificationPlanner()
        func snapshot(_ used: Double?, at seconds: Double) -> QuotaSnapshot {
            QuotaSnapshot(accountID: id, windows: [QuotaWindow(id: "rolling", name: "滚动额度", scope: nil,
                usedPercentage: used, remainingCount: nil, totalCount: nil, resetsAt: nil,
                resetSemantics: .continuousReplenishment)], collectedAt: Date(timeIntervalSince1970: seconds))
        }
        let initial = planner.planSuccessfulRefresh(accountID: id, accountName: "rolling", previousSnapshot: nil,
            newSnapshot: snapshot(95, at: 100), settings: settings, ledger: ReminderLedger(), now: Date(timeIntervalSince1970: 100))
        let restored = try JSONDecoder().decode(ReminderLedger.self, from: JSONEncoder().encode(initial.ledger))
        let stale = planner.planSuccessfulRefresh(accountID: id, accountName: "rolling", previousSnapshot: nil,
            newSnapshot: snapshot(20, at: 90), settings: settings, ledger: restored, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(stale.ledger, restored)
        XCTAssertTrue(stale.operations.isEmpty)
        let unknown = planner.planSuccessfulRefresh(accountID: id, accountName: "rolling", previousSnapshot: nil,
            newSnapshot: snapshot(nil, at: 110), settings: settings, ledger: stale.ledger, now: Date(timeIntervalSince1970: 110))
        let above = planner.planSuccessfulRefresh(accountID: id, accountName: "rolling", previousSnapshot: nil,
            newSnapshot: snapshot(85, at: 120), settings: settings, ledger: unknown.ledger, now: Date(timeIntervalSince1970: 120))
        XCTAssertTrue(above.operations.isEmpty)
    }

    func testNonResettingAllowancePurchaseDoesNotNotifyResetAndLegacyDecodeUsesOriginalRules() throws {
        let id = UUID()
        let planner = NotificationPlanner()
        let date = Date(timeIntervalSince1970: 100)
        func snapshot(_ percentage: Double, at date: Date) -> QuotaSnapshot {
            QuotaSnapshot(accountID: id, windows: [QuotaWindow(id: "pack", name: "补充包", scope: nil,
                usedPercentage: percentage, remainingCount: nil, totalCount: nil, resetsAt: nil,
                resetSemantics: .nonResettingAllowance)], collectedAt: date)
        }
        let prior = snapshot(95, at: date)
        XCTAssertEqual(QuotaFormatting.nextEventLabel(prior.windows[0]), "额度类型")
        XCTAssertEqual(QuotaFormatting.nextEventValue(prior.windows[0]), "无周期重置")
        let first = planner.planSuccessfulRefresh(accountID: id, accountName: "pack", previousSnapshot: nil,
            newSnapshot: prior, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: date)
        let second = planner.planSuccessfulRefresh(accountID: id, accountName: "pack", previousSnapshot: prior,
            newSnapshot: snapshot(10, at: date.addingTimeInterval(10)), settings: AccountReminderSettings(),
            ledger: first.ledger, now: date.addingTimeInterval(10))
        XCTAssertTrue(second.operations.isEmpty)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(prior.windows[0])) as? [String: Any])
        object.removeValue(forKey: "resetSemantics")
        object.removeValue(forKey: "nextReplenishmentAt")
        let legacy = try JSONDecoder().decode(QuotaWindow.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.resetSemantics)
        XCTAssertNil(legacy.nextReplenishmentAt)
        let displayed = QuotaWindow(id: "rolling", name: "额度", scope: nil, usedPercentage: 90,
            remainingCount: nil, totalCount: nil, resetsAt: nil,
            resetSemantics: .continuousReplenishment, nextReplenishmentAt: date)
        XCTAssertEqual(QuotaFormatting.nextEventLabel(displayed), "下次补充")
        XCTAssertFalse(displayed.needsUpdate(at: date.addingTimeInterval(10)))
    }
}
