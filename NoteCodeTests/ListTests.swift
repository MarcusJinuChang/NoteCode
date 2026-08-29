//
//  ListTests.swift
//  NoteCodeTests
//

import Foundation
import Testing
@testable import NoteCode

private func firstBlock(_ source: String) -> BlockNode {
    DocumentParser.parse(source)[0]
}

@Suite("List parsing")
struct ListParsingTests {

    @Test("Every unordered marker starts a list item", arguments: ["-", "*", "+"])
    func unorderedMarkers(marker: String) {
        #expect(firstBlock("\(marker) item").listMarker == .bullet)
    }

    @Test("Ordered markers carry the number typed", arguments: [
        ("1. item", 1),
        ("2) item", 2),
        ("17. item", 17),
    ])
    func orderedMarkers(source: String, number: Int) {
        #expect(firstBlock(source).listMarker == .ordered(number))
    }

    @Test("A space after the marker is required", arguments: [
        "-item",
        "*item*",
        "+1",
        "1.item",
        "2)x",
    ])
    func spaceRequired(source: String) {
        #expect(firstBlock(source).listMarker == nil)
    }

    @Test("Emphasis at the start of a line is not a list")
    func emphasisIsNotAList() {
        // The classic collision: `*` opens both a bullet and emphasis.
        let block = firstBlock("*italic* then text")

        #expect(block.listMarker == nil)
        #expect(block.inlines.first?.kind == .emphasis)
    }

    @Test("The marker is not part of the content")
    func markerExcludedFromContent() {
        let source = "- buy milk"
        let block = firstBlock(source)

        #expect(String(source[block.markerRange!]) == "- ")
        #expect(String(source[block.contentRange]) == "buy milk")
    }

    @Test("List content is scanned for inline markup")
    func listCarriesInlines() {
        #expect(firstBlock("- a **bold** point").inlines.map(\.kind) == [.text, .strong, .text])
    }

    @Test("A list marker inside a code block stays code")
    func markersInCodeAreNotLists() {
        let blocks = DocumentParser.parse("```py\n- not a list\n```")

        #expect(blocks.count == 1)
        #expect(blocks[0].isCode)
    }
}

@Suite("List nesting")
struct ListNestingTests {

    @Test("Indentation sets depth, two columns per level", arguments: [
        ("- top", 0),
        ("  - one deep", 1),
        ("    - two deep", 2),
        ("      - three deep", 3),
    ])
    func depthFromIndent(source: String, depth: Int) {
        #expect(firstBlock(source).listDepth == depth)
    }

    @Test("A tab counts as two columns")
    func tabsCountAsTwoColumns() {
        #expect(firstBlock("\t- item").listDepth == 1)
        #expect(firstBlock("\t\t- item").listDepth == 2)
    }

    @Test("A list survives being mixed with other blocks")
    func listAmongOtherBlocks() {
        let blocks = DocumentParser.parse("# Title\n- one\n- two\ntext\n```py\nx\n```")

        #expect(blocks.count == 5)
        #expect(blocks[0].headingLevel == 1)
        #expect(blocks[1].listMarker == .bullet)
        #expect(blocks[2].listMarker == .bullet)
        #expect(blocks[3].listMarker == nil)
        #expect(blocks[4].isCode)
    }
}

#if canImport(UIKit)

import UIKit

@Suite("List styling")
@MainActor
struct ListStylingTests {

    private func styled(_ source: String) -> UITextView {
        let textView = DocumentTextView.makeConfiguredTextView()
        textView.text = source
        DocumentStyler.applyStyling(to: textView)
        return textView
    }

    private func paragraphStyle(_ textView: UITextView, at offset: Int) -> NSParagraphStyle? {
        textView.textStorage.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
    }

    @Test("Deeper items indent further")
    func deeperItemsIndentFurther() {
        let source = "- top\n  - nested"
        let textView = styled(source)

        let top = paragraphStyle(textView, at: 0)
        let nested = paragraphStyle(textView, at: ("- top\n" as NSString).length)

        #expect(top?.firstLineHeadIndent == 0)
        #expect((nested?.firstLineHeadIndent ?? 0) > 0)
    }

    @Test("Wrapped lines align past the marker, not under it")
    func wrappedLinesClearTheMarker() {
        let textView = styled("- an item long enough to wrap somewhere")
        let style = paragraphStyle(textView, at: 0)

        // This is the whole point of the paragraph style: a continuation line
        // should start where the text does, not where the bullet does.
        #expect((style?.headIndent ?? 0) > (style?.firstLineHeadIndent ?? 0))
    }

    @Test("The marker is dimmed and the content is not")
    func markerIsDimmed() {
        let textView = styled("- buy milk")
        let storage = textView.textStorage

        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor == DocumentStyler.markerColor)
        #expect(storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? UIColor == .label)
    }

    @Test("A paragraph gets no list indentation")
    func paragraphsAreNotIndented() {
        let textView = styled("just prose")
        #expect(paragraphStyle(textView, at: 0) == nil)
    }
}

#endif
