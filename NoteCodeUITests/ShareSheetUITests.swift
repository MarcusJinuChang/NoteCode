//
//  ShareSheetUITests.swift
//  NoteCodeUITests
//
//  The note's Share button opens the share sheet, on a short note with no
//  ink as well as a long one. On a short note it once wrote the PDF and
//  opened nothing: the popover anchor was the only copy SwiftUI made, and
//  it sat in a toolbar item host that was in no window (device pass, 7 Nov).
//

import XCTest

final class ShareSheetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Taps Share and waits for the sheet's popover, then dismisses it.
    @MainActor
    private func shareOpensSheet(_ app: XCUIApplication) -> Bool {
        let share = app.buttons["shareButton"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 10), "no Share button")
        share.tap()
        let region = app.otherElements["PopoverDismissRegion"].firstMatch
        guard region.waitForExistence(timeout: 10) else { return false }
        region.tap()
        _ = region.waitForNonExistence(timeout: 5)
        return true
    }

    @MainActor
    func testShareOpensTheSheetOnAnEmptyNote() {
        let app = XCUIApplication()
        app.launchArguments = ["-debug-note", "empty", "-debug-mode", "seamless"]
        app.launch()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 15), "the note never opened")
        XCTAssertTrue(shareOpensSheet(app), "Share on an empty note opened no share sheet")
        XCTAssertTrue(shareOpensSheet(app), "a second Share on an empty note opened no share sheet")
    }

    @MainActor
    func testShareOpensTheSheetOnALongNote() {
        let app = XCUIApplication()
        app.launchArguments = ["-debug-note", "pages", "-debug-mode", "seamless"]
        app.launch()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 15), "the note never opened")
        XCTAssertTrue(shareOpensSheet(app), "Share on a long note opened no share sheet")
    }
}
