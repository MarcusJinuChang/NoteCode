//
//  InkPaletteTests.swift
//  NoteCodeTests
//

import Foundation
import Testing
@testable import NoteCode

@Suite("Ink palette")
struct InkPaletteTests {

    private let yellow = InkColor(red: 1, green: 0.8, blue: 0)
    private let purple = InkColor(red: 0.5, green: 0, blue: 0.5)
    private let teal = InkColor(red: 0, green: 0.5, blue: 0.5)

    @Test("A new colour goes on the end and is the one returned")
    func addsAtTheEnd() {
        var palette = InkPalette([.black, yellow])

        let added = palette.add(purple)

        #expect(added == purple)
        #expect(palette.colors == [.black, yellow, purple])
    }

    @Test("A colour already there, to 8 bits a channel, isn't added twice")
    func noNearDuplicates() {
        var palette = InkPalette([.black, yellow])
        let almostBlack = InkColor(red: 0.000_001, green: 0, blue: 0.000_002)

        let added = palette.add(almostBlack)

        #expect(added == .black)
        #expect(palette.colors == [.black, yellow])
    }

    @Test("Removing a colour hands back the one that took its place")
    func removeHandsBackItsNeighbour() {
        var palette = InkPalette([.black, yellow, purple])

        #expect(palette.remove(yellow) == purple)
        #expect(palette.colors == [.black, purple])
        // At the end, the one before it.
        #expect(palette.remove(purple) == .black)
        #expect(palette.colors == [.black])
    }

    @Test("The last colour can't be removed")
    func keepsOneColour() {
        var palette = InkPalette([yellow])

        #expect(palette.remove(yellow) == nil)
        #expect(palette.colors == [yellow])
        #expect(InkPalette([]).colors == [.black])
    }

    @Test("A dragged colour takes the place of the one it's dropped on, either way")
    func moveIntoPlace() {
        var palette = InkPalette([.black, yellow, purple, teal])

        palette.move(.black, to: purple)
        #expect(palette.colors == [yellow, purple, .black, teal])

        palette.move(teal, to: yellow)
        #expect(palette.colors == [teal, yellow, purple, .black])
    }

    @Test("Moving by a step stops at the ends")
    func moveByStep() {
        var palette = InkPalette([.black, yellow, purple])

        palette.move(yellow, by: 1)
        #expect(palette.colors == [.black, purple, yellow])
        palette.move(yellow, by: 1)
        #expect(palette.colors == [.black, purple, yellow])
        palette.move(.black, by: -1)
        #expect(palette.colors == [.black, purple, yellow])
    }

    @Test("Repeats are dropped when a palette is made")
    func noRepeats() {
        #expect(InkPalette([.black, yellow, .black]).colors == [.black, yellow])
    }

    @Test("A palette survives storage exactly, and anything else reads as no palette")
    func storage() {
        let palette = InkPalette([.black, InkColor(red: 1.0746, green: -0.0226, blue: 0.1, alpha: 1), teal])

        #expect(InkPalette(rawValue: palette.rawValue) == palette)
        #expect(InkPalette(rawValue: "") == nil)
        #expect(InkPalette(rawValue: "[]") == nil)
        #expect(InkPalette(rawValue: "[[1, 0]]") == nil)
    }
}

@Suite("Eraser settings")
struct EraserSettingsTests {

    @Test("Settings survive storage, and a bad value reads as none")
    func storage() {
        var settings = EraserSettings()
        settings.mode = .wholeStroke
        settings.size = .custom
        settings.customWidth = 44.5

        #expect(EraserSettings(rawValue: settings.rawValue) == settings)
        #expect(EraserSettings(rawValue: "partial;huge;20") == nil)
        #expect(EraserSettings(rawValue: "") == nil)
    }

    @Test("A custom width stays inside what PencilKit takes, however it's set")
    func customWidthClamped() {
        var settings = EraserSettings()
        settings.customWidth = 500
        #expect(settings.customWidth == EraserSettings.widthRange.upperBound)
        settings.customWidth = 1
        #expect(settings.customWidth == EraserSettings.widthRange.lowerBound)

        #expect(EraserSettings(rawValue: "partial;custom;500")?.customWidth == EraserSettings.widthRange.upperBound)
    }

