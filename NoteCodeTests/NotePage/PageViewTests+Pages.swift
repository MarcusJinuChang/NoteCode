//
//  PageViewTests+Pages.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

extension PageViewTests {

    @Suite("Pages and the reader's place")
    @MainActor
    struct Pages: PageViewSuite {

        private nonisolated static let longProse = TestFixtures.longProse

        // MARK: Pages

        @Test("An empty note is exactly one page tall")
        func emptyNoteIsOnePage() {
            let harness = PageHarness(text: "")
            let layout = harness.page.pageLayout

            #expect(harness.page.pageCount == 1)
            #expect(abs(harness.page.textView.contentSize.height - layout.noteHeight(pageCount: 1)) < 0.5)
        }

        @Test("Text flows across pages without a line ever sitting in a page break", arguments: PageViewMode.allCases)
        func linesAvoidBreaks(mode: PageViewMode) {
            let layout = PageLayout(mode: mode)
            let harness = PageHarness(text: Self.severalPages, layout: layout)
            let page = harness.page

            #expect(page.pageCount > 2)
            // The breaks are paragraphs pushed down, not exclusion paths (F5).
            #expect(page.textView.textContainer.exclusionPaths.isEmpty)

            let breaks = layout.exclusionBands(pageCount: page.pageCount, containerTop: layout.firstBodyTop)
                .map { $0.offsetBy(dx: 0, dy: layout.firstBodyTop) }
            let intruding = harness.lines.filter { line in breaks.contains { $0.intersects(line.frame.insetBy(dx: 0, dy: 0.5)) } }
            #expect(intruding.isEmpty)
        }

        /// Prose, a run of blank lines long enough to cross a page break in any
        /// mode, and more prose after it.
        private static let blankRun = (0..<30).map { "Line \($0): the loop invariant holds before and after every iteration." }
            .joined(separator: "\n")
            + String(repeating: "\n", count: 60)
            + (30..<60).map { "Line \($0): the loop invariant holds before and after every iteration." }
            .joined(separator: "\n")

        @Test("Blank lines never sit in a page break", arguments: PageViewMode.allCases)
        func blankLinesAvoidBreaks(mode: PageViewMode) {
            let layout = PageLayout(mode: mode)
            let harness = PageHarness(text: Self.blankRun, layout: layout)
            let page = harness.page

            let breaks = layout.exclusionBands(pageCount: page.pageCount, containerTop: layout.firstBodyTop)
                .map { $0.offsetBy(dx: 0, dy: layout.firstBodyTop) }
            let intruding = harness.lines.filter { line in breaks.contains { $0.intersects(line.frame.insetBy(dx: 0, dy: 0.5)) } }

            // TextKit left empty paragraphs where they fell: 18 of them in print
            // layout's first two breaks, before blank lines were laid out as
            // zero-width spaces (probe, 23 September).
            #expect(page.pageCount > 1)
            #expect(intruding.isEmpty)
        }

        @Test("Blank lines paginate the same in every mode")
        func blankLinesPaginateAlike() {
            let harness = PageHarness(text: Self.blankRun)

            var placements: [[String]] = []
            for mode in PageViewMode.allCases {
                let layout = PageLayout(mode: mode)
                harness.switchTo(layout)
                placements.append(harness.lines.map { line in
                    let index = layout.pageIndex(atY: line.frame.minY)
                    return "\(line.range.location) p\(index) \(String(format: "%.1f", line.frame.minY - layout.bodyTop(ofPage: index)))"
                })
            }

            #expect(placements[0] == placements[1])
            #expect(placements[0] == placements[2])
        }

        @Test("A tap on a blank line puts the caret on it, not on the line below")
        func tapOnBlankLine() throws {
            let harness = PageHarness(text: Self.blankRun, layout: PageLayout(mode: .print))
            let textView = harness.page.textView
            let text = textView.textStorage.string as NSString
            // The first blank line: the newline after one.
            let blank = text.range(of: "\n\n").location + 1
            let position = try #require(textView.position(from: textView.beginningOfDocument, offset: blank))
            let caret = textView.caretRect(for: position)

            let tapped = try #require(textView.closestPosition(to: CGPoint(x: caret.midX + 200, y: caret.midY)))

            #expect(textView.offset(from: textView.beginningOfDocument, to: tapped) == blank)
        }

        @Test("A blank line keeps the note's text a newline")
        func blankLineTextUnchanged() {
            let harness = PageHarness(text: Self.blankRun)

            #expect(harness.page.textView.text == Self.blankRun)
            #expect(!harness.page.textView.text.contains(BlankLineLayout.stand))
        }

