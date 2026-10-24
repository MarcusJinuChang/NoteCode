//
//  Formula.swift
//  LaTeXSpike
//
//  What the app would need from SwiftMath, and nothing else: a formula's
//  metrics (width, ascent over the baseline, descent under it), an image of
//  it at a pixel scale in a colour, and a vector draw into any CGContext.
//
//  SwiftMath's typesetter (`MTTypesetter`) is internal, so everything goes
//  through `MTMathUILabel`, whose `displayList` is public.

#if canImport(UIKit)
import UIKit
import SwiftMath

public struct FormulaMetrics: Equatable {
    /// Points from the baseline up to the top of the ink's box.
    public var ascent: CGFloat
    /// Points from the baseline down to the bottom of the ink's box.
    public var descent: CGFloat
    public var width: CGFloat
    public var height: CGFloat { ascent + descent }
}

public enum FormulaResult {
    case drawn(Formula)
    case failed(message: String)
}

@MainActor
public final class Formula {
    public let latex: String
    public let fontSize: CGFloat
    public let isDisplay: Bool
    public let metrics: FormulaMetrics
    private let label: MTMathUILabel

    /// `nil` message-less success only through `.drawn`; a parse error is `.failed`.
    public static func make(latex: String, fontSize: CGFloat, display: Bool) -> FormulaResult {
        let label = MTMathUILabel()
        label.displayErrorInline = false
        label.fontSize = fontSize
        label.labelMode = display ? .display : .text
        label.textAlignment = .left
        label.latex = latex
        if let error = label.error {
            return .failed(message: error.localizedDescription)
        }
        let fit = label.intrinsicContentSize
        label.frame = CGRect(origin: .zero, size: fit)
        label.layoutIfNeeded()
        guard let list = label.displayList else { return .failed(message: "no display list") }
        let metrics = FormulaMetrics(ascent: list.ascent, descent: list.descent, width: list.width)
        return .drawn(Formula(latex: latex, fontSize: fontSize, isDisplay: display, metrics: metrics, label: label))
    }

    private init(latex: String, fontSize: CGFloat, isDisplay: Bool, metrics: FormulaMetrics, label: MTMathUILabel) {
        self.latex = latex
        self.fontSize = fontSize
        self.isDisplay = isDisplay
        self.metrics = metrics
        self.label = label
    }

    /// Draws with the baseline at `baselineY` from the top of the image, in a
    /// colour already resolved for the appearance.
    public func image(color: UIColor, scale: CGFloat) -> UIImage {
        label.textColor = color
        label.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let size = label.bounds.size
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            // The label's layer is geometry-flipped (SwiftMath draws y up), so
            // rendering it into UIKit's y-down context needs one more flip.
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            label.layer.render(in: context.cgContext)
        }
    }

    /// Vector: the label's own display list into a context, y up, the
    /// baseline at `origin`. The list is positioned inside the label at
    /// (0, descent) since the label is exactly as high as the formula.
    public func draw(in context: CGContext, baselineOrigin origin: CGPoint, color: UIColor) {
        label.textColor = color
        label.layoutIfNeeded()
        guard let list = label.displayList else { return }
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y - metrics.descent)
        list.draw(context)
        context.restoreGState()
    }
}
#endif
