//
//  CaretAnywhereTests.swift
//  NoteCodeTests
//
//  A tap below the note's last line adds the lines it takes to reach it.
//

#if canImport(UIKit)

import Testing
import UIKit

@testable import NoteCode

@Suite("Caret anywhere: a tap below the text")
@MainActor
struct CaretAnywhereTests {

    @Test("The lines a tap asks for")
    func newlines() {
        // A 22pt line ending at 100.
        func n(_ y: CGFloat) -> Int { CaretAnywhere.newlines(tapY: y, lineBottom: 100, lineHeight: 22) }
        #expect(n(50) == 0)
        #expect(n(100) == 0)
        #expect(n(100.5) == 1)
        #expect(n(122) == 1)
        #expect(n(122.5) == 2)
        #expect(n(10_000) == CaretAnywhere.maximumLines)
        #expect(CaretAnywhere.newlines(tapY: 500, lineBottom: 100, lineHeight: 0) == 0)
    }

    /// The line the caret stands on, from the note's end.
    static func caretLine(_ harness: CodeFenceDisplayTests.Harness) -> ClosedRange<CGFloat> {
        let rect = harness.textView.lineCaretRect(for: harness.textView.endOfDocument)
        return (rect.minY + CaretHeight.above)...(rect.maxY - CaretHeight.below)
    }

    static let endings: [(String, String)] = [
        ("prose, no newline", "Intro\nPara"),
        ("prose, newline", "Intro\nPara\n"),
        ("prose, blank lines", "Intro\nPara\n\n\n"),
        ("heading", "Intro\n# Heading"),
        ("closed block", "Intro\n```cpp\nint a = 1;\n```"),
        ("closed block, newline", "Intro\n```cpp\nint a = 1;\n```\n"),
        ("unclosed block", "Intro\n```cpp\nint a = 1;"),
    ]

    @Test("A tap k lines below the end puts the caret on that line, at the end of the note",
          arguments: endings, [1.0, 2.5, 6.0])
    func reachesTheTap(_ ending: (String, String), lines: Double) async throws {
        let harness = CodeFenceDisplayTests.Harness(ending.1)
        try await harness.settle()
        let lineHeight = NoteTypography.standard.codeLineHeight
        let bottom = try #require(harness.textView.lastLineBottom(blankLineHeight: lineHeight))
        let point = CGPoint(x: 200, y: bottom + lines * lineHeight - 3)

        #expect(harness.coordinator.isEmptySpace(at: point, in: harness.textView))
        harness.coordinator.extendNote(toReach: point, in: harness.textView)
        harness.layOut()

        let line = Self.caretLine(harness)
        #expect(line.contains(point.y), "\(ending.0): the caret's line \(line) misses the tap at \(point.y)")
        #expect(harness.textView.selectedRange == NSRange(location: harness.textView.textStorage.length, length: 0))
        #expect((harness.textView.text as NSString).hasPrefix(ending.1))
    }

    @Test("A tap on the text, or beside it, adds nothing")
    func textIsLeftAlone() async throws {
        let harness = CodeFenceDisplayTests.Harness("Intro\nPara\n")
        try await harness.settle()
        let rect = harness.rect(of: "Para")
        for point in [CGPoint(x: rect.midX, y: rect.midY), CGPoint(x: 700, y: rect.midY), CGPoint(x: 5, y: 40)] {
            #expect(!harness.coordinator.isEmptySpace(at: point, in: harness.textView))
        }
        harness.coordinator.extendNote(toReach: CGPoint(x: 700, y: rect.midY), in: harness.textView)
        #expect(harness.stored == "Intro\nPara\n")
    }

    @Test("Ink mode and a locked note leave the empty space alone")
    func notWhenNotEditing() async throws {
        let lineHeight = NoteTypography.standard.codeLineHeight
        for (label, setUp) in [
            ("ink", { (h: CodeFenceDisplayTests.Harness) in h.editor.setMode(.ink) }),
            ("locked", { (h: CodeFenceDisplayTests.Harness) in h.editor.setTextLocked(true) }),
        ] {
            let harness = CodeFenceDisplayTests.Harness("Intro\nPara")
            try await harness.settle()
            setUp(harness)
            let bottom = try #require(harness.textView.lastLineBottom(blankLineHeight: lineHeight))
            let point = CGPoint(x: 200, y: bottom + 3 * lineHeight)
            #expect(!harness.coordinator.isEmptySpace(at: point, in: harness.textView), "\(label)")
            harness.coordinator.extendNote(toReach: point, in: harness.textView)
            #expect(harness.textView.textStorage.string == "Intro\nPara", "\(label)")
        }
    }

    @Test("The lines are one undo step")
    func undoIsOneStep() async throws {
        let harness = CodeFenceDisplayTests.Harness("Intro\nPara")
        try await harness.settle()
        let lineHeight = NoteTypography.standard.codeLineHeight
        let bottom = try #require(harness.textView.lastLineBottom(blankLineHeight: lineHeight))
        harness.coordinator.extendNote(toReach: CGPoint(x: 200, y: bottom + 4.5 * lineHeight), in: harness.textView)
        #expect(harness.textView.textStorage.length > "Intro\nPara".count)

        try await Task.sleep(for: .milliseconds(50))
        harness.textView.undoManager?.undo()
        #expect(harness.textView.textStorage.string == "Intro\nPara")
    }

    @Test("A tap on a code block's buttons is theirs, and the gesture asks the same question")
    func barsStayTheirs() async throws {
        let harness = CodeFenceDisplayTests.Harness("Intro\n```cpp\nint a = 1;\n```")
        try await harness.settle()
        let lineHeight = NoteTypography.standard.codeLineHeight
        let overlay = try #require(harness.textView.overlay)
        let button = try #require(harness.textView.subviews.compactMap { $0 as? CodeBlockActionBar }.first)

        let onBar = CGPoint(x: button.frame.midX, y: button.frame.midY)
        #expect(overlay.containsInteractiveElement(at: onBar))
        #expect(!harness.coordinator.isEmptySpace(at: onBar, in: harness.textView))

        let bottom = try #require(harness.textView.lastLineBottom(blankLineHeight: lineHeight))
        let below = CGPoint(x: button.frame.midX, y: bottom + 2 * lineHeight)
        let gestures = try #require(harness.textView.markerGestures)
        #expect(gestures.isEmptySpace?(below) == true)
        #expect(gestures.isEmptySpace?(onBar) == false)
        #expect(gestures.emptySpaceTap != nil)
    }
}

#endif
