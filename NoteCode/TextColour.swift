//
//  TextColour.swift
//  NoteCode
//
//  Coloured text (roadmap step 10): the palette, and the Markdown it is
//  written in, `<span style="color:#RRGGBB">text</span>`.
//

import Foundation

/// A colour text can be set in, and how it is written in a note.
///
/// **The format is Obsidian's own** (decided 16 Oct from step 3's research,
/// docs/research-notability-obsidian.md): an HTML span with an inline colour,
/// the one convention Obsidian draws without a plugin that GitHub reads as
/// plain text. Exactly this shape, `<span style="color:#RRGGBB">`, hex in
/// either case, is a colour; any other `<span …>` (a class, a named colour,
/// another property) stays visible text, so pasted HTML is never half hidden.
/// A run is on one line and colours don't nest.
///
/// The hex is stored as chosen. What is drawn is that colour taken just far
/// enough toward black on a light page, or white on a dark one, for 4.5:1
/// (`AccentPalette.textHex`, as links are), so the same note reads in both
/// appearances and a colour from elsewhere is as legible as the palette's.
nonisolated enum TextColour: Int, CaseIterable, Sendable {
    case red = 0xE5484D
    case orange = 0xE5750A
    case yellow = 0xB88700
    case green = 0x2F9E44
    case blue = 0x3B82F6
    case purple = 0x9061F9

    var hex: Int { rawValue }

    var name: String {
        switch self {
        case .red:    "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green:  "Green"
        case .blue:   "Blue"
        case .purple: "Purple"
        }
    }

    // MARK: Writing

    static let openPrefix = "<span style=\"color:#"
    static let openSuffix = "\">"
    static let close = "</span>"

    /// `<span style="color:#E5484D">`, hex in capitals.
    static func openTag(hex: Int) -> String {
        openPrefix + String(format: "%06X", hex & 0xFFFFFF) + openSuffix
    }

    // MARK: Reading

    /// A coloured run: its opening tag, its closing tag, and the colour.
    struct Pair: Equatable {
        var open: Range<String.Index>
        var close: Range<String.Index>
        var hex: Int
    }

    /// The first opening tag in `range` with a closing tag after it, and
    /// something between the two. An opening tag with no closing one, or
    /// with nothing before its closing one, is text.
    static func firstPair(in text: String, range: Range<String.Index>) -> Pair? {
        var searchStart = range.lowerBound
        while let prefix = text.range(of: openPrefix, options: .caseInsensitive, range: searchStart..<range.upperBound) {
            searchStart = prefix.upperBound
            guard let (hex, openEnd) = hexAndEnd(in: text, after: prefix.upperBound, limit: range.upperBound),
                  let close = text.range(of: close, options: .caseInsensitive, range: openEnd..<range.upperBound),
                  close.lowerBound > openEnd
            else { continue }
            return Pair(open: prefix.lowerBound..<openEnd, close: close, hex: hex)
        }
        return nil
    }

    /// `text` with every coloured run's tags replaced by word joiners, a
    /// unit for a unit: what search reads, so a tag is never found and an
    /// excerpt never shows one, and every offset still points at the same
    /// character of the note, for the matches opening a result highlights.
    static func maskingTags(in text: String) -> String {
        guard text.range(of: openPrefix, options: .caseInsensitive) != nil else { return text }
        let masked = NSMutableString(string: text)
        func mask(_ range: Range<String.Index>) {
            let units = NSRange(range, in: text)
            masked.replaceCharacters(in: units, with: String(repeating: "\u{2060}", count: units.length))
        }
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            var cursor = lineStart
            while let pair = firstPair(in: text, range: cursor..<lineEnd) {
                mask(pair.open)
                mask(pair.close)
                cursor = pair.close.upperBound
            }
            lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }
        return masked as String
    }

    /// Six hex digits and `">`, from `start`: the colour, and where the tag
    /// ends.
    private static func hexAndEnd(in text: String, after start: String.Index, limit: String.Index) -> (Int, String.Index)? {
        guard let digitsEnd = text.index(start, offsetBy: 6, limitedBy: limit) else { return nil }
        let digits = text[start..<digitsEnd]
        guard digits.allSatisfy(\.isHexDigit), let hex = Int(digits, radix: 16),
              text[digitsEnd..<limit].hasPrefix(openSuffix)
        else { return nil }
        return (hex, text.index(digitsEnd, offsetBy: openSuffix.count))
    }
}
