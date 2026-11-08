//
//  PageViewTests+Scale.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

extension PageViewTests {

    @Suite("Width, scale and zoom")
    @MainActor
    struct Scale: PageViewSuite {

        /// Every view the text view draws with, apart from the ink layer.
        private static func textDrawingViews(in page: PageView) -> [UIView] {
            func walk(_ view: UIView) -> [UIView] {
                view === page.canvas ? [] : [view] + view.subviews.flatMap(walk)
            }
            return walk(page.textView)
        }

        // MARK: Width and scale

        @Test("The text lays out at its pages' width, whatever the area", arguments: PageOrientation.allCases)
        func fixedLayoutWidth(orientation: PageOrientation) {
            let layout = PageLayout(orientation: orientation)
            let narrow = PageHarness(area: CGSize(width: 682, height: 900), layout: layout)
            let wide = PageHarness(area: CGSize(width: 1224, height: 700), layout: layout)

            for harness in [narrow, wide] {
                #expect(harness.page.textView.bounds.width == layout.pageSize.width)
                #expect(harness.page.textView.textContainer.size.width == layout.textWidth)
            }
        }

        @Test("Portrait and landscape iPads give identical line breaks")
        func identicalLineBreaks() {
            let harness = PageHarness(area: CGSize(width: 682, height: 1000))
            let portrait = harness.lines.map(\.range)

            harness.resize(to: CGSize(width: 1224, height: 800))
            let landscape = harness.lines.map(\.range)

            #expect(harness.page.displayScale == CanvasGeometry.maximumFitScale)   // the scale really did change
            #expect(portrait.count > 40)                                            // and the text really does wrap
            #expect(portrait == landscape)
        }

        @Test("The page is drawn at its fitted scale, centred in its area")
        func drawnAtScale() {
            let harness = PageHarness(area: CGSize(width: 1224, height: 800))
            let frame = harness.page.textView.frame

            #expect(harness.page.displayScale == CanvasGeometry.maximumFitScale)
            #expect(abs(frame.width - 1020) < 0.01)
            #expect(abs(frame.midX - 612) < 0.01)
            #expect(abs(frame.height - 800) < 0.01)
        }

        @Test("A scale change keeps the scroll position, so the top line stays on top")
        func scrollSurvivesScale() {
            let harness = PageHarness(text: Self.severalPages, area: CGSize(width: 682, height: 900))
            harness.page.textView.contentOffset = CGPoint(x: 0, y: 640)

            harness.resize(to: CGSize(width: 1224, height: 700))

            #expect(harness.page.textView.contentOffset.y == 640)
        }

        @Test("Text is rendered at the density it is shown at")
        func renderingScale() {
            let harness = PageHarness(area: CGSize(width: 1224, height: 800))
            let expected = CanvasGeometry.maximumFitScale * harness.page.traitCollection.displayScale

            #expect(harness.page.textView.contentScaleFactor == expected)
        }

        /// Typing doesn't lay the text view out: the edited paragraph gets a new
        /// view at the screen's density, and until something else laid the text
        /// view out, the line being typed was soft (on the iPad and the simulator,
        /// 25 September). A layout pass of the window is what the next frame gets.
        @Test("A line being typed is drawn at the page's density by the next frame")
        func typedLineRenderingScale() {
            let harness = PageHarness(area: CGSize(width: 1224, height: 800))
            let textView = harness.page.textView
            let expected = CanvasGeometry.maximumFitScale * harness.page.traitCollection.displayScale

            textView.becomeFirstResponder()
            textView.selectedRange = NSRange(location: 120, length: 0)
            harness.layOut()

            // The keyboard's own path, which a reader typing takes.
            textView.insertText("z")
            let softAtOnce = Self.textDrawingViews(in: harness.page).filter { $0.contentScaleFactor != expected }
            harness.window.layoutIfNeeded()
            let soft = Self.textDrawingViews(in: harness.page).filter { $0.contentScaleFactor != expected }

            #expect(softAtOnce.isEmpty, "at once: \(softAtOnce.count) views at \(softAtOnce.map(\.contentScaleFactor))")
            #expect(soft.isEmpty, "\(soft.count) views at \(soft.map(\.contentScaleFactor))")
        }

