import XCTest

final class HomeAcceptance: XCTestCase {
    @MainActor func testEnglishHome() throws { try checkHome(language: "en") }
    @MainActor func testChineseHome() throws { try checkHome(language: "zh-Hans") }
    @MainActor func testEnglishProviderSelection() throws { try checkProviderSelection(language: "en") }
    @MainActor func testChineseProviderSelection() throws { try checkProviderSelection(language: "zh-Hans") }

    @MainActor
    private func checkProviderSelection(language: String) throws {
        let english = language == "en"
        let app = XCUIApplication(bundleIdentifier: "com.tokenpulse.app")
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", english ? "en_US" : "zh_CN", "-demoModeEnabled", "NO"]
        app.launch()
        let addLabel = english ? "Add Account" : "添加账号"
        XCTAssertTrue(app.buttons[addLabel].firstMatch.waitForExistence(timeout: 15))
        app.buttons[addLabel].firstMatch.tap()
        app.buttons.containing(.staticText, identifier: english ? "Change" : "更换").firstMatch.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let index = XCTAttachment(string: app.debugDescription)
        index.name = "ProviderIndex-\(language)"
        index.lifetime = .keepAlways
        add(index)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Providers-\(language)"
        screen.lifetime = .keepAlways
        add(screen)
        let sectionIndex = app.otherElements[english ? "Section index" : "节索引"]
        XCTAssertTrue(sectionIndex.exists)
        do {
            let c = sectionIndex.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
            c.tap()
            XCTAssertTrue(app.buttons["Claude"].isHittable)
            let z = sectionIndex.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: english ? 0.72 : 0.71))
            c.press(forDuration: 0.1, thenDragTo: z)
            XCTAssertTrue(app.buttons["Z.ai"].isHittable)
        }
        search.tap()
        search.typeText("深度求索")
        XCTAssertTrue(app.buttons["DeepSeek"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["DeepSeek"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["DeepSeek"].exists)
        let label = english ? "For example: Work account" : "例如：工作账号"
        let name = app.textFields[label]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("原文 Keep My Name")
        XCTAssertEqual(name.value as? String, "原文 Keep My Name")
        let form = XCTAttachment(screenshot: app.screenshot())
        form.name = "APIKey-\(language)"
        form.lifetime = .keepAlways
        add(form)
    }


    @MainActor
    private func checkHome(language: String) throws {
        let english = language == "en"
        let home = english ? "Home" : "主屏幕"
        let settings = english ? "Settings" : "设置"
        let addLabel = english ? "Add Account" : "添加账号"
        let quota = english ? "5-Hour Quota" : "5 小时额度"
        let app = XCUIApplication(bundleIdentifier: "com.tokenpulse.app")
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", english ? "en_US" : "zh_CN", "-demoModeEnabled", "YES"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons[home].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts[quota].firstMatch.exists)
        XCTAssertTrue(app.buttons[addLabel].firstMatch.isHittable)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Home-\(language)"
        image.lifetime = .keepAlways
        add(image)
        app.tabBars.buttons[settings].tap()
        XCTAssertTrue(app.tabBars.buttons[settings].isSelected)
        app.tabBars.buttons[home].tap()
        XCTAssertTrue(app.tabBars.buttons[home].isSelected)
        let sample = english ? "Demo · MiniMax China" : "演示 · MiniMax 国内版"
        app.staticTexts[sample].firstMatch.tap()
        XCTAssertTrue(app.staticTexts[english ? "5-Hour Quota Details" : "5 小时额度详情"].firstMatch.waitForExistence(timeout: 5))
        let quotaAccessibility = english ? "5-Hour Quota Used" : "5 小时额度已用额度"
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: quotaAccessibility).firstMatch.exists)
        let spoken = XCTAttachment(string: app.debugDescription)
        spoken.name = "Accessibility-\(language)"
        spoken.lifetime = .keepAlways
        add(spoken)
        let detail = XCTAttachment(screenshot: app.screenshot())
        detail.name = "Details-\(language)"
        detail.lifetime = .keepAlways
        add(detail)
        app.buttons[addLabel].firstMatch.tap()
        XCTAssertTrue(app.navigationBars.count > 0)
        app.buttons[english ? "Cancel" : "取消"].firstMatch.tap()
        app.buttons[english ? "Exit Demo" : "退出演示"].tap()
        XCTAssertTrue(app.staticTexts[english ? "Add a Service Account" : "添加服务账号"].waitForExistence(timeout: 15))
        let empty = XCTAttachment(screenshot: app.screenshot())
        empty.name = "Empty-\(language)"
        empty.lifetime = .keepAlways
        add(empty)
        app.buttons[english ? "Try Demo" : "体验演示"].tap()
        XCTAssertTrue(app.staticTexts[quota].firstMatch.waitForExistence(timeout: 15))
    }
}

