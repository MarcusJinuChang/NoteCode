//
//  InkingSettings.swift
//  NoteCode
//
//  How wide the pen and highlighter draw, and the shape the Select tool uses.
//

import Foundation

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
        SettingKeys.Drawing.inking(for: kind).name
    }

    /// What a tool starts on, before the reader has chosen: the pen in black,
    /// and the highlighter in yellow, since graphite, first in its palette,
    /// is the least like one.
    static func standard(for kind: InkToolKind) -> InkingSettings {
        SettingKeys.Drawing.inking(for: kind).defaultValue
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

/// How the reader draws the Select tool's shape.
nonisolated enum SelectionKind: String, CaseIterable, Sendable {
    case lasso
    case rectangle


    var title: String {
        switch self {
        case .lasso:     "Lasso"
        case .rectangle: "Rectangle"
        }
    }

    var systemImage: String {
        switch self {
        case .lasso:     "lasso"
        case .rectangle: "rectangle.dashed"
        }
    }
}
