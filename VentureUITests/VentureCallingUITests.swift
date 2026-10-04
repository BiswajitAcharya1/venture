import XCTest

final class VentureCallingUITests: XCTestCase {
    private let experimentIDs = ["clinic-receptionist", "nova-dear-care", "rural-health-ai"]

    private func openCare() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-skipOnboarding", "-skipModelWarmup", "-venture.language", "en",
            "-venture.call-tests.url", ""
        ]
        app.launch()
        XCTAssertTrue(app.buttons["tab-3"].waitForExistence(timeout: 20))
        app.buttons["tab-3"].tap()
        reveal(app.buttons["appointment-practice"], in: app)
        app.buttons["appointment-practice"].tap()
        let restore = app.buttons["restore-call-tests"]
        if restore.exists {
            reveal(restore, in: app)
            restore.tap()
            for _ in 0..<5 {
                if app.buttons["test-call-clinic-receptionist"].isHittable { break }
                app.swipeDown()
            }
        }
        reveal(app.buttons["test-call-clinic-receptionist"], in: app)
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    func testThreeButtonsOpenIsolatedUnconfiguredConversations() {
        let app = openCare()
        for id in experimentIDs {
            let button = app.buttons["test-call-\(id)"]
            reveal(button, in: app)
            button.tap()
            XCTAssertTrue(app.staticTexts["call-needs-service"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["try: help me request a routine appointment."].exists)
            XCTAssertFalse(app.staticTexts["call-reply-received"].exists)
            app.buttons["call-personalization"].tap()
            let summary = app.switches["call-share-summary"]
            XCTAssertTrue(summary.exists)
            XCTAssertEqual(summary.value as? String, "0")
            XCTAssertFalse(app.buttons["send-call-test"].isEnabled)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "calling-conversation-\(id)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.buttons["done"].tap()
        }
    }

    func testDisconnectedDraftCannotBeSentAndResetClearsIt() {
        let app = openCare()
        app.buttons["test-call-clinic-receptionist"].tap()
        XCTAssertTrue(app.staticTexts["call-needs-service"].waitForExistence(timeout: 5))
        let field = app.textFields["call-test-message"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("please help me ask for a routine appointment")
        XCTAssertFalse(app.buttons["send-call-test"].isEnabled)
        XCTAssertFalse(app.staticTexts["call-reply-received"].exists)
        app.buttons["reset-call-test"].tap()
        XCTAssertTrue(app.staticTexts["try: help me request a routine appointment."].exists)
        XCTAssertEqual(field.value as? String, "type or dictate")
    }

    func testRemovingOneExperimentPreservesOtherButtonsAndCanRestore() {
        let app = openCare()
        app.buttons["call-test-options-clinic-receptionist"].tap()
        app.buttons["remove test"].tap()
        XCTAssertFalse(app.buttons["test-call-clinic-receptionist"].exists)
        XCTAssertTrue(app.buttons["test-call-nova-dear-care"].exists)
        reveal(app.buttons["test-call-rural-health-ai"], in: app)
        XCTAssertTrue(app.buttons["test-call-rural-health-ai"].exists)
        let restore = app.buttons["restore-call-tests"]
        reveal(restore, in: app)
        restore.tap()
        for _ in 0..<5 {
            if app.buttons["test-call-clinic-receptionist"].isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(app.buttons["test-call-clinic-receptionist"].exists)
    }
}
