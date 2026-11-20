//
//  PageViewTests+InkBreaks.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

extension PageViewTests {

    @Suite("Ink across page breaks")
    @MainActor
    struct InkBreaks: PageViewSuite {

        // MARK: Ink across page breaks

        /// The canvas's strokes, top to bottom.
        private static func shownStrokes(_ harness: PageHarness) -> [PKStroke] {
            harness.page.canvas.markup.subelements.strokes.sorted { area(of: $0).minY < area(of: $1).minY }
        }

        @Test(
            "A stroke drawn across a page break stays on its words on both pages in every mode",
            arguments: PageViewMode.allCases
        )
        func strokeAcrossABreakStaysOnItsWords(drawnIn mode: PageViewMode) throws {
            let drawn = PageLayout(mode: mode)
            let harness = PageHarness(text: Self.severalPages, layout: drawn)
            try #require(harness.page.pageCount > 3)

            // From 60 points above page 2's last line to 60 below page 3's first.
            let bottom = drawn.bodyTop(ofPage: 1) + drawn.bodyHeight
            let top = drawn.bodyTop(ofPage: 2)
            Self.draw([Self.verticalStroke(from: bottom - 60, to: top + 60)], on: harness)

            // Where each piece sits against its own page's text, per mode.
            var placements: [[CGFloat]] = []
            var overflow: [CGFloat] = []
            // The other modes first: switching to the mode it's in shows nothing anew.
            for mode in PageViewMode.allCases.filter({ $0 != mode }) + [mode] {
                let layout = PageLayout(mode: mode)
                harness.switchTo(layout)
                let pieces = Self.shownStrokes(harness).map(Self.area(of:))
                // Only seamless shows the part past the page it was started on.
                try #require(pieces.count == (mode == .seamless ? 2 : 1), "in \(mode)")
                let pageBottom = layout.bodyTop(ofPage: 1) + layout.bodyHeight
                let pageTop = layout.bodyTop(ofPage: 2)
                placements.append([pieces[0].minY - pageBottom, pieces[0].maxY - pageBottom])
                // Nothing in the room seamless doesn't have.
                #expect(pieces[0].maxY <= layout.inkRegion(ofPage: 1, pageCount: harness.page.pageCount).maxY + 0.001)
                if mode == .seamless {
                    overflow = [pieces[1].minY - pageTop, pieces[1].maxY - pageTop]
                    #expect(pieces[1].minY >= layout.inkRegion(ofPage: 2, pageCount: harness.page.pageCount).minY - 0.001)
                }
            }
            for placement in placements.dropFirst() {
                #expect(zip(placement, placements[0]).allSatisfy { abs($0 - $1) < 0.5 }, "\(placements)")
            }
            // The text above the break is where the stroke began, and in
            // seamless it carries on to where it ended.
            #expect(abs(placements[0][0] - -62) < 1.5, "\(placements[0])")
            #expect(abs((overflow.last ?? 0) - 62) < 1.5, "\(overflow)")
        }

        @Test("A stroke reaching three pages is stored as three pieces, each inside its sheet")
        func strokeOverThreePages() throws {
            let seamless = PageLayout(mode: .seamless)
            let harness = PageHarness(text: Self.severalPages, layout: seamless)
            try #require(harness.page.pageCount > 3)

            let from = seamless.bodyTop(ofPage: 0) + seamless.bodyHeight - 50
            let to = seamless.bodyTop(ofPage: 2) + 50
            Self.draw([Self.verticalStroke(from: from, to: to)], on: harness)

            let print = Self.printPortrait
            let stored = harness.page.ink.subelements.strokes.map(Self.area(of:)).sorted { $0.minY < $1.minY }
            try #require(stored.count == 3)
            for (index, piece) in stored.enumerated() {
                #expect(print.sheet(ofPage: index).contains(piece))
                #expect(print.inkRegion(ofPage: index, pageCount: harness.page.pageCount).contains(piece))
            }
        }

