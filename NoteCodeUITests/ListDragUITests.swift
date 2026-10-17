//
//  ListDragUITests.swift
//  NoteCodeUITests
//
//  Dragging in the note list, with a real drag: XCUITest's press-and-drag
//  starts a drag session the way a finger does, which the simulator tools'
//  synthesised touches don't.
//
//  FAILS today (17 Oct): no drop target in the list ever hears the drag. See
//  AGENTS.md › Organising notes › "Why the drops never land".
//

import XCTest

final class ListDragUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The sample notes and folders, with the list open over Home.
    @MainActor
    private func launchWithList() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-debug-home"]
        app.launch()
        let sidebar = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5), "no sidebar button")
        sidebar.tap()
        XCTAssertTrue(listRow(app, "Big-O cheat sheet").waitForExistence(timeout: 5), "the list never opened")
        Thread.sleep(forTimeInterval: 0.6)
        return app
    }

    private func listRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.cells.containing(.staticText, identifier: title).firstMatch
    }

    @MainActor
    func testNoteDroppedOnFolderIsFiled() {
        let app = launchWithList()
        let note = listRow(app, "Big-O cheat sheet")
        let folder = listRow(app, "Discrete math")
        let notesHeader = app.staticTexts["Notes"].firstMatch
        XCTAssertGreaterThan(note.frame.minY, notesHeader.frame.minY, "starts at the top level")

        note.press(forDuration: 1.2, thenDragTo: folder, withVelocity: .slow, thenHoldForDuration: 0.6)
        Thread.sleep(forTimeInterval: 1)

        // Filed in Discrete math: listed under it, above the Notes header.
        let moved = listRow(app, "Big-O cheat sheet")
        XCTAssertTrue(moved.waitForExistence(timeout: 3))
        XCTAssertLessThan(moved.frame.minY, app.staticTexts["Notes"].firstMatch.frame.minY, "still at the top level")
        XCTAssertGreaterThan(moved.frame.minY, listRow(app, "Discrete math").frame.minY)
    }
}
