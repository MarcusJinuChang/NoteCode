//
//  InkBending.swift
//  NoteCode
//
//  Ink moved between view modes, bent at a page break it crosses.
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import UIKit

/// Moves ink from one view mode's coordinates to another's.
///
/// **Why bend.** Every mode puts the same lines on the same pages, but the
/// space between one page's text and the next differs: 1 point in seamless,
/// 24 in compressed, 168 in print layout. Text reflows across it; a stroke
/// moved whole can't. Moved by the page its middle is on, a stroke drawn
/// across a break sat on its words on one side and was off by the
/// difference on the other, 23 points between seamless and compressed
/// (simulator, 9 October). Bent, each of its points moves with its own page
/// (`PageLayout.inkY`), so both ends stay on their words in every mode, and
/// it's still one stroke: one erase, one lasso, one undo.
///
/// **What bending changes.** Only the stretch across the break, which lies
/// in room seamless doesn't have and is hidden under `PageCoverView`. The
/// bent stroke is rebuilt from points sampled close together along the one
/// drawn (`samples`), so either side of the break it follows the original.
/// A stroke drawn across compressed's strip or print layout's gap is
/// squeezed into seamless's break, so it stays joined there.
///
/// **What isn't bent.** A stroke within one page's region, which is nearly
/// every stroke, moves whole, as before. So does one that reaches only one
/// page's region and runs into the room beside it: ink saved before
/// 9 October was stored whole, by the page its middle was on, and a stroke
/// drawn across a break in seamless then sits on one page and in the gap
/// beyond it in print coordinates. Moved whole, it still shows as it was
/// drawn; bent, the part in the gap would be squeezed into seamless's break
/// and lost. A stroke reaching two pages' regions can only have been bent
/// when it was saved — or be an old one more than 1.7 inches past a break.
enum InkBending {

    /// `element`, drawn or stored in `from`'s coordinates, as it goes in
    /// `to`'s. `nil` across orientations.
    static func moved(_ element: any Markup, from: PageLayout, to: PageLayout) -> (any Markup)? {
        guard from.orientation == to.orientation else { return nil }
        guard from != to else { return element }
        if let stroke = element as? PKStroke, crossesBreak(stroke, in: from) {
            return bent(stroke, from: from, to: to)
        }
        // Whole, by the page its middle is on.
        var element = element
        let middle = element.renderFrame.midY
        if let target = from.inkY(middle, in: to), target != middle {
            element.applyTransform(CGAffineTransform(translationX: 0, y: target - middle))
        }
        return element
    }

    /// Whether `stroke`'s ink reaches into two pages' regions in `layout`.
    static func crossesBreak(_ stroke: PKStroke, in layout: PageLayout) -> Bool {
        let shown = visibleFrame(of: stroke)
        guard !shown.isNull, !shown.isEmpty else { return false }
        return layout.inkPagesReached(from: shown.minY, to: shown.maxY) >= 2
    }

    /// Where a stroke has ink: its path's extent, within its mask if it has
    /// one. The mask's own bounds rather than the stroke's frame, which
    /// PaperKit rounds out to whole points.
    static func visibleFrame(of stroke: PKStroke) -> CGRect {
        var bare = stroke
        bare.mask = nil
        var frame = bare.renderFrame
        if let mask = stroke.mask {
            frame = frame.intersection(mask.bounds.applying(stroke.transform))
        }
        return frame
    }

