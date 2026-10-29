//
//  NoteOutlineTests.swift
//  NoteCodeTests
//
//  Phase 6 of v3: the outline lists the headings the parser finds, and a tap
//  puts that heading's line at the top of the page.
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Outline: the headings")
struct NoteOutlineEntriesTests {

    static let note = """
    Intro line before any heading.
    # Algorithms
    Some text.
    ## Sorting **fast**
    - a list item
    ```cpp
    # not a heading, this is code
    #include <vector>
    ```
    #hashtag has no space, so it is prose
    ### `std::sort` and [friends](https://example.com)
    ## 
    # Last
    """

    @Test("Every heading the parser finds is an entry, in order, and nothing else")
    func matchesTheParser() {
        let entries = NoteOutline.entries(in: Self.note)
        let blocks = DocumentParser.parse(Self.note)
        let parsed = blocks.compactMap(\.headingLevel)

        #expect(entries.map(\.level) == parsed)
        #expect(entries.map(\.level) == [1, 2, 3, 2, 1])
    }

    @Test("A heading's title is its words, without the hashes or the inline markers")
    func titles() {
        let titles = NoteOutline.entries(in: Self.note).map(\.title)
        #expect(titles == ["Algorithms", "Sorting fast", "std::sort and friends", "", "Last"])
    }

    @Test("Each entry's location is where its line starts, in UTF-16 units")
    func locations() {
        let text = Self.note as NSString
        for entry in NoteOutline.entries(in: Self.note) {
            #expect(text.character(at: entry.location) == 0x23, "\(entry.title) should start at a #")
            #expect(entry.location == 0 || text.character(at: entry.location - 1) == 0x0A, "\(entry.title) starts a line")
        }
    }

    @Test("Offsets count UTF-16 units, so a heading after emoji is found where TextKit has it")
    func utf16() {
        let source = "😀😀 prose\n# After\n"
        let entry = NoteOutline.entries(in: source).first
        #expect(entry?.location == ("😀😀 prose\n" as NSString).length)
    }

    @Test("The current heading is the last one at or above a character")
    func current() {
        let entries = NoteOutline.entries(in: Self.note)
        #expect(NoteOutline.currentIndex(in: entries, atCharacter: 0) == nil, "above the first heading")
        #expect(NoteOutline.currentIndex(in: entries, atCharacter: entries[0].location) == 0)
        #expect(NoteOutline.currentIndex(in: entries, atCharacter: entries[1].location + 3) == 1)
        #expect(NoteOutline.currentIndex(in: entries, atCharacter: (Self.note as NSString).length) == entries.count - 1)
    }

    @Test("A note that starts at ## isn't indented by a level nobody wrote")
    func topLevel() {
        let entries = NoteOutline.entries(in: "## A\n### B\n")
        #expect(NoteOutline.topLevel(of: entries) == 2)
        #expect(NoteOutline.topLevel(of: []) == 1)
    }

    @Test("A note with no headings has an empty outline")
    func empty() {
        #expect(NoteOutline.entries(in: "just\nprose\n").isEmpty)
        #expect(NoteOutline.entries(in: "").isEmpty)
    }
}

#if canImport(UIKit)

import UIKit

@Suite("Outline: going to a heading", .serialized)
@MainActor
struct NoteOutlineScrollTests {

    @Test("A tap puts that heading's line at the top, as a laid-out note has it", arguments: PageViewMode.allCases)
    func headingGoesToTheTop(mode: PageViewMode) async throws {
        let opened = await ReopenTests.open(resumingAtPage: nil, layout: PageLayout(mode: mode))
        let page = opened.page
        let entries = NoteOutline.entries(in: ReopenTests.note)
        try #require(entries.count >= 5)

        // Out of order, so each jump is from somewhere else.
        for entry in [entries[3], entries[1], entries[4], entries[0], entries[2]] {
            page.scroll(toLineAt: entry.location)
            // Layout passes come only when asked for: a window made outside
            // the test host's scene has no display link.
            await ReopenTests.layOut(page, over: 0.2)
            let top = try #require(PageSettlingTests.characterAtTop(of: page.textView))
            #expect(top == entry.location, "\(mode): \(entry.title) should be at the top; the top line starts at \(top)")
        }
        withExtendedLifetime(opened) {}
    }

    @Test("A heading too near the end to reach the top lands as far up as the note scrolls")
    func lastHeadingIsClamped() async throws {
        let short = "# One\n" + (1...30).map { "line \($0)" }.joined(separator: "\n") + "\n## Two\nend\n"
        let (window, coordinator, page) = await PageSettlingTests.openNote(short, layout: PageLayout())
        let entry = try #require(NoteOutline.entries(in: short).last)

        page.scroll(toLineAt: entry.location)
        await PageSettlingTests.settle(0.1)

        let maxOffset = max(page.textView.contentSize.height - page.textView.bounds.height, 0)
        #expect(page.textView.contentOffset.y <= maxOffset + 0.5)
        withExtendedLifetime((window, coordinator)) {}
    }

@Suite("Outline: formulas in headings")
struct NoteOutlineMathTests {

    @Test("A heading's title is the formula's TeX without its dollars")
    func titleDropsDollars() {
        let entries = NoteOutline.entries(in: "# Big-O of $O(n \\log n)$ sorts\n## $$x^2$$\ntext")

        #expect(entries.map(\.title) == ["Big-O of O(n \\log n) sorts", "x^2"])
    }

    @Test("A $$ block's lines are not headings")
    func blockIsNotAHeading() {
        #expect(NoteOutline.entries(in: "$$\n# a\n$$\n# real").map(\.title) == ["real"])
    }
}
}

#endif