        @Test("A stroke drawn across compressed's strip leaves the strip out")
        func compressedStripLeftOut() throws {
            let compressed = PageLayout(mode: .compressed)
            let harness = PageHarness(text: Self.severalPages, layout: compressed)
            let bottom = compressed.bodyTop(ofPage: 1) + compressed.bodyHeight
            Self.draw([Self.verticalStroke(from: bottom - 40, to: compressed.bodyTop(ofPage: 2) + 40)], on: harness)

            // In seamless the two pieces meet: the strip had no room to keep.
            harness.switchTo(PageLayout(mode: .seamless))
            let pieces = Self.shownStrokes(harness).map(Self.area(of:))
            try #require(pieces.count == 2)
            #expect(abs(pieces[0].maxY - pieces[1].minY) < 0.001)
        }

        /// Erases what the canvas shows of `element` and tells the page, as
        /// PaperKit's eraser would.
        private static func erase(_ id: MarkupOrderedSet.ElementID, on harness: PageHarness) {
            var markup = harness.page.canvas.markup
            markup.subelements.removeElement(for: id)
            harness.page.canvas.markup = markup
            harness.page.canvas.onMarkupChanged?()
        }

        /// What PaperKit's pixel eraser adds over `stroke`: not the stroke cut
        /// apart, but a stroke of its own in `com.apple.ink.eraser`, an ink
        /// `PKInk.InkType` has no case for (simulator, 28 October).
        private static func eraserStroke(over stroke: PKStroke) -> PKStroke {
            var eraser = stroke
            eraser.ink = PKInkReference(inkType: __PKInkType(rawValue: "com.apple.ink.eraser"), color: .clear) as PKInk
            return eraser
        }

        @Test("A pixel erase is taken in and saved")
        func pixelEraseIsSaved() async {
            let harness = PageHarness(text: Self.severalPages)
            var reported = 0
            harness.page.onInkChanged = { _ in reported += 1 }
            let drawn = Self.stroke(at: 300)

            Self.draw([drawn], on: harness)
            #expect(await waitFor { reported == 1 })
            // Taken in off the main thread, where reading the eraser's
            // `inkType` trapped.
            Self.draw([Self.eraserStroke(over: drawn)], on: harness)
            #expect(await waitFor { reported == 2 })

            let inks = harness.page.ink.subelements.strokes.map { ($0.ink as PKInkReference).inkType.rawValue }
            #expect(inks == [PKInk.InkType.pen.rawValue, "com.apple.ink.eraser"])
        }

        /// Where a stroke shows ink: its mask's parts with area to speak of.
        private static func inked(_ stroke: PKStroke) -> CGRect {
            guard let mask = stroke.mask else { return stroke.renderFrame }
            return mask.cgPath.componentsSeparated()
                .map(\.boundingBoxOfPath)
                .filter { $0.width > 0.5 && $0.height > 0.5 }
                .reduce(CGRect.null) { $0.union($1) }
                .applying(stroke.transform)
        }

