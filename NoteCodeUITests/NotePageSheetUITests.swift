//
//  NotePageSheetUITests.swift
//  NoteCodeUITests
//
//  Sheets over an open note: each must appear and go away again. On an
//  iPhone a page sheet over the note once never appeared: the app's main
//  thread spun in the sheet's layout pass for good, because the note handed
//  the menu bar a new `OpenNote` on every build (see `OpenNote`). Run on an
//  iPhone simulator to cover that; on an iPad they are ordinary checks.
//  The Pro sheets (Summarise Note) are in Pro/NotePageProSheetUITests.swift,
//  which the open-source build deletes.
//

import XCTest

final class NotePageSheetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // A hung app fails each query only after a long wait; this keeps a
        // hang from holding the run for the default ten minutes (it rounds up
        // to whole minutes). A healthy run from a cold simulator took 49s.
        executionTimeAllowance = 120
    }

    /// The code note. Nothing here needs Pro, so it runs in either edition.
    @MainActor
    private func openNote() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-debug-note", "code"]
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
}
