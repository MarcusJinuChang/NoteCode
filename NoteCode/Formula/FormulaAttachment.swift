//
//  FormulaAttachment.swift
//  NoteCode
//
//  LaTeX, step 3 (docs/design/latex.md › Drawing): an inline formula as a
//  text attachment the layout swaps in for its `$…$`. A template image, so the
//  text view draws it in the run's own foreground colour and one bitmap serves
//  both appearances and every coloured span.
//

#if canImport(UIKit)

import UIKit
import SwiftMath

enum FormulaAttachment {

    /// The attribute carrying a formula's `Source` on its attachment character.
    static let sourceKey = NSAttributedString.Key("NoteCode.formulaSource")

    /// Latin Modern is smaller than the system font at the same point size
    /// (x-height 84%), so a formula is set a little larger (docs/design/latex.md
    /// › Size). Provisional, to be judged on screen.
    static let sizeScale: CGFloat = 1.1

    /// Pixels per point of the bitmap. Fixed rather than following zoom:
    /// sharpness at high zoom is unverified (latex.md › Unverified).
    static let renderScale: CGFloat = 3

    /// The metrics of a typeset formula: points up from the baseline, down
    /// from it, and across.
    struct Metrics: Equatable {
        var ascent: CGFloat
        var descent: CGFloat
        var width: CGFloat
    }

    private struct Key: Hashable {
        var tex: String
        var points: CGFloat
        var display: Bool
    }

    private struct Drawn {
        var image: UIImage
        var metrics: Metrics
    }

    private static var cache: [Key: Drawn] = [:]
    private static let cacheLimit = 500

    /// The attachment for `tex` (already through `TeXAliases`) at the text's
    /// `pointSize`, or nil when SwiftMath can't typeset it.
    private static func drawn(tex: String, pointSize: CGFloat, display: Bool) -> Drawn? {
        let key = Key(tex: tex, points: pointSize, display: display)
        if let cached = cache[key] { return cached }
        guard let fresh = render(tex: tex, pointSize: pointSize * sizeScale, display: display) else { return nil }
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[key] = fresh
        return fresh
    }

    /// `fitting` is for a display block, whose formula scales down to the
    /// column rather than running off it (`FittingAttachment`).
    static func make(tex: String, pointSize: CGFloat, display: Bool, fitting: Bool = false) -> NSTextAttachment? {
        guard let drawn = drawn(tex: tex, pointSize: pointSize, display: display) else { return nil }
        let attachment = fitting ? FittingAttachment() : NSTextAttachment()
        attachment.image = drawn.image
        // The attachment sits on the baseline; a descender hangs below it by
        // the formula's descent (measured within 0.5pt, latex.md › Drawing).
        attachment.bounds = CGRect(x: 0, y: fitting ? 0 : -drawn.metrics.descent, width: drawn.metrics.width, height: drawn.metrics.ascent + drawn.metrics.descent)
        return attachment
    }

    /// What a paper draw needs to typeset a formula again: kept on the
    /// formula's U+FFFC in a laid-out paragraph (`MarkdownLayout.laidOut`).
    final class Source: NSObject {
        let tex: String
        /// The text's point size, before `sizeScale`.
        let pointSize: CGFloat
        let display: Bool
        init(tex: String, pointSize: CGFloat, display: Bool) {
            self.tex = tex
            self.pointSize = pointSize
            self.display = display
        }
    }

    /// Draws `source` as vectors (paths and an embedded font subset, so a PDF
    /// stays small and sharp at any zoom), its baseline starting at `origin` in
    /// a UIKit (y down) context, in concrete black: paper is light. Scaled down
    /// about the origin to `room` when wider, as a display block's attachment is.
    /// Returns false when SwiftMath can't typeset it.
    @discardableResult
    static func drawVector(_ source: Source, at origin: CGPoint, room: CGFloat? = nil, in context: CGContext) -> Bool {
        let label = MTMathUILabel()
        label.displayErrorInline = false
        label.fontSize = source.pointSize * sizeScale
        label.labelMode = source.display ? .display : .text
        label.textColor = .black
        label.latex = source.tex
        guard label.error == nil else { return false }
        let fit = label.intrinsicContentSize
        guard fit.width > 0, fit.height > 0 else { return false }
        label.frame = CGRect(origin: .zero, size: fit)
        label.layoutIfNeeded()
        guard let list = label.displayList else { return false }
        var scale: CGFloat = 1
        if let room, room > 0, list.width > room { scale = room / list.width }
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        // The display list is y up from its baseline.
        context.scaleBy(x: scale, y: -scale)
        // The label placed the list with its baseline `descent` above its
        // frame's bottom (left aligned, no insets).
        context.translateBy(x: 0, y: -list.descent)
        list.draw(context)
        context.restoreGState()
        return true
    }

