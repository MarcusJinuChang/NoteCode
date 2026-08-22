//
//  CodeBlockPositionTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import Testing
import Foundation
@testable import NoteCode

@Suite("Code block position")
struct CodeBlockPositionTests {

    /// A block occupying UTF-16 offsets 10..<40.
    private let block = NSRange(location: 10, length: 30)

    @Test("A paragraph spanning the whole block is the only one")
    func wholeBlock() {
        #expect(CodeBlockPosition.of(element: NSRange(location: 10, length: 30), in: block) == .only)
    }

    @Test("A paragraph at the block's start is first")
    func firstParagraph() {
        #expect(CodeBlockPosition.of(element: NSRange(location: 10, length: 5), in: block) == .first)
    }

    @Test("A paragraph in the interior is middle")
    func middleParagraph() {
        #expect(CodeBlockPosition.of(element: NSRange(location: 20, length: 5), in: block) == .middle)
    }

    @Test("A paragraph reaching the block's end is last")
    func lastParagraph() {
        #expect(CodeBlockPosition.of(element: NSRange(location: 35, length: 5), in: block) == .last)
    }

    @Test("A paragraph running past the block's end still counts as last")
    func overhangingParagraph() {
        #expect(CodeBlockPosition.of(element: NSRange(location: 35, length: 20), in: block) == .last)
    }

    @Test("Paragraphs outside the block have no position", arguments: [
        NSRange(location: 0, length: 5),    // before
        NSRange(location: 40, length: 5),   // exactly at the end, i.e. past it
        NSRange(location: 60, length: 5),   // after
    ])
    func outsideBlock(element: NSRange) {
        #expect(CodeBlockPosition.of(element: element, in: block) == nil)
    }

    @Test("Only the outer edges round")
    func rounding() {
        #expect(CodeBlockPosition.only.roundsTop)
        #expect(CodeBlockPosition.only.roundsBottom)
        #expect(CodeBlockPosition.first.roundsTop)
        #expect(!CodeBlockPosition.first.roundsBottom)
        #expect(!CodeBlockPosition.last.roundsTop)
        #expect(CodeBlockPosition.last.roundsBottom)
        #expect(!CodeBlockPosition.middle.roundsTop)
        #expect(!CodeBlockPosition.middle.roundsBottom)
    }
}

#endif
