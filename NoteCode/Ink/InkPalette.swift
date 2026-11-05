//
//  InkPalette.swift
//  NoteCode
//
//  The inks the design offers.
//

import Foundation

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

    /// The Refined set's highlighters: what a new device starts with. Orange
    /// is today's, kept on purpose; the others are lifted so that a dark
    /// page's version reads (see docs/design/colour.md).
    static let highlighterShades: [(name: String, color: InkColor)] = [
        ("Graphite", InkColor(hex: 0x9B9BA1)),
        ("Orange",   InkColor(hex: 0xFFB866)),
        ("Yellow",   InkColor(hex: 0xFCDD79)),
        ("Green",    InkColor(hex: 0x81E4A2)),
        ("Pink",     InkColor(hex: 0xEC558D)),
    ]

    /// The Original set's highlighters, as the app shipped them. Pinned
    /// forever: a reader restores them from Settings › Drawing › Colour Set.
    static let originalHighlighterShades: [(name: String, color: InkColor)] = [
        ("Graphite", InkColor(hex: 0xB8B8B8)),
        ("Orange",   InkColor(hex: 0xFFB866)),
        ("Yellow",   InkColor(hex: 0xFFF066)),
        ("Green",    InkColor(hex: 0x83E286)),
        ("Pink",     InkColor(hex: 0xF877B8)),
    ]

    /// The highlighter's starting colour in the Refined set.
    static let highlighterYellow = InkColor(hex: 0xFCDD79)

    /// ... and in the Original set.
    static let originalHighlighterYellow = InkColor(hex: 0xFFF066)

    /// What VoiceOver should call one of the design's inks: "Ink", not
    /// "black", and the highlighter's "Yellow" apart from the pen's. Both sets'
    /// highlighters are named, so a palette saved before Refined still reads.
    static let shadeNames: [InkColor: String] = {
        var names: [InkColor: String] = [:]
        for shade in penShades + highlighterShades + originalHighlighterShades where names[shade.color] == nil {
            names[shade.color] = shade.name
        }
        return names
    }()

    /// How a swatch on a dark bar shows a highlighter, which is more vivid
    /// than the ink it draws: PencilKit shows a highlighter on a dark page at
    /// the light value's lightness flipped, a dark olive or maroon that looks
    /// dull as a button. The hotbar's face keeps the hue and lifts the
    /// saturation to at least 0.78 and the lightness to at least 0.58 (HSL);
    /// a grey stays grey, at 0.62. Hotbar only: the ink, and anywhere else
    /// that shows it, keeps the real colour. Called on what a dark page shows
    /// for the stored ink.
    var vividFace: InkColor {
        let high = max(red, green, blue), low = min(red, green, blue)
        let lightness = (high + low) / 2
        let chroma = high - low
        guard chroma > 1e-9 else { return InkColor(red: 0.62, green: 0.62, blue: 0.62, alpha: alpha) }
        let saturation = chroma / (1 - abs(2 * lightness - 1))
        guard saturation >= 0.1 else {
            return InkColor(red: 0.62, green: 0.62, blue: 0.62, alpha: alpha)
        }

        var hue: Double
        switch high {
        case red:   hue = ((green - blue) / chroma).truncatingRemainder(dividingBy: 6)
        case green: hue = (blue - red) / chroma + 2
        default:    hue = (red - green) / chroma + 4
        }
        if hue < 0 { hue += 6 }

        let newSaturation = max(saturation, 0.78)
        let newLightness = max(lightness, 0.58)
        let newChroma = (1 - abs(2 * newLightness - 1)) * newSaturation
        let x = newChroma * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double)
        switch Int(hue) {
        case 0:  (r, g, b) = (newChroma, x, 0)
        case 1:  (r, g, b) = (x, newChroma, 0)
        case 2:  (r, g, b) = (0, newChroma, x)
        case 3:  (r, g, b) = (0, x, newChroma)
        case 4:  (r, g, b) = (x, 0, newChroma)
        default: (r, g, b) = (newChroma, 0, x)
        }
        let m = newLightness - newChroma / 2
        return InkColor(red: r + m, green: g + m, blue: b + m, alpha: alpha)
    }
}

nonisolated extension InkPalette {

    /// What a new device's pen starts with.
    static let standard = SettingKeys.Drawing.penPalette.defaultValue

    /// What a new device's highlighter starts with.
    static let standardHighlighter = SettingKeys.Drawing.highlighterPalette.defaultValue

    /// What a tool starts with. A device that has saved a palette keeps it:
    /// `@AppStorage` reads this only where nothing is stored.
    static func standard(for kind: InkToolKind) -> InkPalette {
        SettingKeys.Drawing.palette(for: kind).defaultValue
    }
}
