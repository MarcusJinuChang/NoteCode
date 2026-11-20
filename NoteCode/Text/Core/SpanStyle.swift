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
/// one line. The menus never write one run inside another, but one written
/// elsewhere is read as nested (`InlineAttributes.inside`).
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

    /// The opening tag at `start`, if one starts there: its style, and where
    /// it ends. Only the shapes above; anything else is text.
    static func openingTag(in text: String, at start: String.Index, limit: String.Index) -> (style: SpanStyle, end: String.Index)? {
        guard let prefixEnd = tag(tagPrefix, in: text, at: start, limit: limit) else { return nil }
        guard let (style, end) = declarations(in: text, from: prefixEnd, limit: limit) else { return nil }
        return (style, end)
    }

    /// Where a closing tag at `start` ends, if one starts there.
    static func closingTag(in text: String, at start: String.Index, limit: String.Index) -> String.Index? {
        tag(close, in: text, at: start, limit: limit)
    }

    /// Where `tag` ends, if it is at `start`, in either case. Most `<` in a
    /// note are `vector<int>`, so the second character is checked first.
    static func tag(_ tag: String, in text: String, at start: String.Index, limit: String.Index) -> String.Index? {
        let second = text.index(after: start)
        guard second < limit, text[second].lowercased() == String(tag[tag.index(after: tag.startIndex)]),
              let end = text.index(start, offsetBy: tag.count, limitedBy: limit),
              text[start..<end].caseInsensitiveCompare(tag) == .orderedSame
        else { return nil }
        return end
    }

    /// `text` with every run's tags replaced by word joiners, a unit for a
    /// unit: what search reads, so a tag is never found and an excerpt never
    /// shows one, and every offset still points at the same character of the
    /// note, for the matches opening a result highlights.
    ///
    /// The tags are the parser's (`InlineParser`), so what search leaves out
    /// is what the page hides: not a tag in a code block, which is code.
    static func maskingTags(in text: String) -> String {
        guard mayHoldTags(text) else { return text }
        let masked = NSMutableString(string: text)
        for block in DocumentParser.parse(text) {
            for inline in block.inlines where inline.kind.isSpanTag {
                let units = NSRange(inline.range, in: text)
                masked.replaceCharacters(in: units, with: String(repeating: "\u{2060}", count: units.length))
            }
        }
        return masked as String
    }

    /// Whether `text` could hold a tag at all, so a search of notes with none
    /// doesn't parse them: a run's `<span style="`, an underline's `<u>`, or
    /// a highlight's `==` and an emoji (a note of code is full of `==`).
    private static func mayHoldTags(_ text: String) -> Bool {
        text.range(of: tagPrefix, options: .caseInsensitive) != nil
            || text.range(of: InlineTag.underlineOpen, options: .caseInsensitive) != nil
            || HighlightColour.allCases.contains { text.contains(InlineTag.highlightMark + $0.emoji) }
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
            style.size = SpanSize(em: em)
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
/// **Any size** (text overhaul, phase 1, 18 Oct; docs/archive/text-system-overhaul.md).
/// Written as em against the text around it, to the thousandth, so a note
/// resized with its stepper keeps its proportions and Obsidian draws it the
/// same way; chosen and shown in points (`init(points:against:)`,
/// `points(against:)`). Step 10's three steps, 0.85, 1.25 and 1.5em, read as
/// they always did. Exactly 1em is no size.
nonisolated struct SpanSize: Hashable, Sendable {

    /// Thousandths of an em, as written: two sizes that write the same tag
    /// are the same size.
    let thousandths: Int

    /// What a tag can say, clamped: a size from elsewhere outside it reads
    /// as its nearest end, rather than as text.
    static let ems: ClosedRange<Double> = 0.1...10

    /// `nil` for 1em, the size of the text around it, and for a size that
    /// isn't one.
    init?(em: Double) {
        guard em.isFinite, em > 0 else { return nil }
        let clamped = min(max(em, Self.ems.lowerBound), Self.ems.upperBound)
        let thousandths = Int((clamped * 1000).rounded())
        guard thousandths != 1000 else { return nil }
        self.thousandths = thousandths
    }

    var em: Double { Double(thousandths) / 1000 }

    /// How it is written in the tag: `1.412em`, `1.5em`, `2em`.
    var written: String {
        var number = String(thousandths / 1000)
        var fraction = String(format: "%03d", thousandths % 1000)
        while fraction.hasSuffix("0") { fraction.removeLast() }
        if !fraction.isEmpty { number += "." + fraction }
        return number + "em"
    }

    // MARK: Points

    /// The sizes the size control sets, in points.
    static let points: ClosedRange<Double> = 8...72

    /// The sizes its list offers, as Word's does.
    static let presets: [Double] = [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 60, 72]

    /// The size that sets text at `points` beside text of `base` points:
    /// `nil` where that is `base` itself.
    init?(points: Double, against base: Double) {
        guard base > 0 else { return nil }
        self.init(em: points / base)
    }

    /// The points a run of this size comes to beside text of `base` points,
    /// to the half point, which is what the styler sets it in. Written to
    /// the thousandth, every half point the control sets comes back exactly
    /// beside text of up to 80 points; a note's largest is a heading of about
    /// 40.
    func points(against base: Double) -> Double {
        (base * em * 2).rounded() / 2
    }

    /// `points(against:)`, with no size being `base` itself.
    static func points(_ size: SpanSize?, against base: Double) -> Double {
        size?.points(against: base) ?? base
    }

    /// `points` stepped a point at a time, or `nil` past the control's ends.
    /// Text already outside them (a large run in a note made larger) steps
    /// back towards them, never further out.
    static func stepped(_ points: Double, by steps: Int) -> Double? {
        let range = Self.points
        if steps > 0, points >= range.upperBound { return nil }
        if steps < 0, points <= range.lowerBound { return nil }
        let next = points + Double(steps)
        return min(max(next, min(range.lowerBound, points)), max(range.upperBound, points))
    }

    /// A size in points as the control writes it: `24`, or `24.5`.
    static func label(points: Double) -> String {
        points.rounded() == points ? String(Int(points)) : String(format: "%.1f", points)
    }
}