        @Test("Every mode puts every line on the same page, at the same place on it")
        func paginationIdenticalAcrossModes() {
            let harness = PageHarness(text: Self.severalPages)

            var placements: [[String]] = []
            for mode in PageViewMode.allCases {
                let layout = PageLayout(mode: mode)
                harness.switchTo(layout)
                placements.append(harness.lines.map { line in
                    let index = layout.pageIndex(atY: line.frame.minY)
                    return "\(line.range.location) p\(index) \(String(format: "%.1f", line.frame.minY - layout.bodyTop(ofPage: index)))"
                })
            }

            #expect(placements[0].count > 250)   // wrapped paragraphs, not just one line each
            #expect(placements[0] == placements[1])
            #expect(placements[0] == placements[2])
        }

        @Test("Switching modes keeps the reader at the same place on the same page")
        func modeSwitchKeepsPlace() {
            let harness = PageHarness(text: Self.severalPages, layout: PageLayout(mode: .seamless))
            harness.page.textView.contentOffset.y = PageLayout(mode: .seamless).bodyTop(ofPage: 2) + 300
            harness.layOut()

            for mode in [PageViewMode.print, .compressed, .seamless, .print] {
                let layout = PageLayout(mode: mode)
                harness.switchTo(layout)
                // Checked after the layout passes, not just after the switch: a
                // page count that settles late relays out the note and moves the
                // offset after it was set.
                #expect(abs(harness.page.textView.contentOffset.y - (layout.bodyTop(ofPage: 2) + 300)) < 0.5, "\(mode)")
            }
        }

        @Test("At the very top of a note, switching modes stays at the very top", arguments: PageViewMode.allCases)
        func noteTopStaysAtTop(target: PageViewMode) {
            let start: PageViewMode = target == .print ? .seamless : .print
            let harness = PageHarness(text: Self.severalPages, layout: PageLayout(mode: start))

            harness.switchTo(PageLayout(mode: target))

            #expect(harness.page.textView.contentOffset.y == 0)
        }

        @Test("Changing orientation re-wraps the note and keeps the same text at the top")
        func orientationKeepsTopText() throws {
            let harness = PageHarness(text: Self.severalPages)
            harness.page.textView.contentOffset.y = 2500
            harness.layOut()
            let before = try #require(harness.lineAtTop)

            harness.switchTo(PageLayout(orientation: .landscape))

            let after = try #require(harness.lineAtTop)
            let line = try #require(harness.lines.first { $0.range.location == after })
            // Lines re-wrap, so the top line may now start earlier; it has to be
            // the one holding the character that was at the top.
            #expect(NSLocationInRange(before, line.range) || line.range.location == before)
        }

        @Test("Scrolled to the top of a sheet, switching to seamless shows that page from its top edge")
        func sheetTopOpensPageStart() {
            let print = PageLayout(mode: .print)
            let seamless = PageLayout(mode: .seamless)
            let harness = PageHarness(text: Self.severalPages, layout: print)
            harness.page.textView.contentOffset.y = print.sheet(ofPage: 2).minY
            harness.layOut()

            harness.switchTo(seamless)

            // After the layout passes. When the page count was taken from the old
            // mode's text height it swung as the text reflowed, each change
            // relaid out the note, and TextKit moved the offset 33pt into the page.
            #expect(abs(harness.page.textView.contentOffset.y - seamless.scrollTop(forPage: 2)) < 0.5)
        }

        @Test("A note with landscape pages opens at its very top", arguments: PageViewMode.allCases)
        func landscapeOpensAtTop(mode: PageViewMode) {
            // PageView starts with default portrait pages and takes the note's own
            // on opening, which counts as an orientation change. That path kept
            // the top line at the top of the view: 36pt down in seamless, past the
            // note's top margin.
            let harness = PageHarness(text: Self.severalPages, layout: PageLayout(orientation: .landscape, mode: mode))

            #expect(harness.page.textView.contentOffset.y == 0)
        }

        @Test("At a note's very top, switching orientation stays at the very top", arguments: PageOrientation.allCases)
        func orientationSwitchAtTopStaysAtTop(target: PageOrientation) {
            let start: PageOrientation = target == .portrait ? .landscape : .portrait
            let harness = PageHarness(text: Self.severalPages, layout: PageLayout(orientation: start))
            harness.page.textView.contentOffset.y = 0
            harness.layOut()

            harness.switchTo(PageLayout(orientation: target))

            #expect(harness.page.textView.contentOffset.y == 0)
        }

        @Test("Landscape pages wrap wider")
        func landscapeRewraps() {
            let harness = PageHarness(text: Self.longProse)
            let portraitLines = harness.lines.count

            harness.switchTo(PageLayout(orientation: .landscape))

            #expect(harness.page.textView.bounds.width == 1056)
            #expect(harness.page.textView.textContainer.size.width == 912)
            #expect(harness.lines.count < portraitLines)
        }
    }
}

#endif
