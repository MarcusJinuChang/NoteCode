//
//  InkColor.swift
//  NoteCode
//
//  A colour ink is drawn in, and the palette of colours a tool remembers.
//

import Foundation

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
