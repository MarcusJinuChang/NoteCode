//
//  DocumentParserTests.swift
//  NoteCodeTests
//

import Testing
@testable import NoteCode

private func text(_ source: String, _ block: BlockNode) -> String {
    String(source[block.range])
}

private func content(_ source: String, _ block: BlockNode) -> String? {
    guard let block = block.codeBlock else { return nil }
    return String(source[block.contentRange])
}

/// Parses `source` and fails the test (without crashing the process) unless it
/// produced exactly `count` blocks. Every test that indexes into the result
/// goes through here — `#expect` records a failure and keeps running, so a bare
/// subscript on an unexpectedly short array would trap and kill the whole test
/// host, masking every later test.
private func parse(_ source: String, expecting count: Int) throws -> [BlockNode] {
    let blocks = DocumentParser.parse(source)
    try #require(blocks.count == count, "expected \(count) blocks, got \(blocks.count)")
    return blocks
}

// MARK: - Shape

@Suite("Fence parsing")
struct DocumentParserTests {

    @Test("An empty document has no blocks")
    func emptyDocument() {
        #expect(DocumentParser.parse("").isEmpty)
    }

    @Test("Prose is one block per source line")
    func proseIsOneBlockPerLine() throws {
        let source = "Binary search notes.\nStill just prose."
        let blocks = try parse(source, expecting: 2)

        #expect(blocks.allSatisfy { !$0.isCode })
        #expect(text(source, blocks[0]) == "Binary search notes.\n")
        #expect(text(source, blocks[1]) == "Still just prose.")
    }

    @Test("A single line of prose is a single block")
    func singleLineProse() throws {
        let source = "just prose"
        let blocks = try parse(source, expecting: 1)

        #expect(blocks[0].isCode == false)
        #expect(text(source, blocks[0]) == source)
    }

    @Test("Blank lines are blocks of their own, so coverage stays complete")
    func blankLinesAreBlocks() throws {
        // Three newlines are three line-terminated blocks; the empty run after
        // the last one spans nothing and is dropped rather than emitted as a
        // zero-length block.
        let blocks = try parse("\n\n\n", expecting: 3)
        #expect(blocks.allSatisfy { !$0.isCode })
    }

    @Test("A closed fence splits the document into text, code, text")
    func closedFence() throws {
        let source = """
        before
        ```cpp
        int main() {}
        ```
        after
        """
        let blocks = try parse(source, expecting: 3)

        #expect(blocks[0].isCode == false)
        #expect(blocks[1].isCode == true)
        #expect(blocks[2].isCode == false)

        #expect(text(source, blocks[0]) == "before\n")
        #expect(text(source, blocks[2]) == "after")

        let block = blocks[1].codeBlock
        #expect(block?.language == .cpp)
        #expect(block?.isClosed == true)
        #expect(content(source, blocks[1]) == "int main() {}\n")
    }

    @Test("Two fences in one document produce two code blocks")
    func multipleFences() {
        let source = """
        ```py
        print(1)
        ```
        prose between
        ```java
        class A {}
        ```
        """
        let blocks = DocumentParser.parse(source)

        #expect(blocks.filter(\.isCode).count == 2)
        #expect(blocks.compactMap(\.codeBlock).map(\.language) == [.python, .java])
    }
}

// MARK: - Unclosed fences

@Suite("Unclosed fences")
struct UnclosedFenceTests {

    @Test("An unclosed fence runs to the end of the document")
    func unclosedRunsToEnd() throws {
        let source = "notes\n```cpp\nint x = 1;\nstill code"
        let blocks = try parse(source, expecting: 2)

        let block = blocks[1].codeBlock
        #expect(block?.isClosed == false)
        #expect(block?.language == .cpp)
        #expect(content(source, blocks[1]) == "int x = 1;\nstill code")
        #expect(blocks[1].range.upperBound == source.endIndex)
    }

    @Test("A fence on the very last line opens an empty code block")
    func fenceOnLastLine() throws {
        let source = "notes\n```py"
        let blocks = try parse(source, expecting: 2)

        #expect(blocks[1].codeBlock?.isClosed == false)
        #expect(content(source, blocks[1]) == "")
    }

    @Test("A tagged fence inside a block does not close it")
    func taggedFenceDoesNotClose() throws {
        let source = "```cpp\ncode\n```java\nmore\n```"
        let blocks = try parse(source, expecting: 1)

        #expect(blocks[0].codeBlock?.isClosed == true)
        #expect(content(source, blocks[0]) == "code\n```java\nmore\n")
    }
}

// MARK: - Language tags

@Suite("Language tags")
struct LanguageTagTests {

    @Test("Aliases normalize onto the three supported languages", arguments: [
        ("cpp", CodeLanguage.cpp),
        ("c++", CodeLanguage.cpp),
        ("cxx", CodeLanguage.cpp),
        ("CPP", CodeLanguage.cpp),
        ("java", CodeLanguage.java),
        ("Java", CodeLanguage.java),
        ("py", CodeLanguage.python),
        ("python", CodeLanguage.python),
        ("python3", CodeLanguage.python),
    ])
    func aliases(tag: String, expected: CodeLanguage) throws {
        let blocks = try parse("```\(tag)\nx\n```", expecting: 1)
        #expect(blocks[0].codeBlock?.language == expected)
    }

