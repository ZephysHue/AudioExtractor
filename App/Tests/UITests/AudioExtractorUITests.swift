import XCTest

final class AudioExtractorUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(tone: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (tone ? ["-uiTestingTone"] : [])
        app.launch()
        return app
    }

    func testHomeShowsEntryPointsAndTabs() {
        let app = launch(tone: false)
        XCTAssertTrue(app.buttons["pickFromPhotos"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["pickFromFiles"].exists)

        app.tabBars.buttons["作品库"].tap()
        XCTAssertTrue(app.staticTexts["还没有作品"].waitForExistence(timeout: 5))

        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["默认导出设置"].waitForExistence(timeout: 5)
                      || app.staticTexts["默认导出设置".uppercased()].exists)
    }

    func testTrimExportRenameDeleteFlow() {
        let app = launch(tone: true)

        // Editor opens with the generated 4 s tone.
        let export = app.buttons["exportButton"]
        XCTAssertTrue(export.waitForExistence(timeout: 15))
        let length = app.staticTexts["selectionLength"]
        XCTAssertEqual(length.label, "00:04.0")

        // Trim: start +0.5 s, end -0.5 s.
        for _ in 0..<5 { app.buttons["startPlus"].tap() }
        for _ in 0..<5 { app.buttons["endMinus"].tap() }
        XCTAssertEqual(length.label, "00:03.0")

        // Preview toggles.
        app.buttons["previewButton"].tap()
        app.buttons["previewButton"].tap()

        // Pick M4A, then export.
        app.buttons["format_m4a"].tap()
        export.tap()
        XCTAssertTrue(app.images["exportDone"].waitForExistence(timeout: 30)
                      || app.otherElements["exportDone"].exists)
        app.buttons["goToLibrary"].tap()

        // Library shows exactly one item.
        let rows = app.buttons.matching(identifier: "libraryRow")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows.firstMatch.label.contains("测试音频"))

        // Play it (mini player appears).
        rows.firstMatch.tap()
        XCTAssertTrue(app.buttons["miniPlayerToggle"].waitForExistence(timeout: 5))
        app.buttons["关闭播放器"].tap()

        // Rename via swipe.
        rows.firstMatch.swipeLeft()
        app.buttons["重命名"].tap()
        let field = app.textFields["renameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        field.typeText("My Ringtone")
        app.buttons["renameSave"].tap()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(rows.firstMatch.label.contains("My Ringtone"))

        // Delete via swipe.
        rows.firstMatch.swipeLeft()
        app.buttons["删除"].tap()
        XCTAssertTrue(app.staticTexts["还没有作品"].waitForExistence(timeout: 5))
    }
}