    @Test("The size in use sets the width; the custom width waits its turn")
    func widthFollowsSize() {
        var settings = EraserSettings()
        settings.customWidth = 70
        settings.size = .medium
        #expect(settings.width == EraserSettings.width(of: .medium))
        settings.size = .custom
        #expect(settings.width == 70)
    }
}

// MARK: - Two palettes

@Suite("Pen and highlighter palettes")
struct InkPalettesTests {

    private func hexes(_ palette: InkPalette) -> [Int] {
        palette.colors.map { color in
            Int((color.red * 255).rounded()) << 16 | Int((color.green * 255).rounded()) << 8 | Int((color.blue * 255).rounded())
        }
    }

    @Test("A new device's pen has the design's seven inks, in order")
    func penDefaults() {
        #expect(hexes(.standard) == [0x000000, 0xDA101E, 0xFA8500, 0xEBB000, 0x27A551, 0x066EE5, 0x8E22C3])
        #expect(InkColor.penShades.map(\.name) == ["Ink", "Red", "Orange", "Yellow", "Green", "Blue", "Purple"])
    }

    @Test("A new device's highlighter has its own five, in order: the Refined set, with Original's orange")
    func highlighterDefaults() {
        #expect(hexes(.standardHighlighter) == [0x9B9BA1, 0xFFB866, 0xFCDD79, 0x81E4A2, 0xEC558D])
        #expect(InkColor.highlighterShades.map(\.name) == ["Graphite", "Orange", "Yellow", "Green", "Pink"])
    }

    @Test("The Original highlighters are today's, pinned for good")
    func originalHighlighters() {
        let original = InkPalette(InkColor.originalHighlighterShades.map(\.color))
        #expect(hexes(original) == [0xB8B8B8, 0xFFB866, 0xFFF066, 0x83E286, 0xF877B8])
        #expect(InkColor.originalHighlighterShades.map(\.name) == ["Graphite", "Orange", "Yellow", "Green", "Pink"])
        #expect(InkPaletteSet.original.palette(for: .highlighter) == original)
        #expect(InkPaletteSet.refined.palette(for: .highlighter) == .standardHighlighter)
        // The pens are one table for both sets.
        #expect(InkPaletteSet.original.palette(for: .pen) == InkPaletteSet.refined.palette(for: .pen))
    }

    @Test("Each tool has a palette and a key of its own")
    func twoPalettes() {
        #expect(InkPalette.standard(for: .pen) == .standard)
        #expect(InkPalette.standard(for: .highlighter) == .standardHighlighter)
        #expect(InkPalette.standard != .standardHighlighter)
        #expect(InkPalette.defaultsKey(for: .pen) != InkPalette.defaultsKey(for: .highlighter))
    }

    @Test("The pen keeps the key it always had, or a device's saved palette is forgotten")
    func penKeepsItsKey() {
        #expect(InkPalette.defaultsKey == "inkPalette")
        #expect(InkPalette.defaultsKey(for: .pen) == "inkPalette")
        #expect(InkPalette.highlighterDefaultsKey == "highlighterPalette")
    }

    @Test("A palette saved before the redesign still reads, and isn't replaced by the new defaults")
    func savedPaletteSurvives() throws {
        // What the old build wrote under "inkPalette": black and four of the
        // system's colours, as a reader who'd moved them around might have.
        let saved = "[[0,0,0,1],[1,0.23,0.19,1],[0,0.478,1,1],[1,0.8,0,1]]"

        let palette = try #require(InkPalette(rawValue: saved))

        #expect(palette.colors.count == 4)
        #expect(palette != .standard)
        #expect(palette.colors[1] == InkColor(red: 1, green: 0.23, blue: 0.19))
    }

    @Test("The design's inks go by the design's names, and others by the system's")
    func names() {
        #expect(InkColor(hex: 0x000000).name == "Ink")
        // Orange is both a pen and a highlighter colour, and two different ones.
        #expect(InkColor(hex: 0xFA8500).name == "Orange")
        #expect(InkColor(hex: 0xFFB866).name == "Orange")
        // Both sets' highlighters have the design's names, so a palette saved
        // under Original still reads aloud as it did.
        #expect(InkColor(hex: 0xFFF066).name == "Yellow")
        #expect(InkColor(hex: 0xFCDD79).name == "Yellow")
        #expect(InkColor(hex: 0xF877B8).name == "Pink")
        #expect(InkColor(hex: 0xEC558D).name == "Pink")
        #expect(InkColor(hex: 0x123456).name != "")
    }
}

