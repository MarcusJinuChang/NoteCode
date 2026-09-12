//
//  PageViewTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import PencilKit
import Testing
import UIKit
@testable import NoteCode

@Suite("Page view")
@MainActor
struct PageViewTests {

    /// Enough prose to wrap many times at any width.
    private static let longProse = (0..<40)
        .map { "Line \($0): an invariant holds before and after every iteration of the loop, which is what the proof rests on." }
        .joined(separator: "\n")

    @MainActor
    private final class Harness {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1400, height: 1400))
        let page: PageView

        init(text: String = PageViewTests.longProse, area: CGSize) {
            let textView = DocumentTextView.makeConfiguredTextView()
            textView.text = text
            page = PageView(textView: textView)
            page.frame = CGRect(origin: .zero, size: area)
            window.addSubview(page)
            window.makeKeyAndVisible()
            layOut()
        }

        func layOut() {
            page.setNeedsLayout()
            page.layoutIfNeeded()
            page.textView.layoutIfNeeded()
        }

        func resize(to area: CGSize) {
            page.frame = CGRect(origin: .zero, size: area)
            layOut()
        }

        /// Every laid-out line in the viewport, as UTF-16 ranges.
        var lineRanges: [NSRange] {
            guard let manager = page.textView.textLayoutManager,
                  let content = manager.textContentManager
            else { return [] }

            var ranges: [NSRange] = []
            manager.enumerateTextLayoutFragments(from: content.documentRange.location, options: [.ensuresLayout]) { fragment in
                let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
                for line in fragment.textLineFragments {
                    ranges.append(NSRange(location: start + line.characterRange.location, length: line.characterRange.length))
                }
                return ranges.count < 60
            }
            return ranges
        }
    }

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

    // MARK: Width and scale

    @Test("The text lays out at the page width, whatever the area")
    func fixedLayoutWidth() {
        let narrow = Harness(area: CGSize(width: 682, height: 900))
        let wide = Harness(area: CGSize(width: 1224, height: 700))

        #expect(narrow.page.textView.bounds.width == CanvasGeometry.pageWidth)
        #expect(wide.page.textView.bounds.width == CanvasGeometry.pageWidth)
    }

    @Test("Portrait and landscape scales give identical line breaks")
    func identicalLineBreaks() {
        let harness = Harness(area: CGSize(width: 682, height: 1000))
        let portrait = harness.lineRanges

        harness.resize(to: CGSize(width: 1224, height: 800))
        let landscape = harness.lineRanges

        #expect(harness.page.displayScale != 682.0 / 700)   // the scale really did change
        #expect(portrait.count > 40)                         // and the text really does wrap
        #expect(portrait == landscape)
    }

    @Test("The page is drawn at the display scale, centred in its area")
    func drawnAtScale() {
        let harness = Harness(area: CGSize(width: 1224, height: 800))
        let frame = harness.page.textView.frame

        #expect(harness.page.displayScale == CanvasGeometry.maximumScale)
        #expect(abs(frame.width - 875) < 0.01)
        #expect(abs(frame.midX - 612) < 0.01)
        #expect(abs(frame.height - 800) < 0.01)
    }

    @Test("A scale change keeps the scroll position, so the top line stays on top")
    func scrollSurvivesScale() {
        let harness = Harness(area: CGSize(width: 682, height: 900))
        harness.page.textView.contentOffset = CGPoint(x: 0, y: 640)

        harness.resize(to: CGSize(width: 1224, height: 700))

        #expect(harness.page.textView.contentOffset.y == 640)
    }

    @Test("Text is rendered at the density it is shown at")
    func renderingScale() {
        let harness = Harness(area: CGSize(width: 1224, height: 800))
        let expected = CanvasGeometry.maximumScale * harness.page.traitCollection.displayScale

        #expect(harness.page.textView.contentScaleFactor == expected)
    }

    // MARK: Ink and the page's length

    @Test("The canvas covers the text")
    func canvasCoversText() {
        let harness = Harness(area: CGSize(width: 682, height: 900))
        let textView = harness.page.textView

        #expect(harness.page.canvas.superview === textView)
        #expect(harness.page.canvas.frame.width == textView.bounds.width)
        #expect(harness.page.canvas.frame.height >= textView.contentSize.height)
    }

    @Test("Ink below the last line can be scrolled to")
    func inkBelowTextIsReachable() {
        let harness = Harness(text: "A short note.", area: CGSize(width: 682, height: 900))

        harness.page.canvas.drawing = PKDrawing(strokes: [Self.stroke(at: 3000)])
        harness.page.drawingDidChange()
        harness.layOut()

        let textView = harness.page.textView
        #expect(textView.contentSize.height >= 3000 + PageView.roomBelowInk)
        #expect(harness.page.canvas.frame.maxY >= 3000)
    }

    @Test("Deleting text never clips ink")
    func deletingTextKeepsInk() {
        let harness = Harness(area: CGSize(width: 682, height: 900))
        harness.page.canvas.drawing = PKDrawing(strokes: [Self.stroke(at: 3000)])
        harness.page.drawingDidChange()
        harness.layOut()

        harness.page.textView.text = "Nearly empty now."
        harness.layOut()

        #expect(harness.page.textView.contentSize.height >= 3000)
        #expect(harness.page.canvas.frame.maxY >= 3000)
    }

    @Test("Laying out again doesn't grow the page again")
    func layoutIsIdempotent() {
        let harness = Harness(text: "A short note.", area: CGSize(width: 682, height: 900))
        harness.page.canvas.drawing = PKDrawing(strokes: [Self.stroke(at: 3000)])
        harness.page.drawingDidChange()
        harness.layOut()
        let first = harness.page.textView.contentSize.height

        for _ in 0..<3 {
            harness.page.textView.setNeedsLayout()
            harness.layOut()
        }

        #expect(harness.page.textView.contentSize.height == first)
    }

    @Test("With no ink, the page ends where the text does")
    func noInkNoGrowth() {
        let harness = Harness(text: "A short note.", area: CGSize(width: 682, height: 900))

        #expect(harness.page.textView.textContainerInset.bottom == PageView.minimumBottomInset)
    }
}

#endif
