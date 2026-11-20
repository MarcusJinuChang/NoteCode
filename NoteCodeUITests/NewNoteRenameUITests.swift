//
//  NewNoteRenameUITests.swift
//  NoteCodeUITests
//
//  A note just made opens with its title being renamed: the navigation
//  bar's title is a text field with the keyboard's focus. Whether the system
//  starts the rename at all is only visible in the running app. Over
//  `-debug-home`'s sample notes, in an in-memory store.
//

import XCTest

final class NewNoteRenameUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-debug-home", "-debug-pro", "on", "-openNoteAfterCreating", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Exam 1 review"].firstMatch.waitForExistence(timeout: 10), "the sample notes never showed")
        return app
    }

    /// The title field, being edited.
    @MainActor
    private func renaming(in app: XCUIApplication) -> XCUIElement {
        app.navigationBars.textFields.matching(NSPredicate(format: "hasKeyboardFocus == YES")).firstMatch
    }

    @MainActor
    func testHomesNewNoteOpensRenaming() throws {
        let app = launch()
        app.buttons["homeNewNote"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Untitled"].waitForExistence(timeout: 5), "no new note opened")
        XCTAssertTrue(renaming(in: app).waitForExistence(timeout: 5), "the new note's title isn't being renamed")
    }

    @MainActor
    func testCommandNFromANoteOpensRenaming() throws {
        let app = launch()
        let row = app.collectionViews.cells.containing(.staticText, identifier: "Exam 1 review").firstMatch
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Exam 1 review,")).firstMatch
        (card.exists ? card : row).tap()
        XCTAssertTrue(app.navigationBars["Exam 1 review"].waitForExistence(timeout: 5), "the note didn't open")
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["Untitled"].waitForExistence(timeout: 5), "⌘N made no note")
        XCTAssertTrue(renaming(in: app).waitForExistence(timeout: 5), "the new note's title isn't being renamed")
    }
}
