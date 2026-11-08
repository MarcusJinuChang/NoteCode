//
//  HeldFenceTests.swift
//  NoteCodeTests
//
//  A fence line half-typed inside a block doesn't close it
//  (`DocumentParser.heldFence`).
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Held fences", .tags(.pure))
struct HeldFenceTests {

    static let note = "Prose above.\n```cpp\nint a = 1;\n```\nint b = 2;\n```\nProse below."

    /// Where the bare fence inside the block is, in UTF-16.
    static var held: NSRange { (note as NSString).range(of: "```", options: [], range: NSRange(location: 15, length: 30)) }

    @Test("Unheld, a bare fence inside a block closes it")
    func unheldCloses() {
        let codes = DocumentParser.parse(Self.note).compactMap(\.codeBlock)
        #expect(codes.count == 2)
    }

    @Test("Held, the block runs past it to its own closing fence")
    func heldStaysOpen() throws {
        let source = Self.note
        let blocks = DocumentParser.parse(source, holdingOpen: String.Index(utf16Offset: Self.held.location, in: source))
        let codes = blocks.compactMap(\.codeBlock)
        try #require(codes.count == 1)
        #expect(String(source[codes[0].contentRange]) == "int a = 1;\n```\nint b = 2;\n")
        #expect(codes[0].isClosed)
        #expect(blocks.last.map { String(source[$0.range]) } == "Prose below.")
    }

    @Test("A snapshot parses with its held fence")
    func snapshot() {
        #expect(DocumentSnapshot(text: Self.note, heldFence: Self.held.location).codeRanges.count == 1)
        #expect(DocumentSnapshot(text: Self.note).codeRanges.count == 2)
    }

    @Test("The third backtick at a line's end holds the line")
    func thirdBacktick() {
        let note = Self.note as NSString
        let third = NSRange(location: Self.held.location + 2, length: 1)
        #expect(DocumentParser.heldFence(afterEditing: third, in: note) == Self.held)
        // A backspace at the end of ```s, leaving ```.
        #expect(DocumentParser.heldFence(afterEditing: NSRange(location: NSMaxRange(Self.held), length: 0), in: note) == Self.held)
    }

    @Test("Nothing is held for a tagged fence, a line break, an edit before the end, or prose")
    func notHeld() {
        let tagged = "```cpp\nx\n```swift\n" as NSString
        #expect(DocumentParser.heldFence(afterEditing: NSRange(location: 16, length: 1), in: tagged) == nil)
        let note = Self.note as NSString
        // Return after the fence.
        #expect(DocumentParser.heldFence(afterEditing: NSRange(location: NSMaxRange(Self.held), length: 1), in: note) == nil)
        // The first backtick of three.
        #expect(DocumentParser.heldFence(afterEditing: NSRange(location: Self.held.location, length: 1), in: note) == nil)
        #expect(DocumentParser.heldFence(afterEditing: NSRange(location: 11, length: 1), in: note) == nil)
    }
}
