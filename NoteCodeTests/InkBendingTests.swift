//
//  InkBendingTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

@Suite("Ink bent at page breaks")
@MainActor
struct InkBendingTests {

    private static let seamless = PageLayout(mode: .seamless)
    private static let compressed = PageLayout(mode: .compressed)
    private static let print = PageLayout(mode: .print)

    /// A stroke through `points`, 4 points wide.
    private static func stroke(through points: [CGPoint], mask: UIBezierPath? = nil) -> PKStroke {
        let controlPoints = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.01, size: CGSize(width: 4, height: 4),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black),
                        path: PKStrokePath(controlPoints: controlPoints, creationDate: Date(timeIntervalSince1970: 0)),
                        mask: mask)
    }

    /// A vertical stroke at `x` from `top` to `bottom`, a point every 4.
    private static func vertical(x: CGFloat = 300, from top: CGFloat, to bottom: CGFloat) -> PKStroke {
        stroke(through: stride(from: top, through: bottom, by: 4).map { CGPoint(x: x, y: $0) })
    }

    /// The bottom of page `index`'s text in `layout`.
    private static func bottom(of index: Int, in layout: PageLayout) -> CGFloat {
        layout.bodyTop(ofPage: index) + layout.bodyHeight
    }

    private static func points(of stroke: PKStroke) -> [CGPoint] {
        stroke.path.map { $0.location.applying(stroke.transform) }
    }

    @Test("A stroke on one page moves whole and isn't rebuilt")
    func onePageMovesWhole() throws {
        let original = Self.vertical(from: Self.seamless.bodyTop(ofPage: 1) + 100, to: Self.seamless.bodyTop(ofPage: 1) + 200)
        let moved = try #require(InkBending.moved(original, from: Self.seamless, to: Self.print) as? PKStroke)

        #expect(!InkBending.crossesBreak(original, in: Self.seamless))
        // The same path, moved by the page's offset through its transform.
        #expect(moved.path.count == original.path.count)
        #expect(moved.path.first?.location == original.path.first?.location)
        let shift = Self.print.bodyTop(ofPage: 1) - Self.seamless.bodyTop(ofPage: 1)
        #expect(abs(moved.transform.ty - shift) < 0.001)
    }

    @Test("A stroke across a break is bent: each point moves with its own page", arguments: [PageViewMode.compressed, .print])
    func acrossABreakIsBent(to mode: PageViewMode) throws {
        let target = PageLayout(mode: mode)
        let edge = Self.bottom(of: 1, in: Self.seamless)
        let original = Self.vertical(from: edge - 60, to: edge + 60)
        let bent = try #require(InkBending.moved(original, from: Self.seamless, to: target) as? PKStroke)

        #expect(InkBending.crossesBreak(original, in: Self.seamless))
        #expect(bent.id == original.id)
        #expect(bent.randomSeed == original.randomSeed)
        #expect(bent.ink.color == original.ink.color)
        #expect(bent.path.creationDate == original.path.creationDate)
        // The stroke as drawn, sampled, each sample moved by its own page.
        let samples = InkBending.samples(of: original, in: Self.seamless).map { $0.location.applying(original.transform) }
        let points = Self.points(of: bent)
        try #require(samples.count == points.count)
        for (before, after) in zip(samples, points) {
            let page = Self.seamless.pageIndex(atY: before.y)
            let into = before.y - Self.seamless.bodyTop(ofPage: page)
            #expect(abs(after.y - (target.bodyTop(ofPage: page) + into)) < 0.001, "\(before) → \(after)")
            #expect(abs(after.x - before.x) < 0.001)
        }
        // Close together on each page, however far the break stretches.
        let page1 = points.filter { $0.y < Self.bottom(of: 1, in: target) }.map(\.y)
        for (a, b) in zip(page1, page1.dropFirst()) {
            #expect(b - a <= InkBending.sampleSpacing + 0.01)
        }
    }

    /// The nearest distance from `point` to the line through `samples`.
    private static func distance(from point: CGPoint, to samples: [CGPoint]) -> CGFloat {
        zip(samples, samples.dropFirst()).map { a, b in
            let along = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let length = along.x * along.x + along.y * along.y
            let t = length > 0 ? max(0, min(1, ((point.x - a.x) * along.x + (point.y - a.y) * along.y) / length)) : 0
            return hypot(point.x - (a.x + t * along.x), point.y - (a.y + t * along.y))
        }.min() ?? .infinity
    }

    @Test("Bent there and back, a stroke follows the line it was drawn along")
    func roundTrip() throws {
        let edge = Self.bottom(of: 2, in: Self.seamless)
        let original = Self.stroke(through: (0..<30).map { CGPoint(x: 200 + CGFloat($0) * 5, y: edge - 60 + CGFloat($0) * 4) })
        let there = try #require(InkBending.moved(original, from: Self.seamless, to: Self.print) as? PKStroke)
        let back = try #require(InkBending.moved(there, from: Self.print, to: Self.seamless) as? PKStroke)

        let drawn = InkBending.samples(of: original, in: Self.seamless).map(\.location)
        let breakY = Self.seamless.inkRegion(ofPage: 2).maxY
        for point in Self.points(of: back) {
            // At the break itself, what was the stretch across print
            // layout's gap, squeezed back: it wanders sideways a little in
            // the gap, so it comes back as a tick narrower than the stroke.
            let allowed: CGFloat = abs(point.y - breakY) < 1 ? 2 : 0.6
            #expect(Self.distance(from: point, to: drawn) < allowed, "\(point)")
        }
    }

    @Test("Drawn across compressed's strip, a stroke is squeezed into seamless's break and stays joined")
    func squeezedIntoSeamless() throws {
        let edge = Self.bottom(of: 0, in: Self.compressed)
        let original = Self.vertical(from: edge - 40, to: Self.compressed.bodyTop(ofPage: 1) + 40)
        let squeezed = try #require(InkBending.moved(original, from: Self.compressed, to: Self.seamless) as? PKStroke)

        let ys = Self.points(of: squeezed).map(\.y)
        // No gap between neighbouring points wider than the 4 they were drawn apart.
        for (a, b) in zip(ys, ys.dropFirst()) {
            #expect(b - a <= 4.001)
            #expect(b >= a)
        }
        let breakY = Self.seamless.inkRegion(ofPage: 0).maxY
        #expect(ys.contains { abs($0 - breakY) < 0.001 })
    }

    @Test("A stroke that reaches one page and the room beside it moves whole")
    func onePageAndTheGapMovesWhole() {
        // Saved before 9 October: drawn across a break in seamless, stored
        // whole by its page, so in print layout it runs into the margin.
        let edge = Self.bottom(of: 0, in: Self.print)
        let saved = Self.vertical(from: edge - 60, to: edge + 30)

        #expect(!InkBending.crossesBreak(saved, in: Self.print))
    }

    @Test("A moved stroke is bent through its transform")
    func transformedStroke() throws {
        var original = Self.vertical(from: 0, to: 120)
        let edge = Self.bottom(of: 1, in: Self.seamless)
        original.applyTransform(CGAffineTransform(translationX: 0, y: edge - 60))
        let bent = try #require(InkBending.moved(original, from: Self.seamless, to: Self.print) as? PKStroke)

        #expect(bent.transform == original.transform)
        let last = try #require(Self.points(of: bent).last)
        #expect(abs(last.y - (Self.print.bodyTop(ofPage: 2) + 60 - 1)) < 3)
    }

    // MARK: Drawn

    /// Alpha down the line x = `x`, drawn by PaperKit as the PDF draws it.
    private static func alphas(of strokes: [PKStroke], at ys: [CGFloat], x: CGFloat = 300, height: CGFloat) async -> [Int] {
        var markup = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 816, height: height))
        for stroke in strokes {
            markup.subelements.updateOrAppend(stroke)
        }
        let context = CGContext(data: nil, width: 816, height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
        await markup.draw(in: context, frame: CGRect(x: 0, y: 0, width: 816, height: height))
        let image = context.makeImage()!
        return ys.map { y in
            var pixel = [UInt8](repeating: 0, count: 4)
            let one = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            one.draw(image, in: CGRect(x: -x, y: -(height - y - 1), width: 816, height: height))
            return Int(pixel[3])
        }
    }

    @Test("Drawn, a bent stroke's ends are on their own pages' lines")
    func bentStrokeDrawn() async throws {
        let edge = Self.bottom(of: 0, in: Self.seamless)
        let original = Self.vertical(from: edge - 60, to: edge + 60)
        let bent = try #require(InkBending.moved(original, from: Self.seamless, to: Self.print) as? PKStroke)

        let bottom = Self.bottom(of: 0, in: Self.print)
        let top = Self.print.bodyTop(ofPage: 1)
        let ys: [CGFloat] = [bottom - 50, bottom - 5, top + 5, top + 50, top + 70]
        let alphas = await Self.alphas(of: [bent], at: ys, height: Self.print.noteHeight(pageCount: 2))

        #expect(alphas[0] > 200 && alphas[1] > 200, "page 1: \(alphas)")
        #expect(alphas[2] > 200 && alphas[3] > 200, "page 2: \(alphas)")
        // Ends 60 points into page 2's text, as it was drawn.
        #expect(alphas[4] == 0, "past its end: \(alphas)")
    }

    @Test("A mask bends with its stroke")
    func maskBends() async throws {
        let edge = Self.bottom(of: 0, in: Self.seamless)
        // Only y edge-40 to edge+40 of it shows: the pixel eraser leaves masks like this.
        let mask = UIBezierPath(rect: CGRect(x: 0, y: edge - 40, width: 816, height: 80))
        let original = Self.stroke(through: stride(from: edge - 100, through: edge + 100, by: 4).map { CGPoint(x: 300, y: $0) }, mask: mask)
        let bent = try #require(InkBending.moved(original, from: Self.seamless, to: Self.print) as? PKStroke)

        let bottom = Self.bottom(of: 0, in: Self.print)
        let top = Self.print.bodyTop(ofPage: 1)
        let ys: [CGFloat] = [bottom - 60, bottom - 20, top + 20, top + 60]
        let alphas = await Self.alphas(of: [bent], at: ys, height: Self.print.noteHeight(pageCount: 2))

        #expect(alphas == [0, alphas[1], alphas[2], 0], "\(alphas)")
        #expect(alphas[1] > 200 && alphas[2] > 200, "\(alphas)")
    }
}

#endif
