//
//  SpanStyle.swift
//  NoteCode
//
//  Colour and size anywhere (roadmap step 10): a run of text in a note's
//  Markdown, `<span style="color:#RRGGBB;font-size:1.25em">text</span>`.
//

import Foundation

/// What a styled run sets: a colour (`TextColour`), a size (`SpanSize`), or
/// both, and how its tag is written and read.
///
/// **The format is Obsidian's own** (decided 16 Oct from step 3's research,
/// docs/research-notability-obsidian.md): an HTML span with an inline style,
/// the one convention Obsidian draws without a plugin that GitHub reads as
/// plain text. Colour and size share one tag, colour first, the order the
/// HTML Font Toolbar plugin writes, so the two never nest:
///
///     <span style="color:#E5484D">        a colour
///     <span style="font-size:1.25em">     a size
///     <span style="color:#E5484D;font-size:1.25em">
///
/// Exactly these shapes, hex and keywords in either case, are a run; any
/// other `<span …>` (a class, a named colour, another property, another
/// order) stays visible text, so pasted HTML is never half hidden. A run is on
/// one line and runs don't nest.
nonisolated struct SpanStyle: Hashable, Sendable {
    var colour: Int?
    var size: SpanSize?

    init(colour: Int? = nil, size: SpanSize? = nil) {
        self.colour = colour
        self.size = size
    }

    var isEmpty: Bool { colour == nil && size == nil }

    // MARK: Writing

    static let tagPrefix = "<span style=\""
    static let tagSuffix = "\">"
    static let close = "</span>"

    private static let colourKey = "color:#"
    private static let sizeKey = "font-size:"

    /// `<span style="color:#E5484D;font-size:1.25em">`, hex in capitals,
    /// with only what is set.
    var openTag: String {
        var declarations: [String] = []
        if let colour { declarations.append(Self.colourKey + String(format: "%06X", colour & 0xFFFFFF)) }
        if let size { declarations.append(Self.sizeKey + size.written) }
        return Self.tagPrefix + declarations.joined(separator: ";") + Self.tagSuffix
    }

    // MARK: Reading

    /// A styled run: its opening tag, its closing tag, and its style.
    struct Pair: Equatable {
        var open: Range<String.Index>
        var close: Range<String.Index>
        var style: SpanStyle
    }

    /// The first opening tag in `range` with a closing tag after it, and
    /// something between the two. An opening tag with no closing one, or
    /// with nothing before its closing one, is text.
    static func firstPair(in text: String, range: Range<String.Index>) -> Pair? {
        var searchStart = range.lowerBound
        while let prefix = text.range(of: tagPrefix, options: .caseInsensitive, range: searchStart..<range.upperBound) {
            searchStart = prefix.upperBound
            guard let (style, openEnd) = declarations(in: text, from: prefix.upperBound, limit: range.upperBound),
                  let close = text.range(of: close, options: .caseInsensitive, range: openEnd..<range.upperBound),
                  close.lowerBound > openEnd
            else { continue }
            return Pair(open: prefix.lowerBound..<openEnd, close: close, style: style)
        }
        return nil
    }

    /// `text` with every run's tags replaced by word joiners, a unit for a
    /// unit: what search reads, so a tag is never found and an excerpt never
    /// shows one, and every offset still points at the same character of the
    /// note, for the matches opening a result highlights.
    static func maskingTags(in text: String) -> String {
        guard text.range(of: tagPrefix, options: .caseInsensitive) != nil else { return text }
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

    /// The declarations after `style="`, from `start`, and `">`: the style,
    /// and where the tag ends. A colour, a size, or a colour then `;` and a
    /// size, nothing else.
    private static func declarations(in text: String, from start: String.Index, limit: String.Index) -> (SpanStyle, String.Index)? {
        var style = SpanStyle()
        var cursor = start

        func take(_ keyword: String) -> Bool {
            guard let end = text.index(cursor, offsetBy: keyword.count, limitedBy: limit),
                  text[cursor..<end].caseInsensitiveCompare(keyword) == .orderedSame
            else { return false }
            cursor = end
            return true
        }

        /// `font-size:` has been taken: the number and `em`.
        func size() -> Bool {
            let number = text[cursor..<limit].prefix { $0.isASCII && ($0.isNumber || $0 == ".") }
            guard let em = Double(number) else { return false }
            cursor = text.index(cursor, offsetBy: number.count)
            guard take("em") else { return false }
            style.size = SpanSize.nearest(toEm: em)
            return true
        }

        if take(colourKey) {
            guard let digitsEnd = text.index(cursor, offsetBy: 6, limitedBy: limit) else { return nil }
            let digits = text[cursor..<digitsEnd]
            guard digits.allSatisfy(\.isHexDigit), let hex = Int(digits, radix: 16) else { return nil }
            style.colour = hex
            cursor = digitsEnd
            if take(";") {
                guard take(sizeKey), size() else { return nil }
            }
        } else if take(sizeKey) {
            guard size() else { return nil }
        } else {
            return nil
        }
        guard take(tagSuffix) else { return nil }
        return (style, cursor)
    }
}

/// A size text can be set in, against the text around it: a heading's run
/// is larger than a paragraph's.
///
/// Three steps, as the research proposed: body text and headings cover the
/// rest. A size read from elsewhere snaps to the nearest step, and one nearer
/// to 1em than to any is no size at all, so every line holds text in one of
/// a few sizes.
nonisolated enum SpanSize: Int, CaseIterable, Sendable {
    case small
    case large
    case larger

    var em: Double {
        switch self {
        case .small:  0.85
        case .large:  1.25
        case .larger: 1.5
        }
    }

    /// How it is written in the tag.
    var written: String {
        switch self {
        case .small:  "0.85em"
        case .large:  "1.25em"
        case .larger: "1.5em"
        }
    }

    var name: String {
        switch self {
        case .small:  "Small"
        case .large:  "Large"
        case .larger: "Larger"
        }
    }

    /// The step nearest `em`, or `nil` where 1em, normal size, is nearer.
    static func nearest(toEm em: Double) -> SpanSize? {
        let nearest = allCases.min { abs($0.em - em) < abs($1.em - em) }
        guard let nearest, abs(nearest.em - em) < abs(1 - em) else { return nil }
        return nearest
    }
}