        @Test(
            "In compressed and print layout, a stroke drawn across a border stops at it once the pen lifts",
            arguments: [PageViewMode.compressed, .print], [true, false]
        )
        func strokeStopsAtTheBorder(in mode: PageViewMode, downward: Bool) async throws {
            let layout = PageLayout(mode: mode)
            let harness = PageHarness(text: Self.severalPages, layout: layout)
            var reported = 0
            harness.page.onInkChanged = { _ in reported += 1 }
            let bottom = layout.bodyTop(ofPage: 1) + layout.bodyHeight
            let top = layout.bodyTop(ofPage: 2)
            let stroke = downward
                ? Self.verticalStroke(from: bottom - 60, to: top + 60)
                : Self.verticalStroke(from: top + 60, to: bottom - 60)
            Self.draw([stroke], on: harness)
            let drawn = try #require(harness.page.canvas.markup.subelements.ids.first)

            #expect(await waitFor { reported == 1 })

            // One stroke still, the one PaperKit's undo knows, showing only on
            // the page the pen went down on.
            let shown = Self.shownStrokes(harness)
            try #require(shown.count == 1)
            #expect(shown[0].elementID == drawn)
            let own = layout.inkRegion(ofPage: downward ? 1 : 2, pageCount: harness.page.pageCount)
            #expect(own.insetBy(dx: 0, dy: -0.001).contains(Self.inked(shown[0])), "\(Self.inked(shown[0])) in \(own)")
            // The rest is kept, for seamless.
            let stored = harness.page.ink.subelements.strokes
            #expect(stored.count == 2)
            #expect(stored.filter { InkPages.isOverflow($0.id) }.count == 1)

            // Seamless shows it whole again, both pieces on their words: from
            // 60 points above one page's last line to 60 below the next's first.
            let seamless = PageLayout(mode: .seamless)
            harness.switchTo(seamless)
            let pieces = Self.shownStrokes(harness).map(Self.inked)
            try #require(pieces.count == 2)
            let pageBottom = seamless.bodyTop(ofPage: 1) + seamless.bodyHeight
            let pageTop = seamless.bodyTop(ofPage: 2)
            #expect(abs(pieces[0].maxY - pieces[1].minY) < 0.001, "\(pieces)")
            #expect(abs(pieces[0].minY - (pageBottom - 62)) < 1.5, "\(pieces)")
            #expect(abs(pieces[1].maxY - (pageTop + 62)) < 1.5, "\(pieces)")
        }

        @Test("A stroke drawn across a break in seamless shows only on the page it was started on elsewhere")
        func seamlessStrokeElsewhere() throws {
            let seamless = PageLayout(mode: .seamless)
            let harness = PageHarness(text: Self.severalPages, layout: seamless)
            let bottom = seamless.bodyTop(ofPage: 1) + seamless.bodyHeight
            Self.draw([Self.verticalStroke(from: bottom - 60, to: bottom + 60)], on: harness)

            for mode in [PageViewMode.compressed, .print] {
                let layout = PageLayout(mode: mode)
                harness.switchTo(layout)
                let shown = Self.shownStrokes(harness)
                try #require(shown.count == 1, "in \(mode)")
                let own = layout.inkRegion(ofPage: 1, pageCount: harness.page.pageCount)
                #expect(own.insetBy(dx: 0, dy: -0.001).contains(Self.area(of: shown[0])), "in \(mode)")
            }
            harness.switchTo(seamless)
            #expect(Self.shownStrokes(harness).count == 2)
        }

        @Test("Erasing what shows of a stroke takes the part that doesn't, and undoing the erase brings it back")
        func erasingTakesHiddenOverflow() throws {
            let seamless = PageLayout(mode: .seamless)
            let harness = PageHarness(text: Self.severalPages, layout: seamless)
            let bottom = seamless.bodyTop(ofPage: 1) + seamless.bodyHeight
            Self.draw([Self.verticalStroke(from: bottom - 60, to: bottom + 60)], on: harness)
            harness.switchTo(PageLayout(mode: .compressed))

            let shown = try #require(harness.page.canvas.markup.subelements.first)
            Self.erase(shown.elementID, on: harness)
            #expect(harness.page.ink.subelements.count == 0)

            // Undone, PaperKit puts back what it took.
            var markup = harness.page.canvas.markup
            markup.subelements.append(shown)
            harness.page.canvas.markup = markup
            harness.page.canvas.onMarkupChanged?()
            #expect(harness.page.ink.subelements.count == 2)

            harness.switchTo(seamless)
            #expect(Self.shownStrokes(harness).count == 2)
        }

