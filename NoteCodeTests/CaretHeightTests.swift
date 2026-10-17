//
//  CaretHeightTests.swift
//  NoteCodeTests
//
//  The caret is as tall as the font it stands in, not the line: step 10's
//  code lines, fence lines and sized text are taller than their fonts.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("The caret's height")
@MainActor
struct CaretHeightTests {

    static let note = "Prose line here\n# Heading one\n```cpp\nint value = 1;\nint other = 2;\n```\nAfter <span style=\"font-size:1.5em\">big</span> text\n- item one\n"

    static func harness() -> CodeFenceDisplayTests.Harness {
        let harness = CodeFenceDisplayTests.Harness(note)
        harness.coordinator.setRendersMarkdown(true, in: harness.textView)
        harness.coordinator.invalidateStyling()
        harness.coordinator.restyle(harness.textView)
        harness.layOut()
        return harness
    }

    struct Carets {
        let caret: CGRect
        let line: CGRect
        let font: UIFont
    }

    static func carets(_ harness: CodeFenceDisplayTests.Harness, at needle: String, plus delta: Int) throws -> Carets {
        let textView = try #require(harness.textView as? DocumentUITextView)
        let offset = harness.offset(of: needle) + delta
        let position = try #require(textView.position(from: textView.beginningOfDocument, offset: offset))
        let font = try #require(textView.textStorage.attribute(.font, at: offset - 1, effectiveRange: nil) as? UIFont)
        return Carets(caret: textView.caretRect(for: position), line: textView.lineCaretRect(for: position), font: font)
    }

    /// What UIKit draws on a line that is its font's own height.
    static func naturalHeight(of font: UIFont) -> CGFloat {
        font.ascender - font.descender + font.leading + CaretHeight.above + CaretHeight.below
    }

    @Test("Prose, a heading and a list item keep UIKit's caret")
    func naturalLinesUnchanged() throws {
        let harness = Self.harness()
        for (needle, delta) in [("Prose line", 3), ("Heading one", 3), ("item one", 2)] {
            let carets = try Self.carets(harness, at: needle, plus: delta)
            #expect(abs(carets.caret.minY - carets.line.minY) < 0.01, "\(needle): \(carets.caret) against \(carets.line)")
            #expect(abs(carets.caret.height - carets.line.height) < 0.01, "\(needle): \(carets.caret) against \(carets.line)")
            #expect(carets.caret.minX == carets.line.minX)
        }
    }

    @Test("A code line's caret is the code's height, at the bottom of the taller line")
    func codeLine() throws {
        let harness = Self.harness()
        for (needle, delta) in [("int value", 3), ("other = 2;", 10)] {
            let carets = try Self.carets(harness, at: needle, plus: delta)
            #expect(abs(carets.caret.height - Self.naturalHeight(of: carets.font)) < 0.01, "\(needle): \(carets.caret)")
            #expect(carets.caret.height < carets.line.height - 3, "\(needle): \(carets.caret) against \(carets.line)")
            // Code's extra line height is above its glyphs, so the caret
            // still ends where UIKit's does.
            #expect(abs(carets.caret.maxY - carets.line.maxY) < 0.01)
        }
    }

    @Test("A fence line's caret is the code's height, beside the backticks in the header or footer")
    func fenceLines() throws {
        let harness = Self.harness()

        let opening = try Self.carets(harness, at: "```cpp", plus: 2)
        // The header has room for the code's own caret.
        #expect(abs(opening.caret.height - Self.naturalHeight(of: opening.font)) < 0.01, "\(opening.caret)")
        // UIKit's caret is the line, a point above and half a point below.
        let line = CGRect(
            x: opening.line.minX, y: opening.line.minY + CaretHeight.above,
            width: opening.line.width, height: opening.line.height - CaretHeight.above - CaretHeight.below
        )
        let header = CodeBlockRoom.header(ofFenceLine: line)
        #expect(header.contains(opening.caret), "\(opening.caret) in \(header)")
        #expect(abs(opening.caret.midY - header.midY) < 4, "\(opening.caret.midY) against \(header.midY)")

        // The footer is shallower than the code's caret, so the caret is the
        // footer, a point clear of each edge, and never in the gap below.
        let closing = try Self.carets(harness, at: "```\nAfter", plus: 1)
        let footer = CodeBlockRoom.footerHeight(font: closing.font)
        let footerTop = closing.line.minY + CaretHeight.above
        #expect(abs(closing.caret.minY - (footerTop + 1)) < 0.01, "\(closing.caret) in \(closing.line)")
        #expect(abs(closing.caret.height - (footer - 2)) < 0.01, "\(closing.caret)")
        #expect(closing.caret.maxY <= closing.line.maxY - CaretHeight.below - CodeBlockRoom.gapBelow)
    }

    @Test("On a line with larger text, the caret is the height of the text it stands in")
    func sizedText() throws {
        let harness = Self.harness()
        let small = try Self.carets(harness, at: "After", plus: 2)
        let large = try Self.carets(harness, at: "big", plus: 1)

        #expect(large.font.pointSize > small.font.pointSize)
        #expect(abs(small.caret.height - Self.naturalHeight(of: small.font)) < 0.01, "\(small.caret)")
        #expect(abs(large.caret.height - Self.naturalHeight(of: large.font)) < 0.01, "\(large.caret)")
        #expect(small.caret.height < small.line.height - 5)
        // One line, one baseline: each caret ends its own descent below it.
        let smallBaseline = small.caret.maxY - CaretHeight.below - small.font.leading + small.font.descender
        let largeBaseline = large.caret.maxY - CaretHeight.below - large.font.leading + large.font.descender
        #expect(abs(smallBaseline - largeBaseline) < 0.01)
    }
}

#endif
