import XCTest

final class QuotaSupplementAcceptance: XCTestCase {
    @MainActor func testEnglishCharacters() throws { try check("en", "characters") }
    @MainActor func testChineseCharacters() throws { try check("zh-Hans", "characters") }
    @MainActor func testEnglishHours() throws { try check("en", "hours") }
    @MainActor func testChineseHours() throws { try check("zh-Hans", "hours") }
    @MainActor func testEnglishUnknownUnits() throws { try check("en", "unknownUnits") }
    @MainActor func testChineseUnknownUnits() throws { try check("zh-Hans", "unknownUnits") }
    @MainActor func testEnglishModelNames() throws { try check("en", "modelNames") }
    @MainActor func testChineseModelNames() throws { try check("zh-Hans", "modelNames") }
    @MainActor func testEnglishManusRefill() throws { try check("en", "manusRefill") }
    @MainActor func testChineseManusRefill() throws { try check("zh-Hans", "manusRefill") }
    @MainActor func testEnglishOwnedScope() throws { try check("en", "ownedScope") }
    @MainActor func testChineseOwnedScope() throws { try check("zh-Hans", "ownedScope") }
    @MainActor func testEnglishPayAsYouGo() throws { try check("en", "payAsYouGo") }
    @MainActor func testChinesePayAsYouGo() throws { try check("zh-Hans", "payAsYouGo") }
    @MainActor func testEnglishTeamPlan() throws { try check("en", "teamPlan") }
    @MainActor func testChineseTeamPlan() throws { try check("zh-Hans", "teamPlan") }

    @MainActor private func check(_ language: String, _ fixture: String) throws {
        continueAfterFailure = false
        let english = language == "en"
        let app = XCUIApplication(bundleIdentifier: "com.tokenpulse.app")
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", english ? "en_US" : "zh_CN",
                               "-demoModeEnabled", "NO", "-cloudSyncEnabled", "NO", "-TokenPulseQuotaFixture", fixture]
        app.launch()
        let cancel = app.buttons[english ? "Cancel" : "取消"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 15))
        let expected: String
        switch fixture {
        case "characters": expected = english ? "2 / 3 characters" : "2 / 3 字符"
        case "hours": expected = english ? "1 hour" : "1 小时"
        case "unknownUnits": expected = english ? "1 unit (type not provided)" : "1 单位（类型未提供）"
        case "modelNames": expected = english ? "原始模型（未启用） (disabled)" : "原始模型（未启用）（未启用）"
        case "manusRefill": expected = english ? "Replenishing allowance" : "恢复额度"
        case "ownedScope": expected = english ? "Team · Original target 原文 · Shared" : "团队 · Original target 原文 · 共享"
        case "payAsYouGo": expected = english ? "Pay-as-you-go" : "按量计费"
        default: expected = english ? "Team original-team-原文" : "团队 original-team-原文"
        }
        let value = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", expected)).firstMatch
        let matched = value.waitForExistence(timeout: 5)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "QuotaSupplement-\(fixture)-\(language)"
        screen.lifetime = .keepAlways
        add(screen)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "QuotaSupplementAccessibility-\(fixture)-\(language)"
        tree.lifetime = .keepAlways
        add(tree)
        XCTAssertTrue(matched, "The native producer-backed view must show its localized unit/scope/plan while preserving raw names")
        if fixture == "modelNames" {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "原始模型（未启用）")).firstMatch.exists)
        }
        cancel.tap()
    }
}
