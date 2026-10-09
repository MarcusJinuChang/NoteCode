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
enum InkPages {

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

        let covered = regions.compactMap { region -> CGRect? in
            let part = region.intersection(visible)
            guard !part.isNull, part.height >= minimumPieceHeight, part.width > 0 else { return nil }
            return part
        }
        if covered.isEmpty {
            return [stroke]
        }
        if covered.count == 1, covered[0].height >= visible.height - minimumPieceHeight {
            return [stroke]
        }

        // A mask is drawn through the stroke's transform, so it's built in the
        // stroke's own space: the note's area brought back through the inverse.
        let toStroke = stroke.transform.inverted()
        return covered.compactMap { part in
            let area = UIBezierPath(rect: part)
            area.apply(toStroke)
            var mask = area.cgPath
            if let existing = stroke.mask {
                mask = existing.cgPath.intersection(mask)
            }
            guard !mask.boundingBoxOfPath.isEmpty else { return nil }

            // A copy, so the ink, texture seed and PaperKit's render state
            // come with it. Not a render group to name the pieces as one
            // stroke: setting `renderGroupID` on a stroke from the canvas
            // traps inside PaperKit, whose strokes are a subclass that can't
            // copy with one (unit test, 9 October). `PageView` keeps which
            // stroke each piece came from instead.
            var piece = stroke
            piece.mask = UIBezierPath(cgPath: mask)
            piece.id = UUID()
            return piece
        }
    }
}

#endif