final class AuthorizationAcceptance: XCTestCase {
    @MainActor func testEnglishGoogle() throws { try checkAuthorization(language: "en", fixture: "google") }
    @MainActor func testChineseGoogle() throws { try checkAuthorization(language: "zh-Hans", fixture: "google") }
    @MainActor func testEnglishJetBrains() throws { try checkAuthorization(language: "en", fixture: "jetbrains") }
    @MainActor func testChineseJetBrains() throws { try checkAuthorization(language: "zh-Hans", fixture: "jetbrains") }
    @MainActor func testEnglishDeviceCode() throws { try checkAuthorization(language: "en", fixture: "deviceRecovery") }
    @MainActor func testChineseDeviceCode() throws { try checkAuthorization(language: "zh-Hans", fixture: "deviceRecovery") }

    @MainActor
    private func checkAuthorization(language: String, fixture: String) throws {
        let english = language == "en"
        let app = XCUIApplication(bundleIdentifier: "com.tokenpulse.app")
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", english ? "en_US" : "zh_CN", "-demoModeEnabled", "YES", "-TokenPulseAuthorizationFixture", fixture]
        app.launch()
        let cancel = app.buttons[english ? "Cancel" : "取消"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 15))
        if fixture == "google" {
            XCTAssertTrue(app.textFields.firstMatch.exists)
            XCTAssertTrue(app.buttons[english ? "Authorize with a Google account" : "使用 Google 账户授权"].exists)
        } else if fixture == "jetbrains" {
            XCTAssertTrue(app.secureTextFields["central-…"].exists)
            XCTAssertTrue(app.buttons[english ? "Import and read usage" : "导入并读取额度"].exists)
        } else {
            let code = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "TEST-CODE")).firstMatch
            XCTAssertTrue(code.waitForExistence(timeout: 15))
            let resume = app.buttons[english ? "Keep waiting" : "继续等待"].firstMatch
            XCTAssertTrue(resume.waitForExistence(timeout: 15))
            resume.tap()
            XCTAssertTrue(code.exists)
            let authorize = app.buttons[english ? "Authorize with GitHub Copilot" : "前往 GitHub Copilot 授权"]
            XCTAssertTrue(authorize.exists)
            authorize.tap()
            XCTAssertTrue(code.exists)
            code.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).press(forDuration: 1)
            let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Copy", "拷贝"])).firstMatch
            XCTAssertTrue(copy.waitForExistence(timeout: 5))
            copy.tap()
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Authorization-\(fixture)-\(language)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let spoken = XCTAttachment(string: app.debugDescription)
        spoken.name = "AuthorizationAccessibility-\(fixture)-\(language)"
        spoken.lifetime = .keepAlways
        add(spoken)
        cancel.tap()
    }
}

