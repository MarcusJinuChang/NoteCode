//
//  CodeBlockActionTests.swift
//  NoteCodeTests
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Finding the code block an action applies to", .tags(.editor))
struct CodeBlockActionTests {

    // MARK: Locating every block

    private static func targets(in source: String) -> [CodeBlockTarget] {
        DocumentSnapshot(text: source).targets
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
        let source = "```cpp\na\n```\n```ruby\nb\n```\n```\nc\n```\n"
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
