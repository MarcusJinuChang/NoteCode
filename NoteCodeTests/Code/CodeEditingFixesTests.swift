//
//  CodeEditingFixesTests.swift
//  NoteCodeTests
//
//  13 Oct bug list: Backspace in a code line's indent, a block with no
//  language going back to plain colours, and a tap past the end of a line
//  that ends in bold text.
//

#if canImport(UIKit)

import Foundation
import Testing
import UIKit
@testable import NoteCode

@Suite("Code editing fixes")
@MainActor
struct CodeEditingFixesTests {

    // MARK: Backspace in the indent

    /// A note holding `body` in a fenced block, caret marked with ‸.
    private static func note(_ body: String, tag: String = "cpp") -> (text: String, caret: Int) {
        var text = "Prose.\n```\(tag)\n" + body + "\n```\nAfter.\n"
        var location = 0
        if let mark = text.range(of: "‸") {
            location = (text[..<mark.lowerBound] as Substring).utf16.count
            text.removeSubrange(mark)
        }
        return (text, location)
    }

    /// What Backspace leaves the body as, caret marked, or `nil` for the
    /// ordinary one-character delete.
    private static func backspace(_ body: String, width: Int = 4, tag: String = "cpp") -> String? {
        let (text, caret) = note(body, tag: tag)
        guard let edit = CodeIndent.backspaceEdit(
            in: text as NSString, caret: caret, codeRanges: DocumentCache().codeRanges(for: text), width: width
        ) else { return nil }
        var result = edit.applied(to: text) as NSString
        result = result.replacingCharacters(in: NSRange(location: edit.selection.location, length: 0), with: "‸") as NSString
        let head = "Prose.\n```\(tag)\n"
        return String((result as String).dropFirst(head.count)).components(separatedBy: "\n```\nAfter.\n")[0]
    }

    @Test("Backspace in an indent takes back one level", arguments: [
        // A whole level at once, to the left edge.
        ("    ‸int x;", 4, "‸int x;"),
        ("        ‸int x;", 4, "    ‸int x;"),
        // To the previous multiple of the width, not by the width.
        ("      ‸int x;", 4, "    ‸int x;"),
        ("  ‸int x;", 4, "‸int x;"),
        ("    ‸int x;", 2, "  ‸int x;"),
        ("      ‸x", 2, "    ‸x"),
        // The caret in the middle of an indent.
        ("      ‸  x", 4, "    ‸  x"),
        // A line of only whitespace.
        ("        ‸", 4, "    ‸"),
        ("    ‸return x", 4, "‸return x"),
    ])
    func levels(body: String, width: Int, expected: String) {
        #expect(Self.backspace(body, width: width) == expected)
    }

    @Test("Backspace anywhere else is the ordinary delete", arguments: [
        "int x;‸",                // not in an indent
        "    int‸ x;",            // after text
        "    int x;‸",
        " ‸int x;",               // one space is one character
        "     ‸int x;",           // five: one space over a level is one character
        "‸    int x;",            // the line's first column
        "\t‸int x;",              // one tab is one level already
        "\t\t‸int x;",
        "\t  ‸int x;",            // mixed: not spaces all the way back
    ])
    func ordinary(body: String) {
        #expect(Self.backspace(body) == nil)
    }

