//
//  SmokeUITests.swift
//  NoteCodeUITests
//
//  One pass through the note page as a reader takes it: draw mode and back,
//  type, find a code block's buttons, the view menu, Settings. Over
//  `-debug-note code`, in an in-memory store, so the simulator's notes are
//  untouched. Under a minute; anything slower is a finding.
//

import XCTest

final class SmokeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testThroughTheNotePage() throws {
        let app = XCUIApplication()
        // Seamless to start, so the switch below is to a different mode.
        app.launchArguments = ["-debug-note", "code", "-debug-mode", "seamless"]
        app.launch()

        let text = app.textViews.firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 10), "the note never opened")

        // Draw mode and back, before typing: with the soft keyboard up, the
        // bar rides on it, and a tap while the keyboard is still going down
        // misses the moving toggle.
        let toggle = app.buttons["modeToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        wait(for: toggle, toSay: "Draw mode")
        toggle.tap()
        wait(for: toggle, toSay: "Text mode")

        // Type a line.
        text.tap()
        text.typeText("smoke\n")
        XCTAssertTrue((text.value as? String)?.contains("smoke") == true, "the typed line isn't in the note")

        // The first block, C++, has both buttons.
        XCTAssertTrue(app.buttons["codeBlockRun"].firstMatch.waitForExistence(timeout: 5), "no Run button on a code block")
        XCTAssertTrue(app.buttons["codeBlockCopy"].firstMatch.exists, "no Copy button on a code block")

        // ••• › Print Layout, then back to Seamless.
        let menu = app.buttons["noteMenu"].firstMatch
        menu.tap()
        let print = app.buttons["Print Layout"]
        XCTAssertTrue(print.waitForExistence(timeout: 5), "the view menu has no Print Layout")
        choose(print)
        menu.tap()
        let seamless = app.buttons["Seamless"]
        XCTAssertTrue(seamless.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Print Layout"].isSelected, "the switch to Print Layout didn't take")
        choose(seamless)

        // ••• › Settings, and Done.
        menu.tap()
        let settings = app.buttons["noteMenuSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "the note's menu has no Settings entry")
        choose(settings)
        // 8s, as NotePageSheetUITests gives the same sheet over a note.
        let sheet = app.navigationBars["Settings"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 8), "the Settings sheet never opened")
        sheet.buttons["Done"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 8), "the Settings sheet never closed")
        XCTAssertTrue(toggle.exists, "not back on the note")
        app.terminate()
    }

    /// Taps an item of the open ••• menu and waits for the menu to close.
    ///
    /// The menu lists its items before it takes touches: under load the tap
    /// on Seamless landed while the menu was still opening, did nothing, and
    /// left the menu open with Print Layout selected (11 Nov, seen in the
    /// hierarchy at the failure). The next tap on ••• then closed that menu,
    /// the query for Settings found it on its way out, and "the Settings sheet
    /// never opened". So a tap the menu swallowed is made once more, and a
    /// menu still open after that fails here, not at the next step; whether
    /// the item did what it says is still checked by the caller.
    @MainActor
    private func choose(_ item: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let hittable = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: item)
        if XCTWaiter().wait(for: [hittable], timeout: 5) != .completed {
            XCTFail("\(item) never took a tap", file: file, line: line)
            return
        }
        item.tap()
        if !item.waitForNonExistence(timeout: 5) {
            if item.isHittable { item.tap() }
            XCTAssertTrue(item.waitForNonExistence(timeout: 5), "the menu stayed open after \(item.label)", file: file, line: line)
        }
    }

    /// Waits for `element`'s accessibility value to be `value`: a tap's
    /// effect lands after the tap returns.
    @MainActor
    private func wait(for element: XCUIElement, toSay value: String, file: StaticString = #filePath, line: UInt = #line) {
        let said = expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: element)
        if XCTWaiter().wait(for: [said], timeout: 5) != .completed {
            XCTFail("\(element) says \(element.value ?? "nothing"), not \(value)", file: file, line: line)
        }
    }
}
