//
//  PageViewTests+Bands.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

extension PageViewTests {

    @Suite("Sheets, breaks, covers and the surround")
    @MainActor
    struct Bands: PageViewSuite {

        // MARK: Decorations

        @Test("Print layout draws a sheet per page, exactly where each prints")
        func printSheets() {
            let layout = PageLayout(mode: .print)
            let harness = PageHarness(text: Self.severalPages, layout: layout)
            let page = harness.page

            #expect(page.decorations.sheetFrames == (0..<page.pageCount).map { layout.sheet(ofPage: $0) })
            #expect(page.decorations.breakLineYs.isEmpty)
        }

        @Test("Print layout leaves the surround showing either side of its sheets")
        func printSheetsInset() {
            let harness = PageHarness(text: Self.severalPages, area: CGSize(width: 872, height: 1100), layout: PageLayout(mode: .print))
            let frame = harness.page.textView.frame

            #expect(abs(frame.minX - CanvasGeometry.printGutter) < 0.5)
            #expect(abs((872 - frame.maxX) - CanvasGeometry.printGutter) < 0.5)

            harness.switchTo(PageLayout(mode: .seamless))
            #expect(abs(harness.page.textView.frame.minX) < 0.5)
        }

        @Test("A touch beside the page goes to the text view, which scrolls the note", arguments: PageViewMode.allCases)
        func besideThePageScrolls(mode: PageViewMode) throws {
            // Wider than a page fits at 1.25x, so there's room either side.
            let harness = PageHarness(text: Self.severalPages, area: CGSize(width: 1300, height: 900), layout: PageLayout(mode: mode))
            let page = harness.page
            let frame = page.textView.frame
            try #require(frame.minX > 20)

            #expect(page.hitTest(CGPoint(x: frame.minX / 2, y: 400), with: nil) === page.textView)
            #expect(page.hitTest(CGPoint(x: (frame.maxX + 1300) / 2, y: 400), with: nil) === page.textView)
        }

        @Test("In ink mode, print layout's surround between sheets is the text view's, and the sheets are the canvas's")
        func surroundBetweenSheets() throws {
            let layout = PageLayout(mode: .print)
            let harness = PageHarness(text: Self.severalPages, layout: layout)
            let page = harness.page
            try #require(page.pageCount > 1)
            page.canvas.isUserInteractionEnabled = true

            let gapY = (layout.sheet(ofPage: 0).maxY + layout.sheet(ofPage: 1).minY) / 2
            page.textView.contentOffset.y = gapY - 300
            harness.layOut()

            func hit(_ note: CGPoint) -> UIView? {
                page.hitTest(page.textView.convert(note, to: page), with: nil)
            }
            let x = layout.pageSize.width / 2

            let between = try #require(hit(CGPoint(x: x, y: gapY)))
            #expect(!between.isDescendant(of: page.canvas))
            let onSheet = try #require(hit(CGPoint(x: x, y: gapY + 100)))
            #expect(onSheet.isDescendant(of: page.canvas))
        }

        @Test("The page has square corners and no border in every mode: it fills its window")
        func pageIsSquare() {
            let harness = PageHarness(text: Self.severalPages, area: CGSize(width: 1300, height: 900), layout: PageLayout(mode: .seamless))
            let page = harness.page

            #expect(page.textView.layer.cornerRadius == 0)
            // The page's edge is the one bordered view; nothing else is (W2).
            #expect(!page.subviews.contains { !($0 is PageEdgeView) && $0.layer.borderWidth > 0 })
            #expect(page.subviews.contains { $0 is PageEdgeView && !$0.isHidden })
            // Painted as the page against its surround.
            #expect(page.textView.backgroundColor == PageView.pageColor)

            harness.switchTo(PageLayout(mode: .print))
            #expect(page.textView.layer.cornerRadius == 0)
            #expect(page.decorations.sheetBorderWidths.allSatisfy { $0 > 0 })
        }

        @Test("A resting clearance lets the end of the note scroll clear of a bar floating over the page, and is given back")
        func restingClearanceInsetsTheText() throws {
            let harness = PageHarness()
            let page = harness.page
            harness.window.frame = harness.window.screen.bounds
            page.layoutIfNeeded()
            #expect(page.textView.contentInset.bottom == 0)

            page.restingClearance = 116
            #expect(abs(page.textView.contentInset.bottom - 116 / page.displayScale) < 0.5)

            page.restingClearance = 0
            #expect(page.textView.contentInset.bottom == 0)
        }

