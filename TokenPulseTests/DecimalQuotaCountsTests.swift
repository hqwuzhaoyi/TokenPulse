import Foundation
import XCTest
@testable import TokenPulse

final class DecimalQuotaCountsTests: XCTestCase {
    private func window(_ counts: DecimalQuotaCounts) -> QuotaWindow {
        QuotaWindow(id: "exact", name: "精确用量", scope: "团队", usedPercentage: nil,
                    remainingCount: nil, totalCount: nil, resetsAt: nil, unit: "Bobcoins", exactCounts: counts)
    }

    func testUsageOnlyExactCountsStayPreciseAcrossSerializationAndWidgetSummary() throws {
        let value = Decimal(string: "12.000000000000000001")!
        let metric = window(DecimalQuotaCounts(used: value))
        let text = "已用 \(QuotaFormatting.count(value)) Bobcoins"
        XCTAssertEqual(QuotaFormatting.exactCountSummary(metric), text)
        XCTAssertEqual(QuotaFormatting.usage(metric), text)
        XCTAssertEqual(WidgetQuotaMetric(id: "exact", title: "用量", window: metric).valueText, text)
        XCTAssertNil(WidgetQuotaMetric(id: "exact", title: "用量", window: metric).ringFraction)
        let restored = try JSONDecoder().decode(QuotaWindow.self, from: JSONEncoder().encode(metric))
        XCTAssertEqual(restored.exactCounts?.used, value)
        XCTAssertNil(restored.exactCounts?.remaining)
        XCTAssertNil(restored.exactCounts?.total)
        XCTAssertNil(restored.usedPercentage)
    }

    func testEachMissingExactQuantityIsDistinctFromReportedZero() {
        XCTAssertNil(QuotaFormatting.exactCountSummary(window(DecimalQuotaCounts())))
        XCTAssertEqual(QuotaFormatting.exactCountSummary(window(DecimalQuotaCounts(used: 0))), "已用 0 Bobcoins")
        XCTAssertEqual(QuotaFormatting.exactCountSummary(window(DecimalQuotaCounts(remaining: 0))), "剩余 0 Bobcoins")
        XCTAssertEqual(QuotaFormatting.exactCountSummary(window(DecimalQuotaCounts(total: 10))), "总量 10 Bobcoins")
        XCTAssertEqual(QuotaFormatting.exactCountSummary(window(DecimalQuotaCounts(used: 4, total: 10))), "已用 4 / 10 Bobcoins")
        XCTAssertEqual(QuotaFormatting.exactCountSummary(window(DecimalQuotaCounts(used: 4, remaining: 6, total: 10))), "6 / 10 Bobcoins")
    }

    func testOldCompleteAndNewPartialCountArchivesDecode() throws {
        let complete = try JSONDecoder().decode(DecimalQuotaCounts.self, from: Data(#"{"used":4,"remaining":6,"total":10}"#.utf8))
        XCTAssertEqual(complete, DecimalQuotaCounts(used: 4, remaining: 6, total: 10))
        let partial = try JSONDecoder().decode(DecimalQuotaCounts.self, from: Data(#"{"used":4}"#.utf8))
        XCTAssertEqual(partial.used, 4)
        XCTAssertNil(partial.remaining)
        XCTAssertNil(partial.total)
        XCTAssertEqual(try JSONDecoder().decode(DecimalQuotaCounts.self, from: Data("{}".utf8)), DecimalQuotaCounts())
    }
}