    /// Metrics only, for tests.
    static func metrics(tex: String, pointSize: CGFloat, display: Bool) -> Metrics? {
        drawn(tex: tex, pointSize: pointSize, display: display)?.metrics
    }

    private static func render(tex: String, pointSize: CGFloat, display: Bool) -> Drawn? {
        let label = MTMathUILabel()
        label.displayErrorInline = false
        label.fontSize = pointSize
        label.labelMode = display ? .display : .text
        label.textAlignment = .left
        label.textColor = .black
        label.latex = tex
        guard label.error == nil else { return nil }
        let fit = label.intrinsicContentSize
        guard fit.width > 0, fit.height > 0 else { return nil }
        label.frame = CGRect(origin: .zero, size: fit)
        label.layoutIfNeeded()
        guard let list = label.displayList else { return nil }
        let metrics = Metrics(ascent: list.ascent, descent: list.descent, width: list.width)

        let format = UIGraphicsImageRendererFormat()
        format.scale = renderScale
        format.opaque = false
        let size = label.bounds.size
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            // The label's layer is geometry-flipped, so UIKit's y-down
            // context needs one more flip.
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            label.layer.render(in: context.cgContext)
        }.withRenderingMode(.alwaysTemplate)
        return Drawn(image: image, metrics: metrics)
    }
}

/// A display block's formula: the same image, scaled down when it is wider
/// than the line it lands on (the text container's width is pinned per note,
/// so the answer depends on the note alone). No floor.
final class FittingAttachment: NSTextAttachment {
    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        let natural = bounds
        let room = proposedLineFragment.width
        guard natural.width > room, room > 0 else { return natural }
        let scale = room / natural.width
        return CGRect(x: 0, y: natural.minY * scale, width: natural.width * scale, height: natural.height * scale)
    }
}

/// How much room a display formula takes, and where it sits in it.
/// A fixed height on the opening line (the code fences' header does the same,
/// latex.md › Drawing), because TextKit would not grow the line to the
/// attachment's bounds in the probe.
enum DisplayFormula {
    /// Space above and below the formula.
    static let gap: CGFloat = 8
    /// The `$$` block's other lines: the smallest height TextKit keeps.
    static let sourceLineHeight: CGFloat = 1

    /// The formula's own room: its height and the gap above and below.
    static func lineHeight(tex: String, pointSize: CGFloat) -> CGFloat? {
        guard let m = FormulaAttachment.metrics(tex: tex, pointSize: pointSize, display: true) else { return nil }
        return (m.ascent + m.descent + 2 * gap).rounded(.up)
    }

    /// The fixed height to ask TextKit for. Measured (29 Oct, probes at 17pt):
    /// a line holding an attachment that hangs below the baseline comes out
    /// taller than the height asked for, by about the attachment's descent less
    /// the font's, whatever the baseline offset (a sum over a fraction asked
    /// 50 gave 66.3). So a display formula's attachment sits *on* the baseline
    /// (`make(fitting:)`: its descent is part of its height) and is raised by
    /// `baselineLift` instead.
    static func paragraphHeight(tex: String, font: UIFont) -> CGFloat? {
        lineHeight(tex: tex, pointSize: font.pointSize).map { $0 - slack }
    }

    /// What TextKit adds to every fixed-height line (measured: a line asked for
    /// 1pt is 2.71pt, one asked for H - 1.71 is H), at 17pt.
    static let slack: CGFloat = 1.7129

    /// Below the baseline the line has the font's descent and the slack; the
    /// attachment is raised by the gap less that, so its bottom is `gap` above
    /// the line's end.

    static func baselineLift(tex: String, font: UIFont) -> CGFloat {
        gap - CodeBlockRoom.descent(of: font) - slack
    }
}

#endif