        @Test("Compressed layout draws a line at each break, and seamless draws nothing")
        func breakLines() {
            let compressed = PageLayout(mode: .compressed)
            let harness = PageHarness(text: Self.severalPages, layout: compressed)
            let count = harness.page.pageCount

            #expect(harness.page.decorations.breakLineYs == (0..<(count - 1)).map { compressed.breakLineY(afterPage: $0) })
            #expect(harness.page.decorations.sheetFrames.isEmpty)

            harness.switchTo(PageLayout(mode: .seamless))
            #expect(harness.page.decorations.breakLineYs.isEmpty)
            #expect(harness.page.decorations.sheetFrames.isEmpty)
        }

        // MARK: The page against its surround

        /// A pixel of `view` as drawn, as sRGB bytes.
        private static func pixel(of view: UIView, at point: CGPoint) throws -> [Int] {
            try pixels(of: view, at: [point])[0]
        }

        /// Pixels of `view` as drawn, from one drawing, as sRGB bytes.
        private static func pixels(of view: UIView, at points: [CGPoint]) throws -> [[Int]] {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            var drawn = false
            let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { _ in
                drawn = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            }
            try #require(drawn)
            let cg = try #require(image.cgImage)
            return try points.map { point in
                var bytes = [UInt8](repeating: 0, count: 4)
                let context = try #require(CGContext(
                    data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(cg, in: CGRect(x: -point.x.rounded(.down), y: -(CGFloat(cg.height) - point.y.rounded(.down) - 1), width: CGFloat(cg.width), height: CGFloat(cg.height)))
                return bytes.prefix(3).map(Int.init)
            }
        }

        /// What a dynamic colour is in an appearance, as sRGB bytes.
        private static func bytes(_ color: UIColor, in style: UIUserInterfaceStyle) -> [Int] {
            var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
            color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
            return [r, g, b].map { Int(($0 * 255).rounded()) }
        }

        private static func near(_ a: [Int], _ b: [Int]) -> Bool {
            zip(a, b).allSatisfy { abs($0 - $1) <= 2 }
        }

        @Test(
            "Seamless and compressed show the page against the surround, either side of it",
            arguments: [PageViewMode.seamless, .compressed], [UIUserInterfaceStyle.light, .dark]
        )
        func pageAgainstSurround(mode: PageViewMode, style: UIUserInterfaceStyle) throws {
            // Wider than a page fits at 1.25x, so there is surround either side.
            let harness = PageHarness(text: Self.severalPages, area: CGSize(width: 1300, height: 900), layout: PageLayout(mode: mode))
            harness.page.overrideUserInterfaceStyle = style
            harness.layOut()
            let page = harness.page
            let frame = page.textView.frame
            try #require(frame.minX > 40)

            // Beside the page, and inside it where there is no text: the margin.
            let beside = try Self.pixel(of: page, at: CGPoint(x: frame.minX / 2, y: 450))
            let marginX = frame.minX + 20 * page.displayScale
            let onPage = try Self.pixel(of: page, at: CGPoint(x: marginX, y: 450))

            #expect(Self.near(beside, Self.bytes(.secondarySystemBackground, in: style)), "beside: \(beside)")
            #expect(Self.near(onPage, Self.bytes(.systemBackground, in: style)), "on the page: \(onPage)")
            // The page's column runs the full height of the area, not just the
            // note: the corners are the only part of it that gives way.
            let below = try Self.pixel(of: page, at: CGPoint(x: marginX, y: 880))
            #expect(Self.near(below, Self.bytes(.systemBackground, in: style)), "below: \(below)")
        }

        @Test("Print layout keeps the surround between its sheets and the page colour on them", arguments: [UIUserInterfaceStyle.light, .dark])
        func printAgainstSurround(style: UIUserInterfaceStyle) throws {
            let layout = PageLayout(mode: .print)
            let harness = PageHarness(text: Self.severalPages, area: CGSize(width: 1300, height: 900), layout: layout)
            harness.page.overrideUserInterfaceStyle = style
            let page = harness.page
            try #require(page.pageCount > 1)

            // Scrolled so the gap between the first two sheets is on screen.
            let gapY = (layout.sheet(ofPage: 0).maxY + layout.sheet(ofPage: 1).minY) / 2
            page.textView.contentOffset.y = gapY - 300
            harness.layOut()

            let inGap = page.textView.convert(CGPoint(x: layout.pageSize.width / 2, y: gapY), to: page)
            let onSheet = page.textView.convert(CGPoint(x: PageLayout.margin / 2, y: gapY + 100), to: page)

            #expect(Self.near(try Self.pixel(of: page, at: inGap), Self.bytes(.secondarySystemBackground, in: style)))
            #expect(Self.near(try Self.pixel(of: page, at: onSheet), Self.bytes(.systemBackground, in: style)))
        }