    @Test("A fence with no tag is still code, with no language")
    func noTag() throws {
        let blocks = try parse("```\nplain\n```", expecting: 1)
        let block = try #require(blocks[0].codeBlock)

        #expect(block.language == nil)
        #expect(block.infoString == "")
    }

    @Test("An unknown tag is preserved verbatim but maps to no language")
    func unknownTag() throws {
        let blocks = try parse("```rust\nfn main() {}\n```", expecting: 1)
        let block = try #require(blocks[0].codeBlock)

        #expect(block.language == nil)
        #expect(block.infoString == "rust")
    }

    @Test("Canonical names match what online compilers spell")
    func canonicalNames() {
        #expect(CodeLanguage.cpp.canonicalName == "c++")
        #expect(CodeLanguage.java.canonicalName == "java")
        #expect(CodeLanguage.python.canonicalName == "python")
    }
}

// MARK: - Things that must NOT be fences

@Suite("Fence recognition edges")
struct FenceRecognitionTests {

    @Test("Inline backticks are not fences", arguments: [
        "call `main()` here",
        "`x`",
        "``double``",
        "text with ``` in the middle of it",
    ])
    func inlineBackticks(line: String) throws {
        let blocks = try parse(line, expecting: 1)
        #expect(blocks[0].isCode == false)
    }

    @Test("Up to three spaces of indent still opens a fence", arguments: ["", " ", "  ", "   "])
    func indentedFence(indent: String) throws {
        let blocks = try parse("\(indent)```py\nx\n\(indent)```", expecting: 1)
        #expect(blocks[0].isCode == true)
    }

    @Test("Four spaces of indent is not a fence")
    func overIndentedFence() {
        let blocks = DocumentParser.parse("    ```py\nx")
        #expect(blocks.allSatisfy { !$0.isCode })
    }

    @Test("More than three backticks opens a fence")
    func longFence() throws {
        let blocks = try parse("````py\nx\n````", expecting: 1)
        #expect(blocks[0].codeBlock?.isClosed == true)
    }

    @Test("A shorter fence does not close a longer one")
    func shortFenceDoesNotCloseLong() throws {
        let blocks = try parse("````\ncode\n```\nmore\n````", expecting: 1)
        #expect(blocks[0].codeBlock?.isClosed == true)
    }

    @Test("CRLF line endings parse the same as LF")
    func crlf() throws {
        let source = "before\r\n```cpp\r\nint x;\r\n```\r\nafter"
        let blocks = try parse(source, expecting: 3)

        #expect(blocks[1].codeBlock?.language == .cpp)
        #expect(blocks[1].codeBlock?.isClosed == true)
        #expect(content(source, blocks[1]) == "int x;\r\n")
    }
}

// MARK: - Structural guarantees

@Suite("Structural guarantees")
struct BlockInvariantTests {

    @Test("Blocks are contiguous and cover the whole document", arguments: [
        "just prose",
        "before\n```cpp\nint main() {}\n```\nafter",
        "```py\nprint(1)\n",
        "a\n```\nb\n```\nc\n```java\nx",
        "```\n```",
        "\n\n\n",
        "before\r\n```cpp\r\nint x;\r\n```\r\nafter",
    ])
    func contiguousCoverage(source: String) throws {
        let blocks = DocumentParser.parse(source)

        let first = try #require(blocks.first)
        let last = try #require(blocks.last)

        #expect(first.range.lowerBound == source.startIndex)
        #expect(last.range.upperBound == source.endIndex)

        for (current, next) in zip(blocks, blocks.dropFirst()) {
            #expect(current.range.upperBound == next.range.lowerBound)
        }
    }

    @Test("A code block's content range sits inside its block")
    func contentInsideBlock() throws {
        let source = "```cpp\nint main() {}\n```\n"
        let blocks = try parse(source, expecting: 1)
        let block = try #require(blocks[0].codeBlock)

        #expect(block.contentRange.lowerBound >= blocks[0].range.lowerBound)
        #expect(block.contentRange.upperBound <= blocks[0].range.upperBound)
        #expect(content(source, blocks[0]) == "int main() {}\n")
    }
}

// MARK: - Node shape

@Suite("Node shape")
struct NodeShapeTests {

    @Test("A paragraph's inline spans cover its whole range")
    func inlinesCoverParagraph() throws {
        let source = "some prose here\nand a second line"
        let blocks = DocumentParser.parse(source)

        for block in blocks {
            let inlines = block.inlines
            #expect(!inlines.isEmpty)
            #expect(inlines.first?.range.lowerBound == block.range.lowerBound)
            #expect(inlines.last?.range.upperBound == block.range.upperBound)

            for (current, next) in zip(inlines, inlines.dropFirst()) {
                #expect(current.range.upperBound == next.range.lowerBound)
            }
        }
    }

    @Test("A code block carries no inline spans")
    func codeHasNoInlines() {
        let blocks = DocumentParser.parse("```cpp\nint x;\n```")

        #expect(blocks.first?.isCode == true)
        #expect(blocks.first?.inlines.isEmpty == true)
    }

    @Test("Every prose block is a paragraph")
    func proseBlocksAreParagraphs() {
        let blocks = DocumentParser.parse("prose\n```cpp\nx\n```\nmore prose")

        for block in blocks where !block.isCode {
            guard case .paragraph = block.kind else {
                Issue.record("expected a paragraph block")
                continue
            }
        }
    }
}
