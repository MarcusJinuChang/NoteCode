//
//  InkPagesTests.swift
//  NoteCodeTests
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import Testing
import UIKit
@testable import NoteCode

@Suite("Ink cut into pages")
@MainActor
struct InkPagesTests {

    /// Pages 100 points tall, touching, like seamless's.
    private static let touching = (0..<4).map { CGRect(x: 0, y: CGFloat($0) * 100, width: 300, height: 100) }

    /// Pages 100 points tall with 40 points between them that no page has,
    /// like compressed's strip or print layout's margins.
    private static let apart = (0..<3).map { CGRect(x: 0, y: CGFloat($0) * 140, width: 300, height: 100) }

    /// A stroke through `points`, 6 points wide.
    private static func stroke(through points: [CGPoint], mask: UIBezierPath? = nil) -> PKStroke {
        let controlPoints = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.01, size: CGSize(width: 6, height: 6),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black),
                        path: PKStrokePath(controlPoints: controlPoints, creationDate: Date(timeIntervalSince1970: 0)),
                        mask: mask)
    }

    /// A vertical stroke at x = 100 from `top` to `bottom`.
    private static func vertical(from top: CGFloat, to bottom: CGFloat) -> PKStroke {
        stroke(through: stride(from: top, through: bottom, by: 4).map { CGPoint(x: 100, y: $0) })
    }

    @Test("A stroke on one page comes back as it was")
    func onePageUnchanged() {
        let original = Self.vertical(from: 120, to: 180)
        let pieces = InkPages.pieces(ofStroke: original, regions: Self.touching)

        #expect(pieces.count == 1)
        #expect(pieces.first?.id == original.id)
        #expect(pieces.first?.mask == nil)
    }

    @Test("A stroke across a break is cut into a piece per page")
    func acrossOneBreak() throws {
        let original = Self.vertical(from: 60, to: 140)
        let pieces = InkPages.pieces(ofStroke: original, regions: Self.touching)

        try #require(pieces.count == 2)
        // Each on its own page, meeting at the break.
        #expect(Self.touching[0].contains(pieces[0].renderFrame))
        #expect(Self.touching[1].contains(pieces[1].renderFrame))
        #expect(abs(pieces[0].renderFrame.maxY - pieces[1].renderFrame.minY) < 0.001)
        // New elements, with the stroke's path and texture.
        #expect(Set(pieces.map(\.id)).count == 2)
        #expect(!pieces.map(\.id).contains(original.id))
        #expect(pieces.allSatisfy { $0.randomSeed == original.randomSeed && $0.path.count == original.path.count })
    }

    @Test("A stroke reaching four pages is cut into four")
    func acrossManyPages() {
        let pieces = InkPages.pieces(ofStroke: Self.vertical(from: 50, to: 350), regions: Self.touching)

        #expect(pieces.count == 4)
        for (piece, page) in zip(pieces, Self.touching) {
            #expect(page.contains(piece.renderFrame))
        }
    }

    @Test("A stroke crossing a break back and forth is still one piece per page")
    func zigzag() {
        let points = (0..<9).map { CGPoint(x: 40 + CGFloat($0) * 20, y: $0 % 2 == 0 ? 80 : 120) }
        let pieces = InkPages.pieces(ofStroke: Self.stroke(through: points), regions: Self.touching)

        #expect(pieces.count == 2)
    }

    @Test("What falls between pages is in no piece")
    func betweenPagesLeftOut() throws {
        // From page 1 down through the 40 points no page has, onto page 2.
        let pieces = InkPages.pieces(ofStroke: Self.vertical(from: 60, to: 180), regions: Self.apart)

        try #require(pieces.count == 2)
        let gap = CGRect(x: 0, y: 100, width: 300, height: 40)
        for piece in pieces {
            #expect(piece.renderFrame.intersection(gap).height < 0.001)
        }
    }

    @Test("A stroke on one page that runs into space no page has is masked to its page")
    func runsIntoTheGap() throws {
        let pieces = InkPages.pieces(ofStroke: Self.vertical(from: 40, to: 120), regions: Self.apart)

        try #require(pieces.count == 1)
        #expect(pieces[0].mask != nil)
        #expect(Self.apart[0].contains(pieces[0].renderFrame))
    }

    @Test("A stroke wholly in space no page has is left as it is")
    func whollyBetweenPages() {
        let original = Self.vertical(from: 110, to: 130)
        let pieces = InkPages.pieces(ofStroke: original, regions: Self.apart)

        #expect(pieces.count == 1)
        #expect(pieces.first?.id == original.id)
    }

    @Test("A moved stroke is cut where it is now, not where it was drawn")
    func movedStroke() throws {
        var moved = Self.vertical(from: 20, to: 80)
        moved.applyTransform(CGAffineTransform(translationX: 0, y: 60))
        let pieces = InkPages.pieces(ofStroke: moved, regions: Self.touching)

        try #require(pieces.count == 2)
        #expect(Self.touching[0].contains(pieces[0].renderFrame))
        #expect(Self.touching[1].contains(pieces[1].renderFrame))
    }

    @Test("A stroke already masked keeps its mask inside each piece")
    func existingMaskKept() throws {
        // Only y 70 to 130 of it was showing.
        let shown = UIBezierPath(rect: CGRect(x: 0, y: 70, width: 300, height: 60))
        let pieces = InkPages.pieces(ofStroke: Self.stroke(through: [CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 400)], mask: shown),
                                     regions: Self.touching)

        try #require(pieces.count == 2)
        #expect(abs(pieces[0].renderFrame.minY - 70) < 0.001)
        #expect(abs(pieces[1].renderFrame.maxY - 130) < 0.001)
    }

    // MARK: Drawn

    /// Alpha down the line x = 100, drawn by PaperKit as the PDF draws it.
    private static func alphas(of strokes: [PKStroke], at ys: [CGFloat]) async -> [Int] {
        var markup = PaperMarkup(bounds: CGRect(x: 0, y: 0, width: 300, height: 400))
        for stroke in strokes {
            markup.subelements.updateOrAppend(stroke)
        }
        let context = CGContext(data: nil, width: 300, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: 400)
        context.scaleBy(x: 1, y: -1)
        await markup.draw(in: context, frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        let image = context.makeImage()!

        return ys.map { y in
            var pixel = [UInt8](repeating: 0, count: 4)
            let one = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            one.draw(image, in: CGRect(x: -100, y: -(400 - y - 1), width: 300, height: 400))
            return Int(pixel[3])
        }
    }

    @Test("Pieces drawn together are the stroke, with no seam where they meet")
    func piecesDrawAsTheStroke() async {
        let original = Self.vertical(from: 60, to: 140)
        let ys: [CGFloat] = [62, 90, 98, 99, 100, 101, 102, 110, 138]

        let whole = await Self.alphas(of: [original], at: ys)
        let cut = await Self.alphas(of: InkPages.pieces(ofStroke: original, regions: Self.touching), at: ys)

        #expect(whole.allSatisfy { $0 > 200 }, "the check can see the stroke: \(whole)")
        #expect(cut == whole)
    }

    @Test("Pieces draw nothing in the space between pages")
    func piecesDrawNothingBetweenPages() async {
        let original = Self.vertical(from: 60, to: 180)
        let pieces = InkPages.pieces(ofStroke: original, regions: Self.apart)

        let between = await Self.alphas(of: pieces, at: [104, 120, 136])
        let onPages = await Self.alphas(of: pieces, at: [80, 160])
        let wholeBetween = await Self.alphas(of: [original], at: [104, 120, 136])

        #expect(wholeBetween.allSatisfy { $0 > 200 }, "the stroke itself runs through there: \(wholeBetween)")
        #expect(between.allSatisfy { $0 == 0 }, "\(between)")
        #expect(onPages.allSatisfy { $0 > 200 }, "\(onPages)")
    }
}

#endif