    /// `stroke` with each point, and its mask, moved by `PageLayout.inkY`.
    ///
    /// A new stroke with the same id rather than the stroke with a new path:
    /// the canvas ignores a path changed on one of its own strokes when
    /// it's handed back (probe, 9 October). Its ink, texture seed, render
    /// group and PaperKit's render state come with it — but not its path's
    /// id. PencilKit draws a path it has seen before as it drew it then:
    /// with the id kept, print layout showed the stroke's seamless shape at
    /// seamless's positions, though the canvas held the print layout one
    /// (simulator, 9 October).
    static func bent(_ stroke: PKStroke, from: PageLayout, to: PageLayout) -> PKStroke {
        let transform = stroke.transform
        let inverse = transform.inverted()
        // Points are in the stroke's own space and drawn through its
        // transform, so they're moved in the note's.
        func move(_ point: CGPoint) -> CGPoint {
            let note = point.applying(transform)
            let y = from.inkY(note.y, in: to) ?? note.y
            return CGPoint(x: note.x, y: y).applying(inverse)
        }

        let points = samples(of: stroke, in: from).map { point in
            PKStrokePoint(
                location: move(point.location),
                timeOffset: point.timeOffset,
                size: point.size,
                opacity: point.opacity,
                force: point.force,
                azimuth: point.azimuth,
                altitude: point.altitude,
                secondaryScale: point.secondaryScale,
                threshold: point.threshold
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate)
        let mask = stroke.mask.map { mask in
            UIBezierPath(cgPath: bent(mask.cgPath, from: from, to: to, through: transform))
        }
        return PKStroke(
            ink: stroke.ink,
            path: path,
            transform: transform,
            mask: mask,
            randomSeed: stroke.randomSeed,
            id: stroke.id,
            renderGroupID: stroke.renderGroupID,
            renderState: stroke.renderState
        )
    }

    /// How far apart `samples` are, along the stroke.
    static let sampleSpacing: CGFloat = 1.5

    /// `stroke`'s path as it's drawn, as points `sampleSpacing` apart, with
    /// one exactly where it crosses each page region's edge in `layout`.
    ///
    /// Bent from its own control points, a stroke went astray at the break.
    /// PencilKit draws a stroke as a curve its control points steer rather
    /// than pass through, and they can be 25 points apart: pulled 168
    /// points apart either side of the break, they steered the curve off
    /// both pages, and in print layout all that showed was a sliver at the
    /// foot of the first page (simulator, 9 October). Points this close
    /// together steer the curve along the line they sample, so each page
    /// keeps the stroke it had, right up to its edge.
    static func samples(of stroke: PKStroke, in layout: PageLayout) -> [PKStrokePoint] {
        let path = stroke.path
        var points = Array(path.interpolatedPoints(by: .distance(sampleSpacing)))
        if path.count > 0 {
            let end = path.interpolatedPoint(at: CGFloat(path.count - 1))
            if let last = points.last, hypot(last.location.x - end.location.x, last.location.y - end.location.y) > 0.01 {
                points.append(end)
            } else if points.isEmpty {
                points.append(end)
            }
        }

        let transform = stroke.transform
        let ys = points.map { $0.location.applying(transform).y }
        guard let low = ys.min(), let high = ys.max() else { return points }
        let first = layout.pageIndex(atY: low)
        let last = max(first, layout.pageIndex(atY: high))
        let edges = (first...last + 1).flatMap { index in
            [layout.inkRegion(ofPage: index).minY, layout.inkRegion(ofPage: index).maxY]
        }

        var result: [PKStrokePoint] = []
        for index in points.indices {
            if index > 0 {
                let (a, b) = (ys[index - 1], ys[index])
                let crossed = edges.filter { $0 > min(a, b) && $0 < max(a, b) }
                    .sorted { a < b ? $0 < $1 : $0 > $1 }
                // Three times: a curve passes through a point repeated
                // three times, so it reaches the page's edge exactly and
                // isn't steered past it by the point across the break.
                for edge in crossed {
                    let point = blend(points[index - 1], points[index], at: (edge - a) / (b - a))
                    result += [point, point, point]
                }
            }
            result.append(points[index])
        }
        return result
    }

    /// The point `fraction` of the way from `a` to `b`.
    private static func blend(_ a: PKStrokePoint, _ b: PKStrokePoint, at fraction: CGFloat) -> PKStrokePoint {
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * fraction }
        return PKStrokePoint(
            location: CGPoint(x: mix(a.location.x, b.location.x), y: mix(a.location.y, b.location.y)),
            timeOffset: a.timeOffset + (b.timeOffset - a.timeOffset) * Double(fraction),
            size: CGSize(width: mix(a.size.width, b.size.width), height: mix(a.size.height, b.size.height)),
            opacity: mix(a.opacity, b.opacity),
            force: mix(a.force, b.force),
            azimuth: mix(a.azimuth, b.azimuth),
            altitude: mix(a.altitude, b.altitude),
            secondaryScale: mix(a.secondaryScale, b.secondaryScale),
            threshold: mix(a.threshold, b.threshold)
        )
    }

    /// A mask — PencilKit's pixel eraser leaves one on what it doesn't
    /// erase — bent the same way, in the stroke's own space.
    ///
    /// Flattened into straight segments and each cut where it crosses a
    /// region's edge, so a side running across a break bends there as the
    /// stroke does, rather than cutting the corner.
    static func bent(_ mask: CGPath, from: PageLayout, to: PageLayout, through transform: CGAffineTransform) -> CGPath {
        var toNote = transform
        guard let inNote = mask.copy(using: &toNote)?.flattened(threshold: 0.25) else { return mask }

        let box = inNote.boundingBoxOfPath
        let first = from.pageIndex(atY: box.minY)
        let last = max(first, from.pageIndex(atY: box.maxY))
        let edges = (first...last + 1).flatMap { index in
            [from.inkRegion(ofPage: index).minY, from.inkRegion(ofPage: index).maxY]
        }
        func move(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: from.inkY(point.y, in: to) ?? point.y)
        }

        let result = CGMutablePath()
        var current = CGPoint.zero
        var start = CGPoint.zero
        func line(to end: CGPoint) {
            let low = min(current.y, end.y), high = max(current.y, end.y)
            let cuts = edges.filter { $0 > low && $0 < high }
                .sorted { current.y < end.y ? $0 < $1 : $0 > $1 }
            for y in cuts {
                let fraction = (y - current.y) / (end.y - current.y)
                result.addLine(to: move(CGPoint(x: current.x + fraction * (end.x - current.x), y: y)))
            }
            result.addLine(to: move(end))
            current = end
        }
        inNote.applyWithBlock { element in
            let element = element.pointee
            switch element.type {
            case .moveToPoint:
                current = element.points[0]
                start = current
                result.move(to: move(current))
            case .addLineToPoint:
                line(to: element.points[0])
            case .closeSubpath:
                line(to: start)
                result.closeSubpath()
            default:
                // Flattened: only moves, lines and closes are left.
                break
            }
        }
        var back = transform.inverted()
        return result.copy(using: &back) ?? result
    }
}

#endif
