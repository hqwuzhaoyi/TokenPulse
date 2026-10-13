import XCTest

final class CodexAcceptance: XCTestCase {
    @MainActor func testEnglishScheduled() throws { try check(language: "en", scenario: "scheduled") }
    @MainActor func testChineseScheduled() throws { try check(language: "zh-Hans", scenario: "scheduled") }
    @MainActor func testEnglishForecast() throws { try check(language: "en", scenario: "forecast") }
    @MainActor func testChineseForecast() throws { try check(language: "zh-Hans", scenario: "forecast") }
    @MainActor func testEnglishEmpty() throws { try check(language: "en", scenario: "empty") }
    @MainActor func testChineseEmpty() throws { try check(language: "zh-Hans", scenario: "empty") }
    @MainActor func testEnglishHistoryOnly() throws { try check(language: "en", scenario: "historyOnly") }
    @MainActor func testChineseHistoryOnly() throws { try check(language: "zh-Hans", scenario: "historyOnly") }
    @MainActor func testEnglishExpired() throws { try check(language: "en", scenario: "expired") }
    @MainActor func testChineseExpired() throws { try check(language: "zh-Hans", scenario: "expired") }
    @MainActor func testEnglishCanceled() throws { try check(language: "en", scenario: "canceled") }
    @MainActor func testChineseCanceled() throws { try check(language: "zh-Hans", scenario: "canceled") }
    @MainActor func testEnglishRetainedFailure() throws { try check(language: "en", scenario: "retainedFailure") }
    @MainActor func testChineseRetainedFailure() throws { try check(language: "zh-Hans", scenario: "retainedFailure") }

    @MainActor private func check(language: String, scenario: String) throws {
        continueAfterFailure = false
        let english = language == "en"
        let app = XCUIApplication(bundleIdentifier: "com.tokenpulse.app")
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", english ? "en_US" : "zh_CN",
                               "-demoModeEnabled", "NO", "-cloudSyncEnabled", "NO", "-TokenPulseCodexFixture", scenario]
        app.launch()
        let accountName = english ? "Demo · Codex Pro" : "演示 · Codex Pro"
        let heading = app.staticTexts[english ? "Codex Reset Preview" : "Codex 重置预告"].firstMatch
        let source = app.buttons[english ? "Data source: Codex Resets" : "数据来源：Codex Resets"].firstMatch
        let hidden = ["empty", "historyOnly", "expired"].contains(scenario)
        if hidden {
            XCTAssertTrue(app.staticTexts[accountName].firstMatch.waitForExistence(timeout: 20))
            XCTAssertFalse(heading.exists)
            XCTAssertFalse(source.exists)
        } else {
            XCTAssertTrue(heading.waitForExistence(timeout: 20))
            if scenario == "scheduled" {
                XCTAssertTrue(app.staticTexts["Original announcement 原文"].exists)
                XCTAssertTrue(app.staticTexts[english ? "The scheduled time has passed; execution is still unconfirmed." : "预定时间已过，尚未确认执行。"].exists)
            } else {
                XCTAssertTrue(app.staticTexts["Original prediction 原文"].exists)
                XCTAssertTrue(app.staticTexts[english ? "Forecast window: Original window 原文" : "预测时段：Original window 原文"].exists)
            }
            if scenario == "canceled" || scenario == "retainedFailure" {
                app.staticTexts[accountName].firstMatch.tap()
                let refresh = app.buttons[english ? "Refresh " + accountName : "刷新 " + accountName].firstMatch
                for _ in 0..<8 {
                    if refresh.isHittable { break }
                    app.swipeUp()
                }
                XCTAssertTrue(refresh.isHittable)
                refresh.tap()
                for _ in 0..<4 { app.swipeDown() }
                XCTAssertTrue(app.staticTexts[accountName].firstMatch.exists)
                if scenario == "canceled" {
                    let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: heading)
                    XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
                    XCTAssertFalse(source.exists)
                } else {
                    XCTAssertTrue(app.staticTexts[english ? "Reset previews cannot be updated right now; previous data is shown" : "重置预告暂时无法更新，当前显示上次数据"].waitForExistence(timeout: 10))
                    XCTAssertTrue(heading.exists)
                }
            }
        }
        capture(app, name: "Codex-\(scenario)-\(language)")
        if !hidden && scenario != "canceled" {
            for _ in 0..<10 {
                if source.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(source.isHittable)
            capture(app, name: "CodexSource-\(scenario)-\(language)")
            source.tap() // Debug-only OpenURL handler preserves the real Link action without launching a website.
        }
    }

    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = name
        screen.lifetime = .keepAlways
        add(screen)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-Accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
