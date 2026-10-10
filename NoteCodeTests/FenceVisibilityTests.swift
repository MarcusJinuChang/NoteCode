//
//  FenceVisibilityTests.swift
//  NoteCodeTests
//
//  Which code blocks show their backticks, and how a language pick rewrites
//  a fence. Pure: the ranges come from the real parser.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Fence visibility")
struct FenceVisibilityTests {

    /// The note's code blocks, as the editor works them out.
    private static func ranges(_ source: String) -> [CodeRange] {
        DocumentCache().codeRanges(for: source)
    }

    private static func editing(
        _ source: String,
        caret: Int,
        length: Int = 0,
        mode: ShowMarkdown = .whileEditing,
        isInk: Bool = false
    ) -> Set<Int> {
        FenceVisibility.at(
            selection: NSRange(location: caret, length: length),
            in: ranges(source),
            mode: mode,
            isInk: isInk
        ).editing
    }

    private static let note = "Before\n```cpp\nint x;\n```\nAfter\n"

    private static func offset(of text: String, in source: String = note) -> Int {
        (source as NSString).range(of: text).location
    }

    // MARK: A caret

    @Test("A caret on the opening fence's line, in the code, or on the closing fence's line is in the block")
    func caretInside() {
        let open = Self.offset(of: "```cpp")
        #expect(Self.editing(Self.note, caret: open) == [0], "start of the opening fence")
        #expect(Self.editing(Self.note, caret: open + 3) == [0], "inside the opening fence")
        #expect(Self.editing(Self.note, caret: open + 6) == [0], "end of the opening fence's line")
        #expect(Self.editing(Self.note, caret: Self.offset(of: "int x;") + 3) == [0], "in the code")
        let close = Self.offset(of: "```\nAfter")
        #expect(Self.editing(Self.note, caret: close) == [0], "start of the closing fence")
        #expect(Self.editing(Self.note, caret: close + 3) == [0], "end of the closing fence's line")
    }

    @Test("A caret on the prose either side is outside the block")
    func caretOutside() {
        let open = Self.offset(of: "```cpp")
        #expect(Self.editing(Self.note, caret: 0).isEmpty)
        #expect(Self.editing(Self.note, caret: open - 1).isEmpty, "end of the line before the fence")
        let after = Self.offset(of: "After")
        #expect(Self.editing(Self.note, caret: after).isEmpty, "start of the line after the closing fence")
        #expect(Self.editing(Self.note, caret: after + 5).isEmpty)
    }

    @Test("A block closed on the note's last line, with no newline, holds a caret at the very end")
    func closedAtEndOfNote() {
        let source = "```py\nx\n```"
        #expect(Self.editing(source, caret: source.utf16.count) == [0])
    }

    @Test("After a closing fence's newline at the end of the note, the empty last line is prose")
    func emptyLastLine() {
        let source = "```py\nx\n```\n"
        #expect(Self.editing(source, caret: source.utf16.count).isEmpty)
    }

    @Test("A CRLF note: the caret before the closing fence's CRLF is in the block, after it isn't")
    func crlf() {
        let source = "```py\r\nx\r\n```\r\nafter"
        let closingEnd = (source as NSString).range(of: "```\r\nafter").location + 3
        #expect(Self.editing(source, caret: closingEnd) == [0])
        #expect(Self.editing(source, caret: closingEnd + 2).isEmpty)
    }

    @Test("An unclosed block holds the caret from its fence to the end of the note, even after a final newline")
    func unclosed() {
        let source = "Before\n```cpp\nint x;\n"
        #expect(Self.editing(source, caret: 0).isEmpty)
        #expect(Self.editing(source, caret: Self.offset(of: "```", in: source)) == [0])
        #expect(Self.editing(source, caret: source.utf16.count) == [0], "the empty line after the code is still code")
    }

    // MARK: A selection

    @Test("A selection overlapping a block by a character edits it; one that ends where it starts doesn't")
    func selection() {
        let open = Self.offset(of: "```cpp")
        #expect(Self.editing(Self.note, caret: open - 4, length: 4).isEmpty, "ends at the fence's first character")
        #expect(Self.editing(Self.note, caret: open - 4, length: 5) == [0])
        #expect(Self.editing(Self.note, caret: Self.offset(of: "int"), length: 3) == [0], "inside")
        #expect(Self.editing(Self.note, caret: 0, length: Self.note.utf16.count) == [0], "everything")
    }

    @Test("A selection across two blocks edits both, and not the one between")
    func twoBlocks() {
        let source = "```a\nx\n```\nmiddle\n```b\ny\n```\nlast\n```c\nz\n```"
        let start = Self.offset(of: "x", in: source)
        let end = Self.offset(of: "y", in: source) + 1
        #expect(Self.editing(source, caret: start, length: end - start) == [0, 1])
    }

    // MARK: Ink and the setting

    @Test("In ink mode no block is being edited, wherever the selection was")
    func ink() {
        let inside = Self.offset(of: "int")
        #expect(Self.editing(Self.note, caret: inside, isInk: true).isEmpty)
        #expect(Self.editing(Self.note, caret: 0, length: Self.note.utf16.count, isInk: true).isEmpty)
    }

    @Test("Always shows every fence, and still marks only the block being edited")
    func always() {
        let source = Self.note + "```java\ny\n```\n"
        let inFirst = FenceVisibility.at(
            selection: NSRange(location: Self.offset(of: "int", in: source), length: 0),
            in: Self.ranges(source), mode: .always, isInk: false
        )
        #expect(inFirst.showsFences(ofBlock: 0))
        #expect(inFirst.showsFences(ofBlock: 1))
        #expect(inFirst.isEditing(block: 0))
        #expect(!inFirst.isEditing(block: 1))
    }

