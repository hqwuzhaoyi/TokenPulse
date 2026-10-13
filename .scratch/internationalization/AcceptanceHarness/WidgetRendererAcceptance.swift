import XCTest
import Vision
import UIKit

/// Real shared renderer in native views; this is not an extension runtime or a system WidgetKit host.
final class WidgetRendererAcceptance: XCTestCase {
    @MainActor func testEnglishLargeQuota() throws { try check("en", "quota", "large") }
    @MainActor func testChineseLargeQuota() throws { try check("zh-Hans", "quota", "large") }
    @MainActor func testEnglishSmallWallet() throws { try check("en", "wallet", "small") }
    @MainActor func testChineseSmallWallet() throws { try check("zh-Hans", "wallet", "small") }
    @MainActor func testEnglishSmallEmpty() throws { try check("en", "empty", "small") }
    @MainActor func testChineseSmallEmpty() throws { try check("zh-Hans", "empty", "small") }
    @MainActor func testEnglishMediumUnselected() throws { try check("en", "unselected", "medium") }
    @MainActor func testChineseMediumUnselected() throws { try check("zh-Hans", "unselected", "medium") }
    @MainActor func testEnglishSmallMissing() throws { try check("en", "missing", "small") }
    @MainActor func testChineseSmallMissing() throws { try check("zh-Hans", "missing", "small") }
    @MainActor func testEnglishSmallStale() throws { try check("en", "stale", "small") }
    @MainActor func testChineseSmallStale() throws { try check("zh-Hans", "stale", "small") }
    @MainActor func testEnglishSmallReplenishment() throws { try check("en", "replenishment", "small") }
    @MainActor func testChineseSmallReplenishment() throws { try check("zh-Hans", "replenishment", "small") }
    @MainActor func testEnglishSmallDateOnly() throws { try check("en", "dateOnly", "small") }
    @MainActor func testChineseSmallDateOnly() throws { try check("zh-Hans", "dateOnly", "small") }
    @MainActor func testEnglishLargeLongName() throws { try check("en", "longName", "large") }
    @MainActor func testChineseLargeLongName() throws { try check("zh-Hans", "longName", "large") }
    @MainActor func testEnglishSmallExhausted() throws { try check("en", "exhausted", "small") }
    @MainActor func testChineseSmallExhausted() throws { try check("zh-Hans", "exhausted", "small") }
    @MainActor func testEnglishCircularQuota() throws { try check("en", "quota", "circular") }
    @MainActor func testChineseCircularQuota() throws { try check("zh-Hans", "quota", "circular") }
    @MainActor func testEnglishRectangularDateOnly() throws { try check("en", "dateOnly", "rectangular") }
    @MainActor func testChineseRectangularDateOnly() throws { try check("zh-Hans", "dateOnly", "rectangular") }
    @MainActor func testEnglishRectangularWalletShowsAmountAndCurrency() throws {
        try check("en", "wallet", "rectangular", visibleWalletAmount: "1,234.56789012 USD")
    }
    @MainActor func testChineseRectangularWalletShowsAmountAndCurrency() throws {
        try check("zh-Hans", "wallet", "rectangular", visibleWalletAmount: "1,234.56789012 USD")
    }
    @MainActor func testEnglishInlineQuota() throws { try check("en", "quota", "inline") }
    @MainActor func testChineseInlineQuota() throws { try check("zh-Hans", "quota", "inline") }

    @MainActor private func check(_ language: String, _ scenario: String, _ family: String,
                                 visibleWalletAmount: String? = nil) throws {
        continueAfterFailure = false
        let english = language == "en"
        let app = XCUIApplication(bundleIdentifier: "com.tokenpulse.app")
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", english ? "en_US" : "zh_CN",
                               "-demoModeEnabled", "NO", "-cloudSyncEnabled", "NO", "-TokenPulseWidgetFixture", scenario,
                               "-TokenPulseWidgetFamily", family]
        app.launch()
        let cancel = app.buttons[english ? "Cancel" : "取消"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 15))
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "WidgetRenderer-\(scenario)-\(family)-\(language)"
        screen.lifetime = .keepAlways
        add(screen)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "WidgetRendererAccessibility-\(scenario)-\(family)-\(language)"
        tree.lifetime = .keepAlways
        add(tree)
        XCTAssertTrue(app.staticTexts["TokenPulse"].exists)
        if let visibleWalletAmount {
            // The old rectangular view exposed the amount in AX while omitting it on screen.
            // Recognize rendered pixels so an accessible-but-invisible balance cannot pass.
            let pixels = try XCTUnwrap(app.screenshot().image.cgImage)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: pixels).perform([request])
            let recognized = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let normalized = recognized.joined().filter { !$0.isWhitespace && $0 != "," }
            let expected = visibleWalletAmount.filter { !$0.isWhitespace && $0 != "," }
            let ocr = XCTAttachment(string: recognized.joined(separator: "\n"))
            ocr.name = "VisibleWalletPixels-\(family)-\(language)"
            ocr.lifetime = .keepAlways
            add(ocr)
            XCTAssertTrue(normalized.contains(expected), "Visible pixels must retain the complete balance and currency: \(recognized)")
        }
        cancel.tap()
    }
}
