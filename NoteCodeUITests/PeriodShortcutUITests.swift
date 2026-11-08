//
//  PeriodShortcutUITests.swift
//  NoteCodeUITests
//
//  The on-screen keyboard's "." shortcut: two spaces in quick succession
//  become ". ". No text-input trait turns it off, so where the keyboard may
//  not rewrite (code, or prose with Settings › Writing › Autocorrect off)
//  the editor puts the two spaces back. Only the on-screen keyboard has the
//  shortcut, so these tap its keys rather than `typeText`.
//

import XCTest

final class PeriodShortcutUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Taps `keys` on the on-screen keyboard, back to back.
    @MainActor
    private func tap(_ keys: String, in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "no on-screen keyboard")
        for character in keys {
            // With capitals on, the letter keys are named in capitals.
            var key = character == " " ? keyboard.keys["space"] : keyboard.keys[String(character)]
            if !key.exists { key = keyboard.keys[String(character).uppercased()] }
            XCTAssertTrue(key.exists && key.isHittable, "no key for \(character.debugDescription)")
            key.tap()
        }
    }

    @MainActor
    private func launch(note: [String], autocorrect: Bool) -> XCUIElement {
        let app = XCUIApplication()
        app.launchArguments = note + ["-debug-mode", "seamless", "-autocorrectInProse", autocorrect ? "YES" : "NO"]
        app.launch()
        let text = app.textViews.firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 15), "the note never opened")
        return text
    }

    /// Prose with Autocorrect off: two spaces stay two.
    @MainActor
    func testProseWithAutocorrectOffKeepsTwoSpaces() {
        let text = launch(note: ["-debug-note", "empty"], autocorrect: false)
        text.tap()
        tap("ab  cd", in: XCUIApplication())
        XCTAssertEqual(text.value as? String, "ab  cd")
    }

    /// Code, with Autocorrect on: two spaces stay two.
    @MainActor
    func testCodeKeepsTwoSpaces() throws {
        // An unclosed fence runs to the end of the note, so the whole note
        // is code. Written where the app (a simulator process on this Mac)
        // can read it.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("period-shortcut-code.md")
        try "```cpp\nint x".write(to: file, atomically: true, encoding: .utf8)
        let text = launch(note: ["-debug-note-file", file.path], autocorrect: true)
        // Anywhere in it is code.
        text.tap()
        tap(" ef  gh", in: XCUIApplication())
        let value = text.value as? String ?? ""
        XCTAssertTrue(value.contains("ef  gh"), "the code is \(value.debugDescription)")
        XCTAssertFalse(value.contains("."), "the code is \(value.debugDescription)")
    }

    /// Prose with Autocorrect on: the shortcut is the keyboard's to make.
    @MainActor
    func testProseWithAutocorrectOnTakesTheShortcut() {
        let text = launch(note: ["-debug-note", "empty"], autocorrect: true)
        text.tap()
        tap("ab  cd", in: XCUIApplication())
        XCTAssertEqual((text.value as? String)?.lowercased(), "ab. cd")
    }
}