@Suite("Ink widths and tool settings")
struct InkSettingsTests {

    @Test("Three widths each, as the design's multiples")
    func multiples() {
        #expect(InkWidth.allCases.map { $0.multiplier(for: .pen) } == [0.5, 1, 2])
        #expect(InkWidth.allCases.map { $0.multiplier(for: .highlighter) } == [0.6, 1, 1.6])
        #expect(InkWidth.standard == .medium)
    }

    @Test("A width is its multiple of the default, kept inside what the ink takes")
    func points() {
        let range = 1.0...10.0
        #expect(InkWidth.medium.points(for: .pen, defaultWidth: 4, validRange: range) == 4)
        #expect(InkWidth.fine.points(for: .pen, defaultWidth: 4, validRange: range) == 2)
        #expect(InkWidth.bold.points(for: .pen, defaultWidth: 4, validRange: range) == 8)
        // Past either end of the range it stops at the end.
        #expect(InkWidth.bold.points(for: .pen, defaultWidth: 8, validRange: range) == 10)
        #expect(InkWidth.fine.points(for: .pen, defaultWidth: 1, validRange: range) == 1)
    }

    @Test("A tool's colour and width survive storage exactly, and anything else reads as none")
    func storage() {
        for width in InkWidth.allCases {
            // A Display P3 colour, outside 0 to 1, as the picker can hand back.
            let settings = InkingSettings(
                color: InkColor(red: 1.0746, green: -0.0226, blue: 0.123_456_789, alpha: 0.5),
                width: width
            )
            #expect(InkingSettings(rawValue: settings.rawValue) == settings)
        }

        #expect(InkingSettings(rawValue: "") == nil)
        #expect(InkingSettings(rawValue: "0,0,0,1;huge") == nil)
        #expect(InkingSettings(rawValue: "0,0,1;fine") == nil)
        #expect(InkingSettings(rawValue: "a,b,c,d;fine") == nil)
    }

    @Test("Each tool starts on a colour its own palette holds, so a swatch always shows it")
    func startsInItsPalette() {
        for kind in [InkToolKind.pen, .highlighter] {
            let start = InkingSettings.standard(for: kind)
            #expect(InkPalette.standard(for: kind).colors.contains(start.color))
            #expect(start.width == .medium)
        }
        #expect(InkingSettings.standard(for: .pen).color == .black)
        #expect(InkingSettings.standard(for: .highlighter).color == InkColor.highlighterYellow)
        #expect(InkColor.highlighterYellow == InkColor(hex: 0xFCDD79))
        for set in InkPaletteSet.allCases {
            #expect(set.palette(for: .highlighter).colors.contains(set.highlighterStart))
        }
    }

    @Test("The pen and the highlighter each remember their own colour and width")
    func separateSettings() {
        var state = InkToolState()
        state[inking: .pen].color = InkColor(hex: 0x066EE5)
        state[inking: .pen].width = .bold

        #expect(state.pen.color == InkColor(hex: 0x066EE5))
        #expect(state.highlighter == .standard(for: .highlighter))

        state[inking: .highlighter].width = .fine
        #expect(state.highlighter.width == .fine)
        #expect(state.pen.width == .bold)
    }

    @Test("Every tool has an options row: the Select tool's is its shape and, with a selection, its commands")
    func optionsRow() {
        for kind in InkToolKind.allCases {
            #expect(InkToolState(kind: kind).hasOptions, "\(kind)")
        }
    }
}

@Suite("Colour sets")
struct InkPaletteSetTests {