    @Test("Backspace in prose, on a fence line and in an output block is the ordinary delete")
    func notInCode() {
        let prose = "Prose.\n    indented prose\n"
        let proseCaret = (prose as NSString).range(of: "indented").location
        #expect(CodeIndent.backspaceEdit(
            in: prose as NSString, caret: proseCaret, codeRanges: DocumentCache().codeRanges(for: prose), width: 4
        ) == nil)

        let output = "```output\n    ok\n```\n"
        let outputCaret = (output as NSString).range(of: "ok").location
        #expect(CodeIndent.backspaceEdit(
            in: output as NSString, caret: outputCaret, codeRanges: DocumentCache().codeRanges(for: output), width: 4
        ) == nil)

        let fence = "```cpp\n    x\n```\n"
        #expect(CodeIndent.backspaceEdit(
            in: fence as NSString, caret: 6, codeRanges: DocumentCache().codeRanges(for: fence), width: 4
        ) == nil)
    }

    @Test("In the editor, one Backspace removes a level and one undo puts it back")
    func inTheEditor() async throws {
        let harness = CodeFenceDisplayTests.Harness("```cpp\nint main() {\n        x;\n}\n```\n")
        let start = harness.offset(of: "x;")
        try await harness.caret(at: start)
        let textView = harness.textView

        // What the keyboard sends for Backspace: a one-character replacement
        // by nothing, ending at the caret.
        let range = NSRange(location: start - 1, length: 1)
        #expect(!harness.coordinator.textView(textView, shouldChangeTextIn: range, replacementText: ""),
                "the coordinator takes Backspace and makes the edit itself")
        #expect(textView.text.contains("\n    x;\n"), "eight spaces became four")
        #expect(textView.selectedRange == NSRange(location: start - 4, length: 0))

        textView.undoManager?.undo()
        #expect(textView.text.contains("\n        x;\n"), "one undo puts the level back")
    }

    // MARK: Plain colours

    @Test("A block whose language is deleted goes back to plain colours",
          arguments: [UIUserInterfaceStyle.light, .dark])
    func plainAfterTheTagGoes(style: UIUserInterfaceStyle) async throws {
        let source = "```python\ndef f(x): return x\n```\n"
        let harness = CodeFenceDisplayTests.Harness(source, style: style)
        // As in `OutputBlockTests.retagRecolours`: the harness's window
        // applies its appearance after the first restyle.
        harness.coordinator.restyle(harness.textView)
        try await harness.caret(at: harness.source.length)
        try await harness.settle()
        func colour(_ text: String) -> UIColor? {
            harness.textView.textStorage.attribute(.foregroundColor, at: harness.offset(of: text), effectiveRange: nil) as? UIColor
        }
        #expect(colour("def f") != UIColor.label, "python colours def")

        let target = try #require(CodeBlockAction.targets(in: source, blocks: DocumentParser.parse(source)).first)
        harness.coordinator.setKind(.plain, of: target, in: harness.textView)
        try await harness.settle()
        try await harness.settle()
        #expect(harness.textView.text.hasPrefix("```\n"), "the tag went")
        #expect(colour("def f") == UIColor.label, "no language, no colour")
        #expect(colour("return") == UIColor.label)
    }

    @Test("Deleting the tag by hand does the same")
    func deletingTheTag() async throws {
        let harness = CodeFenceDisplayTests.Harness("```python\ndef f(x): return x\n```\n", style: .light)
        harness.coordinator.restyle(harness.textView)
        try await harness.caret(at: harness.source.length)
        try await harness.settle()

        let tag = (harness.textView.text as NSString).range(of: "python")
        harness.textView.selectedRange = NSRange(location: NSMaxRange(tag), length: 0)
        for _ in 0..<tag.length { harness.textView.deleteBackward() }
        harness.coordinator.textViewDidChange(harness.textView)
        try await harness.settle()
        try await harness.settle()

        let at = (harness.textView.text as NSString).range(of: "def f").location
        let colour = harness.textView.textStorage.attribute(.foregroundColor, at: at, effectiveRange: nil) as? UIColor
        #expect(harness.textView.text.hasPrefix("```\n"))
        #expect(colour == UIColor.label)
    }

    // MARK: Tapping past the end of bold text

    @Test("A tap in the empty space after a line that ends in bold puts the caret at the line's end, after its markers")
    func tapAfterBold() throws {
        let harness = CodeFenceDisplayTests.Harness("A line ending in **bold**\nNext line\n")
        harness.coordinator.setRendersMarkdown(true, in: harness.textView)
        harness.layOut()
        let textView = harness.textView
        let text = textView.textStorage.string as NSString
        let bold = text.range(of: "**bold**")
        let lineEnd = NSMaxRange(bold)

        let end = try #require(textView.position(from: textView.beginningOfDocument, offset: lineEnd))
        let caret = textView.caretRect(for: end)

        // Out in the margin of the line.
        let past = try #require(textView.closestPosition(to: CGPoint(x: caret.midX + 120, y: caret.midY)))
        #expect(textView.offset(from: textView.beginningOfDocument, to: past) == lineEnd)

        // On the last letter: inside the bold, in front of its markers, as before.
        let on = try #require(textView.closestPosition(to: CGPoint(x: caret.midX - 4, y: caret.midY)))
        let onOffset = textView.offset(from: textView.beginningOfDocument, to: on)
        #expect(onOffset < lineEnd, "a tap on the word stays in the word")
        #expect(onOffset > bold.location + 1)
    }

    @Test("The same for a link at the end of a line")
    func tapAfterLink() throws {
        let harness = CodeFenceDisplayTests.Harness("See [the notes](https://example.com)\nNext line\n")
        harness.coordinator.setRendersMarkdown(true, in: harness.textView)
        harness.layOut()
        let textView = harness.textView
        let text = textView.textStorage.string as NSString
        let lineEnd = NSMaxRange(text.range(of: "(https://example.com)"))

        let end = try #require(textView.position(from: textView.beginningOfDocument, offset: lineEnd))
        let caret = textView.caretRect(for: end)
        let past = try #require(textView.closestPosition(to: CGPoint(x: caret.midX + 120, y: caret.midY)))
        #expect(textView.offset(from: textView.beginningOfDocument, to: past) == lineEnd)
    }
}

#endif