        @Test(
            "Ink is drawn at the density the page is shown at, up to the cap",
            arguments: [(CGFloat(1224), CGFloat(1)), (1224, 4), (682, 1), (880, 2)]
        )
        func inkRenderScale(width: CGFloat, zoom: CGFloat) {
            let harness = PageHarness(text: Self.severalPages, area: CGSize(width: width, height: 800))
            harness.page.setZoom(zoom, about: CGPoint(x: width / 2, y: 400))
            harness.layOut()
            let page = harness.page
            let expected = max(1, min(page.displayScale, CanvasGeometry.maximumRenderingScale))

            #expect(abs(page.canvas.renderScale - expected) < 0.0001)
            // PaperKit takes input only inside the markup's bounds, in the
            // note's coordinates: they have to cover the whole note, or part of
            // every page can't be drawn on.
            #expect(page.canvas.markup.bounds.width >= page.pageLayout.pageSize.width - 0.01)
            #expect(page.canvas.markup.bounds.height >= page.canvas.noteSize.height - 0.01)
            #expect(abs(page.canvas.controller.scrollConfiguration.zoomScale - expected) < 0.0001)
            // Zoomed and shrunk by the same factor: the canvas's own points are
            // screen points, and it still covers the part of the note on screen.
            #expect(abs(page.canvas.bounds.height - page.textView.bounds.height * expected) < 0.01)
            let covered = CGRect(x: 0, y: page.textView.contentOffset.y, width: page.pageLayout.pageSize.width, height: page.textView.bounds.height)
            #expect(Self.close(page.canvas.frame, covered), "canvas at \(page.canvas.frame)")
        }

        /// Where PaperKit actually draws an element, against the text: the
        /// check that zooming it didn't move ink off its words. Measured on a
        /// shape, which PaperKit draws in a view of its own. Before its bounds
        /// were scaled, this shape sat 81.6 points right of where it belonged.
        @Test(
            "Ink lands on its note coordinates at any render scale",
            arguments: [(CGFloat(1224), CGFloat(1)), (1224, 2.5), (682, 1)]
        )
        func inkLinesUpWithText(width: CGFloat, zoom: CGFloat) throws {
            let harness = PageHarness(text: Self.severalPages, area: CGSize(width: width, height: 800))
            harness.page.setZoom(zoom, about: CGPoint(x: width / 2, y: 400))
            harness.page.textView.contentOffset.y = 1500
            harness.layOut()

            let placed = CGRect(x: 200, y: 1700, width: 100, height: 50)
            var markup = harness.page.canvas.markup
            markup.insertNewShape(configuration: ShapeConfiguration(type: .rectangle, fillColor: UIColor.red.cgColor), frame: placed)
            harness.page.canvas.markup = markup
            harness.layOut()

            func shapeView(in view: UIView) -> UIView? {
                if NSStringFromClass(type(of: view)).hasSuffix("ShapeView") { return view }
                return view.subviews.lazy.compactMap(shapeView(in:)).first
            }
            let shape = try #require(shapeView(in: harness.page.canvas))
            let drawn = shape.convert(shape.bounds, to: harness.page.textView)
            // PaperKit puts the shape's edges on the screen's pixels at the
            // canvas's zoom, so they can land a fraction of a pixel from the
            // note's: 50pt at 1.25x on a 3x iPhone is 187.5 pixels, drawn as 188.
            let pixel = 1 / (harness.page.traitCollection.displayScale * harness.page.canvas.renderScale)
            #expect(Self.close(drawn, placed, within: pixel), "shape drawn at \(drawn)")
        }

        // MARK: Zoom

        @Test("Zooming keeps the page point between the fingers under them")
        func zoomKeepsFocus() {
            let harness = PageHarness(text: Self.severalPages)
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
            let harness = PageHarness()
            harness.page.setZoom(100, about: .zero)
            #expect(harness.page.zoom == CanvasGeometry.maximumZoom)

            harness.page.setZoom(0.001, about: .zero)
            #expect(harness.page.zoom == CanvasGeometry.minimumZoom)
        }

        @Test("Zoomed far in, text is rendered no denser than the cap")
        func renderingScaleCapped() {
            let harness = PageHarness()
            harness.page.setZoom(4, about: CGPoint(x: 440, y: 550))
            harness.layOut()

            let expected = CanvasGeometry.maximumRenderingScale * harness.page.traitCollection.displayScale
            #expect(harness.page.textView.contentScaleFactor == expected)
        }
    }
}

#endif