    private func defaults(_ name: String) throws -> UserDefaults {
        let suite = "InkPaletteSetTests.\(name)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("Applying a set writes the choice, both palettes and the highlighter's colour, and keeps its width")
    func apply() throws {
        let defaults = try defaults("apply")
        defer { defaults.removePersistentDomain(forName: "InkPaletteSetTests.apply") }
        let key = InkingSettings.defaultsKey(for: .highlighter)
        defaults.set(InkingSettings(color: .red, width: .bold).rawValue, forKey: key)
        defaults.set(InkPalette([.red]).rawValue, forKey: InkPalette.defaultsKey(for: .pen))

        InkPaletteSet.original.apply(to: defaults)

        let marker = defaults.string(forKey: InkPalette.highlighterDefaultsKey).flatMap(InkPalette.init(rawValue:))
        let pen = defaults.string(forKey: InkPalette.defaultsKey).flatMap(InkPalette.init(rawValue:))
        let remembered = try #require(defaults.string(forKey: key).flatMap(InkingSettings.init(rawValue:)))
        #expect(defaults.string(forKey: InkPaletteSet.defaultsKey) == "original")
        #expect(marker == InkPaletteSet.original.palette(for: .highlighter))
        #expect(pen == InkPaletteSet.original.palette(for: .pen))
        #expect(remembered.color == InkColor.originalHighlighterYellow)
        #expect(remembered.width == .bold)

        InkPaletteSet.refined.apply(to: defaults)
        let back = try #require(defaults.string(forKey: key).flatMap(InkingSettings.init(rawValue:)))
        #expect(back.color == InkColor.highlighterYellow)
    }

    @Test("A device that never saved a palette is Refined; one that did, before sets, is Original; a choice wins")
    func storedSet() throws {
        let defaults = try defaults("stored")
        defer { defaults.removePersistentDomain(forName: "InkPaletteSetTests.stored") }

        #expect(InkPaletteSet.stored(in: defaults) == .refined)

        defaults.set(InkPalette([.red]).rawValue, forKey: InkPalette.highlighterDefaultsKey)
        #expect(InkPaletteSet.stored(in: defaults) == .original)

        defaults.set("refined", forKey: InkPaletteSet.defaultsKey)
        #expect(InkPaletteSet.stored(in: defaults) == .refined)

        defaults.set("neon", forKey: InkPaletteSet.defaultsKey)
        #expect(InkPaletteSet.stored(in: defaults) == .original)
    }

    @Test("The two palettes are a set exactly, and Custom once a colour is added or moved")
    func matching() {
        for set in InkPaletteSet.allCases {
            #expect(InkPaletteSet.matching(pen: set.palette(for: .pen), highlighter: set.palette(for: .highlighter)) == set)
        }
        var added = InkPaletteSet.refined.palette(for: .highlighter)
        added.add(InkColor(hex: 0x123456))
        #expect(InkPaletteSet.matching(pen: .standard, highlighter: added) == nil)
        // Pens alone don't tell the sets apart.
        #expect(InkPaletteSet.matching(pen: .standard, highlighter: .standardHighlighter) == .refined)
    }

    @Test("Restoring one palette leaves the other alone")
    func restoreOne() throws {
        let defaults = try defaults("restoreOne")
        defer { defaults.removePersistentDomain(forName: "InkPaletteSetTests.restoreOne") }
        let custom = InkPalette([.red, .blue])
        defaults.set(custom.rawValue, forKey: InkPalette.defaultsKey(for: .pen))
        defaults.set(custom.rawValue, forKey: InkPalette.defaultsKey(for: .highlighter))

        InkPaletteSet.refined.resetPalette(for: .highlighter, in: defaults)

        let pen = defaults.string(forKey: InkPalette.defaultsKey(for: .pen)).flatMap(InkPalette.init(rawValue:))
        let marker = defaults.string(forKey: InkPalette.defaultsKey(for: .highlighter)).flatMap(InkPalette.init(rawValue:))
        #expect(pen == custom)
        #expect(marker == .standardHighlighter)
    }

    // MARK: The hotbar's vivid face

    private func hsl(_ c: InkColor) -> (h: Double, s: Double, l: Double) {
        let high = max(c.red, c.green, c.blue), low = min(c.red, c.green, c.blue)
        let l = (high + low) / 2, d = high - low
        guard d > 1e-9 else { return (0, 0, l) }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double
        switch high {
        case c.red:   h = ((c.green - c.blue) / d).truncatingRemainder(dividingBy: 6)
        case c.green: h = (c.blue - c.red) / d + 2
        default:      h = (c.red - c.green) / d + 4
        }
        if h < 0 { h += 6 }
        return (h * 60, s, l)
    }

    @Test("A vivid face keeps the hue and is at least 0.78 saturated and 0.58 light", arguments: [
        0x5E5E64, 0x995200, 0x866703, 0x1B7E3C, 0xAA134B, 0x474747, 0x998A00, 0x880748,
    ])
    func vividFace(dark: Int) {
        let before = hsl(InkColor(hex: dark)), after = hsl(InkColor(hex: dark).vividFace)
        if before.s < 0.1 {
            #expect(after.s < 0.01, "a grey stays grey")
            #expect(abs(after.l - 0.62) < 0.005)
        } else {
            #expect(abs(after.h - before.h) < 0.6)
            #expect(after.s >= 0.78 - 0.005)
            #expect(after.l >= 0.58 - 0.005)
        }
    }

    @Test("A face already vivid isn't dulled")
    func vividStays() {
        let bright = InkColor(hex: 0xFF3B30)
        let face = hsl(bright.vividFace), was = hsl(bright)
        #expect(face.s >= was.s - 0.005)
        #expect(face.l >= was.l - 0.005)
    }

    @Test("Known faces, as the swatch sheet shows them")
    func knownFaces() {
        let expected: [(dark: Int, face: Int)] = [
            (0x995200, 0xFF9C29), (0x866703, 0xFACA2D), (0x1B7E3C, 0x40E778), (0xAA134B, 0xE93E7E), (0x5E5E64, 0x9E9EA1),
        ]
        for (dark, face) in expected {
            let made = InkColor(hex: dark).vividFace
            let want = InkColor(hex: face)
            #expect(abs(made.red - want.red) < 3.0 / 255, "\(String(dark, radix: 16))")
            #expect(abs(made.green - want.green) < 3.0 / 255, "\(String(dark, radix: 16))")
            #expect(abs(made.blue - want.blue) < 3.0 / 255, "\(String(dark, radix: 16))")
        }
    }
}

#if canImport(UIKit)

import PencilKit
import UIKit

@Suite("Ink shades and widths in PencilKit")
@MainActor
struct InkShadeTests {

