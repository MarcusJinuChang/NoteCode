//
//  InkPaletteSet.swift
//  NoteCode
//
//  Which highlighters a device starts from, and restores to.
//

import Foundation

/// Which highlighters a device starts from, and restores to.
///
/// The pens are the same in both sets, so the set is the highlighters. Where
/// they have to move together (the key, both palettes, the highlighter's
/// remembered colour) they move here, in one `apply(to:)`, so Settings'
/// picker and its two resets can't disagree. Stored per device.
nonisolated enum InkPaletteSet: String, CaseIterable, Sendable {
    case refined
    case original

    static let defaultsKey = SettingKeys.Drawing.paletteSet.name

    var title: String {
        switch self {
        case .refined:  "Refined"
        case .original: "Original"
        }
    }

    var highlighterShades: [(name: String, color: InkColor)] {
        self == .refined ? InkColor.highlighterShades : InkColor.originalHighlighterShades
    }

    /// The colour the highlighter starts on: yellow, since graphite, first in
    /// its palette, is the least like one.
    var highlighterStart: InkColor {
        self == .refined ? InkColor.highlighterYellow : InkColor.originalHighlighterYellow
    }

    func palette(for kind: InkToolKind) -> InkPalette {
        kind == .highlighter
            ? InkPalette(highlighterShades.map(\.color))
            : InkPalette(InkColor.penShades.map(\.color))
    }

    /// The set a device is on: the one it chose; failing that, Original for a
    /// device that has saved a palette of its own before sets existed (its
    /// highlighters are the old ones), and Refined for one that saved none.
    static func stored(in defaults: UserDefaults = .standard) -> InkPaletteSet {
        if let raw = defaults.string(forKey: defaultsKey), let chosen = InkPaletteSet(rawValue: raw) {
            return chosen
        }
        let savedAPalette = [InkPalette.defaultsKey, InkPalette.highlighterDefaultsKey]
            .contains { defaults.object(forKey: $0) != nil }
        return savedAPalette ? .original : .refined
    }

    /// The set the two palettes are exactly, or `nil` ("Custom") once the
    /// reader has added, removed or reordered a colour.
    static func matching(pen: InkPalette, highlighter: InkPalette) -> InkPaletteSet? {
        allCases.first { pen == $0.palette(for: .pen) && highlighter == $0.palette(for: .highlighter) }
    }

    /// Makes this the device's set: writes the choice, both palettes and the
    /// highlighter's remembered colour (keeping its width), in the defaults
    /// the hotbar reads them from. Ink already on a page keeps its colour.
    func apply(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
        resetPalette(for: .pen, in: defaults)
        resetPalette(for: .highlighter, in: defaults)

        let key = InkingSettings.defaultsKey(for: .highlighter)
        var settings = defaults.string(forKey: key).flatMap(InkingSettings.init(rawValue:))
            ?? InkingSettings.standard(for: .highlighter)
        settings.color = highlighterStart
        defaults.set(settings.rawValue, forKey: key)
    }

    /// Puts one palette back to this set's colours and nothing else.
    func resetPalette(for kind: InkToolKind, in defaults: UserDefaults = .standard) {
        defaults.set(palette(for: kind).rawValue, forKey: InkPalette.defaultsKey(for: kind))
    }
}
