//
//  FenceParserTests.swift
//  NoteCodeTests
//

import Testing
@testable import NoteCode

private func text(_ source: String, _ region: Region) -> String {
    String(source[region.range])
}

private func content(_ source: String, _ region: Region) -> String? {
    guard let block = region.codeBlock else { return nil }
    return String(source[block.contentRange])
}

/// Parses `source` and fails the test (without crashing the process) unless it
/// produced exactly `count` regions. Every test that indexes into the result
/// goes through here — `#expect` records a failure and keeps running, so a bare
/// subscript on an unexpectedly short array would trap and kill the whole test
/// host, masking every later test.
private func parse(_ source: String, expecting count: Int) throws -> [Region] {
    let regions = FenceParser.parse(source)
    try #require(regions.count == count, "expected \(count) regions, got \(regions.count)")
    return regions
}

// MARK: - Shape

@Suite("Fence parsing")
struct FenceParserTests {

    @Test("An empty document has no regions")
    func emptyDocument() {
        #expect(FenceParser.parse("").isEmpty)
    }

    @Test("Prose with no fences is a single text region")
    func proseOnly() throws {
        let source = "Binary search notes.\nStill just prose."
        let regions = try parse(source, expecting: 1)

        #expect(regions[0].isCode == false)
        #expect(text(source, regions[0]) == source)
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
        let regions = try parse(source, expecting: 3)

        #expect(regions[0].isCode == false)
        #expect(regions[1].isCode == true)
        #expect(regions[2].isCode == false)

        #expect(text(source, regions[0]) == "before\n")
        #expect(text(source, regions[2]) == "after")

        let block = regions[1].codeBlock
        #expect(block?.language == .cpp)
        #expect(block?.isClosed == true)
        #expect(content(source, regions[1]) == "int main() {}\n")
    }

    @Test("Two fences in one document produce two code regions")
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
        let regions = FenceParser.parse(source)

        #expect(regions.filter(\.isCode).count == 2)
        #expect(regions.compactMap(\.codeBlock).map(\.language) == [.python, .java])
    }
}

// MARK: - Unclosed fences

@Suite("Unclosed fences")
struct UnclosedFenceTests {

    @Test("An unclosed fence runs to the end of the document")
    func unclosedRunsToEnd() throws {
        let source = "notes\n```cpp\nint x = 1;\nstill code"
        let regions = try parse(source, expecting: 2)

        let block = regions[1].codeBlock
        #expect(block?.isClosed == false)
        #expect(block?.language == .cpp)
        #expect(content(source, regions[1]) == "int x = 1;\nstill code")
        #expect(regions[1].range.upperBound == source.endIndex)
    }

    @Test("A fence on the very last line opens an empty code region")
    func fenceOnLastLine() throws {
        let source = "notes\n```py"
        let regions = try parse(source, expecting: 2)

        #expect(regions[1].codeBlock?.isClosed == false)
        #expect(content(source, regions[1]) == "")
    }

    @Test("A tagged fence inside a block does not close it")
    func taggedFenceDoesNotClose() throws {
        let source = "```cpp\ncode\n```java\nmore\n```"
        let regions = try parse(source, expecting: 1)

        #expect(regions[0].codeBlock?.isClosed == true)
        #expect(content(source, regions[0]) == "code\n```java\nmore\n")
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
        let regions = try parse("```\(tag)\nx\n```", expecting: 1)
        #expect(regions[0].codeBlock?.language == expected)
    }

    @Test("A fence with no tag is still code, with no language")
    func noTag() throws {
        let regions = try parse("```\nplain\n```", expecting: 1)
        let block = try #require(regions[0].codeBlock)

        #expect(block.language == nil)
        #expect(block.infoString == "")
    }

    @Test("An unknown tag is preserved verbatim but maps to no language")
    func unknownTag() throws {
        let regions = try parse("```rust\nfn main() {}\n```", expecting: 1)
        let block = try #require(regions[0].codeBlock)

        #expect(block.language == nil)
        #expect(block.infoString == "rust")
    }

    @Test("Piston names match what the API expects")
    func pistonNames() {
        #expect(CodeLanguage.cpp.pistonName == "c++")
        #expect(CodeLanguage.java.pistonName == "java")
        #expect(CodeLanguage.python.pistonName == "python")
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
        let regions = try parse(line, expecting: 1)
        #expect(regions[0].isCode == false)
    }

    @Test("Up to three spaces of indent still opens a fence", arguments: ["", " ", "  ", "   "])
    func indentedFence(indent: String) throws {
        let regions = try parse("\(indent)```py\nx\n\(indent)```", expecting: 1)
        #expect(regions[0].isCode == true)
    }

    @Test("Four spaces of indent is not a fence")
    func overIndentedFence() {
        let regions = FenceParser.parse("    ```py\nx")
        #expect(regions.allSatisfy { !$0.isCode })
    }

    @Test("More than three backticks opens a fence")
    func longFence() throws {
        let regions = try parse("````py\nx\n````", expecting: 1)
        #expect(regions[0].codeBlock?.isClosed == true)
    }

    @Test("A shorter fence does not close a longer one")
    func shortFenceDoesNotCloseLong() throws {
        let regions = try parse("````\ncode\n```\nmore\n````", expecting: 1)
        #expect(regions[0].codeBlock?.isClosed == true)
    }

    @Test("CRLF line endings parse the same as LF")
    func crlf() throws {
        let source = "before\r\n```cpp\r\nint x;\r\n```\r\nafter"
        let regions = try parse(source, expecting: 3)

        #expect(regions[1].codeBlock?.language == .cpp)
        #expect(regions[1].codeBlock?.isClosed == true)
        #expect(content(source, regions[1]) == "int x;\r\n")
    }
}

// MARK: - Structural guarantees

@Suite("Structural guarantees")
struct RegionInvariantTests {

    @Test("Regions are contiguous and cover the whole document", arguments: [
        "just prose",
        "before\n```cpp\nint main() {}\n```\nafter",
        "```py\nprint(1)\n",
        "a\n```\nb\n```\nc\n```java\nx",
        "```\n```",
        "\n\n\n",
        "before\r\n```cpp\r\nint x;\r\n```\r\nafter",
    ])
    func contiguousCoverage(source: String) throws {
        let regions = FenceParser.parse(source)

        let first = try #require(regions.first)
        let last = try #require(regions.last)

        #expect(first.range.lowerBound == source.startIndex)
        #expect(last.range.upperBound == source.endIndex)

        for (current, next) in zip(regions, regions.dropFirst()) {
            #expect(current.range.upperBound == next.range.lowerBound)
        }
    }

    @Test("A code block's content range sits inside its region")
    func contentInsideRegion() throws {
        let source = "```cpp\nint main() {}\n```\n"
        let regions = try parse(source, expecting: 1)
        let block = try #require(regions[0].codeBlock)

        #expect(block.contentRange.lowerBound >= regions[0].range.lowerBound)
        #expect(block.contentRange.upperBound <= regions[0].range.upperBound)
        #expect(content(source, regions[0]) == "int main() {}\n")
    }
}