        @Test("Moving what shows of a stroke carries the part that doesn't")
        func movingCarriesHiddenOverflow() throws {
            let seamless = PageLayout(mode: .seamless)
            let harness = PageHarness(text: Self.severalPages, layout: seamless)
            let bottom = seamless.bodyTop(ofPage: 1) + seamless.bodyHeight
            Self.draw([Self.verticalStroke(from: bottom - 60, to: bottom + 60)], on: harness)
            harness.switchTo(PageLayout(mode: .compressed))
            let before = try #require(harness.page.ink.subelements.strokes.first { InkPages.isOverflow($0.id) })

            var markup = harness.page.canvas.markup
            var shown = try #require(markup.subelements.strokes.first)
            shown.applyTransform(CGAffineTransform(translationX: 30, y: 0))
            markup.subelements.updateOrAppend(shown)
            harness.page.canvas.markup = markup
            harness.page.canvas.onMarkupChanged?()

            let after = try #require(harness.page.ink.subelements.strokes.first { InkPages.isOverflow($0.id) })
            #expect(abs(Self.area(of: after).minX - Self.area(of: before).minX - 30) < 0.5)
            #expect(abs(Self.area(of: after).minY - Self.area(of: before).minY) < 0.5)
        }

        @Test("Erasing or undoing a stroke cut into pieces takes every piece")
        func erasingTakesEveryPiece() throws {
            let seamless = PageLayout(mode: .seamless)
            let harness = PageHarness(text: Self.severalPages, layout: seamless)
            let bottom = seamless.bodyTop(ofPage: 1) + seamless.bodyHeight
            Self.draw([Self.verticalStroke(from: bottom - 60, to: bottom + 60)], on: harness)
            try #require(harness.page.ink.subelements.count == 2)

            // Still whole on the canvas, which is all PaperKit's undo knows of.
            var markup = harness.page.canvas.markup
            try #require(markup.subelements.count == 1)
            let drawn = try #require(markup.subelements.ids.first)
            markup.subelements.removeElement(for: drawn)
            harness.page.canvas.markup = markup
            harness.page.canvas.onMarkupChanged?()

            #expect(harness.page.ink.subelements.count == 0)
        }

        @Test("Once seamless shows the pieces, erasing one leaves the other")
        func erasingOnePiece() throws {
            let seamless = PageLayout(mode: .seamless)
            let harness = PageHarness(text: Self.severalPages, layout: seamless)
            let bottom = seamless.bodyTop(ofPage: 1) + seamless.bodyHeight
            Self.draw([Self.verticalStroke(from: bottom - 60, to: bottom + 60)], on: harness)
            harness.switchTo(PageLayout(mode: .compressed))
            harness.switchTo(seamless)

            var markup = harness.page.canvas.markup
            try #require(markup.subelements.count == 2)
            let first = try #require(Self.shownStrokes(harness).first)
            markup.subelements.removeElement(for: first.elementID)
            harness.page.canvas.markup = markup
            harness.page.canvas.onMarkupChanged?()

            #expect(harness.page.ink.subelements.count == 1)
        }

        @Test("Moving a stroke cut into pieces cuts it again where it lands")
        func movingRecuts() throws {
            let seamless = PageLayout(mode: .seamless)
            let harness = PageHarness(text: Self.severalPages, layout: seamless)
            let bottom = seamless.bodyTop(ofPage: 1) + seamless.bodyHeight
            Self.draw([Self.verticalStroke(from: bottom - 60, to: bottom + 60)], on: harness)
            try #require(harness.page.ink.subelements.count == 2)

            // Lifted off the break, onto page 2's text.
            var markup = harness.page.canvas.markup
            var stroke = try #require(markup.subelements.strokes.first)
            stroke.applyTransform(CGAffineTransform(translationX: 0, y: -200))
            markup.subelements.updateOrAppend(stroke)
            harness.page.canvas.markup = markup
            harness.page.canvas.onMarkupChanged?()

            let stored = harness.page.ink.subelements.strokes
            #expect(stored.count == 1)
            #expect(stored.first?.mask == nil)
        }