    @Test("While Editing shows only the block being edited")
    func whileEditing() {
        let source = Self.note + "```java\ny\n```\n"
        let state = FenceVisibility.at(
            selection: NSRange(location: Self.offset(of: "int", in: source), length: 0),
            in: Self.ranges(source), mode: .whileEditing, isInk: false
        )
        #expect(state.showsFences(ofBlock: 0))
        #expect(!state.showsFences(ofBlock: 1))
        #expect(!FenceVisibility.away.showsFences(ofBlock: 0))
    }

    @Test("Always still shows the fences in ink mode; nothing is being edited")
    func alwaysInInk() {
        let state = FenceVisibility.at(
            selection: NSRange(location: Self.offset(of: "int"), length: 0),
            in: Self.ranges(Self.note), mode: .always, isInk: true
        )
        #expect(state.showsFences(ofBlock: 0))
        #expect(state.editing.isEmpty)
    }

    @Test("The setting stores under the key the page reads it from, and defaults to While Editing")
    func settingKey() {
        #expect(ShowMarkdown.defaultsKey == "showMarkdown")
        #expect(ShowMarkdown(rawValue: "always") == .always)
        #expect(ShowMarkdown(rawValue: "whileEditing") == .whileEditing)
        #expect(ShowMarkdown(rawValue: "") == nil)
    }

    // MARK: Finding a block

    @Test("A fragment's block is found by its offset")
    func blockIndex() {
        let source = "a\n```x\nb\n```\nc\n```y\nd\n```\n"
        let ranges = Self.ranges(source)
        #expect(ranges.count == 2)
        #expect(FenceVisibility.blockIndex(containing: 0, in: ranges) == nil)
        #expect(FenceVisibility.blockIndex(containing: ranges[0].range.location, in: ranges) == 0)
        #expect(FenceVisibility.blockIndex(containing: ranges[0].range.location + ranges[0].range.length - 1, in: ranges) == 0)
        #expect(FenceVisibility.blockIndex(containing: ranges[0].range.location + ranges[0].range.length, in: ranges) == nil)
        #expect(FenceVisibility.blockIndex(containing: ranges[1].range.location + 2, in: ranges) == 1)
        #expect(FenceVisibility.blockIndex(containing: 10_000, in: ranges) == nil)
    }
}

@Suite("Fence tags")
struct FenceTagTests {

    private func edit(_ line: String, as language: CodeLanguage?) -> String? {
        guard let edit = FenceTag.retag(line: line, as: language) else { return nil }
        return (line as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    @Test("A tag is replaced by the language's")
    func replaces() {
        #expect(edit("```cpp\n", as: .python) == "```python\n")
        #expect(edit("```py", as: .java) == "```java")
        #expect(edit("```c++", as: .python) == "```python", "a spelling the app reads as C++")
        #expect(edit("```rust", as: .cpp) == "```cpp", "a tag it doesn't know")
    }

    @Test("A bare fence gets the tag")
    func inserts() {
        #expect(edit("```\n", as: .cpp) == "```cpp\n")
        #expect(edit("```", as: .java) == "```java")
        #expect(edit("``` \n", as: .java) == "``` java\n", "kept as typed, trailing space and all")
    }

    @Test("Plain text takes the whole info string away")
    func plain() {
        #expect(edit("```cpp\n", as: nil) == "```\n")
        #expect(edit("```cpp title=a\n", as: nil) == "```\n")
        #expect(edit("``` python", as: nil) == "```")
        #expect(edit("```\n", as: nil) == nil, "already plain")
    }

    @Test("Words after the tag are kept when a language replaces it")
    func keepsTheRest() {
        #expect(edit("```cpp title=a\n", as: .python) == "```python title=a\n")
    }

    @Test("Already that language: nothing to do")
    func unchanged() {
        #expect(edit("```cpp\n", as: .cpp) == nil)
        #expect(edit("```java", as: .java) == nil)
    }

    @Test("Indented fences, longer fences and CRLF lines")
    func shapes() {
        #expect(edit("  ```cpp\n", as: .java) == "  ```java\n")
        #expect(edit("````cpp\n", as: .java) == "````java\n")
        #expect(edit("```cpp\r\n", as: .java) == "```java\r\n")
        #expect(edit("```cpp\r\n", as: nil) == "```\r\n")
    }

    @Test("A line that isn't a fence is left alone")
    func notAFence() {
        #expect(edit("`cpp`\n", as: .java) == nil)
        #expect(edit("``cpp\n", as: .java) == nil)
        #expect(edit("prose\n", as: .java) == nil)
        #expect(edit("", as: .java) == nil)
    }

    @Test("The label is the language's name, the tag as typed, or Plain Text")
    func labels() {
        #expect(FenceTag.label(language: .cpp, tag: "c++") == "C++")
        #expect(FenceTag.label(language: .python, tag: "py") == "Python")
        #expect(FenceTag.label(language: nil, tag: "rust") == "rust")
        #expect(FenceTag.label(language: nil, tag: "") == "Plain Text")
    }

    @Test("A target carries the tag as typed")
    func targetTag() {
        let source = "```c++\nx\n```\n```\ny\n```\n```rust\nz\n```\n"
        let targets = CodeBlockAction.targets(in: source, blocks: DocumentParser.parse(source))
        #expect(targets.map(\.tag) == ["c++", "", "rust"])
        #expect(targets.map(\.languageLabel) == ["C++", "Plain Text", "rust"])
    }
}
