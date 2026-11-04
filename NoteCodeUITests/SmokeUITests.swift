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
        print.tap()
        XCTAssertTrue(print.waitForNonExistence(timeout: 5), "the menu stayed open")
        menu.tap()
        let seamless = app.buttons["Seamless"]
        XCTAssertTrue(seamless.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Print Layout"].isSelected, "the switch to Print Layout didn't take")
        seamless.tap()

        // ••• › Settings, and Done.
        menu.tap()
        let settings = app.buttons["noteMenuSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let sheet = app.navigationBars["Settings"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "the Settings sheet never opened")
        sheet.buttons["Done"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "the Settings sheet never closed")
        XCTAssertTrue(toggle.exists, "not back on the note")
        app.terminate()
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