    struct Shade: CustomTestStringConvertible {
        var name: String
        var light: Int
        var dark: Int
        var testDescription: String { name }
    }

    /// The design's dark column: what PencilKit shows for each stored ink on
    /// a dark page, measured on macOS 27.
    static let pens = [
        Shade(name: "Ink",    light: 0x000000, dark: 0xFFFFFF),
        Shade(name: "Red",    light: 0xDA101E, dark: 0xEF2533),
        Shade(name: "Orange", light: 0xFA8500, dark: 0xFF8A05),
        Shade(name: "Yellow", light: 0xEBB000, dark: 0xFFC414),
        Shade(name: "Green",  light: 0x27A551, dark: 0x5AD884),
        Shade(name: "Blue",   light: 0x066EE5, dark: 0x1A82F9),
        Shade(name: "Purple", light: 0x8E22C3, dark: 0xA83CDD),
    ]

    /// The Original set's highlighters, as shipped.
    static let originalHighlighters = [
        Shade(name: "Graphite", light: 0xB8B8B8, dark: 0x474747),
        Shade(name: "Orange",   light: 0xFFB866, dark: 0x995200),
        Shade(name: "Yellow",   light: 0xFFF066, dark: 0x998A00),
        Shade(name: "Green",    light: 0x83E286, dark: 0x1D7C20),
        Shade(name: "Pink",     light: 0xF877B8, dark: 0x880748),
    ]

    /// The Refined set's: the dark column is the stored light value with its
    /// HSL lightness flipped, which is what PencilKit does (computed, and
    /// checked here against PencilKit itself).
    static let highlighters = [
        Shade(name: "Graphite", light: 0x9B9BA1, dark: 0x5E5E64),
        Shade(name: "Orange",   light: 0xFFB866, dark: 0x995200),
        Shade(name: "Yellow",   light: 0xFCDD79, dark: 0x866703),
        Shade(name: "Green",    light: 0x81E4A2, dark: 0x1B7E3C),
        Shade(name: "Pink",     light: 0xEC558D, dark: 0xAA134B),
    ]

