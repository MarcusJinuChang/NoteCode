//
//  TextRegionSelection.swift
//  NoteCode
//
//  The text a Select-tool shape covers: one range per line it crosses, the
//  characters inside the shape (docs/design/object-system.md, decisions 2
//  and 3). The geometry is pure; one function reads it from a text view.
//

import CoreGraphics
import Foundation

nonisolated enum TextRegion {

    /// A laid-out line of text, in the note's coordinates.
    struct Line: Sendable {
        /// The characters on the line, in the text's UTF-16 units.
        var range: NSRange
        var rect: CGRect
        /// The character offset (within the whole text) nearest an x.
        var offset: @Sendable (CGFloat) -> Int
    }

    /// A range of one line, and where it is drawn.
    struct Piece: Equatable, Sendable {
        var range: NSRange
        var rect: CGRect
    }

    /// The characters of each line `shape` covers, left to right.
    ///
    /// A rectangle covers the line from its left edge to its right; a lasso,
    /// from where it first crosses the line's middle to where it last does.
    /// A line the shape only grazes (less than a character wide) gives nothing,
    /// so a tap selects no text.
    static func pieces(for shape: SelectionShape, lines: [Line]) -> [Piece] {
        let area = shape.bounds
        guard !area.isNull else { return [] }
        var pieces: [Piece] = []
        for line in lines where line.rect.intersects(area) {
            guard let span = span(of: shape, at: line.rect.midY, within: line.rect) else { continue }
            let from = line.offset(span.lowerBound)
            let to = line.offset(span.upperBound)
            let lower = min(max(min(from, to), line.range.location), NSMaxRange(line.range))
            let upper = min(max(max(from, to), line.range.location), NSMaxRange(line.range))
            guard upper > lower else { continue }
            let x0 = max(span.lowerBound, line.rect.minX), x1 = min(span.upperBound, line.rect.maxX)
            pieces.append(Piece(range: NSRange(location: lower, length: upper - lower),
                                rect: CGRect(x: x0, y: line.rect.minY, width: max(x1 - x0, 0), height: line.rect.height)))
        }
        return pieces
    }

    private static func span(of shape: SelectionShape, at y: CGFloat, within line: CGRect) -> ClosedRange<CGFloat>? {
        switch shape {
        case .rectangle(let rect):
            let r = rect.standardized
            guard r.minY <= y && y <= r.maxY, r.maxX > r.minX else { return nil }
            return r.minX...r.maxX
        case .lasso(let points):
            guard points.count >= 3 else { return nil }
            var crossings: [CGFloat] = []
            var previous = points[points.count - 1]
            for current in points {
                if (current.y > y) != (previous.y > y) {
                    crossings.append((previous.x - current.x) * (y - current.y) / (previous.y - current.y) + current.x)
                }
                previous = current
            }
            guard let low = crossings.min(), let high = crossings.max(), high > low else { return nil }
            return low...high
        }
    }
}

/// Which text colour an ink colour stands for. Ink and text have palettes of
/// their own (docs/design/object-system.md, question 4): the ink colour is
/// mapped to the nearest text colour, and a grey, black or white is "no
/// colour", the text's own.
nonisolated extension TextColour {

    static func nearest(red: Double, green: Double, blue: Double) -> TextColour? {
        let top = max(red, green, blue), bottom = min(red, green, blue)
        // Greys, black and white have no hue to speak of.
        if top - bottom < 0.15 { return nil }
        var best: (colour: TextColour, distance: Double)?
        for colour in TextColour.allCases {
            let r = Double((colour.hex >> 16) & 0xFF) / 255
            let g = Double((colour.hex >> 8) & 0xFF) / 255
            let b = Double(colour.hex & 0xFF) / 255
            let distance = (r - red) * (r - red) + (g - green) * (g - green) + (b - blue) * (b - blue)
            if best == nil || distance < best!.distance { best = (colour, distance) }
        }
        return best?.colour
    }
}

#if canImport(UIKit)

import UIKit

extension TextRegion {

    /// The lines of `textView` on screen, in its content's coordinates (the
    /// note's). Reads only what TextKit has laid out for the viewport; asking
    /// for more would lay out the note down to it (AGENTS.md, lazy layout).
    @MainActor
    static func visibleLines(in textView: UITextView) -> [Line] {
        guard let manager = textView.textLayoutManager,
              let content = manager.textContentManager,
              let viewport = manager.textViewportLayoutController.viewportRange
        else { return [] }
        let origin = CGPoint(x: textView.textContainerInset.left, y: textView.textContainerInset.top)
        var lines: [Line] = []
        manager.enumerateTextLayoutFragments(from: viewport.location, options: []) { fragment in
            if fragment.rangeInElement.location.compare(viewport.endLocation) != .orderedAscending { return false }
            let base = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            for line in fragment.textLineFragments {
                let bounds = line.typographicBounds
                let rect = CGRect(
                    x: origin.x + fragment.layoutFragmentFrame.minX + bounds.minX,
                    y: origin.y + fragment.layoutFragmentFrame.minY + bounds.minY,
                    width: bounds.width, height: bounds.height
                )
                let range = NSRange(location: base + line.characterRange.location, length: line.characterRange.length)
                let left = rect.minX, fragmentBase = base, line = line
                lines.append(Line(range: range, rect: rect, offset: { x in
                    fragmentBase + line.characterIndex(for: CGPoint(x: x - left + line.typographicBounds.minX, y: line.typographicBounds.midY))
                }))
            }
            return true
        }
        return lines
    }
}

#endif
