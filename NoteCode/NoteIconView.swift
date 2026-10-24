//
//  NoteIconView.swift
//  NoteCode
//
//  Draws `NoteIcon`s for the hotbar and its rows, and the one setting that
//  says whether they are drawn at all.
//

import SwiftUI

/// Whether the bar's icons are NoteCode's own or the system's, and how heavy
/// the drawn ones are. Per device, stored as one string (`drawn.regular`).
nonisolated struct IconStyle: Equatable, Sendable {
    static let defaultsKey = "iconStyle"

    var isDrawn = true
    var weight = IconWeight.regular

    /// One step heavier, for Increase Contrast.
    var increased: IconStyle {
        var style = self
        switch weight {
        case .light:   style.weight = .regular
        case .regular: style.weight = .bold
        case .bold:    break
        }
        return style
    }
}

extension IconStyle: RawRepresentable {

    nonisolated var rawValue: String {
        "\(isDrawn ? "drawn" : "system").\(weight.rawValue)"
    }

    nonisolated init?(rawValue: String) {
        let parts = rawValue.split(separator: ".").map(String.init)
        guard parts.count == 2, ["drawn", "system"].contains(parts[0]),
              let weight = IconWeight(rawValue: parts[1]) else { return nil }
        self.init(isDrawn: parts[0] == "drawn", weight: weight)
    }
}

extension IconWeight {
    var title: String { rawValue.capitalized }
}

/// One icon, at whatever size it is given, in the style it is given: strokes
/// in the foreground style, a second soft tone behind them.
struct NoteIconView: View {
    var icon: NoteIcon
    var weight = IconWeight.regular

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            var drawing = context
            drawing.translateBy(x: (size.width - 24 * scale) / 2, y: (size.height - 24 * scale) / 2)
            drawing.scaleBy(x: scale, y: scale)
            for layer in icon.layers {
                let path = Path(layer.path)
                switch layer.kind {
                case .stroke:
                    drawing.stroke(path, with: .foreground, style: StrokeStyle(
                        lineWidth: weight.lineWidth * layer.weight, lineCap: .round, lineJoin: .round))
                case .solid:
                    drawing.fill(path, with: .foreground)
                case .soft:
                    var soft = drawing
                    soft.opacity = IconLayer.softOpacity
                    soft.fill(path, with: .foreground)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