final class QuotaAcceptance: XCTestCase {
    @MainActor func testEnglishWallet() throws { try checkQuota(language: "en", fixture: "wallet") }
    @MainActor func testEnglishBudget() throws { try checkQuota(language: "en", fixture: "budget") }
    @MainActor func testEnglishCredits() throws { try checkQuota(language: "en", fixture: "credits") }
    @MainActor func testEnglishGpu() throws { try checkQuota(language: "en", fixture: "gpu") }
    @MainActor func testEnglishHybrid() throws { try checkQuota(language: "en", fixture: "hybrid") }
    @MainActor func testEnglishDateOnly() throws { try checkQuota(language: "en", fixture: "dateOnly") }
    @MainActor func testEnglishLegacy() throws { try checkQuota(language: "en", fixture: "legacy") }
    @MainActor func testChineseWallet() throws { try checkQuota(language: "zh-Hans", fixture: "wallet") }
    @MainActor func testChineseBudget() throws { try checkQuota(language: "zh-Hans", fixture: "budget") }
    @MainActor func testChineseCredits() throws { try checkQuota(language: "zh-Hans", fixture: "credits") }
    @MainActor func testChineseGpu() throws { try checkQuota(language: "zh-Hans", fixture: "gpu") }
    @MainActor func testChineseHybrid() throws { try checkQuota(language: "zh-Hans", fixture: "hybrid") }
    @MainActor func testChineseDateOnly() throws { try checkQuota(language: "zh-Hans", fixture: "dateOnly") }
    @MainActor func testChineseLegacy() throws { try checkQuota(language: "zh-Hans", fixture: "legacy") }

    @MainActor
    private func checkQuota(language: String, fixture: String) throws {
        let english = language == "en"
        let app = XCUIApplication(bundleIdentifier: "com.tokenpulse.app")
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", english ? "en_US" : "zh_CN", "-demoModeEnabled", "YES", "-TokenPulseQuotaFixture", fixture]
        app.launch()
        let cancel = app.buttons[english ? "Cancel" : "取消"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 15))
        let term: String
        switch fixture {
        case "wallet", "hybrid": term = "CNY"
        case "budget": term = english ? "budget" : "预算"
        case "credits": term = "points"
        case "gpu": term = "GPU"
        case "dateOnly": term = "2026-10"
        default: term = "MiniMax-M2.5"
        }
        let output = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", term)).firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        if fixture == "hybrid", english {
            XCTAssertTrue(app.staticTexts["Monthly Token allowance Details"].exists)
        }
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Quota-\(fixture)-\(language)"
        image.lifetime = .keepAlways
        add(image)
        let spoken = XCTAttachment(string: app.debugDescription)
        spoken.name = "QuotaAccessibility-\(fixture)-\(language)"
        spoken.lifetime = .keepAlways
        add(spoken)
        cancel.tap()
    }
}

final class AccountSaveAcceptance: XCTestCase {
    @MainActor func testEnglishDirect() throws { try saveAccount(language: "en", gateway: false) }
    @MainActor func testChineseDirect() throws { try saveAccount(language: "zh-Hans", gateway: false) }
    @MainActor func testEnglishGateway() throws { try saveAccount(language: "en", gateway: true) }
    @MainActor func testChineseGateway() throws { try saveAccount(language: "zh-Hans", gateway: true) }

    @MainActor
    private func saveAccount(language: String, gateway: Bool) throws {
        let english = language == "en"
        let app = XCUIApplication(bundleIdentifier: "com.tokenpulse.app")
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", english ? "en_US" : "zh_CN", "-demoModeEnabled", "YES", "-TokenPulseAccountFixture"]
        app.launch()
        let save = app.buttons[english ? "Save" : "保存"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        XCTAssertFalse(save.isEnabled)
        app.buttons.containing(.staticText, identifier: english ? "Change" : "更换").firstMatch.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(gateway ? "New API" : "DeepSeek")
        app.buttons[gateway ? "New API" : "DeepSeek"].firstMatch.tap()
        let name = app.textFields[english ? "For example: Work account" : "例如：工作账号"]
        name.tap()
        name.typeText("原文 Fixture Account")
        if gateway {
            let server = app.textFields["https://gateway.example.com/v1"]
            XCTAssertTrue(server.exists)
            server.tap()
            server.typeText("https://fixture.example/v1")
        }
        let key = app.secureTextFields.firstMatch
        key.tap()
        key.typeText("fixture-only-key")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["原文 Fixture Account"].waitForExistence(timeout: 15))
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Saved-\(gateway ? "gateway" : "direct")-\(language)"
        image.lifetime = .keepAlways
        add(image)
    }
}

final class SettingsAcceptance: XCTestCase {
    @MainActor func testEnglishSettings() throws { try checkSettings(language: "en") }
    @MainActor func testChineseSettings() throws { try checkSettings(language: "zh-Hans") }

