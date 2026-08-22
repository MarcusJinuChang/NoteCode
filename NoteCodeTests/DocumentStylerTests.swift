//
//  DocumentStylerTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Document styling")
@MainActor
struct DocumentStylerTests {

    /// prose\n```cpp\nint x;\n```\nafter
    private static let source = "prose\n```cpp\nint x;\n```\nafter"

    private func styledTextView(_ source: String = DocumentStylerTests.source) -> UITextView {
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.text = source
        DocumentStyler.applyStyling(to: textView)
        return textView
    }

    private func font(_ textView: UITextView, at offset: Int) -> UIFont? {
        textView.textStorage.attribute(.font, at: offset, effectiveRange: nil) as? UIFont
    }

    @Test("Prose is styled with the body font")
    func proseUsesBodyFont() {
        let textView = styledTextView()
        #expect(font(textView, at: 0) == DocumentStyler.proseFont)
    }

    @Test("Code is styled with the monospaced font")
    func codeUsesMonospacedFont() {
        let textView = styledTextView()

        // Offset of "int x;" — after "prose\n```cpp\n".
        let offset = ("prose\n```cpp\n" as NSString).length
        #expect(font(textView, at: offset) == DocumentStyler.codeFont)
    }

    @Test("The fence lines themselves are styled as part of the block")
    func fenceLinesAreStyledAsCode() {
        let textView = styledTextView()

        let openingFence = ("prose\n" as NSString).length
        #expect(font(textView, at: openingFence) == DocumentStyler.codeFont)
    }

    @Test("Prose after a closing fence returns to the body font")
    func proseAfterBlockIsNotCode() {
        let textView = styledTextView()

        let offset = ("prose\n```cpp\nint x;\n```\n" as NSString).length
        #expect(font(textView, at: offset) == DocumentStyler.proseFont)
    }

    @Test("Nothing carries a glyph-level background colour")
    func noGlyphBackgrounds() {
        let textView = styledTextView()
        let storage = textView.textStorage

        // The code panel is drawn by CodeBlockLayoutFragment, not by a
        // .backgroundColor attribute — that one paints per glyph and leaves a
        // ragged right edge. If this starts failing, the two are fighting.
        let codeOffset = ("prose\n```cpp\n" as NSString).length

        #expect(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
        #expect(storage.attribute(.backgroundColor, at: codeOffset, effectiveRange: nil) == nil)
    }

    @Test("An unclosed fence styles everything after it as code")
    func unclosedFenceStylesToEnd() {
        let textView = styledTextView("notes\n```py\nprint(1)")

        let lastOffset = ("notes\n```py\nprint(1)" as NSString).length - 1
        #expect(font(textView, at: lastOffset) == DocumentStyler.codeFont)
    }

    @Test("Typing attributes follow the caret across a fence boundary")
    func typingAttributesFollowCaret() {
        let textView = styledTextView()
        let regions = FenceParser.parse(Self.source)

        // Caret inside the code block.
        textView.selectedRange = NSRange(location: ("prose\n```cpp\n" as NSString).length, length: 0)
        DocumentStyler.applyTypingAttributes(to: textView, regions: regions)
        #expect(textView.typingAttributes[.font] as? UIFont == DocumentStyler.codeFont)

        // Caret back in the prose above it.
        textView.selectedRange = NSRange(location: 0, length: 0)
        DocumentStyler.applyTypingAttributes(to: textView, regions: regions)
        #expect(textView.typingAttributes[.font] as? UIFont == DocumentStyler.proseFont)
    }

    @Test("A caret just past a closing fence types prose, not code")
    func caretAfterBlockTypesProse() {
        let textView = styledTextView()
        let regions = FenceParser.parse(Self.source)

        textView.selectedRange = NSRange(location: ("prose\n```cpp\nint x;\n```\n" as NSString).length, length: 0)
        DocumentStyler.applyTypingAttributes(to: textView, regions: regions)

        #expect(textView.typingAttributes[.font] as? UIFont == DocumentStyler.proseFont)
    }

    @Test("Styling an empty document does not crash")
    func emptyDocument() {
        let textView = styledTextView("")
        #expect(textView.textStorage.length == 0)
    }
}

#endif
