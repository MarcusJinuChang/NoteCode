//
//  InkTool.swift
//  NoteCode
//
//  The pen, highlighter, eraser and lasso the hotbar offers in ink mode, the
//  colours they draw in, and how the eraser erases.
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

// MARK: - Colour

/// A colour ink is drawn in, as sRGB components in the light appearance.
///
/// Components rather than a `UIColor`, so a colour can be compared, stored
/// and shown in a palette. Extended sRGB: a colour chosen from the Display P3
/// part of the picker has components outside 0 to 1, and keeps them.
nonisolated struct InkColor: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    static let black = InkColor(red: 0, green: 0, blue: 0)

    /// Whether two colours are the same to 8 bits a channel, which is as
    /// finely as the picker's own sliders and hex field set one.
    func matches(_ other: InkColor) -> Bool {
        let tolerance = 0.5 / 255
        return abs(red - other.red) < tolerance
            && abs(green - other.green) < tolerance
            && abs(blue - other.blue) < tolerance
            && abs(alpha - other.alpha) < tolerance
    }
}

/// The colours the hotbar offers, in the reader's order.
///
/// Five to start with. A lecture is not the moment for a colour wheel, so
/// the picker is for building a palette, and the palette is what's used.
/// Stored per device, like the dock: it's how this reader likes to work,
/// not part of any note.
nonisolated struct InkPalette: Equatable, Sendable {

    static let defaultsKey = "inkPalette"

    /// Never empty, and never holding one colour twice.
    private(set) var colors: [InkColor]

    /// - Parameter colors: repeats are dropped, keeping the first; an empty
    ///   list keeps black, so there's always something to draw with.
    init(_ colors: [InkColor]) {
        var seen = Set<InkColor>()
        let unique = colors.filter { seen.insert($0).inserted }
        self.colors = unique.isEmpty ? [.black] : unique
    }

    /// Adds a colour at the end, unless it's already there.
    ///
    /// - Returns: the palette's colour: the new one, or the one already
    ///   there that it matches. A colour back from the picker has been
    ///   through float conversions, and black came back a hair off black.
    @discardableResult
    mutating func add(_ color: InkColor) -> InkColor {
        if let existing = colors.first(where: { $0.matches(color) }) {
            return existing
        }
        colors.append(color)
        return color
    }

    /// Removes a colour, unless it's the last one.
    ///
    /// - Returns: the colour now in its place — the next, or the one before
    ///   it at the end — for when the removed colour was the one in use; or
    ///   `nil` if nothing was removed.
    @discardableResult
    mutating func remove(_ color: InkColor) -> InkColor? {
        guard colors.count > 1, let index = colors.firstIndex(of: color) else { return nil }
        colors.remove(at: index)
        return colors[min(index, colors.count - 1)]
    }

    /// Moves a colour into another's place, shifting the colours between.
    mutating func move(_ color: InkColor, to target: InkColor) {
        guard color != target,
              let from = colors.firstIndex(of: color),
              let to = colors.firstIndex(of: target)
        else { return }
        colors.remove(at: from)
        colors.insert(color, at: to)
    }

    /// Moves a colour `offset` places along, stopping at either end.
    mutating func move(_ color: InkColor, by offset: Int) {
        guard let from = colors.firstIndex(of: color) else { return }
        let to = min(max(from + offset, 0), colors.count - 1)
        guard to != from else { return }
        move(color, to: colors[to])
    }
}

extension InkPalette: RawRepresentable {

    /// The colours as JSON, `[[red, green, blue, alpha]]`, for `@AppStorage`.
    ///
    /// Written by hand rather than by making the palette `Codable`: a type
    /// that is both `RawRepresentable` and `Codable` gets an encoder that goes
    /// through `rawValue`, and a `rawValue` that encodes the palette calls
    /// itself forever.
    nonisolated var rawValue: String {
        let components = colors.map { [$0.red, $0.green, $0.blue, $0.alpha] }
        guard let data = try? JSONEncoder().encode(components) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// `nil` for anything that isn't a palette, which leaves `@AppStorage`
    /// on the default.
    nonisolated init?(rawValue: String) {
        guard let components = try? JSONDecoder().decode([[Double]].self, from: Data(rawValue.utf8)),
              !components.isEmpty,
              components.allSatisfy({ $0.count == 4 })
        else { return nil }
        self.init(components.map { InkColor(red: $0[0], green: $0[1], blue: $0[2], alpha: $0[3]) })
    }
}

// MARK: - Eraser

/// How the eraser erases: which parts of a stroke, and how wide.
nonisolated struct EraserSettings: Hashable, Sendable {

    static let defaultsKey = "eraser"

    enum Mode: String, CaseIterable, Sendable {
        /// Only what it passes over, so fixing one letter of handwriting
        /// doesn't take the rest of the word with it.
        case partial
        /// Every stroke it touches, whole.
        case wholeStroke
    }

    enum Size: String, CaseIterable, Sendable {
        case small
        case medium
        case large
        case custom
    }

    var mode = Mode.partial
    var size = Size.small

    /// The width `custom` erases at, kept when another size is chosen so the
    /// reader's own size is there to go back to.
    var customWidth: Double = 40 {
        didSet { customWidth = Self.clamped(customWidth) }
    }

    static func clamped(_ width: Double) -> Double {
        min(max(width, widthRange.lowerBound), widthRange.upperBound)
    }

    /// Widths PencilKit's fixed-width eraser takes. Read from the SDK on
    /// 26 September: PencilKit's other erasers report no width at all, and
    /// PaperKit turns the plain pixel eraser into this one, clamped to it.
    static let widthRange: ClosedRange<Double> = 16.4...80.4

    /// The narrowest is the width the eraser had before sizes existed.
    static func width(of size: Size) -> Double? {
        switch size {
        case .small:  16.4
        case .medium: 32
        case .large:  56
        case .custom: nil
        }
    }

    /// How wide the eraser is now. The whole-stroke eraser has no width, so
    /// this is only what `partial` erases at.
    var width: Double {
        Self.width(of: size) ?? customWidth
    }
}

extension EraserSettings: RawRepresentable {

    /// `mode;size;customWidth`, for `@AppStorage`. Plain text, for the reason
    /// `InkPalette.rawValue` gives.
    nonisolated var rawValue: String {
        "\(mode.rawValue);\(size.rawValue);\(customWidth)"
    }

    nonisolated init?(rawValue: String) {
        let parts = rawValue.split(separator: ";").map(String.init)
        guard parts.count == 3,
              let mode = Mode(rawValue: parts[0]),
              let size = Size(rawValue: parts[1]),
              let customWidth = Double(parts[2])
        else { return nil }
        self.init()
        self.mode = mode
        self.size = size
        // An initialiser doesn't run `didSet`.
        self.customWidth = Self.clamped(customWidth)
    }
}

// MARK: - Selection

/// What the hotbar has selected in ink mode.
nonisolated struct InkToolState: Equatable, Sendable {
    var kind: InkToolKind = .pen
    var color: InkColor = .black
    var eraser = EraserSettings()
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

    /// What VoiceOver calls it: "black", "light blue".
    var name: String {
        inkColor.accessibilityName
    }
}

extension InkPalette {
    /// What a new device starts with.
    static let standard = InkPalette([.black, .blue, .red, .green, .orange])
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
            PKInkingTool(.pen, color: color.inkColor)
        case .highlighter:
            PKInkingTool(.marker, color: color.inkColor)
        case .eraser:
            eraser.pencilKitTool
        case .lasso:
            PKLassoTool()
        }
    }
}

#endif
