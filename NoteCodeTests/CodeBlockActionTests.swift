//
//  CodeBlockActionTests.swift
//  NoteCodeTests
//

import Foundation
import Testing
@testable import NoteCode

private func code(at offset: Int, in source: String) -> String? {
    CodeBlockAction.code(atCaret: offset, in: source, blocks: DocumentParser.parse(source))
}

@Suite("Copying a code block")
struct CodeBlockActionTests {

    private static let source = "notes\n```cpp\nint x = 0;\n```\nafter"

    @Test("The caret inside a block yields its code")
    func caretInsideBlock() {
        let offset = ("notes\n```cpp\n" as NSString).length
        #expect(code(at: offset, in: Self.source) == "int x = 0;\n")
    }

    @Test("The caret on a fence line still yields the block's code")
    func caretOnFenceLine() {
        // The fence is part of the block, so the action stays available there.
        let offset = ("notes\n" as NSString).length
        #expect(code(at: offset, in: Self.source) == "int x = 0;\n")
    }

    @Test("The fence lines are not included in what gets copied")
    func fenceLinesExcluded() {
        let copied = code(at: ("notes\n```cpp\n" as NSString).length, in: Self.source)

        #expect(copied?.contains("```") == false)
        #expect(copied?.contains("cpp") == false)
    }

    @Test("The caret in prose yields nothing", arguments: [0, 30])
    func caretInProse(offset: Int) {
        #expect(code(at: offset, in: Self.source) == nil)
    }

    @Test("An unclosed block still yields its code")
    func unclosedBlock() {
        let source = "notes\n```py\nprint(1)"
        #expect(code(at: (source as NSString).length - 1, in: source) == "print(1)")
    }

    @Test("The right block is picked when there are several")
    func picksTheRightBlock() {
        let source = "```cpp\nfirst();\n```\ntext\n```py\nsecond()\n```"
        let secondOffset = ("```cpp\nfirst();\n```\ntext\n```py\n" as NSString).length

        #expect(code(at: 7, in: source) == "first();\n")
        #expect(code(at: secondOffset, in: source) == "second()\n")
    }

    @Test("An empty document yields nothing")
    func emptyDocument() {
        #expect(code(at: 0, in: "") == nil)
    }
}