        @Test("Compressed layout marks a page end with a dashed line and nothing else", arguments: [UIUserInterfaceStyle.light, .dark])
        func compressedBreakIsOnlyALine(style: UIUserInterfaceStyle) throws {
            let layout = PageLayout(mode: .compressed)
            let harness = PageHarness(text: Self.severalPages, area: CGSize(width: 1300, height: 900), layout: layout)
            harness.page.overrideUserInterfaceStyle = style
            let page = harness.page
            try #require(page.pageCount > 1)

            let top = layout.bodyTop(ofPage: 0) + layout.bodyHeight
            page.textView.contentOffset.y = top - 300
            harness.layOut()

            // Across the break, clear of the line in its middle, is the page:
            // the same surface as above and below it, not a gap.
            for x in [PageLayout.margin / 2, layout.pageSize.width / 2, layout.pageSize.width - PageLayout.margin / 2] {
                for y in [top + 3, top + PageLayout.compressedGap - 3] {
                    let point = page.textView.convert(CGPoint(x: x, y: y), to: page)
                    let got = try Self.pixel(of: page, at: point)
                    #expect(Self.near(got, Self.bytes(.systemBackground, in: style)), "break at \(x),\(y): \(got)")
                }
            }
        }

        // MARK: Ink stays on print layout's sheets

        // MARK: Covers

        @Test("Covers lie over the ink, on exactly the bands no page's ink shows in", arguments: PageViewMode.allCases)
        func coversOverTheInk(mode: PageViewMode) throws {
            let harness = PageHarness(text: Self.severalPages, layout: PageLayout(mode: .seamless))
            harness.switchTo(PageLayout(mode: mode))
            let page = harness.page

            #expect(page.covers.bandFrames == page.pageLayout.inkHiddenBands(pageCount: page.pageCount))
            let views = page.textView.subviews
            let covers = try #require(views.firstIndex(of: page.covers))
            let canvas = try #require(views.firstIndex(of: page.canvas))
            #expect(covers > canvas)
            #expect(!page.covers.isUserInteractionEnabled)
        }

        @Test("No line of text is ever under a cover", arguments: PageViewMode.allCases)
        func coversMissTheText(mode: PageViewMode) {
            let harness = PageHarness(text: Self.severalPages, layout: PageLayout(mode: mode))
            let bands = harness.page.covers.bandFrames

            for line in harness.lines {
                #expect(bands.allSatisfy { $0.intersection(line.frame).height < 0.001 }, "\(line.frame)")
            }
        }

        @Test(
            "A cover looks like the page beneath it",
            arguments: [PageViewMode.compressed, .print], [UIUserInterfaceStyle.light, .dark]
        )
        func coversMatchThePage(mode: PageViewMode, style: UIUserInterfaceStyle) throws {
            let layout = PageLayout(mode: mode)
            let harness = PageHarness(text: Self.severalPages, area: CGSize(width: 1300, height: 900), layout: layout)
            harness.page.overrideUserInterfaceStyle = style
            let page = harness.page
            try #require(page.pageCount > 1)

            let band = try #require(page.covers.bandFrames.first { $0.minY > 0 })
            page.textView.contentOffset.y = band.midY - 300
            harness.layOut()

            // Down the band and across it: the dashed line, the sheets' edges,
            // borders and shadows, the surround.
            let xs = [0.5, 2, PageLayout.margin / 2, layout.pageSize.width / 2 + 3, layout.pageSize.width - 1]
            let ys = stride(from: band.minY + 0.5, to: band.maxY, by: 3).map { $0 } + [layout.breakLineY(afterPage: 0)]
            let points = xs.flatMap { x in ys.map { y in page.textView.convert(CGPoint(x: x, y: y), to: page) } }
            page.covers.isHidden = true
            let beneath = try Self.pixels(of: page, at: points)
            page.covers.isHidden = false
            let covered = try Self.pixels(of: page, at: points)

            for (under, over) in zip(beneath, covered) {
                #expect(Self.near(under, over), "beneath \(under), cover \(over)")
            }
        }

        @Test("Switching modes repaints the page column and the surround each time")
        func switchingKeepsPaintInStep() {
            let harness = PageHarness(text: Self.severalPages, layout: PageLayout(mode: .print))
            let page = harness.page
            #expect(page.textView.backgroundColor == .clear)
            #expect(page.backgroundColor == PageView.surroundColor)

            harness.switchTo(PageLayout(mode: .seamless))
            #expect(page.textView.backgroundColor == PageView.pageColor)
            #expect(page.backgroundColor == PageView.surroundColor)

            harness.switchTo(PageLayout(mode: .print))
            #expect(page.textView.backgroundColor == .clear)
        }
    }
}

#endif
