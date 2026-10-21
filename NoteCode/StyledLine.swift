//
//  StyledLine.swift
//  NoteCode
//
//  Formatting per character (text overhaul, phase 3): a line read as the
//  characters it shows, each with what it is drawn with, and written back
//  as Markdown once some of them have changed.
//

import Foundation

/// One line of a note as the characters on the page, for the formatting
/// buttons: a button sets or clears one attribute over some of them, and the
/// line is written back so it reads that way (docs/archive/text-system-overhaul.md,
/// decision 3).
///
/// - **Only what has to change is rewritten**: the stretch between the
///   nearest points either side of the change where nothing is open, so the
///   rest of the line keeps what the reader typed, `__bold__` included. A
///   point with a marker just outside it doesn't count, or `**a**` and a
///   newly bold `b` beside it would be written as `**a****b**`.
/// - **Written the shortest way that reads back**, among a few nestings
///   (`Layer.orders`): a run's tag outside the emphasis or inside it, bold
///   outside italic or inside it, a link inside the emphasis or, for a link
///   with part of its own text bold or coloured, outside it. So a size on "ld" of a bold
///   word is `**bo<span …>ld</span>**`, Italic on it is `**bo*ld***`, and a
///   bold sentence holding a link is one bold. Equal neighbours share
///   markers. Spaces at the ends of `**`, `*` and `~~` go outside them,
///   since those can't open before a space or close after one; a tag and
///   code keep theirs. Code is innermost, since nothing in code is read.
/// - **`*`, and `_` only where `*` can't be read back.** Italic that starts
///   where bold ends puts `*` beside `**`, and the two make one run of
///   `***`, which pairs another way (CommonMark's rule of three); `_` never
///   joins a run of `*`. So `__` and `_` are tried after `**` and `*`.
/// - **Read back before it is used.** The parser has no escapes, so a `*` the
///   reader typed as text can pair with a marker put beside it. A line whose
///   rewrite doesn't read back as asked is no edit at all (`restyled`
///   returns `nil`), never a line that shows its markers.
nonisolated struct StyledLine: Sendable {

    /// What one character is drawn with.
    struct Style: Hashable, Sendable {
        var bold = false
        var italic = false
        var strikethrough = false
        var code = false
        /// The link the character is in, or `nil`.
        var link: Link?
        /// `TextColour`'s hex, or `nil` for none.
        var colour: Int?
        /// Against the block's text, or `nil` for its own size.
        var size: SpanSize?
        var underline = false
        var highlight: HighlightColour?

        /// The run's tag that says the colour and size: empty for neither.
        var tag: SpanStyle { SpanStyle(colour: colour, size: size) }
    }

    /// A link, so two side by side stay two.
    struct Link: Hashable, Sendable {
        /// Where the link was read from, in the line's UTF-16 units: no two
        /// links on a line share it.
        var id: Int
        /// The address of `[text](address)`, as written; `nil` for a bare
        /// address, which is its own text and has no markers.
        var address: String?
    }

    /// A character on the page: one composed character sequence.
    struct Glyph: Sendable {
        var text: String
        var style: Style
        /// Where it is in the line, in UTF-16 units.
        var source: NSRange

        /// White space outside code, which `*`, `**` and `~~` can't open
        /// before or close after.
        var isSpace: Bool {
            !style.code && text.allSatisfy(\.isWhitespace)
        }

        /// A letter, digit or underscore: what a word is made of.
        var isWordCharacter: Bool {
            guard let scalar = text.unicodeScalars.first else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }
    }

    let line: String
    /// The line after its heading's or list item's marker, in UTF-16 units.
    let content: NSRange
    /// 1 to 6, or 0 for anything but a heading.
    let headingLevel: Int
    /// What the parser made of the content, for the rules that act on a
    /// whole span.
    let inlines: [InlineNode]
    let glyphs: [Glyph]

    /// For each position from the content's start to its end: whether a
    /// rewrite may start there, and whether one may end there. Nothing is
    /// open at either, and the node just outside isn't a marker.
    private let mayStart: [Bool]
    private let mayEnd: [Bool]

    /// `nil` for a line of code: a fence, read alone. A blank line is a line
    /// of no glyphs, which is where text is typed first.
    init?(_ line: String) {
        let block = DocumentParser.parse(line).first
        guard !(block?.isCode ?? false), block != nil || line.isEmpty else { return nil }
        let ns = line as NSString
        self.line = line
        content = block.map { NSRange($0.contentRange, in: line) } ?? NSRange(location: 0, length: 0)
        headingLevel = block?.headingLevel ?? 0
        inlines = block?.inlines ?? []

        var starts = [Bool](repeating: false, count: content.length + 1)
        var ends = [Bool](repeating: false, count: content.length + 1)
        var glyphs: [Glyph] = []
        var depth = 0
        var previous: InlineNode?

        for node in inlines {
            let range = NSRange(node.range, in: line)
            let boundary = range.location - content.location
            if depth == 0 {
                if previous?.kind ?? .text == .text { starts[boundary] = true }
                if node.kind == .text { ends[boundary] = true }
            }
            switch node.kind {
            case .opening:
                depth += 1
            case .closing:
                depth -= 1
            case .text:
                let attributes = node.attributes
                let link = node.destination.map { destination in
                    Link(
                        id: NSRange(destination, in: line).location,
                        address: destination == node.range ? nil : String(line[destination])
                    )
                }
                let style = Style(
                    bold: attributes.bold, italic: attributes.italic, strikethrough: attributes.strikethrough,
                    code: attributes.code, link: link, colour: attributes.colour, size: attributes.size,
                    underline: attributes.underline, highlight: attributes.highlight
                )
                var position = range.location
                while position < NSMaxRange(range) {
                    let piece = NSIntersectionRange(ns.rangeOfComposedCharacterSequence(at: position), range)
                    glyphs.append(Glyph(text: ns.substring(with: piece), style: style, source: piece))
                    position = NSMaxRange(piece)
                    // Inside text that nothing is open around, but never inside a
                    // bare address, which is one link.
                    if position < NSMaxRange(range), depth == 0, node.destination == nil {
                        starts[position - content.location] = true
                        ends[position - content.location] = true
                    }
                }
            }
            previous = node
        }
        if previous?.kind ?? .text == .text { starts[content.length] = true }
        ends[content.length] = true
        starts[0] = true

        self.glyphs = glyphs
        mayStart = starts
        mayEnd = ends
    }

    // MARK: Positions

    /// How many glyphs lie wholly before `position`, a place in the line.
    func glyphCount(endingBy position: Int) -> Int {
        glyphs.firstIndex { NSMaxRange($0.source) > position } ?? glyphs.count
    }

    /// How many glyphs start before `position`.
    func glyphCount(startingBefore position: Int) -> Int {
        glyphs.firstIndex { $0.source.location >= position } ?? glyphs.count
    }

    /// The first place in the line in front of glyph `index`, before any
    /// markers there: where a caret stands, and where a selection ends.
    func earliestPosition(at index: Int) -> Int {
        index == 0 ? content.location : NSMaxRange(glyphs[index - 1].source)
    }

    /// The last place in front of glyph `index`, after any markers there:
    /// where a selection starts.
    func latestPosition(at index: Int) -> Int {
        index < glyphs.count ? glyphs[index].source.location : NSMaxRange(content)
    }

    /// The glyphs in `range`, taken out to whole code spans and links: half
    /// a link would be two links, and code can't hold a marker.
    func wholeAtoms(_ range: Range<Int>) -> Range<Int> {
        guard !range.isEmpty else { return range }
        func sameAtom(_ a: Int, _ b: Int) -> Bool {
            let (left, right) = (glyphs[a].style, glyphs[b].style)
            return (left.code && right.code) || (left.link != nil && left.link == right.link)
        }
        var lower = range.lowerBound
        var upper = range.upperBound
        var moved = true
        while moved {
            moved = false
            while lower > 0, sameAtom(lower - 1, lower) { lower -= 1; moved = true }
            while upper < glyphs.count, sameAtom(upper - 1, upper) { upper += 1; moved = true }
        }
        return lower..<upper
    }

    // MARK: Typing

    /// What text typed at `offset`, a place in the line, would be drawn with:
    /// the pairs it falls inside, by the rule the bar's lit state follows (from
    /// just after a pair's first marker character to the end of its text). The
    /// link and code it would join are left out of `style`, and `joinsLinkOrCode`
    /// says there was one: typed text there would be part of it.
    func typedStyle(at offset: Int) -> (style: Style, joinsLinkOrCode: Bool) {
        var attributes = InlineAttributes.plain
        for span in InlineSpan.spans(in: inlines) {
            let whole = NSRange(span.range, in: line)
            let inner = NSRange(span.contentRange, in: line)
            guard offset > whole.location, offset <= NSMaxRange(inner) else { continue }
            attributes = attributes.inside(span.markup)
        }
        let style = Style(
            bold: attributes.bold, italic: attributes.italic, strikethrough: attributes.strikethrough,
            colour: attributes.colour, size: attributes.size,
            underline: attributes.underline, highlight: attributes.highlight
        )
        return (style, attributes.link || attributes.code)
    }

    /// The glyphs of the word a caret at `offset` is inside, or `nil` where it
    /// is not strictly inside one: a word character on each side. At a word's
    /// ends, between words and on a blank line a button sets the typing style
    /// instead (docs/archive/text-system-overhaul.md, decision 5). A word is letters,
    /// digits and the underscore, as `MarkdownFormatting.word` has it.
    func wordGlyphs(atCaret offset: Int) -> Range<Int>? {
        let index = glyphCount(endingBy: offset)
        guard index > 0, index < glyphs.count, glyphs[index - 1].isWordCharacter, glyphs[index].isWordCharacter else { return nil }
        var lower = index - 1
        var upper = index + 1
        while lower > 0, glyphs[lower - 1].isWordCharacter { lower -= 1 }
        while upper < glyphs.count, glyphs[upper].isWordCharacter { upper += 1 }
        return lower..<upper
    }

    // MARK: Rewriting

    /// The line with each glyph drawn as `styles` says, read back: `nil`
    /// where nothing would change, or where the line can't be written to read
    /// that way.
    ///
    /// Spaces at the ends of bold, italic and strikethrough lose them, as the
    /// writer puts them outside the markers, and what comes back says so.
    func restyled(_ styles: [Style]) -> StyledLine? {
        precondition(styles.count == glyphs.count)
        guard let first = styles.indices.first(where: { styles[$0] != glyphs[$0].style }),
              let last = styles.indices.last(where: { styles[$0] != glyphs[$0].style })
        else { return nil }
        return edited(
            replacing: first..<(last + 1),
            with: glyphs[first...last].map(\.text),
            styles: Array(styles[first...last])
        )
    }

    /// The line with glyphs `range` replaced by `texts`, one glyph each,
    /// drawn as `styles` say, read back: `nil` where the line can't be
    /// written to read that way. An empty `range` inserts before it, which is
    /// how typed text is written (`MarkdownFormatting.typed`).
    ///
    /// The stretch rewritten is as `restyled` describes it, out to places
    /// where nothing is open; an insertion starts from the markers between its
    /// two neighbours, so text typed in front of a closing `**` can go in
    /// front of it, behind it or inside a new pair.
    func edited(replacing range: Range<Int>, with newTexts: [String], styles newStyles: [Style]) -> StyledLine? {
        precondition(newTexts.count == newStyles.count && range.upperBound <= glyphs.count)

        // The stretch to rewrite, out to places where nothing is open.
        var start: Int
        var end: Int
        if range.isEmpty {
            start = earliestPosition(at: range.lowerBound)
            end = latestPosition(at: range.lowerBound)
        } else {
            start = glyphs[range.lowerBound].source.location
            end = NSMaxRange(glyphs[range.upperBound - 1].source)
        }
        while !mayStart[start - content.location] { start -= 1 }
        while !mayEnd[end - content.location] { end += 1 }
        let from = glyphCount(startingBefore: start)
        let to = glyphCount(startingBefore: end)
        guard from <= range.lowerBound, to >= range.upperBound else { return nil }

        let ns = line as NSString
        let stretch = Array(glyphs[from..<range.lowerBound])
            + zip(newTexts, newStyles).map { Glyph(text: $0, style: $1, source: NSRange(location: 0, length: 0)) }
            + Array(glyphs[range.upperBound..<to])
        let allTexts = glyphs[..<from].map(\.text) + stretch.map(\.text) + glyphs[to...].map(\.text)
        var best: (read: StyledLine, length: Int)?
        for delimiters in Delimiters.choices {
            for order in Layer.orders {
                let written = Self.normalised(stretch, styles: stretch.map(\.style), order: order)
                let expected = glyphs[..<from].map(\.style) + written + glyphs[to...].map(\.style)

                let markdown = Self.write(texts: stretch.map(\.text), styles: written, order: order, delimiters: delimiters)
                let length = (markdown as NSString).length
                if let best, best.length <= length { continue }
                guard let read = StyledLine(ns.substring(to: start) + markdown + ns.substring(from: end)),
                      read.content.location == content.location,
                      read.headingLevel == headingLevel,
                      read.draws(allTexts, as: expected)
                else { continue }
                best = (read, length)
            }
            if best != nil { break }
        }
        return best?.read
    }

    /// Whether this line shows `texts`, one glyph each, drawn as `styles`
    /// says: the same links, though a link's `id` is where it was read.
    func draws(_ texts: [String], as styles: [Style]) -> Bool {
        guard glyphs.count == texts.count, glyphs.map(\.text) == texts else { return false }
        for index in glyphs.indices {
            var (read, asked) = (glyphs[index].style, styles[index])
            guard (read.link == nil) == (asked.link == nil), read.link?.address == asked.link?.address else { return false }
            if index > 0 {
                let readSame = read.link == glyphs[index - 1].style.link
                let askedSame = asked.link == styles[index - 1].link
                guard readSame == askedSame else { return false }
            }
            read.link = nil
            asked.link = nil
            guard read == asked else { return false }
        }
        return true
    }

    // MARK: Writing

    /// The layers markers are written in.
    enum Layer: CaseIterable, Sendable {
        case tag, link, bold, italic, strikethrough, underline, highlight, code

        /// The nestings a stretch is written in, outermost first: the
        /// shortest that reads back is kept, the first of equals. Emphasis
        /// and a run's tag go outside a link but in the last two, which are
        /// for a link with part of its own text bold or coloured. Code is
        /// always innermost.
        ///
        /// Underline and highlight are tags that hold anything, so each
        /// nesting is tried with the two outermost and with them just outside
        /// the code: all of a sentence highlighted with one word bold is
        /// `==🟡a **b** c==` with them outside, and the same text with them
        /// inside is a highlight round every piece.
        static let orders: [[Layer]] = bases.flatMap { base in
            [[.underline, .highlight] + base, Array(base.dropLast()) + [.underline, .highlight, .code]]
        }

        private static let bases: [[Layer]] = [
            [.tag, .bold, .italic, .strikethrough, .link, .code],
            [.tag, .italic, .bold, .strikethrough, .link, .code],
            [.bold, .italic, .strikethrough, .tag, .link, .code],
            [.italic, .bold, .strikethrough, .tag, .link, .code],
            [.tag, .link, .bold, .italic, .strikethrough, .code],
            [.link, .tag, .bold, .italic, .strikethrough, .code],
        ]

        func value(_ style: Style) -> AnyHashable? {
            switch self {
            case .tag:           style.tag.isEmpty ? nil : style.tag
            case .link:          style.link
            case .bold:          style.bold ? true : nil
            case .italic:        style.italic ? true : nil
            case .strikethrough: style.strikethrough ? true : nil
            case .underline:     style.underline ? true : nil
            case .highlight:     style.highlight
            case .code:          style.code ? true : nil
            }
        }

        func markers(_ style: Style, _ delimiters: Delimiters) -> (open: String, close: String) {
            switch self {
            case .tag:           (style.tag.openTag, SpanStyle.close)
            case .link:          style.link?.address.map { ("[", "](\($0))") } ?? ("", "")
            case .bold:          (delimiters.bold, delimiters.bold)
            case .italic:        (delimiters.italic, delimiters.italic)
            case .strikethrough: ("~~", "~~")
            case .underline:     (InlineTag.underlineOpen, InlineTag.underlineClose)
            case .highlight:     style.highlight.map { (InlineTag.highlightMark + $0.emoji, InlineTag.highlightMark) } ?? ("", "")
            case .code:          ("`", "`")
            }
        }

        /// The ones that can't open before a space or close after one.
        var shedsSpaces: Bool {
            self == .bold || self == .italic || self == .strikethrough
        }
    }

    /// What bold and italic are written with: stars, then underscores where
    /// stars beside each other would make one run.
    struct Delimiters: Sendable {
        var bold: String
        var italic: String

        static let choices = [
            Delimiters(bold: "**", italic: "*"),
            Delimiters(bold: "**", italic: "_"),
            Delimiters(bold: "__", italic: "*"),
        ]
    }

    /// `styles`, less bold, italic and strikethrough on spaces at the ends
    /// of a stretch of them, which the writer puts outside the markers. A
    /// stretch is what one pair of markers will hold in `order`: glyphs with
    /// the attribute whose outer layers agree.
    static func normalised(_ glyphs: [Glyph], styles: [Style], order: [Layer]) -> [Style] {
        var styles = styles
        for (depth, layer) in order.enumerated() where layer.shedsSpaces {
            let outer = order.prefix(depth)
            func key(_ index: Int) -> [AnyHashable?] { outer.map { $0.value(styles[index]) } }
            var index = 0
            while index < styles.count {
                guard layer.value(styles[index]) != nil else { index += 1; continue }
                var last = index
                while last + 1 < styles.count, layer.value(styles[last + 1]) != nil, key(last + 1) == key(index) { last += 1 }
                // Space by the style asked for: one newly made code is code.
                func isSpace(_ index: Int) -> Bool { !styles[index].code && glyphs[index].text.allSatisfy(\.isWhitespace) }
                var lower = index
                while lower <= last, isSpace(lower) { clear(layer, &styles[lower]); lower += 1 }
                var upper = last
                while upper >= lower, isSpace(upper) { clear(layer, &styles[upper]); upper -= 1 }
                index = last + 1
            }
        }
        return styles
    }

    private static func clear(_ layer: Layer, _ style: inout Style) {
        switch layer {
        case .bold:          style.bold = false
        case .italic:        style.italic = false
        case .strikethrough: style.strikethrough = false
        default:             break
        }
    }

    /// The Markdown for `texts` drawn as `styles` say, already normalised
    /// for `order`: each layer's markers round the longest stretches its
    /// outer layers allow.
    static func write(texts: [String], styles: [Style], order: [Layer], delimiters: Delimiters = Delimiters.choices[0]) -> String {
        var out = ""
        write(0..<texts.count, depth: 0, order: order, delimiters: delimiters, texts: texts, styles: styles, into: &out)
        return out
    }

    private static func write(
        _ range: Range<Int>,
        depth: Int,
        order: [Layer],
        delimiters: Delimiters,
        texts: [String],
        styles: [Style],
        into out: inout String
    ) {
        guard depth < order.count else {
            for glyph in range { out += texts[glyph] }
            return
        }
        let layer = order[depth]
        var start = range.lowerBound
        while start < range.upperBound {
            let value = layer.value(styles[start])
            var end = start + 1
            while end < range.upperBound, layer.value(styles[end]) == value { end += 1 }
            let markers = value == nil ? ("", "") : layer.markers(styles[start], delimiters)
            out += markers.0
            write(start..<end, depth: depth + 1, order: order, delimiters: delimiters, texts: texts, styles: styles, into: &out)
            out += markers.1
            start = end
        }
    }
}