    private func expectDark(_ shade: Shade) {
        let stored = InkColor(hex: shade.light)
        let shown = InkColor(stored.displayColor(for: .dark))
        let expected = InkColor(hex: shade.dark)
        let tolerance = 1.0 / 255 + 1e-6

        #expect(abs(shown.red - expected.red) <= tolerance, "\(shade.name) red")
        #expect(abs(shown.green - expected.green) <= tolerance, "\(shade.name) green")
        #expect(abs(shown.blue - expected.blue) <= tolerance, "\(shade.name) blue")
    }

    @Test("A dark page shows each pen ink as the design's dark shade", arguments: pens)
    func darkPens(shade: Shade) {
        expectDark(shade)
    }

    @Test("A dark page shows each Refined highlighter ink as the design's dark shade", arguments: highlighters)
    func darkHighlighters(shade: Shade) {
        expectDark(shade)
    }

    @Test("A dark page shows each Original highlighter ink as it always did", arguments: originalHighlighters)
    func darkOriginalHighlighters(shade: Shade) {
        expectDark(shade)
    }

    @Test("The shade tables match the palettes", arguments: [InkToolKind.pen, .highlighter])
    func tablesMatchPalettes(kind: InkToolKind) {
        let table = kind == .pen ? Self.pens : Self.highlighters
        let palette = InkPalette.standard(for: kind)

        #expect(palette.colors == table.map { InkColor(hex: $0.light) })
    }

    @Test("The Original table matches the Original set")
    func originalTableMatches() {
        #expect(InkPaletteSet.original.palette(for: .highlighter).colors
            == Self.originalHighlighters.map { InkColor(hex: $0.light) })
    }

    @Test("Fine, medium and bold run thin to thick for each ink, medium at its default", arguments: [InkToolKind.pen, .highlighter])
    func widthsRunThinToThick(kind: InkToolKind) {
        let type: PKInkingTool.InkType = kind == .highlighter ? .marker : .pen
        let widths = InkWidth.allCases.map { $0.points(for: kind, ink: type) }

        #expect(widths == widths.sorted())
        #expect(Set(widths).count == 3)
        #expect(abs(widths[1] - type.defaultWidth) < 0.001)
        #expect(widths.allSatisfy { type.validWidthRange.contains($0) })
    }

    @Test("The tool PencilKit gets carries the selected colour and width, tool by tool")
    func toolCarriesSettings() throws {
        var state = InkToolState()
        state[inking: .pen] = InkingSettings(color: InkColor(hex: 0x066EE5), width: .bold)
        state[inking: .highlighter] = InkingSettings(color: InkColor(hex: 0x83E286), width: .fine)

        state.kind = .pen
        let pen = try #require(state.pencilKitTool as? PKInkingTool)
        #expect(pen.inkType == .pen)
        #expect(InkColor(pen.color).matches(InkColor(hex: 0x066EE5)))
        #expect(abs(pen.width - InkWidth.bold.points(for: .pen, ink: .pen)) < 0.001)

        state.kind = .highlighter
        let marker = try #require(state.pencilKitTool as? PKInkingTool)
        #expect(marker.inkType == .marker)
        #expect(InkColor(marker.color).matches(InkColor(hex: 0x83E286)))
        #expect(abs(marker.width - InkWidth.fine.points(for: .highlighter, ink: .marker)) < 0.001)
    }
}

@Suite("The hotbar's swatch faces")
struct SwatchFaceTests {

    @Test("A dark bar shows a highlighter vividly and everything else as the page shows it")
    func faces() {
        let yellow = InkColor(hex: 0xFCDD79)
        let shown = InkColor(yellow.displayColor(for: .dark))
        let face = InkColor(yellow.swatchFace(for: .dark, kind: .highlighter))

        #expect(face.matches(shown.vividFace))
        #expect(!face.matches(shown))

        // A pen, or a light bar, is the ink itself.
        #expect(InkColor(yellow.swatchFace(for: .dark, kind: .pen)).matches(shown))
        #expect(InkColor(yellow.swatchFace(for: .light, kind: .highlighter)).matches(yellow))
        let red = InkColor(hex: 0xDA101E)
        #expect(InkColor(red.swatchFace(for: .dark, kind: .pen)).matches(InkColor(red.displayColor(for: .dark))))
    }
}

#endif
