//
//  SyntaxMarkTests.swift
//  NoteCodeTests
//
//  2T3 (feature-audit A11): a highlighted run is told apart by the
//  `.noteCodeSyntax` attribute, not by its colour. So a token a theme
//  colours exactly `.label` still counts as highlighted, and text that is
//  not highlighted never does, whatever its colour.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Syntax colour marks", .tags(.editor))
@MainActor
struct SyntaxMarkTests {

    nonisolated private static let note = "Notes\n```cpp\nint value = 1;\n```\nAfter the block.\n"

    private func openNote() async -> EditorHarness {
        let harness = EditorHarness(Self.note, style: .light)
        harness.coordinator.restyle(harness.textView)
        await harness.coordinator.highlightingFinished()
        return harness
    }

    private func marked(_ offset: Int, in harness: EditorHarness) -> Bool {
        harness.textView.textStorage.attribute(.noteCodeSyntax, at: offset, effectiveRange: nil) != nil
    }

    @Test("Highlighted code is marked; prose and the fences are not")
    func markedWhereHighlighted() async {
        let harness = await openNote()

        #expect(marked(harness.offset(of: "int value"), in: harness))
        #expect(!marked(harness.offset(of: "Notes"), in: harness))
        #expect(!marked(harness.offset(of: "```cpp"), in: harness))
        #expect(!marked(harness.offset(of: "After"), in: harness))
    }

    @Test("A token the theme colours exactly .label is still highlighted: marked, kept across a restyle, and carried to the next character")
    func labelColouredTokenCounts() async {
        let harness = await openNote()
        let value = NSRange(location: harness.offset(of: "value"), length: 5)

        DocumentStyler.applyColors(
            [ColorRun(range: value, color: .label)], clearing: [value], to: harness.textView)
        #expect(marked(value.location, in: harness))

        // A restyle of every block wipes the attributes and puts the
        // highlighted runs back.
        harness.coordinator.invalidateStyling()
        harness.coordinator.restyle(harness.textView)
        #expect(marked(value.location, in: harness))
        #expect(harness.textView.textStorage.attribute(.foregroundColor, at: value.location, effectiveRange: nil) as? UIColor == .label)

        // The caret after it: what is typed next takes the mark.
        harness.textView.selectedRange = NSRange(location: NSMaxRange(value), length: 0)
        harness.coordinator.restyle(harness.textView)
        DocumentStyler.applyTypingAttributes(
            to: harness.textView, source: harness.textView.text, blocks: harness.coordinator.snapshot(of: harness.textView).blocks)
        #expect(harness.textView.typingAttributes[.noteCodeSyntax] != nil)
    }

    @Test("Text with a colour but no mark is not highlighted: it is not carried across a restyle")
    func colourAloneIsNotASyntaxColour() async {
        let harness = await openNote()
        let value = NSRange(location: harness.offset(of: "value"), length: 5)
        let storage = harness.textView.textStorage
        storage.addAttribute(.foregroundColor, value: UIColor.systemPink, range: value)
        storage.removeAttribute(.noteCodeSyntax, range: value)

        harness.coordinator.invalidateStyling()
        harness.coordinator.restyle(harness.textView)

        #expect(storage.attribute(.foregroundColor, at: value.location, effectiveRange: nil) as? UIColor == .label)
    }
}

#endif
