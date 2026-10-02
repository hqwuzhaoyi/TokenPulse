import Foundation
import XCTest
@testable import TokenPulse

final class QuotaDatePrecisionTests: XCTestCase {
    private let end = Date(timeIntervalSince1970: 1791849600) // 2026-10-13 UTC

    func testDateOnlyFormattingPreservesProviderCalendarDateInEveryTimeZone() throws {
        let window = makeWindow()
        for offset in [-12, -8, 0, 8, 14] {
            XCTAssertEqual(QuotaFormatting.resetDate(end, timeZone: TimeZone(secondsFromGMT: offset * 3600)!, precision: .day), "2026-10-13")
        }
        XCTAssertEqual(QuotaFormatting.nextEventValue(window), "2026-10-13")
        XCTAssertFalse(window.needsUpdate(at: end))
        XCTAssertFalse(window.needsUpdate(at: end.addingTimeInterval(86_400)))
        XCTAssertEqual(try JSONDecoder().decode(QuotaWindow.self, from: JSONEncoder().encode(window)), window)
    }

    func testDateOnlyNeverSchedulesExactResetOrConfirmsItByTimePassing() {
        let id = UUID()
        let window = makeWindow()
        let before = end.addingTimeInterval(-3600)
        let snapshot = QuotaSnapshot(accountID: id, windows: [window], collectedAt: before)
        let planner = NotificationPlanner()
        let first = planner.planSuccessfulRefresh(accountID: id, accountName: "Fixture", previousSnapshot: nil,
            newSnapshot: snapshot, settings: AccountReminderSettings(), ledger: ReminderLedger(), now: before)
        XCTAssertFalse(first.operations.contains { if case .schedule = $0 { return true }; return false })
        let after = planner.planSuccessfulRefresh(accountID: id, accountName: "Fixture", previousSnapshot: snapshot,
            newSnapshot: QuotaSnapshot(accountID: id, windows: [window], collectedAt: end.addingTimeInterval(1)),
            settings: AccountReminderSettings(), ledger: first.ledger, now: end.addingTimeInterval(1))
        XCTAssertFalse(after.operations.contains { operation in
            if case .deliver(let notification) = operation { return notification.kind == .confirmedReset || notification.kind == .expectedReset }
            return false
        })
    }

    func testOldArchivesDefaultToExactAndStillScheduleReportedResetTimestamp() throws {
        let data = Data(#"{"id":"old","name":"Old","isUnlimited":false,"usedPercentage":50,"resetsAt":1791849600000}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let old = try decoder.decode(QuotaWindow.self, from: data)
        XCTAssertNil(old.resetDatePrecision)
        XCTAssertTrue(old.needsUpdate(at: end))
        let id = UUID(), before = end.addingTimeInterval(-3600)
        let result = NotificationPlanner().planSuccessfulRefresh(accountID: id, accountName: "Old", previousSnapshot: nil,
            newSnapshot: QuotaSnapshot(accountID: id, windows: [old], collectedAt: before), settings: AccountReminderSettings(),
            ledger: ReminderLedger(), now: before)
        XCTAssertTrue(result.operations.contains { if case .schedule = $0 { return true }; return false })
    }

    private func makeWindow() -> QuotaWindow {
        QuotaWindow(id: "fixture.day", name: "Billing period", scope: nil, usedPercentage: 50,
                    remainingCount: nil, totalCount: nil, resetsAt: end, resetDatePrecision: .day)
    }
}
