import XCTest

final class VentureExperienceUITests: XCTestCase {
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    func testHindiGuestVoiceOnlyFlowAndHelp() {
        let app = XCUIApplication()
        app.launchArguments = ["-authPreview", "-skipModelWarmup", "-venture.language", "en"]
        app.launch()
        XCTAssertTrue(app.buttons["account-language-button"].waitForExistence(timeout: 15))
        app.buttons["account-language-button"].tap()
        XCTAssertTrue(app.buttons["language-hi"].waitForExistence(timeout: 5))
        app.buttons["language-hi"].tap()
        app.buttons["आगे बढ़ें"].tap()
        reveal(app.buttons["continue-guest"], in: app)
        app.buttons["continue-guest"].tap()
        XCTAssertTrue(app.buttons["आगे बढ़ें"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["कैमरा"].exists)
        app.buttons["आगे बढ़ें"].tap()
        XCTAssertTrue(app.staticTexts["5 सेकंड आह कहें"].waitForExistence(timeout: 5))
        app.buttons["skip-test"].tap()
        XCTAssertTrue(app.staticTexts["अपने दिन के बारे में बताएँ"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["बीच में देखें"].exists)
        app.buttons["skip-test"].tap()
        XCTAssertTrue(app.buttons["finish-scan"].waitForExistence(timeout: 5))
        app.buttons["finish-scan"].tap()
        XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["no-voice-measurements"].exists)
        app.buttons["get-help"].tap()
        XCTAssertTrue(app.staticTexts["help-title"].waitForExistence(timeout: 5))
        app.buttons["voice-care-option"].tap()
        XCTAssertTrue(app.staticTexts["voice-care-option-detail"].waitForExistence(timeout: 5))
        app.buttons["पूरा"].tap()
        app.buttons["settings"].tap()
        XCTAssertTrue(app.buttons["Español"].exists)
        app.buttons["Español"].tap()
        XCTAssertTrue(app.navigationBars["ajustes"].exists)
    }

    func testMeasuredResultsOpenPracticalHelpWithoutEyeResults() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding", "-skipModelWarmup", "-voiceResultsFixture", "-venture.language", "en"]
        app.launch()
        XCTAssertTrue(app.staticTexts["voice-results-title"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["recording captured"].exists)
        XCTAssertTrue(app.staticTexts["188 Hz"].exists)
        XCTAssertFalse(app.staticTexts["eyes"].exists)
        XCTAssertFalse(app.staticTexts["camera"].exists)
        reveal(app.staticTexts["disease screening unavailable"], in: app)
        XCTAssertTrue(app.staticTexts["disease screening unavailable"].exists)
        add(XCTAttachment(screenshot: app.screenshot()))
        app.buttons["get-help"].tap()
        XCTAssertTrue(app.staticTexts["help-title"].waitForExistence(timeout: 5))
        app.buttons["voice-care-option"].tap()
        XCTAssertTrue(app.staticTexts["voice-care-option-detail"].waitForExistence(timeout: 5))
        app.buttons["voice-care-option"].tap()
        app.buttons["telehealth-option"].tap()
        XCTAssertTrue(app.staticTexts["telehealth-option-detail"].waitForExistence(timeout: 5))
        reveal(app.buttons["find-clinic"], in: app)
        XCTAssertTrue(app.links["hrsa-health-centers"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        add(XCTAttachment(screenshot: app.screenshot()))
    }

    func testPoorRecordingOffersRetakeWithoutVoiceFeatureValues() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding", "-skipModelWarmup", "-voiceResultsFixture", "-poorVoiceQuality", "-venture.language", "en"]
        app.launch()
        XCTAssertTrue(app.staticTexts["voice-results-title"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["repeat in a quieter place"].exists)
        XCTAssertFalse(app.staticTexts["188 Hz"].exists)
        reveal(app.buttons["retake-voice"], in: app)
        app.buttons["retake-voice"].tap()
        XCTAssertTrue(app.buttons["record-ahh"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["look at the centre"].exists)
    }
}
