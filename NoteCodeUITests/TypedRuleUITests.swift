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
        Thread.sleep(forTimeInterval: 0.5)
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
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    @MainActor
    func testHyphensTypedAtALineStartStayHyphens() throws {
        let (app, text) = openEmptyNote()
        press("---", in: app)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(value(of: text), "---", "the first line")

        text.typeText("\n")
        press("  ---", in: app)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(value(of: text), "---\n  ---", "an indented line")

        // Between words the keyboard's dash is still made.
        text.typeText("\nab")
        press("--", in: app)
        Thread.sleep(forTimeInterval: 0.6)
        let last = value(of: text).components(separatedBy: "\n").last ?? ""
        XCTAssertTrue(last.hasPrefix("ab") && !last.contains("--"), "a dash between words, got \(last)")
    }

    @MainActor
    func testHyphensTappedOnTheOnScreenKeyboardStayHyphens() throws {
        let (app, text) = openEmptyNote()
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 5) else {
            throw XCTSkip("no on-screen keyboard (a hardware keyboard is connected)")
        }
        if !keyboard.keys["-"].exists { keyboard.keys["more"].firstMatch.tap() }
        let hyphen = keyboard.keys["-"].firstMatch
        XCTAssertTrue(hyphen.waitForExistence(timeout: 3), "no - key")
        // With a hardware keyboard connected the keyboard still exists, its
        // keys below the screen's edge, so a tap could never reach them.
        guard hyphen.isHittable else {
            throw XCTSkip("no on-screen keyboard (a hardware keyboard is connected)")
        }
        for _ in 0..<3 {
            hyphen.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(value(of: text), "---")
    }
}
