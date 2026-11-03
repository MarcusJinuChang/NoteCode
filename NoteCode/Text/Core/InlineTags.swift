//
//  InlineTags.swift
//  NoteCode
//
//  Obsidian's other inline marks (text overhaul, phase 6): underline,
//  `<u>text</u>`, and highlight, `==🟡text==`. Both are pairs of markers that
//  hold no text of their own, like a styled run's tags (`SpanStyle`), so they
//  pair on the parser's stack the way those do.
//

import Foundation

/// The colour of a highlight, named by the emoji that says it.
///
/// **The format is Obsidian 1.14's own** (docs/research-notability-obsidian.md,
/// §2.6): `==🟡text==`, the emoji required. A plain `==text==` is Obsidian's
/// older highlight, and it is left alone here on purpose: a note about code
/// is full of `a==b` and `x == y`, and with markers hidden a false highlight
/// would make the `==` vanish. The emoji can't collide with anything typed by
/// accident. Known cost, as the research says: GitHub shows `==🟡` as text.
///
/// The emoji is part of the opening marker, so it is hidden with the `==`
/// (`MarkdownLayout` swaps every UTF-16 unit, a surrogate pair's two included).
nonisolated enum HighlightColour: String, CaseIterable, Hashable, Sendable {
    case red = "🔴"
    case orange = "🟠"
    case yellow = "🟡"
    case green = "🟢"
    case blue = "🔵"
    case purple = "🟣"

    init?(emoji: Character) {
        self.init(rawValue: String(emoji))
    }

    /// The emoji, as written after the opening `==`.
    var emoji: String { rawValue }

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

    /// 1 to 6, for the block signature (`InlineAttributes.signature`).
    var number: Int {
        Self.allCases.firstIndex(of: self)! + 1
    }

    // MARK: Drawing

    /// The colour as a background: translucent, so the text keeps the colour
    /// it has and the page shows through, in both appearances. Bright system
    /// hues, laid over the page at `alpha`.
    ///
    /// Chosen so the label colour stays readable on every one (4.5:1 or
    /// better, computed in `HighlightColourTests`), since a coloured run's
    /// text is made legible against the page and not against its highlight.
    var hex: (light: Int, dark: Int) {
        switch self {
        case .red:    (0xFF453A, 0xFF453A)
        case .orange: (0xFF9F0A, 0xFF9F0A)
        case .yellow: (0xFFD60A, 0xFFD60A)
        case .green:  (0x30D158, 0x30D158)
        case .blue:   (0x0A84FF, 0x0A84FF)
        case .purple: (0xBF5AF2, 0xBF5AF2)
        }
    }

    /// How much of the colour shows over the page.
    static func alpha(isDark: Bool) -> Double {
        isDark ? 0.40 : 0.38
    }
}

/// Reading the tags of underline and highlight, which are not `SpanStyle`'s.
nonisolated enum InlineTag {

    static let underlineOpen = "<u>"
    static let underlineClose = "</u>"
    static let highlightMark = "=="

    /// Where `<u>` ends, if one starts at `start`, in either case.
    static func underlineOpening(in text: String, at start: String.Index, limit: String.Index) -> String.Index? {
        SpanStyle.tag(underlineOpen, in: text, at: start, limit: limit)
    }

    /// Where `</u>` ends, if one starts at `start`, in either case.
    static func underlineClosing(in text: String, at start: String.Index, limit: String.Index) -> String.Index? {
        SpanStyle.tag(underlineClose, in: text, at: start, limit: limit)
    }

    /// A highlight's opening marker at `start`: two equals signs and an
    /// emoji. Where it ends, and its colour. Whether those two are the whole
    /// of a run of equals signs is the caller's to judge (a run of four is the
    /// end of one highlight and the start of the next).
    static func highlightOpening(in text: String, at start: String.Index, limit: String.Index) -> (colour: HighlightColour, end: String.Index)? {
        guard let afterMark = text.index(start, offsetBy: 2, limitedBy: limit),
              text[start] == "=", text[text.index(after: start)] == "=",
              afterMark < limit,
              let colour = HighlightColour(emoji: text[afterMark])
        else { return nil }
        return (colour, text.index(after: afterMark))
    }
}
