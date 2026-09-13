//
//  PageLayoutTests.swift
//  NoteCodeTests
//

import CoreGraphics
import Testing
@testable import NoteCode

@Suite("Page layout")
struct PageLayoutTests {

    private static let everyLayout: [PageLayout] = PageOrientation.allCases.flatMap { orientation in
        PageViewMode.allCases.map { PageLayout(orientation: orientation, mode: $0) }
    }

    // MARK: Paper

    @Test("Pages are US Letter at 96 points to the inch")
    func letterSize() {
        #expect(PageLayout(orientation: .portrait).pageSize == CGSize(width: 816, height: 1056))
        #expect(PageLayout(orientation: .landscape).pageSize == CGSize(width: 1056, height: 816))
    }

    @Test("A sheet prints at exactly Letter size, 612 by 792 printer points")
    func printsAtPaperSize() {
        let sheet = PageLayout(orientation: .portrait, mode: .print).sheet(ofPage: 0)
        let toPrinter: CGFloat = 72 / PageLayout.unitsPerInch

        #expect(sheet.width * toPrinter == 612)
        #expect(sheet.height * toPrinter == 792)
    }

    @Test("Lines wrap at the same width in every mode", arguments: PageOrientation.allCases)
    func textWidthIgnoresMode(orientation: PageOrientation) {
        let widths = PageViewMode.allCases.map { PageLayout(orientation: orientation, mode: $0).textWidth }
        #expect(Set(widths).count == 1)
    }

    // MARK: One pagination

    @Test("A page holds the same height of text in every mode", arguments: PageOrientation.allCases)
    func bodyHeightIgnoresMode(orientation: PageOrientation) {
        // The invariant everything else rests on. If a page held more text in
        // one mode than another, lines would move to other pages on switching,
        // and no conversion could keep ink on its words.
        let heights = PageViewMode.allCases.map { PageLayout(orientation: orientation, mode: $0).bodyHeight }
        #expect(Set(heights).count == 1)
    }

    @Test("Every mode's page break has height, so a straddling line is always pushed", arguments: PageViewMode.allCases)
    func gapIsNeverZero(mode: PageViewMode) {
        #expect(PageLayout(mode: mode).gap > 0)
    }

    @Test("Bands sit exactly between one body and the next", arguments: everyLayout)
    func bandsBetweenBodies(layout: PageLayout) {
        let top = layout.firstBodyTop
        let bands = layout.exclusionBands(pageCount: 4, containerTop: top)

        #expect(bands.count == 4)
        for (index, band) in bands.enumerated() {
            #expect(band.minY + top == layout.bodyTop(ofPage: index) + layout.bodyHeight)
            #expect(band.maxY + top == layout.bodyTop(ofPage: index + 1))
            #expect(band.width == layout.textWidth)
        }
    }

    // MARK: Which page

    @Test("A point belongs to the nearer page, splitting the band down the middle", arguments: everyLayout)
    func pageBoundaryMidBand(layout: PageLayout) {
        let breakY = layout.bodyTop(ofPage: 2) + layout.bodyHeight + layout.gap / 2

        #expect(layout.pageIndex(atY: layout.bodyTop(ofPage: 2)) == 2)
        #expect(layout.pageIndex(atY: breakY - 0.25) == 2)
        #expect(layout.pageIndex(atY: breakY + 0.25) == 3)
        #expect(layout.pageIndex(atY: 0) == 0)
        #expect(layout.pageIndex(atY: -50) == 0)
    }

    @Test("An empty note is one page")
    func emptyNote() {
        let layout = PageLayout()
        #expect(layout.pageCount(textBottom: layout.firstBodyTop, inkBottom: nil) == 1)
    }

    @Test("Text or ink reaching into a page adds it", arguments: everyLayout)
    func pageCountFollowsContent(layout: PageLayout) {
        let intoThird = layout.bodyTop(ofPage: 2) + 40

        #expect(layout.pageCount(textBottom: intoThird, inkBottom: nil) == 3)
        #expect(layout.pageCount(textBottom: layout.firstBodyTop + 10, inkBottom: intoThird) == 3)
    }

    @Test("A note is tall enough for every page it has", arguments: everyLayout)
    func noteHeightCoversPages(layout: PageLayout) {
        let height = layout.noteHeight(pageCount: 3)

        #expect(height >= layout.bodyTop(ofPage: 2) + layout.bodyHeight)
        if layout.mode == .print {
            #expect(height >= layout.sheet(ofPage: 2).maxY)
        }
    }

    // MARK: Print layout

