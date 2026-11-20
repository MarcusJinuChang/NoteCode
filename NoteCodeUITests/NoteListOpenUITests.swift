//
//  NoteListOpenUITests.swift
//  NoteCodeUITests
//
//  A tap on a note's row in the iPad's sidebar opens the note. Only a real
//  tap can show this: the row is a drag source and a drop target as well,
//  and whether the list still turns the tap into its selection is the
//  system's business, not something a unit test can see. Over `-debug-home`'s
//  sample notes, in an in-memory store.
//

import XCTest

final class NoteListOpenUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The sidebar's list: Home, beside it, has titles of its own.
    @MainActor
    private func sidebar(in app: XCUIApplication) -> XCUIElement {
        app.collectionViews.allElementsBoundByIndex.first { $0.frame.width < 450 && $0.frame.minX < 50 }
            ?? app.collectionViews.firstMatch
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-debug-home", "-debug-pro", "on"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Exam 1 review"].firstMatch.waitForExistence(timeout: 10), "the sample notes never showed")
        return app
    }

    /// A note filed in a folder, tapped in the list beside Home, opens.
    @MainActor
    func testTappingANoteRowOpensIt() throws {
        let app = launch()
        let row = sidebar(in: app).cells.containing(.staticText, identifier: "Two pointers").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Two pointers isn't in the list")
        row.tap()
        XCTAssertTrue(app.navigationBars["Two pointers"].waitForExistence(timeout: 5), "the tap opened nothing")
    }

    /// With a note open and the list brought over it, a tap on another
    /// note's row opens that one.
    @MainActor
    func testTappingARowOverAnOpenNoteOpensIt() throws {
        let app = launch()
        let first = sidebar(in: app).cells.containing(.staticText, identifier: "Two pointers").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        XCTAssertTrue(app.navigationBars["Two pointers"].waitForExistence(timeout: 5), "the first tap opened nothing")
        app.buttons["sidebarButton"].firstMatch.tap()
        let other = sidebar(in: app).cells.containing(.staticText, identifier: "Exam 1 review").firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 5), "the list didn't come over the note")
        other.tap()
        XCTAssertTrue(app.navigationBars["Exam 1 review"].waitForExistence(timeout: 5), "the tap over a note opened nothing")
    }
}
