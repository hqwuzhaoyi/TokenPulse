import XCTest

/// Exercises the installed app and SpringBoard. It never substitutes an in-app banner for a system notification.
final class NotificationAcceptance: XCTestCase {
    @MainActor
    func testEnglishSystemDemoNotification() throws {
        try checkSystemDemoNotification(language: "en")
    }

    @MainActor
    func testChineseSystemDemoNotification() throws {
        try checkSystemDemoNotification(language: "zh-Hans")
    }

    @MainActor
    private func checkSystemDemoNotification(language: String) throws {
        continueAfterFailure = false
        let english = language == "en"
        let app = XCUIApplication(bundleIdentifier: "com.tokenpulse.app")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launchArguments = [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", english ? "en_US" : "zh_CN",
            "-demoModeEnabled", "YES",
        ]
        // The system alert follows the Simulator's language, which can differ from the app override.
        let interruption = addUIInterruptionMonitor(withDescription: "Allow TokenPulse notification permission") { alert in
            for label in ["Allow", "允许", "Allow Notifications", "允许通知"] {
                let allow = alert.buttons[label]
                if allow.exists {
                    allow.tap()
                    return true
                }
            }
            return false
        }
        defer { removeUIInterruptionMonitor(interruption) }

        app.launch()
        let settings = app.tabBars.buttons[english ? "Settings" : "设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15), "The installed app must reach its native settings tab")
        settings.tap()
        let send = app.buttons[english ? "Send Demo Notification" : "发送演示通知"].firstMatch
        for _ in 0..<4 {
            if send.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(send.isHittable, "The native demo notification action must be available")
        send.tap()
        // A new interaction lets XCTest's interruption handler approve a first-run permission alert.
        // Tapping the navigation title area has no app action when permission was already granted.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.07)).tap()
        let submitted = english
            ? "The demo notification was submitted. Check Notification Center."
            : "演示通知已提交，可在通知中心查看。"
        let feedback = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", submitted)).firstMatch
        for _ in 0..<3 {
            if feedback.waitForExistence(timeout: 3) { break }
            app.swipeUp()
        }
        capture(application: app, name: "DemoNotificationSubmitted-\(language)")
        XCTAssertTrue(feedback.exists, "Submission must succeed; denied permissions or delivery failures are not a pass")

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(springboard.windows.firstMatch.waitForExistence(timeout: 5))
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.005))
        let lower = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.85))
        top.press(forDuration: 0.1, thenDragTo: lower)

        // These are the actual catalog values used by NotificationRuntime.sendDemoNotification.
        let title = english ? "TokenPulse Demo Reminder" : "TokenPulse 演示提醒"
        let body = english
            ? "This is a sample notification. Adjust quota thresholds and reset reminders in the demo account settings."
            : "这是示例通知。你可以在演示账号设置中调整额度阈值和重置提醒。"
        let visibleTitle = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        if !visibleTitle.waitForExistence(timeout: 3) {
            let group = springboard.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS[c] %@", "NotificationShortLookView", "TokenPulse")).firstMatch
            if group.isHittable {
                let groupFrame = group.frame
                let screenFrame = springboard.frame
                springboard.coordinate(withNormalizedOffset: CGVector(
                    dx: groupFrame.midX / screenFrame.width,
                    dy: groupFrame.midY / screenFrame.height)).tap()
            }
        }
        let foundTitle = visibleTitle.waitForExistence(timeout: 10)
        capture(application: springboard, name: "SystemNotificationCenterCollapsed-\(language)")
        XCTAssertTrue(foundTitle,
                      "The real system notification is not visible. Preserve the screenshot/tree as an honest acceptance gap.")
        let visibleBody = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", body)).firstMatch
        if !visibleBody.exists, visibleTitle.isHittable {
            // Expand the actual notification to reveal its full body without opening the app.
            visibleTitle.press(forDuration: 1.0)
        }
        let foundBody = visibleBody.waitForExistence(timeout: 5)
        capture(application: springboard, name: "SystemNotificationCenterBody-\(language)")
        XCTAssertTrue(foundBody,
                      "The real system notification body must match the selected app language")
    }

    @MainActor
    private func capture(application: XCUIApplication, name: String) {
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = "\(name)-Screenshot"
        screen.lifetime = .keepAlways
        add(screen)
        let tree = XCTAttachment(string: application.debugDescription)
        tree.name = "\(name)-AccessibilityTree"
        tree.lifetime = .keepAlways
        add(tree)
    }
}

extension NotificationAcceptance {
    /// A separate acceptance of real quota output; it does not replace the demo-notification tests.
    @MainActor
    func testEnglishQuotaNotification() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.tokenpulse.app")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-demoModeEnabled", "YES"]
        let interruption = addUIInterruptionMonitor(withDescription: "Allow TokenPulse notification permission") { alert in
            for label in ["Allow", "允许", "Allow Notifications", "允许通知"] {
                let allow = alert.buttons[label]
                if allow.exists {
                    allow.tap()
                    return true
                }
            }
            return false
        }
        defer { removeUIInterruptionMonitor(interruption) }

        app.launch()
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let send = app.buttons["Send Demo Notification"].firstMatch
        for _ in 0..<4 {
            if send.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(send.isHittable)
        send.tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.07)).tap()
        let feedback = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@", "The demo notification was submitted. Check Notification Center.")).firstMatch
        for _ in 0..<3 {
            if feedback.waitForExistence(timeout: 3) { break }
            app.swipeUp()
        }
        capture(application: app, name: "EnglishQuotaNotification-NativeSubmission")
        XCTAssertTrue(feedback.exists, "The native notification action must report actual submission success")

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(springboard.windows.firstMatch.waitForExistence(timeout: 5))
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.005))
        let lower = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.85))
        top.press(forDuration: 0.1, thenDragTo: lower)
        // Read the actual visible system card without tapping or expanding the notification group.
        let card = springboard.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS[c] %@", "NotificationShortLookView", "TokenPulse")).firstMatch
        let foundCard = card.waitForExistence(timeout: 5)
        capture(application: springboard, name: "EnglishQuotaNotification-SystemCenter")
        XCTAssertTrue(foundCard, "A real TokenPulse system notification must be visible")
        let title = card.staticTexts.matching(identifier: "NotificationTitle").firstMatch
        let body = card.staticTexts.matching(identifier: "TextContent.Primary").firstMatch
        XCTAssertTrue(title.exists && body.exists, "The same system card must expose its native title and complete body")
        let actualTitle = title.label
        let actualBody = body.label
        // Both specimens were observed in native notification-center evidence. Match complete pairs:
        // %@额度告警 + %@达到%@; or %@额度已重置 + the actual preserved scope and localized window name.
        let specimens = [
            ("Demo · Codex Plus Quota Alert", "Weekly Quota reached 80%"),
            ("Demo · Aixy Quota Reset Confirmed", "团队 · 共享 Monthly budget"),
        ]
        let payload = XCTAttachment(string: "Title: \(actualTitle)\nBody: \(actualBody)")
        payload.name = "EnglishQuotaNotification-NativePayload"
        payload.lifetime = .keepAlways
        add(payload)
        XCTAssertTrue(specimens.contains { $0.0 == actualTitle && $0.1 == actualBody },
                      "Expected a complete observed English quota-alert or confirmed-reset specimen; arbitrary English is not acceptance")
    }
}