    @Test("Sheets don't overlap, and are separated by the sheet gap")
    func sheetsSeparated() {
        let layout = PageLayout(orientation: .portrait, mode: .print)
        let first = layout.sheet(ofPage: 0)
        let second = layout.sheet(ofPage: 1)

        #expect(first.minY == PageLayout.printSheetGap)
        #expect(second.minY - first.maxY == PageLayout.printSheetGap)
    }

    @Test("A sheet's text sits inside its margins", arguments: PageOrientation.allCases)
    func bodyInsideSheet(orientation: PageOrientation) {
        let layout = PageLayout(orientation: orientation, mode: .print)
        let sheet = layout.sheet(ofPage: 5)

        #expect(layout.bodyTop(ofPage: 5) - sheet.minY == PageLayout.margin)
        #expect(sheet.maxY - (layout.bodyTop(ofPage: 5) + layout.bodyHeight) == PageLayout.margin)
    }

    @Test("Compressed breaks fall in the middle of their band")
    func breakLines() {
        let layout = PageLayout(mode: .compressed)
        let bodyBottom = layout.bodyTop(ofPage: 0) + layout.bodyHeight

        #expect(layout.breakLineY(afterPage: 0) == bodyBottom + PageLayout.compressedGap / 2)
    }

    // MARK: Between modes

    @Test("A point keeps its page and its place on the page in every mode", arguments: PageOrientation.allCases)
    func conversionKeepsPagePosition(orientation: PageOrientation) {
        let seamless = PageLayout(orientation: orientation, mode: .seamless)
        let y = seamless.bodyTop(ofPage: 3) + 123.5

        for mode in PageViewMode.allCases {
            let other = PageLayout(orientation: orientation, mode: mode)
            let converted = seamless.convert(y: y, to: other)

            #expect(converted == other.bodyTop(ofPage: 3) + 123.5)
            #expect(other.pageIndex(atY: converted!) == 3)
        }
    }

    @Test("Any point converts into print layout and back exactly", arguments: everyLayout)
    func roundTripThroughPrint(layout: PageLayout) {
        let print = PageLayout(orientation: layout.orientation, mode: .print)

        for y in stride(from: CGFloat(0), through: layout.noteHeight(pageCount: 4), by: 7.25) {
            let there = layout.convert(y: y, to: print)!
            #expect(print.convert(y: there, to: layout) == y)
        }
    }

    @Test("A point in a sheet's margin reaches onto the next page in seamless, so print layout can't be converted out and back")
    func marginsDontSurviveNarrowerBreaks() {
        // The reason ink is kept in print layout's coordinates. If this ever
        // stopped being true, that indirection could go.
        let print = PageLayout(mode: .print)
        let seamless = PageLayout(mode: .seamless)
        let inBottomMargin = print.bodyTop(ofPage: 2) + print.bodyHeight + 30

        let there = print.convert(y: inBottomMargin, to: seamless)!
        #expect(seamless.pageIndex(atY: there) == 3)
        #expect(seamless.convert(y: there, to: print) != inBottomMargin)
    }

    @Test("A page is shown from its top edge, and the first page from the note's top", arguments: everyLayout)
    func scrollTopShowsPageEdge(layout: PageLayout) {
        #expect(layout.scrollTop(forPage: 0) == 0)

        let top = layout.scrollTop(forPage: 3)
        #expect(top < layout.bodyTop(ofPage: 3))
        #expect(top > layout.bodyTop(ofPage: 2) + layout.bodyHeight - 0.001)

        switch layout.mode {
        case .print:      #expect(top == layout.sheet(ofPage: 3).minY - PageLayout.printSheetGap / 2)
        case .compressed: #expect(top == layout.breakLineY(afterPage: 2))
        case .seamless:   #expect(top == layout.bodyTop(ofPage: 3) - PageLayout.seamlessGap / 2)
        }
    }

    @Test("There is no conversion between orientations")
    func noConversionAcrossOrientations() {
        let portrait = PageLayout(orientation: .portrait)
        #expect(portrait.convert(y: 500, to: PageLayout(orientation: .landscape)) == nil)
    }

    @Test("Stored values keep their spelling, or saved choices are forgotten on update")
    func rawValuesAreStable() {
        #expect(PageOrientation(rawValue: "portrait") == .portrait)
        #expect(PageOrientation(rawValue: "landscape") == .landscape)
        #expect(PageViewMode(rawValue: "seamless") == .seamless)
        #expect(PageViewMode(rawValue: "compressed") == .compressed)
        #expect(PageViewMode(rawValue: "print") == .print)
    }

    @Test("Defaults are portrait pages, seamless")
    func defaults() {
        #expect(PageLayout() == PageLayout(orientation: .portrait, mode: .seamless))
    }
}
