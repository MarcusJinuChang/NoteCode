//
//  RepeatedHelpersTests.swift
//  NoteCodeTests
//
//  2T9: the helpers that replaced hand-written copies.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Repeated helpers", .tags(.pure))
struct RepeatedHelpersTests {

    // MARK: Tag

    @Test("tag(of:) is the first space-separated word")
    func tagOfInfo() {
        #expect(CodeBlock.tag(of: "cpp") == "cpp")
        #expect(CodeBlock.tag(of: "python title=x") == "python")
        #expect(CodeBlock.tag(of: "  java") == "java")
        #expect(CodeBlock.tag(of: "") == nil)
        #expect(CodeBlock.tag(of: "   ") == nil)
    }

    @Test("a parsed block's tag, isOutput and hasLanguageTag agree with its info string")
    func blockTag() throws {
        let source = "```Python x\nprint(1)\n```\n\n```output\n1\n```\n\n```\nplain\n```\n"
        let blocks = DocumentParser.parse(source).compactMap(\.codeBlock)
        try #require(blocks.count == 3)
        #expect(blocks[0].tag == "Python")
        #expect(blocks[0].hasLanguageTag && !blocks[0].isOutput)
        #expect(blocks[1].tag == "output" && blocks[1].isOutput)
        #expect(blocks[2].tag == nil && !blocks[2].hasLanguageTag)
    }

    // MARK: Newline

    @Test("UTF16Unit.newline is a line feed")
    func newline() {
        #expect(UTF16Unit.newline == 10)
        #expect(("a\nb" as NSString).character(at: 1) == UTF16Unit.newline)
        #expect(MarkdownFormatting.newline == UTF16Unit.newline)
    }

    // MARK: Fence

    @Test("wrapping fences text, longer than any backtick run inside it")
    func wrapping() {
        #expect(CodeFence.wrapping("plain", tag: "output") == "```output\nplain\n```")
        #expect(CodeFence.wrapping("a ``` b", tag: "output") == "````output\na ``` b\n````")
        #expect(CodeFence.wrapping("x", tag: "") == "```\nx\n```")
        #expect(CodeFence.wrapping("``````", tag: "output").hasPrefix("```````output\n"))
    }

    // MARK: Code-range lookups

    @Test("block(atCaret:) follows CodeRange.contains: the closing line yes, the line after no")
    func blockAtCaret() {
        let ranges = [CodeRange(range: NSRange(location: 4, length: 12), isClosed: true, lastCaret: 14)]
        #expect(ranges.block(atCaret: 3) == nil)
        #expect(ranges.block(atCaret: 4) == ranges[0])
        #expect(ranges.block(atCaret: 14) == ranges[0])
        #expect(ranges.block(atCaret: 15) == nil)
        #expect(ranges.hasCode(atCaret: 10))
        #expect(![CodeRange]().hasCode(atCaret: 0))
    }

    @Test("an unclosed block holds a caret at the end of the note")
    func unclosed() {
        let ranges = [CodeRange(range: NSRange(location: 0, length: 9), isClosed: false, lastCaret: 9)]
        #expect(ranges.hasCode(atCaret: 9))
    }
}

#if canImport(UIKit)
import UIKit

@MainActor
@Suite("Text range helper", .tags(.pure))
struct TextRangeHelperTests {
    @Test("textRange(for:) covers the same UTF-16 span, nil outside the text")
    func textRangeFor() throws {
        let view = UITextView()
        view.text = "héllo 😀 world"
        let ns = view.text as NSString
        let range = NSRange(location: 6, length: 2)
        let found = try #require(view.textRange(for: range))
        #expect(view.text(in: found) == ns.substring(with: range))
        #expect(view.textRange(for: NSRange(location: 0, length: 0)) != nil)
        #expect(view.textRange(for: NSRange(location: ns.length + 5, length: 1)) == nil)
    }
}
#endif
