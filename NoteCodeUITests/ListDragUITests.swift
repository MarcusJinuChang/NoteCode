//
//  ListDragUITests.swift
//  NoteCodeUITests
//
//  Dragging in the sidebar list, with a real press and drag: a unit test of
//  `ListDrop` checks the rules, and only this can see whether the system
//  delivers a drop to the list at all. Over `-debug-home`'s sample notes, in
//  an in-memory store, so it is safe to run on a device with real notes.
//

import XCTest

final class ListDragUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The simulator never delivers a drop to the app (read 24 Oct: a drag
    /// lifts and follows the touch, and nothing is entered or dropped on),
    /// so these run on a device.
    @MainActor
    private func launch() throws -> XCUIApplication {
#if targetEnvironment(simulator)
        throw XCTSkip("the simulator doesn't deliver drops; run on a device")
#endif
        let app = XCUIApplication()
        app.launchArguments = ["-debug-home", "-debug-keep-defaults", "-debug-probe"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Exam 1 review"].waitForExistence(timeout: 10), "the sample notes never showed")
        return app
    }

    /// The sidebar's list: Home, beside it, has titles of its own.
    @MainActor
    private func sidebar(in app: XCUIApplication) -> XCUIElement {
        app.collectionViews.allElementsBoundByIndex.first { $0.frame.width < 400 } ?? app.collectionViews.firstMatch
    }

    /// A title in the sidebar.
    @MainActor
    private func title(_ text: String, in app: XCUIApplication) -> XCUIElement {
        sidebar(in: app).staticTexts[text].firstMatch
    }

    /// A note held for `hold` seconds and dragged onto a folder's row is
    /// filed in it. The sample notes put four notes under CS133 and one under
    /// Algorithm practice, and a folder's row says how many it holds, so the 5
    /// that follows is the drop landing, however the list is sorted.
    @MainActor
    private func dragANoteOntoAFolder(holding hold: TimeInterval) throws {
        let app = try launch()
        let list = sidebar(in: app)
        XCTAssertFalse(list.staticTexts["5"].exists, "nothing holds five yet")

        title("Two pointers", in: app)
            .press(forDuration: hold, thenDragTo: title("CS133", in: app), withVelocity: .slow, thenHoldForDuration: 1)

        XCTAssertTrue(list.staticTexts["5"].waitForExistence(timeout: 5), "CS133 didn't take the note")
    }

    @MainActor func testDraggingANoteOntoAFolderFilesIt() throws { try dragANoteOntoAFolder(holding: 0.55) }

    /// A note dragged onto the Library header leaves its folder: Algorithm
    /// practice, which held it, ends with none.
    @MainActor
    func testDraggingANoteOntoLibraryTakesItOutOfItsFolder() throws {
        let app = try launch()
        let list = sidebar(in: app)
        XCTAssertFalse(list.staticTexts["0"].exists, "no folder is empty yet")

        title("Two pointers", in: app)
            .press(forDuration: 0.55, thenDragTo: title("Library", in: app), withVelocity: .slow, thenHoldForDuration: 1)

        XCTAssertTrue(list.staticTexts["0"].waitForExistence(timeout: 5), "the note stayed in its folder")
    }
}
