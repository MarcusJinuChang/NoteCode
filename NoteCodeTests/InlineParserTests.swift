//
//  InlineParserTests.swift
//  NoteCodeTests
//

import Foundation
import Testing
@testable import NoteCode

private func inlines(_ source: String) -> [InlineNode] {
    InlineParser.parse(source, in: source.startIndex..<source.endIndex)
}

private func spans(_ source: String) -> [(InlineNode.Kind, String)] {
    inlines(source).map { ($0.kind, String(source[$0.contentRange])) }
}

private func kinds(_ source: String) -> [InlineNode.Kind] {
    inlines(source).map(\.kind)
}

@Suite("Inline spans")
struct InlineParserTests {

    @Test("Plain text is a single span")
    func plainText() {
        #expect(kinds("just some notes") == [.text])
    }

    @Test("Strong, emphasis and inline code are recognized", arguments: [
        ("**bold**", InlineNode.Kind.strong, "bold"),
        ("__bold__", .strong, "bold"),
        ("*italic*", .emphasis, "italic"),
        ("_italic_", .emphasis, "italic"),
        ("`code`", .inlineCode, "code"),
    ])
    func recognizesMarkup(source: String, kind: InlineNode.Kind, content: String) {
        let parsed = spans(source)

        #expect(parsed.count == 1)
        #expect(parsed.first?.0 == kind)
        #expect(parsed.first?.1 == content)
    }

    @Test("Doubled markers win over single ones")
    func strongBeatsEmphasis() {
        // Parsed as emphasis, this would be *bold* wrapped in stray asterisks.
        #expect(kinds("**bold**") == [.strong])
    }

    @Test("Markup is found in the middle of a line")
    func markupMidLine() {
        #expect(spans("a **b** c").map(\.0) == [.text, .strong, .text])
        #expect(spans("a **b** c").map(\.1) == ["a ", "b", " c"])
    }

    @Test("Several spans on one line")
    func multipleSpans() {
        #expect(kinds("**a** and *b* and `c`") == [.strong, .text, .emphasis, .text, .inlineCode])
    }

    @Test("Inline code wins over emphasis inside it")
    func codeBeatsEmphasis() {
        // The asterisks are code content, not markup.
        let parsed = spans("`a *b* c`")

        #expect(parsed.count == 1)
        #expect(parsed.first?.0 == .inlineCode)
        #expect(parsed.first?.1 == "a *b* c")
    }

    @Test("Unmatched markers are literal text", arguments: [
        "a * b",
        "unclosed **bold",
        "trailing `code",
        "_",
        "**",
    ])
    func unmatchedMarkersAreText(source: String) {
        #expect(kinds(source).allSatisfy { $0 == .text })
    }

    @Test("Empty markup is not a span", arguments: ["****", "``", "__"])
    func emptyMarkupIsText(source: String) {
        #expect(kinds(source).allSatisfy { $0 == .text })
    }

    // MARK: Invariants

    @Test("Spans are contiguous and cover the range", arguments: [
        "plain",
        "a **b** c",
        "**a** and *b* and `c`",
        "`code` at the start",
        "ends with **markup**",
        "",
    ])
    func spansCoverTheRange(source: String) {
        let parsed = inlines(source)
        guard !parsed.isEmpty else {
            #expect(source.isEmpty)
            return
        }

        #expect(parsed.first?.range.lowerBound == source.startIndex)
        #expect(parsed.last?.range.upperBound == source.endIndex)
        for (current, next) in zip(parsed, parsed.dropFirst()) {
            #expect(current.range.upperBound == next.range.lowerBound)
        }
    }

    @Test("A span's content sits inside its range, with markers either side")
    func contentInsideRange() {
        let node = inlines("**bold**")[0]

        #expect(node.range.lowerBound < node.contentRange.lowerBound)
        #expect(node.contentRange.upperBound < node.range.upperBound)
        #expect(node.markerRanges.count == 2)
    }

    @Test("Plain text has no markers")
    func textHasNoMarkers() {
        #expect(inlines("plain")[0].markerRanges.isEmpty)
    }
}

// MARK: - Headings

@Suite("Headings")
struct HeadingTests {

    @Test("Levels one through six are recognized", arguments: 1...6)
    func levels(level: Int) {
        let source = String(repeating: "#", count: level) + " Title"
        #expect(DocumentParser.parse(source).first?.headingLevel == level)
    }

    @Test("Seven hashes is not a heading")
    func sevenHashes() {
        #expect(DocumentParser.parse("####### Title").first?.headingLevel == nil)
    }

    @Test("A space after the hashes is required")
    func spaceRequired() {
        // Otherwise a C preprocessor line in prose becomes a heading.
        #expect(DocumentParser.parse("#include <vector>").first?.headingLevel == nil)
        #expect(DocumentParser.parse("#notatag").first?.headingLevel == nil)
    }

    @Test("The hashes are the block's marker, not its content")
    func markerExcludedFromContent() {
        let source = "## Binary search"
        let block = DocumentParser.parse(source)[0]

        #expect(String(source[block.markerRange!]) == "## ")
        #expect(String(source[block.contentRange]) == "Binary search")
    }

    @Test("Heading content is scanned for inline markup")
    func headingCarriesInlines() {
        let block = DocumentParser.parse("# A **bold** title")[0]
        #expect(block.inlines.map(\.kind) == [.text, .strong, .text])
    }

    @Test("Headings inside a code block stay code")
    func hashesInCodeAreNotHeadings() {
        let blocks = DocumentParser.parse("```cpp\n#include <vector>\n```")

        #expect(blocks.count == 1)
        #expect(blocks[0].isCode)
    }
}
