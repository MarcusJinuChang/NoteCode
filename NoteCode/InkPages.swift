//
//  InkPages.swift
//  NoteCode
//
//  Ink cut at page breaks, so each piece goes with its own page.
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import UIKit

/// Cuts strokes into a piece per page, each masked to that page's region.
///
/// **Why.** Every mode puts the same lines on the same pages, but the space
/// between one page's text and the next differs: 1 point in seamless, 24 in
/// compressed, 168 in print layout. Text reflows across it; a stroke can't.
/// Moved whole by the page its middle is on, a stroke drawn across a break
/// sat on the right words on one side and was off by the difference on the
/// other, 23 points between seamless and compressed (simulator, 9 October).
/// Cut into pieces, each piece moves with its own page and stays on its
/// words in every mode, however many pages the stroke reaches.
///
/// **How.** A piece is the whole stroke — same path, ink and texture seed —
/// with a mask: the part of its page's region it covers
/// (`PageLayout.inkRegion`). PencilKit draws only inside a mask, PaperKit
/// keeps masks through moves, saving and its own drawing, and two pieces
/// meeting at a mask's edge join with no seam (probe, 9 October). A masked
/// stroke's frame is its mask's, so each piece's middle is on its own page
/// and the existing per-element conversion between modes places it.
/// Whatever falls outside every region — space seamless doesn't have — is
/// in no piece, so it shows in no mode and can't turn up on another page.
///
/// **Overflow.** The piece on the page the stroke was started on — where the
/// pen went down — keeps the stroke's id. The others are its *overflow*,
/// which compressed and print layout don't show: a stroke drawn across a
/// border there stops at it (10 October). Seamless shows every piece, so the
/// stroke is whole there. An overflow piece is known by its id, which keeps
/// the first ten bytes of its stroke's — its family — and has
/// `overflowMark` in the next four. PaperKit keeps a stroke's id through
/// saving, as long as the stroke goes into a markup through its
/// `subelements`; `append(contentsOf:)` a `PKDrawing` gives every stroke a
/// new one (probe, 10 October).
nonisolated enum InkPages {

    /// Slivers thinner than this are left out: a stroke's round end poking
    /// a fraction of a point past a page's edge isn't a piece worth keeping.
    static let minimumPieceHeight: CGFloat = 0.5

    /// `element` as the pieces it shows as on pages with `regions`, in the
    /// same coordinates as the element.
    ///
    /// Comes back unchanged when it lies within one region, which is nearly
    /// every stroke, or within none — a stroke moved wholly into space a page
    /// doesn't have is left as it is rather than lost. Only strokes are cut:
    /// a shape or an image moves whole with the page its middle is on.
    static func pieces(of element: any Markup, regions: [CGRect]) -> [any Markup] {
        guard let stroke = element as? PKStroke else { return [element] }
        return pieces(ofStroke: stroke, regions: regions)
    }

    /// The stroke-only form of `pieces(of:regions:)`. Named apart from it:
    /// a `PKStroke` is a `Markup` too, and given the same name, the call
    /// above resolved to itself and recursed until the stack ran out.
    static func pieces(ofStroke stroke: PKStroke, regions: [CGRect]) -> [PKStroke] {
        // Where the stroke actually has ink: its path's extent, within its
        // mask if it has one. The mask's own bounds, not the stroke's frame,
        // which PaperKit rounds out to whole points: a piece masked to end
        // half a point into a break reported a frame reaching a point in,
        // and cut again would have looked as if it crossed.
        var bare = stroke
        bare.mask = nil
        var visible = bare.renderFrame
        if let mask = stroke.mask {
            visible = visible.intersection(mask.bounds.applying(stroke.transform))
        }
        guard !visible.isNull, !visible.isEmpty else { return [stroke] }

        let covered = regions.indices.compactMap { index -> (page: Int, part: CGRect)? in
            let part = regions[index].intersection(visible)
            guard !part.isNull, part.height >= minimumPieceHeight, part.width > 0 else { return nil }
            return (index, part)
        }
        if covered.isEmpty {
            return [stroke]
        }
        if covered.count == 1, covered[0].part.height >= visible.height - minimumPieceHeight {
            return [stroke]
        }

        // Which piece keeps the stroke's id: the one on the page the pen went
        // down on. An overflow piece cut again has no such page, so its
        // largest piece keeps its id, and stays overflow.
        let keeper: Int
        if isOverflow(stroke.id) {
            keeper = covered.indices.max { covered[$0].part.height < covered[$1].part.height } ?? 0
        } else {
            keeper = ownPiece(of: stroke, among: covered.map { regions[$0.page] })
        }
        let family = family(of: stroke.id)

        // A mask is drawn through the stroke's transform, so it's built in the
        // stroke's own space: the note's area brought back through the inverse.
        let toStroke = stroke.transform.inverted()
        return covered.indices.compactMap { index in
            let part = covered[index].part
            let area = UIBezierPath(rect: part)
            area.apply(toStroke)
            var mask = area.cgPath
            if let existing = stroke.mask {
                mask = existing.cgPath.intersection(mask)
            }
            // Nothing left, or only a speck of `shown`'s.
            let kept = mask.boundingBoxOfPath
            guard !kept.isEmpty, kept.height >= minimumPieceHeight || kept.width >= minimumPieceHeight else { return nil }

            // A copy, so the ink, texture seed and PaperKit's render state
            // come with it. Not a render group to name the pieces as one
            // stroke: setting `renderGroupID` on a stroke from the canvas
            // traps inside PaperKit, whose strokes are a subclass that can't
            // copy with one (unit test, 9 October). The family in an
            // overflow piece's id does that instead.
            var piece = stroke
            piece.mask = UIBezierPath(cgPath: mask)
            if index != keeper {
                piece.id = overflowID(in: family)
            }
            return piece
        }
    }

    /// Which of `regions`, the pages a stroke reaches, it was started on:
    /// the one its first point is in, or failing that the nearest — a stroke
    /// moved by the lasso can have its start in space no page has.
    static func ownPiece(of stroke: PKStroke, among regions: [CGRect]) -> Int {
        guard let start = stroke.path.first?.location.applying(stroke.transform) else { return 0 }
        if let index = regions.firstIndex(where: { $0.contains(start) }) {
            return index
        }
        func distance(_ region: CGRect) -> CGFloat {
            max(region.minY - start.y, start.y - region.maxY, 0)
        }
        return regions.indices.min { distance(regions[$0]) < distance(regions[$1]) } ?? 0
    }

    /// `stroke` with a path PencilKit hasn't seen: the same points, so the
    /// same shape, for a stroke whose mask changed under an id the canvas
    /// already has. PencilKit draws a path it has seen as it drew it then:
    /// a stroke drawn across a border and given its piece's mask kept
    /// showing past the border, though the canvas held the mask (simulator,
    /// 10 October), as a bent path kept its old shape on 9 October.
    static func redrawn(_ stroke: PKStroke) -> PKStroke {
        var stroke = stroke
        stroke.path = PKStrokePath(controlPoints: Array(stroke.path), creationDate: stroke.path.creationDate)
        return stroke
    }

    /// `piece` as the canvas shows it in place of its whole stroke, which
    /// covered `extent`: `redrawn`, with a speck added to its mask at each
    /// of the extent's corners.
    ///
    /// Updated in place, PaperKit redraws only the tiles a stroke's new
    /// frame touches, and a masked stroke's frame is its mask's: ink past
    /// the border stayed on screen wherever its tiles missed the piece
    /// (simulator, 10 October). The specks keep the frame, and so what's
    /// redrawn, on the whole stroke. They're `speck` points square, outside
    /// the ink, which a stroke's frame leaves room around; points with no
    /// area didn't do, as PaperKit drops them. Cutting leaves out pieces
    /// thinner than `minimumPieceHeight`, so a speck never becomes one. Not
    /// taken off the canvas and put back instead: that redraws, but
    /// PaperKit's undo then can't find the stroke.
    static func shown(_ piece: PKStroke, over extent: CGRect) -> PKStroke {
        var piece = redrawn(piece)
        guard let mask = piece.mask?.copy() as? UIBezierPath else { return piece }
        let toStroke = piece.transform.inverted()
        for corner in [CGPoint(x: extent.minX, y: extent.minY), CGPoint(x: extent.maxX - speck, y: extent.maxY - speck)] {
            let speck = UIBezierPath(rect: CGRect(origin: corner, size: CGSize(width: speck, height: speck)))
            speck.apply(toStroke)
            mask.append(speck)
        }
        piece.mask = mask
        return piece
    }

    /// The side of `shown`'s specks, in note points.
    static let speck: CGFloat = 0.01

    // MARK: Overflow

    /// The stroke an id's piece belongs to: the id's first ten bytes, which
    /// a stroke's overflow pieces share with it.
    struct Family: Hashable, Sendable {
        fileprivate let bytes: [UInt8]
    }

    /// Bytes 10 to 13 of an overflow piece's id. A random id has these by
    /// chance once in four billion.
    private static let overflowMark: [UInt8] = [0x4E, 0x43, 0x4F, 0x56]

    private static func bytes(of id: UUID) -> [UInt8] {
        withUnsafeBytes(of: id.uuid) { Array($0) }
    }

    static func family(of id: UUID) -> Family {
        Family(bytes: Array(bytes(of: id).prefix(10)))
    }

    /// Whether an id is an overflow piece's: part of a stroke on a page
    /// other than the one it was started on.
    static func isOverflow(_ id: UUID) -> Bool {
        Array(bytes(of: id)[10..<14]) == overflowMark
    }

    /// Whether `element` is an overflow piece. Only strokes are cut.
    static func isOverflow(_ element: any Markup) -> Bool {
        (element as? PKStroke).map { isOverflow($0.id) } ?? false
    }

    /// A new id for an overflow piece of `family`. The last two bytes are
    /// random, so pieces cut again don't take each other's ids.
    static func overflowID(in family: Family) -> UUID {
        var bytes = family.bytes + overflowMark
        bytes.append(UInt8.random(in: .min ... .max))
        bytes.append(UInt8.random(in: .min ... .max))
        return bytes.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }
    }
}

#endif
