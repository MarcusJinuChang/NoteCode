//
//  FolderAppearance.swift
//  NoteCode
//
//  A folder's face: the colour and the symbol it is shown with in the list and
//  on Home. Pure data and rules, so the contrast the design promises is tested.
//

import SwiftUI

/// The eight colours a folder can have (the design's table, `Library` board).
///
/// A folder stores only the name (`Folder.colorName`). Each colour is a tint
/// that sits behind the folder's symbol and a symbol colour on top of it, both
/// chosen per appearance: a light pastel behind a dark symbol in light, and a
/// deep tint behind a bright symbol in dark. `FolderAppearanceTests` computes
/// the contrast of every pair and needs 3:1, the minimum for a graphic.
nonisolated enum FolderColor: String, CaseIterable, Identifiable, Sendable {
    case orange, red, yellow, green, blue, teal, purple, graphite

    var id: String { rawValue }

    /// What a folder with no colour chosen has.
    static let `default` = FolderColor.orange

    var title: String {
        switch self {
        case .orange:   "Orange"
        case .red:      "Red"
        case .yellow:   "Yellow"
        case .green:    "Green"
        case .blue:     "Blue"
        case .teal:     "Teal"
        case .purple:   "Purple"
        case .graphite: "Graphite"
        }
    }

    /// The colour as a swatch, the same in both appearances. Matches the ink
    /// palette's pen shades where there is one.
    var base: Int {
        switch self {
        case .orange:   0xFA8500
        case .red:      0xDA101E
        case .yellow:   0xEBB000
        case .green:    0x27A551
        case .blue:     0x066EE5
        case .teal:     0x00727A
        case .purple:   0x8E22C3
        case .graphite: 0x6C6C70
        }
    }

    /// The tint behind the symbol.
    func tint(isDark: Bool) -> Int {
        switch (self, isDark) {
        case (.orange, false):   0xFFE9CF
        case (.orange, true):    0x3D2400
        case (.red, false):      0xFBE0E2
        case (.red, true):       0x3D0A0E
        case (.yellow, false):   0xFBF1CC
        case (.yellow, true):    0x3A2E00
        case (.green, false):    0xDDF2E4
        case (.green, true):     0x0E3019
        case (.blue, false):     0xDCEBFC
        case (.blue, true):      0x0A2340
        case (.teal, false):     0xD6EDEE
        case (.teal, true):      0x00282B
        case (.purple, false):   0xF1E4F9
        case (.purple, true):    0x2C0E3D
        case (.graphite, false): 0xE9E9EB
        case (.graphite, true):  0x2C2C2E
        }
    }

    /// The symbol drawn on the tint.
    func symbol(isDark: Bool) -> Int {
        switch (self, isDark) {
        case (.orange, false):   0xB85900
        case (.orange, true):    0xFFAA33
        case (.red, false):      0xB00D18
        case (.red, true):       0xFF6B74
        case (.yellow, false):   0x8A6700
        case (.yellow, true):    0xFFD54D
        case (.green, false):    0x1C7A3B
        case (.green, true):     0x5AD884
        case (.blue, false):     0x0A5BBF
        case (.blue, true):      0x6CB6FF
        case (.teal, false):     0x00727A
        case (.teal, true):      0x5ED0D6
        case (.purple, false):   0x7A1CA8
        case (.purple, true):    0xC39BFF
        case (.graphite, false): 0x55555B
        case (.graphite, true):  0xAEAEB2
        }
    }
}

/// The symbols a folder can have, in the folder editor's order: four rows of
/// four. The canvas draws stand-ins for some of these; these are the SF
/// Symbols they stand for.
nonisolated enum FolderSymbol {
    static let all = [
        "chevron.left.forwardslash.chevron.right", "terminal", "cpu", "sum",
        "point.3.connected.trianglepath.dotted", "cylinder", "book.closed", "flask",
        "globe", "graduationcap", "lightbulb", "number",
        "chart.xyaxis.line", "function", "curlybraces", "folder",
    ]

    /// What a folder with no symbol chosen has.
    static let `default` = "folder"

    /// What VoiceOver says for a symbol in the editor's grid; a symbol's own
    /// name ("point.3.connected.trianglepath.dotted") is no help.
    static func title(of symbol: String) -> String {
        switch symbol {
        case "chevron.left.forwardslash.chevron.right":  "Code"
        case "terminal":                                  "Terminal"
        case "cpu":                                       "Processor"
        case "sum":                                       "Sum"
        case "point.3.connected.trianglepath.dotted":     "Graph"
        case "cylinder":                                  "Database"
        case "book.closed":                               "Book"
        case "flask":                                     "Flask"
        case "globe":                                     "Globe"
        case "graduationcap":                             "Graduation Cap"
        case "lightbulb":                                 "Idea"
        case "number":                                    "Number"
        case "chart.xyaxis.line":                         "Chart"
        case "function":                                  "Function"
        case "curlybraces":                               "Braces"
        default:                                          "Folder"
        }
    }
}

extension Folder {
    /// The folder's colour: orange when none was chosen, or when the stored
    /// name is one this build doesn't know (a later version's).
    var color: FolderColor {
        colorName.flatMap(FolderColor.init(rawValue:)) ?? .default
    }

    /// The folder's symbol, `folder` when none was chosen or the stored one
    /// isn't in the editor's set, so a symbol never draws as nothing.
    var symbol: String {
        symbolName.flatMap { FolderSymbol.all.contains($0) ? $0 : nil } ?? FolderSymbol.default
    }
}

// MARK: - Drawing

extension Color {
    /// A colour from a 24-bit sRGB hex value.
    init(hex: Int) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// A folder's symbol on its tint: the 26pt circle in the list's rows, the
/// larger one in the folder editor's preview and, in phase 2, on Home's tiles.
struct FolderBadge: View {
    let color: FolderColor
    let symbol: String
    var diameter: CGFloat = 26

    @Environment(\.colorScheme) private var colorScheme

    init(folder: Folder, diameter: CGFloat = 26) {
        self.init(color: folder.color, symbol: folder.symbol, diameter: diameter)
    }

    init(color: FolderColor, symbol: String, diameter: CGFloat = 26) {
        self.color = color
        self.symbol = symbol
        self.diameter = diameter
    }

    var body: some View {
        let isDark = colorScheme == .dark
        Circle()
            .fill(Color(hex: color.tint(isDark: isDark)))
            .frame(width: diameter, height: diameter)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: diameter * 0.5, weight: .semibold))
                    .foregroundStyle(Color(hex: color.symbol(isDark: isDark)))
            }
            // The row says the folder's name; the badge is decoration.
            .accessibilityHidden(true)
    }
}
