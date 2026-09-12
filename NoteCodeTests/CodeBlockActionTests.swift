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

@Suite("Finding the code block an action applies to")
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

    // MARK: Locating every block

    private static func targets(in source: String) -> [CodeBlockTarget] {
        CodeBlockAction.targets(in: source, blocks: DocumentParser.parse(source))
    }

    @Test("Prose contributes no targets")
    func proseHasNoTargets() {
        #expect(Self.targets(in: "just notes\nand more notes\n").isEmpty)
    }

    @Test("Each block's range starts at its opening fence")
    func rangesStartAtTheFence() {
        let source = "notes\n```cpp\nint x;\n```\nafter\n```py\nprint(1)\n```\n"
        let found = Self.targets(in: source)

        #expect(found.count == 2)
        #expect(found[0].range.location == ("notes\n" as NSString).length)
        #expect(found[1].range.location == ("notes\n```cpp\nint x;\n```\nafter\n" as NSString).length)
    }

    /// The overlay matches a block to its first layout fragment by comparing
    /// offsets, so a range that starts a character off puts the buttons on the
    /// wrong line — or on no line at all.
    @Test("A block's range covers its fences and nothing after them")
    func rangesCoverTheWholeBlock() {
        let source = "notes\n```cpp\nint x;\n```\nafter\n"
        let target = Self.targets(in: source)[0]
        let covered = (source as NSString).substring(with: target.range)

        #expect(covered == "```cpp\nint x;\n```\n")
    }

    @Test("Offsets are UTF-16, so text above a block can be any script")
    func offsetsAreUTF16() {
        // An emoji is two UTF-16 units and one Character; counting Characters
        // would put the block two units early.
        let prefix = "notes 🎉\n"
        let source = prefix + "```py\nprint(1)\n```\n"

        #expect(Self.targets(in: source)[0].range.location == (prefix as NSString).length)
    }

    @Test("The code a target carries excludes the fence lines")
    func targetCodeExcludesFences() {
        let target = Self.targets(in: "```cpp\nint x;\n```\n")[0]

        #expect(target.code == "int x;\n")
    }

    @Test("A recognised tag becomes a language, an unknown one does not")
    func targetLanguages() {
        let source = "```cpp\na\n```\n```rust\nb\n```\n```\nc\n```\n"
        let found = Self.targets(in: source)

        #expect(found.map(\.language) == [.cpp, nil, nil])
    }

    @Test("An unclosed block is still a target")
    func unclosedBlockIsATarget() {
        let found = Self.targets(in: "notes\n```py\nprint(1)")

        #expect(found.count == 1)
        #expect(found[0].code == "print(1)")
    }

    @Test("Targets come back in document order")
    func targetsAreOrdered() {
        let source = "```py\na\n```\n```py\nb\n```\n```py\nc\n```\n"
        let found = Self.targets(in: source)

        #expect(found.map(\.code) == ["a\n", "b\n", "c\n"])
        #expect(found.map(\.range.location) == found.map(\.range.location).sorted())
    }
}
