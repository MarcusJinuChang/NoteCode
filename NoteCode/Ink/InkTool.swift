//
//  InkTool.swift
//  NoteCode
//
//  The pen, highlighter, eraser and lasso the hotbar offers in ink mode, and
//  what each is set to. The colours, widths and eraser live beside it.
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


// MARK: - Selection

/// What the hotbar has selected in ink mode: the tool, and what each tool is
/// set to.
nonisolated struct InkToolState: Equatable, Sendable {
    var kind: InkToolKind = .pen
    var pen = InkingSettings.standard(for: .pen)
    var highlighter = InkingSettings.standard(for: .highlighter)
    var eraser = EraserSettings()
    /// How the Select tool (`.lasso`) draws its shape.
    var selectionKind = SelectionKind.lasso

    /// The settings of the pen or the highlighter. The eraser and lasso have
    /// none; asked, they answer with the pen's, which is what a swatch row
    /// that has outlived its tool by a frame would show.
    subscript(inking kind: InkToolKind) -> InkingSettings {
        get { kind == .highlighter ? highlighter : pen }
        set {
            if kind == .highlighter {
                highlighter = newValue
            } else {
                pen = newValue
            }
        }
    }

    /// Whether the selected tool has anything to set. Every tool does: the
    /// Select tool has its shape and, with a selection, its commands.
    var hasOptions: Bool {
        true
    }

    /// Moves the selected tool one width thinner (`-1`) or thicker (`1`),
    /// stopping at the ends: the `[` and `]` keys.
    ///
    /// The pen and highlighter step through their three widths. The eraser
    /// steps through its sizes, and from a custom size goes to the nearest
    /// preset on that side, so the key always does something visible. The
    /// lasso has no width.
    mutating func stepWidth(by direction: Int) {
        guard direction != 0 else { return }
        let step = direction > 0 ? 1 : -1

        switch kind {
        case .pen, .highlighter:
            let widths = InkWidth.allCases
            guard let index = widths.firstIndex(of: self[inking: kind].width) else { return }
            let target = min(max(index + step, 0), widths.count - 1)
            self[inking: kind].width = widths[target]

        case .eraser:
            let presets: [EraserSettings.Size] = [.small, .medium, .large]
            if let index = presets.firstIndex(of: eraser.size) {
                eraser.size = presets[min(max(index + step, 0), presets.count - 1)]
            } else {
                // Custom: the nearest preset on the side asked for, else the
                // end of the range, so the key never does nothing.
                let width = eraser.customWidth
                let widths = presets.compactMap { EraserSettings.width(of: $0) }
                let candidates = presets.indices.filter { step > 0 ? widths[$0] > width : widths[$0] < width }
                eraser.size = (step > 0 ? candidates.first : candidates.last).map { presets[$0] }
                    ?? (step > 0 ? .large : .small)
            }

        case .lasso:
            break
        }
    }
}


#if canImport(UIKit)

extension InkColor {

    /// A colour's components, in the light appearance.
    init(_ color: UIColor) {
        let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        light.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// A colour the reader chose while looking at a page in `style`.
    ///
    /// PencilKit stores ink in light colours and adapts them for dark mode,
    /// so a colour picked on a dark page is stored as the light colour that
    /// adapts to it. Taken as it is, white picked on a dark page would draw
    /// black.
    init(chosen color: UIColor, on style: UIUserInterfaceStyle) {
        self.init(PKInkingTool.convertColor(color, from: style == .dark ? .dark : .light, to: .light))
    }

    static let blue = InkColor(UIColor.systemBlue)
    static let red = InkColor(UIColor.systemRed)
    static let green = InkColor(UIColor.systemGreen)
    static let orange = InkColor(UIColor.systemOrange)

    /// The colour as it is stored in a drawing.
    ///
    /// Always fixed, never dynamic. PencilKit adapts ink for dark mode on its
    /// own, so a dynamic colour would bake in whichever appearance happened
    /// to be current when the stroke was drawn.
    var inkColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// How this ink looks on a page in the given appearance — what a swatch
    /// should show, so black ink doesn't vanish into a dark hotbar.
    func displayColor(for style: UIUserInterfaceStyle) -> UIColor {
        PKInkingTool.convertColor(inkColor, from: .light, to: style)
    }

    /// What a hotbar swatch shows for this ink on a page in `style`: the ink
    /// as the page shows it, except that a highlighter on a dark bar is made
    /// vivid (`vividFace`).
    func swatchFace(for style: UIUserInterfaceStyle, kind: InkToolKind) -> UIColor {
        let shown = displayColor(for: style)
        guard style == .dark, kind == .highlighter else { return shown }
        return InkColor(shown).vividFace.inkColor
    }

    /// What VoiceOver calls it: the design's name for its own inks, and
    /// otherwise the system's description of the colour: "light blue".
    var name: String {
        Self.shadeNames[self] ?? inkColor.accessibilityName
    }
}

extension InkingSettings {
    /// The PencilKit tool for the pen or the highlighter set this way.
    func pencilKitTool(for kind: InkToolKind) -> PKInkingTool {
        let type: PKInkingTool.InkType = kind == .highlighter ? .marker : .pen
        return PKInkingTool(type, color: color.inkColor, width: width.points(for: kind, ink: type))
    }
}

extension InkWidth {
    /// The width in points for an ink type: its multiple of the type's
    /// default, kept inside the range PencilKit takes.
    func points(for kind: InkToolKind, ink type: PKInkingTool.InkType) -> CGFloat {
        let range = type.validWidthRange
        return points(
            for: kind,
            defaultWidth: Double(type.defaultWidth),
            validRange: Double(range.lowerBound)...Double(range.upperBound)
        )
    }
}

extension EraserSettings {
    /// The PencilKit eraser for these settings.
    ///
    /// The fixed-width eraser rather than the plain pixel one: PaperKit turns
    /// the plain one into this anyway (read back from the canvas on
    /// 26 September), and only this one takes a width.
    var pencilKitTool: PKEraserTool {
        switch mode {
        case .partial:     PKEraserTool(.fixedWidthBitmap, width: width)
        case .wholeStroke: PKEraserTool(.vector)
        }
    }
}

extension InkToolState {
    /// The PencilKit tool this selection stands for. The canvas takes this
    /// directly; nothing else needs to know PencilKit's tool types.
    var pencilKitTool: any PKTool {
        switch kind {
        case .pen:
            pen.pencilKitTool(for: .pen)
        case .highlighter:
            highlighter.pencilKitTool(for: .highlighter)
        case .eraser:
            eraser.pencilKitTool
        case .lasso:
            PKLassoTool()
        }
    }
}

#endif
