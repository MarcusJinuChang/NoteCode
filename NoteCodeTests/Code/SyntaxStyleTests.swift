//
//  SyntaxStyleTests.swift
//  NoteCodeTests
//
//  Syntax colours carry the theme's weight and italic: a keyword is bold and
//  a comment italic, in the code font at the code font's size, so a line is
//  never taller and the action bars never move.
//

#if canImport(UIKit)

import Testing
import UIKit
@testable import NoteCode

@Suite("Syntax weight and italic", .tags(.editor))
@MainActor
struct SyntaxStyleTests {

    nonisolated private static let note = "Notes\n```cpp\n// why\nint value = 1;\nreturn value;\n```\nAfter the block.\n"

    private func openNote() async -> EditorHarness {
        let harness = EditorHarness(Self.note, style: .light)
        harness.coordinator.restyle(harness.textView)
        await harness.coordinator.highlightingFinished()
        return harness
    }

    private func font(at offset: Int, in harness: EditorHarness) -> UIFont {
        harness.textView.textStorage.attribute(.font, at: offset, effectiveRange: nil) as! UIFont
    }

    private func traits(_ font: UIFont) -> UIFontDescriptor.SymbolicTraits {
        font.fontDescriptor.symbolicTraits
    }

    @Test("A keyword is bold and a comment italic; a plain token is neither")
    func traitsFollowTheTheme() async {
        let harness = await openNote()
        let keyword = font(at: harness.offset(of: "return"), in: harness)
        let comment = font(at: harness.offset(of: "why"), in: harness)
        let plain = font(at: harness.offset(of: "value"), in: harness)

        #expect(traits(keyword).contains(.traitBold))
        #expect(!traits(keyword).contains(.traitItalic))
        #expect(traits(comment).contains(.traitItalic))
        #expect(!traits(plain).contains(.traitBold))
        #expect(!traits(plain).contains(.traitItalic))
    }

    @Test("Styled tokens stay monospaced, at the code font's size and line height")
    func sizeAndHeightUnchanged() async {
        let harness = await openNote()
        let code = DocumentStyler.codeFont

        for needle in ["return", "why"] {
            let styled = font(at: harness.offset(of: needle), in: harness)
            #expect(traits(styled).contains(.traitMonoSpace), "\(needle)")
            #expect(styled.pointSize == code.pointSize, "\(needle)")
            #expect(styled.lineHeight == code.lineHeight, "\(needle)")
        }
    }

    @Test("A restyle keeps the weight and italic")
    func restyleKeepsTraits() async {
        let harness = await openNote()
        harness.coordinator.invalidateStyling()
        harness.coordinator.restyle(harness.textView)

        #expect(traits(font(at: harness.offset(of: "return"), in: harness)).contains(.traitBold))
        #expect(traits(font(at: harness.offset(of: "why"), in: harness)).contains(.traitItalic))
    }

    @Test("A fresh pass over a block clears the traits it no longer has")
    func clearingResetsFont() async {
        let harness = await openNote()
        let range = NSRange(location: harness.offset(of: "return"), length: 6)

        DocumentStyler.applyColors([], clearing: [range], to: harness.textView)
        #expect(font(at: range.location, in: harness) == DocumentStyler.codeFont)
    }
}

#endif