    @MainActor
    private func checkSettings(language: String) throws {
        let english = language == "en"
        let app = XCUIApplication(bundleIdentifier: "com.tokenpulse.app")
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", english ? "en_US" : "zh_CN", "-demoModeEnabled", "YES"]
        app.launch()
        app.tabBars.buttons[english ? "Settings" : "设置"].tap()
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Settings-\(language)"
        image.lifetime = .keepAlways
        add(image)
        let account = app.staticTexts[english ? "Demo · MiniMax China" : "演示 · MiniMax 国内版"].firstMatch
        for _ in 0..<4 {
            if account.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(account.isHittable)
        account.tap()
        let alert = app.switches[english ? "Quota Alerts" : "额度告警"]
        for _ in 0..<5 {
            if alert.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(alert.isHittable)
        let before = alert.value as? String
        alert.switches.firstMatch.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before ?? "1"), object: alert)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        alert.switches.firstMatch.tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", before ?? "1"), object: alert)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
        let thresholds = app.textFields[english ? "Thresholds, e.g. 80,95,100" : "阈值，例如 80,95,100"]
        XCTAssertTrue(thresholds.exists)
        let detail = XCTAttachment(screenshot: app.screenshot())
        detail.name = "AccountPreferences-\(language)"
        detail.lifetime = .keepAlways
        add(detail)
        let delete = app.buttons[english ? "Delete Account" : "删除账号"].firstMatch
        for _ in 0..<8 {
            if delete.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(delete.isHittable)
        delete.tap()
        let sheet = app.sheets[english ? "Delete Account?" : "删除账号？"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let dialog = XCTAttachment(screenshot: app.screenshot())
        dialog.name = "DeleteConfirmation-\(language)"
        dialog.lifetime = .keepAlways
        add(dialog)
        if sheet.frame.height > 600 {
            sheet.swipeUp()
            XCTAssertTrue(sheet.exists)
            let scrolled = XCTAttachment(screenshot: app.screenshot())
            scrolled.name = "DeleteConfirmationScrolled-\(language)"
            scrolled.lifetime = .keepAlways
            add(scrolled)
        }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "SettingsAccessibility-\(language)"
        tree.lifetime = .keepAlways
        add(tree)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.6)).tap()
        XCTAssertFalse(sheet.exists)
    }
}

final class SetupLargeTextAcceptance: XCTestCase {
    @MainActor func testEnglishLargeSetup() throws { try inspect(language: "en") }
    @MainActor func testChineseLargeSetup() throws { try inspect(language: "zh-Hans") }

    @MainActor private func inspect(language: String) throws {
        let english = language == "en"
        let app = XCUIApplication(bundleIdentifier: "com.tokenpulse.app")
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-demoModeEnabled", "NO"]
        app.launch()
        let addButton = app.buttons[english ? "Add Account" : "添加账号"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 15))
        addButton.tap()
        let change = app.buttons.containing(.staticText, identifier: english ? "Change" : "更换").firstMatch
        XCTAssertTrue(change.waitForExistence(timeout: 5))
        change.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "LargeProviderDirectory-\(language)"
        screen.lifetime = .keepAlways
        self.add(screen)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "LargeProviderAccessibility-\(language)"
        tree.lifetime = .keepAlways
        self.add(tree)
        search.tap()
        search.typeText("Alibaba")
        let provider = app.buttons[english ? "Alibaba Bailian Token Plan" : "阿里百炼 Token Plan"].firstMatch
        XCTAssertTrue(provider.waitForExistence(timeout: 5))
        provider.tap()
        XCTAssertTrue(app.buttons[english ? "Save" : "保存"].firstMatch.waitForExistence(timeout: 5))
        let form = XCTAttachment(screenshot: app.screenshot())
        form.name = "LargeProviderForm-\(language)"
        form.lifetime = .keepAlways
        self.add(form)
        let labels = XCTAttachment(string: app.debugDescription)
        labels.name = "LargeFormAccessibility-\(language)"
        labels.lifetime = .keepAlways
        self.add(labels)
    }
}
