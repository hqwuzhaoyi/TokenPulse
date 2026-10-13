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
        let text = L10n.format("已用 %@", "\(QuotaFormatting.count(value)) Bobcoins")
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
        XCTAssertEqual(QuotaFormatting.exactCountSummary(window(DecimalQuotaCounts(used: 0))), L10n.format("已用 %@", "0 Bobcoins"))
        XCTAssertEqual(QuotaFormatting.exactCountSummary(window(DecimalQuotaCounts(remaining: 0))), L10n.format("剩余 %@", "0 Bobcoins"))
        XCTAssertEqual(QuotaFormatting.exactCountSummary(window(DecimalQuotaCounts(total: 10))), L10n.format("总量 %@", "10 Bobcoins"))
        XCTAssertEqual(QuotaFormatting.exactCountSummary(window(DecimalQuotaCounts(used: 4, total: 10))), L10n.format("已用 %@ / %@", "4", "10") + " Bobcoins")
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

import Testing

struct DecimalLocalizationTests {
    @Test func decimalPrecisionSurvivesRegionalFormattingAndLanguageChanges() throws {
        let exact = Decimal(string: "12.000000000000000001")!
        let source = QuotaWindow(id: "ibmBob.team.fixture", name: "Bobcoins", scope: "原始团队",
            usedPercentage: nil, remainingCount: nil, totalCount: nil, resetsAt: nil, unit: "Bobcoins",
            exactCounts: .init(used: exact))
        let data = try JSONEncoder().encode(source)
        let restored = try JSONDecoder().decode(QuotaWindow.self, from: data)
        #expect(QuotaFormatting.count(exact, locale: Locale(identifier: "en_US")) == "12.000000000000000001")
        #expect(QuotaFormatting.count(exact, locale: Locale(identifier: "de_DE")) == "12,000000000000000001")
        L10n.withLanguage("en") { #expect(QuotaFormatting.exactCountSummary(restored)?.hasPrefix("Used ") == true) }
        L10n.withLanguage("zh-Hans") { #expect(QuotaFormatting.exactCountSummary(restored)?.hasPrefix("已用 ") == true) }
        #expect(restored.exactCounts?.used == exact)
        #expect(restored.id == source.id)
        #expect(restored.scope == "原始团队")
        #expect(restored.unit == "Bobcoins")
        #expect(restored.exactCounts?.remaining == nil)
        #expect(restored.wallet == nil)
    }
}
