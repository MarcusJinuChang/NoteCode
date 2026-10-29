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
    static func make(tex: String, pointSize: CGFloat, display: Bool) -> NSTextAttachment? {
        let key = Key(tex: tex, points: pointSize, display: display)
        let drawn: Drawn
        if let cached = cache[key] {
            drawn = cached
        } else {
            guard let fresh = render(tex: tex, pointSize: pointSize * sizeScale, display: display) else { return nil }
            if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
            cache[key] = fresh
            drawn = fresh
        }
        let attachment = NSTextAttachment()
        attachment.image = drawn.image
        // The attachment sits on the baseline; a descender hangs below it by
        // the formula's descent (measured within 0.5pt, latex.md › Drawing).
        attachment.bounds = CGRect(x: 0, y: -drawn.metrics.descent, width: drawn.metrics.width, height: drawn.metrics.ascent + drawn.metrics.descent)
        return attachment
    }

    /// Metrics only, for tests.
    static func metrics(tex: String, pointSize: CGFloat, display: Bool) -> Metrics? {
        render(tex: tex, pointSize: pointSize * sizeScale, display: display)?.metrics
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

#endif
