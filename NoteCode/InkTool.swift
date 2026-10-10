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

/// The colours the hotbar offers for one tool, in the reader's order.
///
/// A lecture is not the moment for a colour wheel, so the picker is for
/// building a palette, and the palette is what's used. Stored per device,
/// like the dock: it's how this reader likes to work, not part of any note.
/// The pen and the highlighter each have their own.
nonisolated struct InkPalette: Equatable, Sendable {

    /// The pen's palette. It kept this key when the highlighter got its own,
    /// so a palette a device saved before then is still its pen's.
    static let defaultsKey = "inkPalette"

    static let highlighterDefaultsKey = "highlighterPalette"

    /// Where a tool's palette is stored. Only the pen and highlighter have
    /// one; anything else answers with the pen's.
    static func defaultsKey(for kind: InkToolKind) -> String {
        kind == .highlighter ? highlighterDefaultsKey : defaultsKey
    }

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

// MARK: - Width

/// How thick the pen or highlighter draws: one of three, as a multiple of
/// the ink type's own default width.
///
/// A multiple rather than points, so each tool's three are spread around
/// what PencilKit considers normal for it, and a highlighter's "fine" is
/// still wider than a pen's.
nonisolated enum InkWidth: String, CaseIterable, Sendable {
    case fine
    case medium
    case bold

    /// What the tool starts on.
    static let standard = InkWidth.medium

    /// Times the ink type's `defaultWidth`.
    func multiplier(for kind: InkToolKind) -> Double {
        switch (kind, self) {
        case (.highlighter, .fine):   0.6
        case (.highlighter, .medium): 1
        case (.highlighter, .bold):   1.6
        case (_, .fine):              0.5
        case (_, .medium):            1
        case (_, .bold):              2
        }
    }

    /// The width in points: the multiple of the default, kept inside what
    /// the ink type takes.
    func points(for kind: InkToolKind, defaultWidth: Double, validRange: ClosedRange<Double>) -> Double {
        min(max(defaultWidth * multiplier(for: kind), validRange.lowerBound), validRange.upperBound)
    }

    var title: String { rawValue.capitalized }
}

// MARK: - Inking settings

/// What the pen or the highlighter is set to: its colour and its width.
///
/// Each tool keeps its own, per device like the palettes, so going from the
/// pen to the highlighter and back finds both as they were left.
nonisolated struct InkingSettings: Hashable, Sendable {
    var color: InkColor
    var width = InkWidth.standard

    /// Where a tool's settings are stored. The pen's and the highlighter's,
    /// and nothing for the other tools.
    static func defaultsKey(for kind: InkToolKind) -> String {
        kind == .highlighter ? "highlighterSettings" : "penSettings"
    }

    /// What a tool starts on, before the reader has chosen: the pen in black,
    /// and the highlighter in yellow, since graphite, first in its palette,
    /// is the least like one.
    static func standard(for kind: InkToolKind) -> InkingSettings {
        InkingSettings(color: kind == .highlighter ? InkColor.highlighterYellow : .black)
    }
}

extension InkingSettings: RawRepresentable {

    /// `red,green,blue,alpha;width`, for `@AppStorage`. Plain text, for the
    /// reason `InkPalette.rawValue` gives.
    nonisolated var rawValue: String {
        "\(color.red),\(color.green),\(color.blue),\(color.alpha);\(width.rawValue)"
    }

    nonisolated init?(rawValue: String) {
        let parts = rawValue.split(separator: ";").map(String.init)
        guard parts.count == 2,
              let width = InkWidth(rawValue: parts[1])
        else { return nil }
        let channels = parts[0].split(separator: ",").compactMap { Double($0) }
        guard channels.count == 4 else { return nil }
        self.init(
            color: InkColor(red: channels[0], green: channels[1], blue: channels[2], alpha: channels[3]),
            width: width
        )
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

    /// Whether the selected tool has anything to set. The lasso doesn't.
    var hasOptions: Bool {
        kind != .lasso
    }
}

// MARK: - The design's inks

/// The inks the design offers, in the light values PencilKit stores.
///
/// A dark page shows each with its lightness flipped, which is PencilKit's
/// own doing: only the light value is ever kept (see `displayColor(for:)`).
/// Hex from the design's tables.
nonisolated extension InkColor {

    /// From `0xRRGGBB`, in the light appearance like every stored ink. In an
    /// extension so the struct keeps its memberwise initialiser.
    init(hex: Int, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static let penShades: [(name: String, color: InkColor)] = [
        ("Ink",    InkColor(hex: 0x000000)),
        ("Red",    InkColor(hex: 0xDA101E)),
        ("Orange", InkColor(hex: 0xFA8500)),
        ("Yellow", InkColor(hex: 0xEBB000)),
        ("Green",  InkColor(hex: 0x27A551)),
        ("Blue",   InkColor(hex: 0x066EE5)),
        ("Purple", InkColor(hex: 0x8E22C3)),
    ]

    static let highlighterShades: [(name: String, color: InkColor)] = [
        ("Graphite", InkColor(hex: 0xB8B8B8)),
        ("Orange",   InkColor(hex: 0xFFB866)),
        ("Yellow",   InkColor(hex: 0xFFF066)),
        ("Green",    InkColor(hex: 0x83E286)),
        ("Pink",     InkColor(hex: 0xF877B8)),
    ]

    /// The highlighter's starting colour.
    static let highlighterYellow = InkColor(hex: 0xFFF066)

    /// What VoiceOver should call one of the design's inks: "Ink", not
    /// "black", and the highlighter's "Yellow" apart from the pen's.
    static let shadeNames: [InkColor: String] = {
        var names: [InkColor: String] = [:]
        for shade in penShades + highlighterShades where names[shade.color] == nil {
            names[shade.color] = shade.name
        }
        return names
    }()
}

nonisolated extension InkPalette {

    /// What a new device's pen starts with.
    static let standard = InkPalette(InkColor.penShades.map(\.color))

    /// What a new device's highlighter starts with.
    static let standardHighlighter = InkPalette(InkColor.highlighterShades.map(\.color))

    /// What a tool starts with. A device that has saved a palette keeps it:
    /// `@AppStorage` reads this only where nothing is stored.
    static func standard(for kind: InkToolKind) -> InkPalette {
        kind == .highlighter ? standardHighlighter : standard
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
