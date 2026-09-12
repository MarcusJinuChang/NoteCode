//
//  InkTool.swift
//  NoteCode
//
//  The pen, highlighter, eraser and lasso the hotbar offers in ink mode.
//

import Foundation
#if canImport(UIKit)
import PencilKit
import UIKit
#endif

nonisolated enum InkToolKind: String, CaseIterable, Sendable {
    case pen
    case highlighter
    case eraser
    /// Selects strokes to move or delete — the mockup's selection tool.
    case lasso

    /// Only the tools that lay down ink have a colour.
    var usesColor: Bool {
        self == .pen || self == .highlighter
    }
}

/// A short fixed palette rather than a colour picker. A lecture is not the
/// moment for a colour wheel, and a handful is enough to annotate code.
nonisolated enum InkColor: String, CaseIterable, Sendable {
    case black
    case blue
    case red
    case green
    case orange
}

/// What the hotbar has selected in ink mode.
nonisolated struct InkToolState: Equatable, Sendable {
    var kind: InkToolKind = .pen
    var color: InkColor = .black
}

#if canImport(UIKit)

extension InkColor {
    /// The colour as it is stored in a drawing.
    ///
    /// Always the light-appearance variant. PencilKit stores ink in light
    /// colours and adapts them for dark mode on its own, so handing it a
    /// dynamic colour would bake in whichever appearance happened to be
    /// current when the stroke was drawn.
    var inkColor: UIColor {
        let light = UITraitCollection(userInterfaceStyle: .light)
        return switch self {
        case .black:  UIColor.black
        case .blue:   UIColor.systemBlue.resolvedColor(with: light)
        case .red:    UIColor.systemRed.resolvedColor(with: light)
        case .green:  UIColor.systemGreen.resolvedColor(with: light)
        case .orange: UIColor.systemOrange.resolvedColor(with: light)
        }
    }

    /// How this ink looks on a page in the given appearance — what a swatch
    /// should show, so black ink doesn't vanish into a dark hotbar.
    func displayColor(for style: UIUserInterfaceStyle) -> UIColor {
        PKInkingTool.convertColor(inkColor, from: .light, to: style)
    }
}

extension InkToolState {
    /// The PencilKit tool this selection stands for. The canvas takes this
    /// directly; nothing else needs to know PencilKit's tool types.
    var pencilKitTool: any PKTool {
        switch kind {
        case .pen:
            PKInkingTool(.pen, color: color.inkColor)
        case .highlighter:
            PKInkingTool(.marker, color: color.inkColor)
        case .eraser:
            // Partial rather than whole-stroke, so fixing one letter of
            // handwriting doesn't take the rest of the word with it.
            PKEraserTool(.bitmap)
        case .lasso:
            PKLassoTool()
        }
    }
}

#endif