        @Test("Cutting a stroke keeps the order strokes are drawn in")
        func cuttingKeepsOrder() throws {
            let seamless = PageLayout(mode: .seamless)
            let harness = PageHarness(text: Self.severalPages, layout: seamless)
            let bottom = seamless.bodyTop(ofPage: 1) + seamless.bodyHeight
            Self.draw([Self.verticalStroke(from: bottom - 60, to: bottom + 60)], on: harness)
            Self.draw([Self.stroke(at: bottom - 30)], on: harness)
            let later = try #require(harness.page.ink.subelements.ids.last)

            // Move the first stroke a little: it's cut again, into the same place.
            var markup = harness.page.canvas.markup
            var first = try #require(markup.subelements.strokes.first { $0.elementID != later })
            first.applyTransform(CGAffineTransform(translationX: 10, y: 0))
            markup.subelements.updateOrAppend(first)
            harness.page.canvas.markup = markup
            harness.page.canvas.onMarkupChanged?()

            #expect(harness.page.ink.subelements.count == 3)
            #expect(harness.page.ink.subelements.ids.last == later)

            // Reopened, the canvas draws them in the stored order.
            let reopened = PageHarness(text: Self.severalPages, layout: seamless)
            reopened.page.setInk(harness.page.ink)
            #expect(Array(reopened.page.canvas.markup.subelements.ids) == Array(harness.page.ink.subelements.ids))
        }

        @Test("Ink saved before strokes were cut is left whole")
        func savedInkLeftWhole() {
            let print = Self.printPortrait
            let harness = PageHarness(text: Self.severalPages)
            let crossing = Self.verticalStroke(from: print.bodyTop(ofPage: 2) - 120, to: print.bodyTop(ofPage: 2) + 60)
            harness.setInk(PKDrawing(strokes: [crossing]))
            var reports = 0
            harness.page.onInkChanged = { _ in reports += 1 }
            let before = harness.page.ink.subelements.strokes

            for mode in [PageViewMode.compressed, .seamless, .print] {
                harness.switchTo(PageLayout(mode: mode))
            }

            #expect(reports == 0)
            #expect(harness.page.ink.subelements.strokes.map(\.id) == before.map(\.id))
            #expect(harness.page.ink.subelements.strokes.allSatisfy { $0.mask == nil })
        }

        @Test("Erasing on the canvas takes the stroke out of the stored ink")
        func erasedStrokeLeavesTheInk() {
            let harness = PageHarness(text: Self.severalPages)
            Self.draw([Self.stroke(at: 400), Self.stroke(at: 1500)], on: harness)
            #expect(harness.page.ink.subelements.count == 2)

            var markup = harness.page.canvas.markup
            if let last = markup.subelements.ids.last {
                markup.subelements.removeElement(for: last)
            }
            harness.page.canvas.markup = markup
            harness.page.canvas.onMarkupChanged?()

            #expect(harness.page.ink.subelements.count == 1)
        }

        @Test("Drawing leaves untouched ink exactly where it was stored")
        func drawingDoesNotDisturbStoredInk() {
            let print = Self.printPortrait
            let harness = PageHarness(text: Self.severalPages, layout: print)
            let inMargin = print.bodyTop(ofPage: 2) + print.bodyHeight + 30
            harness.setInk(PKDrawing(strokes: [Self.stroke(at: inMargin)]))
            harness.switchTo(PageLayout(mode: .seamless))

            // Margin ink has no exact place in seamless, so a stroke drawn
            // elsewhere must not drag it through a round trip on the way in.
            Self.draw([Self.stroke(at: 300)], on: harness)
            harness.switchTo(print)

            let marginInk = harness.page.ink.subelements.strokes
                .map(\.renderBounds.midY)
                .max()
            #expect(abs((marginInk ?? 0) - inMargin) < 0.5)
        }

        @Test("Showing ink again clears what ink undo was holding")
        func modeSwitchForgetsInkUndo() {
            let harness = PageHarness(text: Self.severalPages, layout: PageLayout(mode: .seamless))
            Self.draw([Self.stroke(at: 1500)], on: harness)
            let canvas = harness.page.canvas
            canvas.undoManager?.registerUndo(withTarget: canvas) { _ in }
            #expect(canvas.undoManager?.canUndo == true)

            harness.switchTo(PageLayout(mode: .print))

            // That action would have put the stroke back where it sat in seamless.
            #expect(canvas.undoManager?.canUndo == false)
        }
    }
}

#endif
