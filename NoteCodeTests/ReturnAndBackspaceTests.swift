//
//  ReturnAndBackspaceTests.swift
//  NoteCodeTests
//
//  Guards for two reported text bugs that did not reproduce on main (21 Oct):
//  a thin extra space when Return is pressed in a code block, and a Return or
//  Backspace that needed two presses while held. Both pass on the code as it
//  stands; they pin what was measured, so a regression shows up here.
//

#if canImport(UIKit)

import Testing
import UIKit

@testable import NoteCode

@Suite("Return and Backspace through the coordinator")
@MainActor
struct ReturnAndBackspaceTests {

    /// One press as the keyboard makes it: `shouldChangeTextIn`, then UIKit's
    /// own insert or delete if the coordinator let it through.
    static func press(_ harness: CodeFenceDisplayTests.Harness, backspace: Bool) {
        let textView = harness.textView
        let selection = textView.selectedRange
        if backspace {
            guard selection.length == 0, selection.location > 0 else { return }
            let range = NSRange(location: selection.location - 1, length: 1)
            if harness.coordinator.textView(textView, shouldChangeTextIn: range, replacementText: "") {
                textView.deleteBackward()
            }
        } else if harness.coordinator.textView(textView, shouldChangeTextIn: selection, replacementText: "\n") {
            textView.insertText("\n")
        }
    }

    static func top(of text: String, in harness: CodeFenceDisplayTests.Harness) throws -> CGFloat {
        let lines = CodeBlockRoomTests.lines(of: harness.textView)
        return try #require(lines.first { $0.text.hasPrefix(text) }).frame.minY
    }

    // MARK: No extra space

    /// Everything below the caret moves down by one line, and by nothing
    /// else: the panel's border, a fence's gap or an extra-line fragment
    /// adding a sliver would show here as a shift that isn't a whole line.
    @Test("A Return moves the text below it by exactly one line, in code and out",
          arguments: [
              ("code, mid block", "int a = 1;"),
              ("code, last line", "int c = 3;"),
              ("prose", "Prose before"),
              ("after a heading", "# Heading"),
              ("after the closing fence", "```\n"),
          ])
    func returnAddsOneLine(_ scenario: (String, String)) async throws {
        let note = "# Heading\nProse before\n```cpp\nint a = 1;\nint b = 2;\nint c = 3;\n```\nProse after\nmore\n"
        let harness = CodeFenceDisplayTests.Harness(note)
        try await harness.settle()
        let lineHeight = NoteTypography.standard.codeLineHeight

        let anchor = scenario.1
        try await harness.caret(at: harness.offset(of: anchor) + (anchor as NSString).length - (anchor.hasSuffix("\n") ? 1 : 0))
        var below = try Self.top(of: "Prose after", in: harness)

        for press in 1...3 {
            Self.press(harness, backspace: false)
            harness.layOut()
            try await harness.settle()
            let moved = try Self.top(of: "Prose after", in: harness)
            #expect(abs((moved - below) - lineHeight) < 0.01,
                    "\(scenario.0): press \(press) moved the text below by \(moved - below), not \(lineHeight)")
            below = moved
        }
    }

    @Test("A Return in an unclosed block adds one line and leaves the panel's end where a line puts it")
    func unclosedBlock() async throws {
        let harness = CodeFenceDisplayTests.Harness("Intro\n```cpp\nint a = 1;")
        try await harness.settle()
        try await harness.caret(at: harness.source.length)
        let lines = CodeBlockRoomTests.lines(of: harness.textView)
        let before = try #require(lines.last).frame.maxY

        Self.press(harness, backspace: false)
        harness.layOut()
        try await harness.settle()
        let after = try #require(CodeBlockRoomTests.lines(of: harness.textView).last).frame.maxY
        #expect(abs((after - before) - NoteTypography.standard.codeLineHeight) < 0.01)
    }

    // MARK: Every press registers

    /// Presses made back to back, with nothing laid out or settled between
    /// them: each must change the text and move the caret. A key the
    /// coordinator turned away, or an edit it applied to nothing, would fail
    /// here; the dropped keys on the iPad did not reproduce this way.
    @Test("Every held Return and Backspace changes the text and moves the caret",
          arguments: [
              ("prose Return", "Intro\nsome words\nend\n", "some words", false),
              ("heading Return", "# Title\nbody\n", "# Title", false),
              ("Return after bold", "a **bold**\nend\n", "**bold**", false),
              ("code Return", "```cpp\nint f() {\n    return 1;\n}\n```\nafter\n", "return 1;", false),
              ("code Return after a brace", "```cpp\nint f() {\n}\n```\nafter\n", "int f() {", false),
              ("unclosed code Return", "```cpp\nint a;", "int a;", false),
              ("Return on blank lines", "a\n\n\n\nb\n", "a\n\n", false),
              ("prose Backspace", "Intro\nsome words here to delete\nend\n", "delete", true),
              ("Backspace through blank lines", "x\n\n\n\n\n\n\n\nend\n", "x\n\n\n\n\n\n\n", true),
              ("Backspace in code", "```cpp\nint f() {\n\n\n\n\n\n    return 1;\n}\n```\nafter\n", "{\n\n\n\n\n", true),
              ("Backspace in bold", "a **bold word here** z\nend\n", "here**", true),
              ("Backspace in a heading", "# Title text here\nbody\n", "here", true),
          ])
    func everyPressRegisters(_ scenario: (String, String, String, Bool)) async throws {
        let (label, note, anchor, backspace) = scenario
        let harness = CodeFenceDisplayTests.Harness(note)
        try await harness.settle()
        try await harness.caret(at: harness.offset(of: anchor) + (anchor as NSString).length)

        for press in 1...6 {
            let length = harness.textView.textStorage.length
            let caret = harness.textView.selectedRange.location
            Self.press(harness, backspace: backspace)
            let changed = backspace
                ? harness.textView.textStorage.length < length
                : harness.textView.textStorage.length > length
            let moved = backspace
                ? harness.textView.selectedRange.location < caret
                : harness.textView.selectedRange.location > caret
            #expect(changed && moved, "\(label): press \(press) did not register")
        }
    }
}

#endif
