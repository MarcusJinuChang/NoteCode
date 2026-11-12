//
//  TypedRuleUITests.swift
//  NoteCodeUITests
//
//  A `---` typed at a line's start is a rule, not "—-". Only a test that
//  types through the keyboard can see this: the keyboard's smart dashes
//  run inside its own insert, after the text view's delegate has been asked
//  about a plain "-", and `typeText` skips them. Each key is pressed as a
//  hardware key (`typeKey`), and then tapped on the on-screen keyboard.
//

import XCTest

final class TypedRuleUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    private func openEmptyNote() -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments = ["-debug-note", "empty", "-debug-mode", "seamless"]
        app.launch()
        let text = app.textViews.firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 15), "the note never opened")
        text.tap()
        // The caret is in the note once a keyboard is (minimised, under a
        // hardware key, it still exists).
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the caret never arrived in the note")
        return (app, text)
    }

    @MainActor
    private func value(of text: XCUIElement) -> String {
        (text.value as? String) ?? ""
    }

    /// Hardware keys, a beat apart, as a reader types them.
    @MainActor
    private func press(_ keys: String, in app: XCUIApplication) {
        for key in keys {
            app.typeKey(String(key), modifierFlags: [])
            UIWait.pace(0.3, .readerTyping)
        }
    }

    @MainActor
    func testHyphensTypedAtALineStartStayHyphens() throws {
        let (app, text) = openEmptyNote()
        press("---", in: app)
        UIWait.until(timeout: 3) { self.value(of: text) == "---" }
        XCTAssertEqual(value(of: text), "---", "the first line")

        text.typeText("\n")
        press("  ---", in: app)
        UIWait.until(timeout: 3) { self.value(of: text) == "---\n  ---" }
        XCTAssertEqual(value(of: text), "---\n  ---", "an indented line")

        // Between words the keyboard's dash is still made.
        text.typeText("\nab")
        press("--", in: app)
        // Waits for the outcome the test wants, a dash, and only that: two
        // hyphens may be the moment before the keyboard makes one, so
        // stopping on them could fail a run that would have passed. With no
        // dash the wait runs out and the assertion says what was there.
        UIWait.until(timeout: 3) {
            let last = self.value(of: text).components(separatedBy: "\n").last ?? ""
            return last.contains("\u{2014}") || last.contains("\u{2013}")
        }
        let last = value(of: text).components(separatedBy: "\n").last ?? ""
        XCTAssertTrue(last.hasPrefix("ab") && !last.contains("--"), "a dash between words, got \(last)")
    }

    @MainActor
    func testHyphensTappedOnTheOnScreenKeyboardStayHyphens() throws {
        let (app, text) = openEmptyNote()
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 5) else {
            XCTFail("no on-screen keyboard. " + SoftKeyboard.minimisedMessage)
            return
        }
        if !keyboard.keys["-"].exists { keyboard.keys["more"].firstMatch.tap() }
        let hyphen = keyboard.keys["-"].firstMatch
        XCTAssertTrue(hyphen.waitForExistence(timeout: 3), "no - key")
        // Minimised, the keyboard still exists, its keys below the screen's
        // edge, so a tap could never reach them.
        guard hyphen.isHittable else {
            XCTFail(SoftKeyboard.minimisedMessage)
            return
        }
        for _ in 0..<3 {
            hyphen.tap()
            UIWait.pace(0.3, .readerTyping)
        }
        UIWait.until(timeout: 3) { self.value(of: text) == "---" }
        XCTAssertEqual(value(of: text), "---")
    }
}
