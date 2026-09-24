//
//  PageViewTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

@Suite("Page view")
@MainActor
struct PageViewTests {

    /// Lines that wrap on a portrait page and fit on a landscape one.
    private static let longProse = (0..<40)
        .map { "Line \($0): an invariant holds before and after every iteration of the loop, which is what the proof rests on." }
        .joined(separator: "\n")

    /// Several pages of prose, wrapped paragraphs, headings and code, with
    /// descenders — so page breaks land mid-paragraph as well as between lines.
    private static let severalPages = (0..<220)
        .map { index -> String in
            switch index % 30 {
            case 0:  return "## Section \(index) gjpqy"
            case 11: return "```cpp\nint query(gap g) { return g.jump(); }\n```"
            default:
                return index % 3 == 0
                    ? "Line \(index): " + String(repeating: "the loop invariant holds before and after every iteration, ", count: 3)
                    : "Line \(index): the loop invariant holds before and after every iteration."
            }
        }
        .joined(separator: "\n")

    @MainActor
    private final class Harness {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1400, height: 1400))
        let page: PageView

        init(text: String = PageViewTests.longProse, area: CGSize = CGSize(width: 880, height: 1100), layout: PageLayout = PageLayout()) {
            let textView = DocumentTextView.makeConfiguredTextView()
            textView.text = text
            page = PageView(textView: textView)
            page.pageLayout = layout
            page.frame = CGRect(origin: .zero, size: area)
            window.addSubview(page)
            window.makeKeyAndVisible()
            layOut()
        }

        /// Enough passes for a page count change to settle: the pass that finds
        /// a new page adds its band, and the next lays text out against it.
        func layOut() {
            for _ in 0..<3 {
                page.setNeedsLayout()
                page.layoutIfNeeded()
                page.textView.setNeedsLayout()
                page.textView.layoutIfNeeded()
            }
        }

        func resize(to area: CGSize) {
            page.frame = CGRect(origin: .zero, size: area)
            layOut()
        }

        func switchTo(_ layout: PageLayout) {
            page.pageLayout = layout
            layOut()
        }

        /// Ink is a `PaperMarkup`, but strokes are easier to write as a
        /// `PKDrawing`, and PaperKit takes one wholesale.
        func setInk(_ drawing: PKDrawing) {
            var markup = PaperMarkup(bounds: CGRect(origin: .zero, size: CGSize(
                width: page.pageLayout.pageSize.width,
                height: 100_000
            )))
            markup.append(contentsOf: drawing)
            page.setInk(markup)
            layOut()
        }

        /// Every line, in note coordinates, laid out to the end.
        var lines: [(range: NSRange, frame: CGRect)] {
            let textView = page.textView
            guard let manager = textView.textLayoutManager,
                  let content = manager.textContentManager
            else { return [] }

            let top = textView.textContainerInset.top
            var lines: [(NSRange, CGRect)] = []
            manager.enumerateTextLayoutFragments(from: content.documentRange.location, options: [.ensuresLayout]) { fragment in
                let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
                let origin = fragment.layoutFragmentFrame.origin
                for line in fragment.textLineFragments {
                    let range = NSRange(location: start + line.characterRange.location, length: line.characterRange.length)
                    lines.append((range, line.typographicBounds.offsetBy(dx: origin.x, dy: origin.y + top)))
                }
                return true
            }
            return lines
        }

        /// The character that starts the first line reaching below the top of
        /// the view, found the way a reader would: the first line whose bottom
        /// is past the edge. Looking up whatever sits at the edge instead is
        /// ambiguous when the edge is in a margin or a page break.
        var lineAtTop: Int? {
            let textView = page.textView
            guard let manager = textView.textLayoutManager,
                  let content = manager.textContentManager
            else { return nil }

            let edge = textView.contentOffset.y - textView.textContainerInset.top
            let documentStart = content.documentRange.location
            let from = manager.textViewportLayoutController.viewportRange?.location ?? documentStart

            var found: Int?
            manager.enumerateTextLayoutFragments(from: from, options: [.ensuresLayout]) { fragment in
                let frame = fragment.layoutFragmentFrame
                guard let line = fragment.textLineFragments.first(where: { frame.minY + $0.typographicBounds.maxY > edge }) else {
                    return true
                }
                found = content.offset(from: documentStart, to: fragment.rangeInElement.location) + line.characterRange.location
                return false
            }
            return found
        }

        /// Where the first stroke is shown, by its middle.
        var shownInkY: CGFloat? {
            page.canvas.markup.subelements.strokes.first?.renderBounds.midY
        }
    }

    /// A short horizontal stroke centred on `y`.
    private static func stroke(at y: CGFloat) -> PKStroke {
        let points = (0..<10).map { i in
            PKStrokePoint(
                location: CGPoint(x: 100 + CGFloat(i) * 10, y: y),
                timeOffset: Double(i) * 0.01,
                size: CGSize(width: 3, height: 3),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    private static let printPortrait = PageLayout(orientation: .portrait, mode: .print)

    // MARK: Width and scale

    @Test("The text lays out at its pages' width, whatever the area", arguments: PageOrientation.allCases)
    func fixedLayoutWidth(orientation: PageOrientation) {
        let layout = PageLayout(orientation: orientation)
        let narrow = Harness(area: CGSize(width: 682, height: 900), layout: layout)
        let wide = Harness(area: CGSize(width: 1224, height: 700), layout: layout)

        for harness in [narrow, wide] {
            #expect(harness.page.textView.bounds.width == layout.pageSize.width)
            #expect(harness.page.textView.textContainer.size.width == layout.textWidth)
        }
    }

    @Test("Portrait and landscape iPads give identical line breaks")
    func identicalLineBreaks() {
        let harness = Harness(area: CGSize(width: 682, height: 1000))
        let portrait = harness.lines.map(\.range)

        harness.resize(to: CGSize(width: 1224, height: 800))
        let landscape = harness.lines.map(\.range)

        #expect(harness.page.displayScale == CanvasGeometry.maximumFitScale)   // the scale really did change
        #expect(portrait.count > 40)                                            // and the text really does wrap
        #expect(portrait == landscape)
    }

    @Test("The page is drawn at its fitted scale, centred in its area")
    func drawnAtScale() {
        let harness = Harness(area: CGSize(width: 1224, height: 800))
        let frame = harness.page.textView.frame

        #expect(harness.page.displayScale == CanvasGeometry.maximumFitScale)
        #expect(abs(frame.width - 1020) < 0.01)
        #expect(abs(frame.midX - 612) < 0.01)
        #expect(abs(frame.height - 800) < 0.01)
    }

    @Test("A scale change keeps the scroll position, so the top line stays on top")
    func scrollSurvivesScale() {
        let harness = Harness(text: Self.severalPages, area: CGSize(width: 682, height: 900))
        harness.page.textView.contentOffset = CGPoint(x: 0, y: 640)

        harness.resize(to: CGSize(width: 1224, height: 700))

        #expect(harness.page.textView.contentOffset.y == 640)
    }

    @Test("Text is rendered at the density it is shown at")
    func renderingScale() {
        let harness = Harness(area: CGSize(width: 1224, height: 800))
        let expected = CanvasGeometry.maximumFitScale * harness.page.traitCollection.displayScale

        #expect(harness.page.textView.contentScaleFactor == expected)
    }

    // MARK: Zoom

    @Test("Zooming keeps the page point between the fingers under them")
    func zoomKeepsFocus() {
        let harness = Harness(text: Self.severalPages)
        let page = harness.page
        page.textView.contentOffset.y = 2000
        let focus = CGPoint(x: 300, y: 550)

        func pagePoint() -> CGPoint {
            let frame = page.textView.frame
            return CGPoint(
                x: (focus.x + page.contentOffset.x - frame.minX) / page.displayScale,
                y: page.textView.contentOffset.y + focus.y / page.displayScale
            )
        }

        let before = pagePoint()
        page.setZoom(2.5, about: focus)
        harness.layOut()
        let after = pagePoint()

        #expect(abs(page.displayScale - CanvasGeometry.fitScale(areaWidth: 880, pageWidth: 816) * 2.5) < 0.0001)
        #expect(abs(before.x - after.x) < 0.5)
        #expect(abs(before.y - after.y) < 0.5)
        // Zoomed in past the area's width, so it scrolls sideways.
        #expect(page.contentSize.width > 880)
    }

    @Test("Zoom stops at the ends of its range")
    func zoomClamps() {
        let harness = Harness()
        harness.page.setZoom(100, about: .zero)
        #expect(harness.page.zoom == CanvasGeometry.maximumZoom)

        harness.page.setZoom(0.001, about: .zero)
        #expect(harness.page.zoom == CanvasGeometry.minimumZoom)
    }

    @Test("Zoomed far in, text is rendered no denser than the cap")
    func renderingScaleCapped() {
        let harness = Harness()
        harness.page.setZoom(4, about: CGPoint(x: 440, y: 550))
        harness.layOut()

        let expected = CanvasGeometry.maximumRenderingScale * harness.page.traitCollection.displayScale
        #expect(harness.page.textView.contentScaleFactor == expected)
    }

    // MARK: Pages

    @Test("An empty note is exactly one page tall")
    func emptyNoteIsOnePage() {
        let harness = Harness(text: "")
        let layout = harness.page.pageLayout

        #expect(harness.page.pageCount == 1)
        #expect(abs(harness.page.textView.contentSize.height - layout.noteHeight(pageCount: 1)) < 0.5)
    }

    @Test("Text flows across pages without a line ever sitting in a page break", arguments: PageViewMode.allCases)
    func linesAvoidBreaks(mode: PageViewMode) {
        let layout = PageLayout(mode: mode)
        let harness = Harness(text: Self.severalPages, layout: layout)
        let page = harness.page

        #expect(page.pageCount > 2)
        #expect(page.textView.textContainer.exclusionPaths.count == page.pageCount)

        let breaks = layout.exclusionBands(pageCount: page.pageCount, containerTop: layout.firstBodyTop)
            .map { $0.offsetBy(dx: 0, dy: layout.firstBodyTop) }
        let intruding = harness.lines.filter { line in breaks.contains { $0.intersects(line.frame.insetBy(dx: 0, dy: 0.5)) } }
        #expect(intruding.isEmpty)
    }

    @Test("Every mode puts every line on the same page, at the same place on it")
    func paginationIdenticalAcrossModes() {
        let harness = Harness(text: Self.severalPages)

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
        let harness = Harness(text: Self.severalPages, layout: PageLayout(mode: .seamless))
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
        let harness = Harness(text: Self.severalPages, layout: PageLayout(mode: start))

        harness.switchTo(PageLayout(mode: target))

        #expect(harness.page.textView.contentOffset.y == 0)
    }

    @Test("Changing orientation re-wraps the note and keeps the same text at the top")
    func orientationKeepsTopText() throws {
        let harness = Harness(text: Self.severalPages)
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
        let harness = Harness(text: Self.severalPages, layout: print)
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
        let harness = Harness(text: Self.severalPages, layout: PageLayout(orientation: .landscape, mode: mode))

        #expect(harness.page.textView.contentOffset.y == 0)
    }

    @Test("At a note's very top, switching orientation stays at the very top", arguments: PageOrientation.allCases)
    func orientationSwitchAtTopStaysAtTop(target: PageOrientation) {
        let start: PageOrientation = target == .portrait ? .landscape : .portrait
        let harness = Harness(text: Self.severalPages, layout: PageLayout(orientation: start))
        harness.page.textView.contentOffset.y = 0
        harness.layOut()

        harness.switchTo(PageLayout(orientation: target))

        #expect(harness.page.textView.contentOffset.y == 0)
    }

    @Test("Landscape pages wrap wider")
    func landscapeRewraps() {
        let harness = Harness(text: Self.longProse)
        let portraitLines = harness.lines.count

        harness.switchTo(PageLayout(orientation: .landscape))

        #expect(harness.page.textView.bounds.width == 1056)
        #expect(harness.page.textView.textContainer.size.width == 912)
        #expect(harness.lines.count < portraitLines)
    }

    // MARK: Ink across modes

    @Test("Ink is shown on the same place on its page in every mode", arguments: PageViewMode.allCases)
    func inkShownOnItsPage(mode: PageViewMode) {
        let harness = Harness(text: Self.severalPages, layout: PageLayout(mode: mode))
        let printedAt = Self.printPortrait.bodyTop(ofPage: 2) + 50

        harness.setInk(PKDrawing(strokes: [Self.stroke(at: printedAt)]))

        #expect(abs((harness.shownInkY ?? 0) - (PageLayout(mode: mode).bodyTop(ofPage: 2) + 50)) < 0.5)
    }

    @Test("Ink follows its page as the mode changes")
    func inkFollowsModeChanges() {
        let harness = Harness(text: Self.severalPages)
        harness.setInk(PKDrawing(strokes: [Self.stroke(at: Self.printPortrait.bodyTop(ofPage: 2) + 50)]))

        for mode in [PageViewMode.print, .compressed, .seamless, .print] {
            harness.switchTo(PageLayout(mode: mode))
            #expect(abs((harness.shownInkY ?? 0) - (PageLayout(mode: mode).bodyTop(ofPage: 2) + 50)) < 0.5)
        }
    }

    @Test("Ink in a sheet's margin is back in the margin after a trip through seamless")
    func marginInkSurvivesRoundTrip() {
        let print = Self.printPortrait
        let harness = Harness(text: Self.severalPages, layout: print)
        let inMargin = print.bodyTop(ofPage: 2) + print.bodyHeight + 30
        harness.setInk(PKDrawing(strokes: [Self.stroke(at: inMargin)]))

        harness.switchTo(PageLayout(mode: .seamless))
        harness.switchTo(print)

        // Converting what was on screen back from seamless would put this on
        // page 3, 168 points lower. Kept in print coordinates, it can't move.
        #expect(abs((harness.shownInkY ?? 0) - inMargin) < 0.5)
    }

    @Test("Ink keeps its printed position when the orientation changes")
    func inkKeptOnOrientationChange() {
        let harness = Harness(text: Self.severalPages)
        harness.setInk(PKDrawing(strokes: [Self.stroke(at: 1500)]))
        let before = harness.page.ink.subelements.strokes.first?.renderBounds

        harness.switchTo(PageLayout(orientation: .landscape))

        #expect(harness.page.ink.subelements.strokes.first?.renderBounds == before)
    }

    // MARK: Ink drawn on the canvas

    /// Drawing, from the page's side: a stroke lands on the canvas and
    /// PaperKit says the markup changed.
    private static func draw(_ strokes: [PKStroke], on harness: Harness) {
        var markup = harness.page.canvas.markup
        markup.append(contentsOf: PKDrawing(strokes: strokes))
        harness.page.canvas.markup = markup
        harness.page.canvas.onMarkupChanged?()
        harness.layOut()
    }

    @Test("A stroke drawn in any mode is stored where it prints", arguments: PageViewMode.allCases)
    func drawnStrokeIsStoredInPrintCoordinates(mode: PageViewMode) {
        let harness = Harness(text: Self.severalPages, layout: PageLayout(mode: mode))
        let drawnAt = PageLayout(mode: mode).bodyTop(ofPage: 2) + 50

        Self.draw([Self.stroke(at: drawnAt)], on: harness)

        let stored = harness.page.ink.subelements.strokes.first?.renderBounds.midY
        #expect(abs((stored ?? 0) - (Self.printPortrait.bodyTop(ofPage: 2) + 50)) < 0.5)
    }

    @Test("A stroke drawn in seamless is on the same words in every other mode")
    func drawnStrokeFollowsTheModes() {
        let harness = Harness(text: Self.severalPages, layout: PageLayout(mode: .seamless))
        let drawnAt = PageLayout(mode: .seamless).bodyTop(ofPage: 2) + 50

        Self.draw([Self.stroke(at: drawnAt)], on: harness)

        for mode in [PageViewMode.print, .compressed, .seamless] {
            harness.switchTo(PageLayout(mode: mode))
            #expect(abs((harness.shownInkY ?? 0) - (PageLayout(mode: mode).bodyTop(ofPage: 2) + 50)) < 0.5)
        }
    }

    @Test("Erasing on the canvas takes the stroke out of the stored ink")
    func erasedStrokeLeavesTheInk() {
        let harness = Harness(text: Self.severalPages)
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
        let harness = Harness(text: Self.severalPages, layout: print)
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
        let harness = Harness(text: Self.severalPages, layout: PageLayout(mode: .seamless))
        Self.draw([Self.stroke(at: 1500)], on: harness)
        let canvas = harness.page.canvas
        canvas.undoManager?.registerUndo(withTarget: canvas) { _ in }
        #expect(canvas.undoManager?.canUndo == true)

        harness.switchTo(PageLayout(mode: .print))

        // That action would have put the stroke back where it sat in seamless.
        #expect(canvas.undoManager?.canUndo == false)
    }

    // MARK: Decorations

    @Test("Print layout draws a sheet per page, exactly where each prints")
    func printSheets() {
        let layout = PageLayout(mode: .print)
        let harness = Harness(text: Self.severalPages, layout: layout)
        let page = harness.page

        #expect(page.decorations.sheetFrames == (0..<page.pageCount).map { layout.sheet(ofPage: $0) })
        #expect(page.decorations.breakLineYs.isEmpty)
    }

    @Test("Print layout leaves the surround showing either side of its sheets")
    func printSheetsInset() {
        let harness = Harness(text: Self.severalPages, area: CGSize(width: 872, height: 1100), layout: PageLayout(mode: .print))
        let frame = harness.page.textView.frame

        #expect(abs(frame.minX - CanvasGeometry.printGutter) < 0.5)
        #expect(abs((872 - frame.maxX) - CanvasGeometry.printGutter) < 0.5)

        harness.switchTo(PageLayout(mode: .seamless))
        #expect(abs(harness.page.textView.frame.minX) < 0.5)
    }

    @Test("The outline sits on the page's edges, not the area's, and print layout's sheets carry their own")
    func outlineOnThePage() {
        // Wider than a page fits at 1.25x, so the page is narrower than its area.
        let harness = Harness(text: Self.severalPages, area: CGSize(width: 1300, height: 900), layout: PageLayout(mode: .seamless))
        let page = harness.page

        #expect(!page.outline.isHidden)
        #expect(page.outline.frame == page.textView.frame)
        #expect(page.outline.frame.width < 1300 - 1)
        #expect(abs(page.outline.frame.width - page.pageLayout.pageSize.width * page.displayScale) < 0.5)

        harness.switchTo(PageLayout(mode: .print))
        #expect(page.outline.isHidden)
        #expect(page.decorations.sheetBorderWidths.allSatisfy { $0 > 0 })
    }

    @Test("Compressed layout draws a line at each break, and seamless draws nothing")
    func breakLines() {
        let compressed = PageLayout(mode: .compressed)
        let harness = Harness(text: Self.severalPages, layout: compressed)
        let count = harness.page.pageCount

        #expect(harness.page.decorations.breakLineYs == (0..<(count - 1)).map { compressed.breakLineY(afterPage: $0) })
        #expect(harness.page.decorations.sheetFrames.isEmpty)

        harness.switchTo(PageLayout(mode: .seamless))
        #expect(harness.page.decorations.breakLineYs.isEmpty)
        #expect(harness.page.decorations.sheetFrames.isEmpty)
    }

    // MARK: Ink and the note's length

    @Test("The canvas covers what's on screen, and its ink spans every page")
    func canvasCoversScreen() {
        let harness = Harness(text: Self.severalPages)
        let page = harness.page
        let width = page.pageLayout.pageSize.width
        let noteHeight = page.pageLayout.noteHeight(pageCount: page.pageCount)

        #expect(page.canvas.superview === page.textView)
        #expect(page.canvas.markup.bounds.size == CGSize(width: width, height: noteHeight))
        #expect(page.canvas.markup.bounds.height >= page.textView.contentSize.height - 0.5)

        for offset in [0, 1800, noteHeight - page.textView.bounds.height] {
            page.textView.contentOffset.y = offset
            harness.layOut()
            #expect(page.canvas.frame == CGRect(x: 0, y: offset, width: width, height: page.textView.bounds.height))
        }
    }

    @Test("However long the note, the canvas is no taller than the screen")
    func canvasStaysScreenSized() {
        let long = (0..<60).map { _ in Self.severalPages }.joined(separator: "\n")
        let harness = Harness(text: long)
        let page = harness.page

        // PencilKit draws a stroke into a buffer its canvas's size, and Metal
        // refuses one past 16,384 pixels. A canvas as tall as a nine-page
        // note crashed on the first stroke (simulator, 23 September).
        #expect(page.pageCount > 40)
        #expect(page.canvas.bounds.height <= page.textView.bounds.height + 0.5)
    }

    @Test("The part of the note on screen stays within the note")
    func visiblePartClamps() {
        let inside = PageView.visiblePart(ofNoteHeight: 3000, width: 816, scrolledTo: 1000, viewHeight: 800)
        let bouncedAbove = PageView.visiblePart(ofNoteHeight: 3000, width: 816, scrolledTo: -60, viewHeight: 800)
        let bouncedBelow = PageView.visiblePart(ofNoteHeight: 3000, width: 816, scrolledTo: 2400, viewHeight: 800)
        let shortNote = PageView.visiblePart(ofNoteHeight: 500, width: 816, scrolledTo: 0, viewHeight: 800)

        #expect(inside == CGRect(x: 0, y: 1000, width: 816, height: 800))
        #expect(bouncedAbove.minY == 0)
        #expect(bouncedBelow.maxY == 3000)
        #expect(shortNote == CGRect(x: 0, y: 0, width: 816, height: 500))
    }

    @Test("Ink below the last line adds the pages needed to reach it")
    func inkBelowTextAddsPages() {
        let harness = Harness(text: "A short note.")
        let layout = harness.page.pageLayout

        harness.setInk(PKDrawing(strokes: [Self.stroke(at: 3000)]))
        let inkBottom = harness.page.canvas.markup.contentsRenderFrame.maxY

        #expect(harness.page.pageCount == layout.pageIndex(atY: inkBottom) + 1)
        #expect(harness.page.pageCount > 1)
        #expect(harness.page.textView.contentSize.height >= inkBottom)
        #expect(harness.page.canvas.markup.bounds.maxY >= inkBottom)
    }

    @Test("Deleting text never clips ink")
    func deletingTextKeepsInk() {
        let harness = Harness(text: Self.severalPages, area: CGSize(width: 682, height: 900))
        harness.setInk(PKDrawing(strokes: [Self.stroke(at: 3000)]))
        let inkBottom = harness.page.canvas.markup.contentsRenderFrame.maxY

        harness.page.textView.text = "Nearly empty now."
        harness.layOut()

        #expect(harness.page.textView.contentSize.height >= inkBottom)
        #expect(harness.page.canvas.markup.bounds.maxY >= inkBottom)
    }

    @Test("Laying out again doesn't grow the note again")
    func layoutIsIdempotent() {
        let harness = Harness(text: Self.severalPages)
        harness.setInk(PKDrawing(strokes: [Self.stroke(at: 9000)]))
        let height = harness.page.textView.contentSize.height
        let pages = harness.page.pageCount

        harness.layOut()
        harness.layOut()

        #expect(harness.page.textView.contentSize.height == height)
        #expect(harness.page.pageCount == pages)
    }

    // MARK: Cost

    /// Page breaks are exclusion paths, and once any exist TextKit 2 lays out
    /// everything below an edit. Measured on an iPad Pro 13-inch simulator on
    /// 12 September 2026: a 250-line note went from 5.5ms a keystroke near its
    /// top to 34ms. Loose on purpose, like StylingPerformanceTests — this is
    /// here to catch the cost doubling, not to police noise.
    @Test("Typing near the top of a paged note stays within budget")
    func typingCost() {
        let harness = Harness(text: StylingPerformanceTests.document(lines: 250))
        let textView = harness.page.textView

        var times: [TimeInterval] = []
        for index in 0..<9 {
            let position = textView.position(from: textView.beginningOfDocument, offset: 120 + index)!
            let start = Date()
            textView.replace(textView.textRange(from: position, to: position)!, withText: "z")
            textView.layoutIfNeeded()
            times.append(Date().timeIntervalSince(start))
        }

        let median = times.sorted()[4]
        #expect(median < 0.1, "keystroke near the top took \(median)s")
    }
}

#endif
