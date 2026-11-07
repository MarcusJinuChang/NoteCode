//
//  NotePageProSheetUITests.swift
//  NoteCodeUITests
//
//  The Pro sheets over an open note, the twin of NotePageSheetUITests (see
//  its header for the iPhone freeze these cover). They need the App Store
//  edition: `-debug-pro`, the Run disclosure's setting and Summarise Note are
//  all in Pro/, so the open-source build deletes this folder.
//

import XCTest

final class NotePageProSheetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // As in NotePageSheetUITests: a hang fails in two minutes, not ten.
        executionTimeAllowance = 120
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
    func testSummariseOverTheNote() throws {
        let app = openNote()
        let menu = app.buttons["noteMenu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "no ••• button")
        menu.tap()
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
