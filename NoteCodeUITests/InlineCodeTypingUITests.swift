//
//  InlineCodeTypingUITests.swift
//  NoteCodeUITests
//
//  Typing inline code through the keyboard keeps every character, end to
//  end. Each backtick typed in prose moves the caret between prose and
//  code, and the keyboard is reloaded with the other traits there and
//  then. In the 7 Nov device pass (writing-5) that lost characters:
//  typed fast, `a `code` b` was stored as "a code` b", one key every 0.3s
//  as "a `code`b", and the next Undo aborted the app.
//
//  The cause was a SwiftUI render the reload set off inside the keystroke,
//  which pushed the note's stale binding back into the text view; #236
//  stopped that, and MidEditRenderTests is the test that fails without it.
//  These don't fail without it on a headless simulator, whose reload
//  doesn't move the keyboard's frame (the pass's simulator was switching
//  hardware-keyboard mode), so they are the whole path checked, not the
//  bug pinned.
//
//  Also AGENTS.md › Implementation requirements' manual cases for fences
//  (fast typing, a paste, an edit inside a fence), typed rather than
//  tapped through by hand.
//

import XCTest

final class InlineCodeTypingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    private func launch(_ extra: [String] = []) -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments = ["-debug-note", "empty", "-debug-mode", "seamless", "-hotbarDock", "bottom"] + extra
        app.launch()
        let text = app.textViews.firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 15), "the note never opened")
        text.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "no on-screen keyboard")
        return (app, text)
    }

    @MainActor
    private func value(_ text: XCUIElement) -> String { text.value as? String ?? "" }

    /// Waits for the text to settle on `expected`, as the keyboard's last
    /// keys can arrive a moment after `typeText` returns.
    @MainActor
    private func assertSettles(_ text: XCUIElement, on expected: String, _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        UIWait.until(timeout: 3) { self.value(text) == expected }
        XCTAssertEqual(value(text), expected, what, file: file, line: line)
    }

    /// Empties the note: ⌘A and a delete, again until it is empty.
    ///
    /// The simulator drops a `typeKey` ⌘A now and then, and the first of a
    /// launch always: never reaching the app (no `pressesBegan`, no
    /// `selectAll`), while every one that arrived selected all. A fresh app
    /// given `a code b`, then ⌘A and X, kept `a code bX` 40 times in 40,
    /// prose or inline code, a 3s wait or none; after one earlier ⌘A the
    /// next worked 7 times in 12 (11 Nov, iOS 27.0). So waiting doesn't
    /// help and trying again does. A dropped one leaves the caret where it
    /// was and the delete takes one character, so a try is told apart by
    /// whether the note emptied, and the tries stop well short of the text.
    @MainActor
    private func clear(_ app: XCUIApplication, _ text: XCUIElement,
                       file: StaticString = #filePath, line: UInt = #line) {
        let empty = NSPredicate { element, _ in
            ((element as? XCUIElement)?.value as? String ?? "").isEmpty
        }
        for _ in 0..<6 where !value(text).isEmpty {
            app.typeKey("a", modifierFlags: .command)
            text.typeText(XCUIKeyboardKey.delete.rawValue)
            let emptied = XCTNSPredicateExpectation(predicate: empty, object: text)
            _ = XCTWaiter.wait(for: [emptied], timeout: 2)
        }
        XCTAssertEqual(value(text), "", "the note did not empty", file: file, line: line)
    }

    @MainActor
    func testFastInlineCodeKeepsEveryCharacter() {
        let (app, text) = launch()
        for round in 0..<3 {
            clear(app, text)
            text.typeText("a `code` b")
            assertSettles(text, on: "a `code` b", "fast, round \(round)")
        }
    }

    @MainActor
    func testSlowInlineCodeKeepsEveryCharacter() {
        let (app, text) = launch()
        for round in 0..<2 {
            clear(app, text)
            for character in "a `code` b" {
                text.typeText(String(character))
                UIWait.pace(0.3, .readerTyping)
            }
            assertSettles(text, on: "a `code` b", "one key per 0.3s, round \(round)")
        }
    }

    /// Several lines of it, with Returns, which were lost too once the
    /// first backtick had been.
    @MainActor
    func testLinesOfInlineCodeKeepEveryCharacter() {
        let (_, text) = launch()
        var expected = ""
        for i in 0..<6 {
            text.typeText("a `code\(i)` b\n")
            expected += "a `code\(i)` b\n"
        }
        assertSettles(text, on: expected, "six lines")
    }

    /// Undo after typing inline code takes it all away (it crashed when a
    /// character had been lost outside the typing undo).
    @MainActor
    func testUndoAfterInlineCode() {
        let (app, text) = launch()
        text.typeText("a `code` b")
        assertSettles(text, on: "a `code` b", "typed")
        for _ in 0..<15 where !value(text).isEmpty {
            let before = value(text)
            app.typeKey("z", modifierFlags: .command)
            // Each Undo takes something away, or the app quit on it.
            UIWait.until(timeout: 2) { self.value(text) != before || app.state != .runningForeground }
        }
        XCTAssertEqual(app.state, .runningForeground, "the app quit on Undo")
        XCTAssertEqual(value(text), "", "Undo left text behind")
    }

    // MARK: Fences (AGENTS.md › Implementation requirements)

    @MainActor
    func testFastTypedFence() {
        let (_, text) = launch()
        let fence = "```python\nprint(`hi`)\nx = 1\n```\nafter `y` z"
        text.typeText(fence)
        assertSettles(text, on: fence, "a fence typed fast")
    }

    @MainActor
    func testPastedFenceThenTypingInside() {
        let (app, text) = launch()
        UIPasteboard.general.string = "```cpp\nint x;\n```\nend"
        // The first ⌘V after launch can land nowhere on the simulator.
        for _ in 0..<4 where value(text).isEmpty {
            app.typeKey("v", modifierFlags: .command)
            let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Paste"]
            if allow.waitForExistence(timeout: 1) { allow.tap() }
            UIWait.until(timeout: 2) { !self.value(text).isEmpty }
        }
        assertSettles(text, on: "```cpp\nint x;\n```\nend", "the paste")
        // Mid-fence: to the end of `int x;` and type a line there.
        app.typeKey(.upArrow, modifierFlags: [])
        app.typeKey(.upArrow, modifierFlags: [])
        app.typeKey(.rightArrow, modifierFlags: .command)
        text.typeText("\nint `y` = 2;")
        assertSettles(text, on: "```cpp\nint x;\nint `y` = 2;\n```\nend", "typed inside the fence")
    }
}
