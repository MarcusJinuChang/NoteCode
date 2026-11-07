//
//  NotePageSheetUITests.swift
//  NoteCodeUITests
//
//  Sheets over an open note: each must appear and go away again. On an
//  iPhone a page sheet over the note once never appeared: the app's main
//  thread spun in the sheet's layout pass for good, because the note handed
//  the menu bar a new `OpenNote` on every build (see `OpenNote`). Run on an
//  iPhone simulator to cover that; on an iPad they are ordinary checks.
//

import XCTest

final class NotePageSheetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // A hung app fails each query only after a long wait; this keeps a
        // hang from holding the run for the default ten minutes (it rounds up to whole minutes).
        executionTimeAllowance = 60
    }

    /// The code note with Pro on, so ••• has Summarise Note and the
    /// paywall stays out of it.
    @MainActor
    private func openNote() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-debug-note", "code", "-debug-pro", "on", "-runDisclosureAccepted", "YES"]
        app.launch()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 15), "the note never opened")
        return app
    }

    @MainActor
    private func openMoreMenu(_ app: XCUIApplication) {
        let menu = app.buttons["noteMenu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "no ••• button")
        menu.tap()
    }

    @MainActor
    func testSettingsOverTheNote() throws {
        let app = openNote()
        openMoreMenu(app)
        let item = app.buttons["noteMenuSettings"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "••• has no Settings")
        item.tap()

        let sheet = app.navigationBars["Settings"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 8), "the Settings sheet never appeared")
        sheet.buttons["Done"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 8), "the Settings sheet never went away")
        XCTAssertTrue(app.buttons["noteMenu"].firstMatch.waitForExistence(timeout: 5), "not back on the note")
    }

    @MainActor
    func testSummariseOverTheNote() throws {
        let app = openNote()
        openMoreMenu(app)
        let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Summarise Note'")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "••• has no Summarise Note")
        item.tap()

        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 8), "the Summarise sheet never appeared")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 8), "the Summarise sheet never went away")
        XCTAssertTrue(app.buttons["noteMenu"].firstMatch.waitForExistence(timeout: 5), "not back on the note")
    }
}
