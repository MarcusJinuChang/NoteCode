//
//  PageViewTests.swift
//  NoteCodeTests
//
//  `PageView`'s tests, one suite per piece of it, in the
//  `PageViewTests+<piece>.swift` files beside this one. What they share is
//  `PageViewSuite`, below.
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

@Suite("Page view", .tags(.layout))
@MainActor
struct PageViewTests: PageViewSuite {}

/// What `PageViewTests`' suites share: a note of several pages and the strokes,
/// frames and pixels they draw and read. A protocol, so every suite reaches
/// them as `Self.` from its own type.
@MainActor
protocol PageViewSuite {}

extension PageViewSuite {

    static var severalPages: String { TestFixtures.severalPages }

    /// A short horizontal stroke centred on `y`.
    static func stroke(at y: CGFloat) -> PKStroke {
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

    static var printPortrait: PageLayout { PageLayout(orientation: .portrait, mode: .print) }

    /// Frames equal to within float error, which a transform introduces.
    static func close(_ a: CGRect, _ b: CGRect, within tolerance: CGFloat = 0.01) -> Bool {
        abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance
            && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }

    /// Drawing, from the page's side: a stroke lands on the canvas and
    /// PaperKit says the markup changed.
    static func draw(_ strokes: [PKStroke], on harness: PageHarness) {
        var markup = harness.page.canvas.markup
        markup.append(contentsOf: PKDrawing(strokes: strokes))
        harness.page.canvas.markup = markup
        harness.page.canvas.onMarkupChanged?()
        harness.layOut()
    }

    /// A stroke straight through `x`, from `top` to `bottom` — upward if
    /// `bottom` is above — in the coordinates of whatever mode it's drawn in.
    static func verticalStroke(x: CGFloat = 400, from top: CGFloat, to bottom: CGFloat) -> PKStroke {
        let points = stride(from: top, through: bottom, by: top <= bottom ? 4 : -4).enumerated().map { index, y in
            PKStrokePoint(
                location: CGPoint(x: x, y: y),
                timeOffset: Double(index) * 0.01,
                size: CGSize(width: 4, height: 4),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    /// Where a stroke shows: its mask's area if it has one. Exact, unlike
    /// its frame, which PaperKit rounds out to whole points.
    static func area(of stroke: PKStroke) -> CGRect {
        stroke.mask.map { $0.bounds.applying(stroke.transform) } ?? stroke.renderFrame
    }

    /// Two thousand short strokes, thirty to a row, rows down every page's
    /// body, in print coordinates: a long note written by hand.
    static func handwriting(_ count: Int) -> PaperMarkup {
        let print = PageLayout(mode: .print)
        let rows = Int(print.bodyHeight / 28) - 1
        let strokes = (0..<count).map { index -> PKStroke in
            let row = index / 30
            let origin = CGPoint(
                x: 80 + CGFloat(index % 30) * 22,
                y: print.bodyTop(ofPage: row / rows) + 4 + CGFloat(row % rows) * 28
            )
            let points = (0..<20).map { step -> PKStrokePoint in
                let wave: CGFloat = 8 * sin(CGFloat(step + index) / 3)
                let location = CGPoint(x: origin.x + CGFloat(step), y: origin.y + 9 + wave)
                return PKStrokePoint(
                    location: location, timeOffset: Double(step) * 0.01, size: CGSize(width: 2.5, height: 2.5),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
                )
            }
            return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        }
        var markup = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: print.pageSize.width, height: 100_000))
        markup.append(contentsOf: PKDrawing(strokes: strokes))
        return markup
    }
}

#endif
