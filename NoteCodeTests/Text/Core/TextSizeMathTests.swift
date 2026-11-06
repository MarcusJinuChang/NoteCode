//
//  TextSizeMathTests.swift
//  NoteCodeTests
//
//  The size control's arithmetic (`TextSizeMath`), with no editor in the loop.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Size arithmetic", .tags(.pure))
struct TextSizeMathTests {

    @Test("Stepping stops at 8 and 72, and text past them steps back towards them")
    func ends() {
        #expect(TextSizeMath.stepped(72, by: 1) == nil)
        #expect(TextSizeMath.stepped(8, by: -1) == nil)
        #expect(TextSizeMath.stepped(71, by: 1) == 72)
        #expect(TextSizeMath.stepped(97, by: -1) == 96)
        #expect(TextSizeMath.stepped(97, by: 1) == nil)
        #expect(TextSizeMath.stepped(7, by: 1) == 8)
        #expect(TextSizeMath.stepped(24.5, by: 1) == 25.5)
    }

    @Test("A typed size: a number, pt or not, clamped and to the half point", arguments: [
        ("24", 24.0), ("24.5pt", 24.5), (" 30 pt ", 30), ("24,5", 24.5), ("24.3", 24.5), ("100", 72), ("3", 8),
    ] as [(String, Double)])
    func typed(text: String, points: Double) {
        #expect(TextSizeMath.points(typed: text) == points)
    }

    @Test("Not a number sets nothing", arguments: ["", "big", "pt", "nan", "inf"])
    func notTyped(text: String) {
        #expect(TextSizeMath.points(typed: text) == nil)
    }

    @Test("A caret before an edit stays, one after it moves by the change, one inside what changed has no place")
    func offsetThroughEdit() {
        let edit = TextEdit(range: NSRange(location: 10, length: 6), replacement: "<b>abcdef</b>", selection: NSRange(location: 0, length: 0))
        #expect(TextSizeMath.offset(4, through: edit, replacing: "abcdef") == 4)
        #expect(TextSizeMath.offset(16, through: edit, replacing: "abcdef") == 16 + 7)
        #expect(TextSizeMath.offset(12, through: edit, replacing: "abcdef") == nil)
    }
}
