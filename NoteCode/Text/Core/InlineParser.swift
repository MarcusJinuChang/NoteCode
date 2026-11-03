//
//  InlineParser.swift
//  NoteCode
//
//  Splits a block's content into inline nodes.
//

import Foundation

nonisolated enum InlineParser {

    /// Reads `range` within `text` as inline Markdown: inline code, strong,
    /// emphasis, strikethrough, links and styled runs, nested.
    ///
    /// A deliberately small subset. Full CommonMark inline parsing (reference
    /// links, autolinks in angle brackets, raw HTML) is a famous tar pit and
    /// none of it is needed for class notes.
    ///
    /// Returned nodes are contiguous and cover `range` exactly: markers are
    /// nodes of their own and everything else is `.text`, carrying what it
    /// is drawn with (`InlineAttributes`). An unmatched marker is just text.
    ///
    /// **How** (text overhaul, phase 2; docs/archive/text-system-overhaul.md,
    /// decision 4). Code spans and links are found first, left to right, as
    /// before: nothing inside a code span is read, and a link's text is read
    /// on its own, so nothing in it pairs with anything outside. The rest is
    /// CommonMark's delimiter stack ("process emphasis", spec §6.2) for `*`,
    /// `**`, `_`, `__` and `~~`, so pairs nest (`***x***`, `**a *b* c**`)
    /// and pairs that would cross are text. Styled runs' tags pair on the
    /// same stack, first, as a link's brackets do in CommonMark: emphasis
    /// inside a run is processed on its own, so emphasis that would cross a
    /// run's edge is text and shows its `**`, rather than leaving a whole
    /// `<span style="…">` showing.
    ///
    /// Which markers can open or close is today's rule, not CommonMark's
    /// flanking: no opening before a space or closing after one, so
    /// `2 * 3 * 4` stays arithmetic, and no `_` inside a word, so
    /// `snake_case_name` stays an identifier. `~~` has no such rule, as
    /// before. A note about code is full of these, and with markers hidden a
    /// false span would make characters vanish.
    static func parse(_ text: String, in range: Range<String.Index>) -> [InlineNode] {
        guard !range.isEmpty else { return [] }
        var pieces: [Piece] = []
        collect(text, in: range, allowsLinks: true, into: &pieces)
        pieces.sort { $0.range.lowerBound < $1.range.lowerBound }
        return nodes(covering: range, from: pieces)
    }

    // MARK: Pieces

    /// A marker, or a bare address: where the walk that makes the nodes
    /// changes what it is drawing.
    private struct Piece {
        enum Kind {
            case opening(InlineMarkup)
            case closing(InlineMarkup)
            case address
            /// A `\` before a `$`.
            case escape
        }

        var kind: Kind
        var range: Range<String.Index>
        var destination: Range<String.Index>? = nil
    }

    /// The nodes for `range`, from its pieces in order: text between them,
    /// carrying the attributes of every pair it is inside.
    private static func nodes(covering range: Range<String.Index>, from pieces: [Piece]) -> [InlineNode] {
        var nodes: [InlineNode] = []
        nodes.reserveCapacity(pieces.count * 2 + 1)

        var open: [(attributes: InlineAttributes, destination: Range<String.Index>?)] = []
        var attributes = InlineAttributes.plain
        var destination: Range<String.Index>?
        var cursor = range.lowerBound

        func text(upTo end: String.Index) {
            guard cursor < end else { return }
            nodes.append(InlineNode(kind: .text, range: cursor..<end, attributes: attributes, destination: destination))
        }

        for piece in pieces {
            text(upTo: piece.range.lowerBound)
            switch piece.kind {
            case .opening(let markup):
                nodes.append(InlineNode(kind: .opening(markup), range: piece.range, attributes: attributes, destination: piece.destination))
                open.append((attributes, destination))
                attributes = attributes.inside(markup)
                if markup == .link { destination = piece.destination }
            case .closing(let markup):
                if let outside = open.popLast() {
                    attributes = outside.attributes
                    destination = outside.destination
                }
                nodes.append(InlineNode(kind: .closing(markup), range: piece.range, attributes: attributes, destination: piece.destination))
            case .escape:
                nodes.append(InlineNode(kind: .escape, range: piece.range, attributes: attributes, destination: destination))
            case .address:
                var linked = attributes
                linked.link = true
                nodes.append(InlineNode(kind: .text, range: piece.range, attributes: linked, destination: piece.range))
            }
            cursor = piece.range.upperBound
        }
        text(upTo: range.upperBound)
        return nodes
    }

    // MARK: Finding the pairs

    /// A run of `*`, `_` or `~`, or a styled run's opening tag, waiting on
    /// the stack for something to close it.
    private struct Delimiter {
        enum Kind: Equatable {
            case run(Character)
            /// A tag's opening markup (`InlineMarkup.isTag`): a run's, an
            /// underline's, a highlight's.
            case tag(InlineMarkup)
        }

        var kind: Kind
        /// What is left of it. A pair takes the characters nearest its text:
        /// from an opener's end, from a closer's start.
        var lower: String.Index
        var upper: String.Index
        var count: Int
        /// The run's length before anything took from it: CommonMark's rule
        /// of three counts it.
        let length: Int
        let canOpen: Bool
        let canClose: Bool
        var active = true

        var isTag: Bool {
            if case .tag = kind { return true }
            return false
        }

        /// The tag family it opens (`InlineMarkup.tagFamily`), `nil` for a run.
        var tagFamily: Int? {
            if case .tag(let markup) = kind { return markup.tagFamily }
            return nil
        }
    }

    /// Finds the pieces in `range`: code spans and links as they come, then
    /// the pairs on the delimiter stack.
    ///
    /// - Parameter allowsLinks: off inside a link's text. A link can't hold
    ///   another, and an address in its text is its text.
    private static func collect(_ text: String, in range: Range<String.Index>, allowsLinks: Bool, into pieces: inout [Piece]) {
        var delimiters: [Delimiter] = []
        var cursor = range.lowerBound
        let limit = range.upperBound

        while cursor < limit {
            let character = text[cursor]
            switch character {
            case "`":
                // Inline code wins over everything: `a *b* c` is code holding
                // asterisks, not code wrapped around emphasis.
                let contentStart = text.index(after: cursor)
                if let closing = firstIndex(of: "`", in: text, from: contentStart, limit: limit), closing > contentStart {
                    let end = text.index(after: closing)
                    pieces.append(Piece(kind: .opening(.inlineCode), range: cursor..<contentStart))
                    pieces.append(Piece(kind: .closing(.inlineCode), range: closing..<end))
                    cursor = end
                    continue
                }

            case "\\":
                // `\$` is a dollar. It is the only escape there is, and it
                // is read here, past code (found first) and inside a link's
                // text, but never inside a formula, which is skipped whole.
                let next = text.index(after: cursor)
                if next < limit, text[next] == "$" {
                    pieces.append(Piece(kind: .escape, range: cursor..<next))
                    cursor = text.index(after: next)
                    continue
                }

            case "$" where allowsLinks:
                // A formula is an atom: nothing inside is read, so `$a*b*c$`
                // has no emphasis. Not in a link's text, where it is text.
                if let math = mathSpan(in: text, at: cursor, limit: limit) {
                    pieces.append(Piece(kind: .opening(.math(math.style)), range: math.opening))
                    pieces.append(Piece(kind: .closing(.math(math.style)), range: math.closing))
                    cursor = math.closing.upperBound
                    continue
                }

            case "[" where allowsLinks:
                if let link = markdownLink(in: text, at: cursor, limit: limit) {
                    pieces.append(Piece(kind: .opening(.link), range: cursor..<link.text.lowerBound, destination: link.destination))
                    collect(text, in: link.text, allowsLinks: false, into: &pieces)
                    pieces.append(Piece(kind: .closing(.link), range: link.text.upperBound..<link.end, destination: link.destination))
                    cursor = link.end
                    continue
                }

            case "h" where allowsLinks:
                // Inside a highlight, a `==` at an address's end is the
                // highlight's, not the address's.
                let highlightOpen = { delimiters.contains { $0.active && $0.tagFamily == 2 } }
                if let end = bareLink(in: text, at: cursor, lower: range.lowerBound, limit: limit, endsAtHighlight: highlightOpen) {
                    pieces.append(Piece(kind: .address, range: cursor..<end, destination: cursor..<end))
                    cursor = end
                    continue
                }

            case "*", "_", "~":
                var end = text.index(after: cursor)
                var length = 1
                while end < limit, text[end] == character {
                    end = text.index(after: end)
                    length += 1
                }
                // One tilde is prose: `~5ms`, `~/Developer`.
                if character != "~" || length >= 2 {
                    let before: Character? = cursor > range.lowerBound ? text[text.index(before: cursor)] : nil
                    let after: Character? = end < limit ? text[end] : nil
                    let (canOpen, canClose) = flanking(character, before: before, after: after)
                    delimiters.append(Delimiter(
                        kind: .run(character), lower: cursor, upper: end, count: length, length: length,
                        canOpen: canOpen, canClose: canClose
                    ))
                }
                cursor = end
                continue

            case "<":
                if let tag = SpanStyle.openingTag(in: text, at: cursor, limit: limit) {
                    delimiters.append(tagDelimiter(.styled(tag.style), cursor..<tag.end))
                    cursor = tag.end
                    continue
                }
                if let end = InlineTag.underlineOpening(in: text, at: cursor, limit: limit) {
                    delimiters.append(tagDelimiter(.underline, cursor..<end))
                    cursor = end
                    continue
                }
                if let end = SpanStyle.closingTag(in: text, at: cursor, limit: limit) {
                    closeRun(at: cursor..<end, family: 0, delimiters: &delimiters, in: text, into: &pieces)
                    cursor = end
                    continue
                }
                if let end = InlineTag.underlineClosing(in: text, at: cursor, limit: limit) {
                    closeRun(at: cursor..<end, family: 1, delimiters: &delimiters, in: text, into: &pieces)
                    cursor = end
                    continue
                }

            case "=":
                var end = text.index(after: cursor)
                var length = 1
                while end < limit, text[end] == "=" {
                    end = text.index(after: end)
                    length += 1
                }
                guard length >= 2 else { cursor = end; continue }
                // With a highlight open, the first two close it. What is
                // left of the run is read next, so `====🔴` ends one highlight
                // and starts another, and `===` is a closing `==` and an `=`.
                if delimiters.contains(where: { $0.active && $0.tagFamily == 2 }) {
                    let closeEnd = text.index(cursor, offsetBy: 2)
                    closeRun(at: cursor..<closeEnd, family: 2, delimiters: &delimiters, in: text, into: &pieces)
                    cursor = closeEnd
                    continue
                }
                // Otherwise only a run of exactly two, then an emoji, opens
                // one: `a == b` and `====` are text.
                if length == 2, let open = InlineTag.highlightOpening(in: text, at: cursor, limit: limit) {
                    delimiters.append(tagDelimiter(.highlight(open.colour), cursor..<open.end))
                    cursor = open.end
                    continue
                }
                cursor = end
                continue

            default:
                break
            }
            cursor = text.index(after: cursor)
        }

        processEmphasis(&delimiters, above: -1, in: text, into: &pieces)
    }

    /// Whether a run of `character` between `before` and `after` can open
    /// and close a span. `nil` is the edge of the block, which counts as a
    /// space.
    ///
    /// Today's rule, less CommonMark's corners: an opener can't have a space
    /// after it nor a closer one before it, and an underscore can't open or
    /// close inside a word. Tildes have no rule.
    private static func flanking(_ character: Character, before: Character?, after: Character?) -> (canOpen: Bool, canClose: Bool) {
        guard character != "~" else { return (true, true) }
        var canOpen = after.map { !$0.isWhitespace } ?? false
        var canClose = before.map { !$0.isWhitespace } ?? false
        if character == "_" {
            if let before, before.isLetter || before.isNumber { canOpen = false }
            if let after, after.isLetter || after.isNumber { canClose = false }
        }
        return (canOpen, canClose)
    }

    /// A closing tag at `tag` (a `</span>`, a `</u>` or a highlight's `==`):
    /// pairs it with the nearest opening tag of its own family still open, and
    /// settles the emphasis between them on its own, so none of it pairs
    /// across the run's edge. A tag with nothing open, or with nothing between
    /// it and its opening tag, is text, and that opening tag with it. A tag
    /// of another family opened in between is dropped with what lay between,
    /// as emphasis that crosses is: tags that cross are text.
    private static func closeRun(
        at tag: Range<String.Index>,
        family: Int,
        delimiters: inout [Delimiter],
        in text: String,
        into pieces: inout [Piece]
    ) {
        guard let openIndex = delimiters.lastIndex(where: { $0.active && $0.tagFamily == family }),
              case .tag(let markup) = delimiters[openIndex].kind
        else { return }
        let opening = delimiters[openIndex]
        guard opening.upper < tag.lowerBound else {
            delimiters[openIndex].active = false
            return
        }
        processEmphasis(&delimiters, above: openIndex, in: text, into: &pieces)
        delimiters.removeSubrange(openIndex...)
        pieces.append(Piece(kind: .opening(markup), range: opening.lower..<opening.upper))
        pieces.append(Piece(kind: .closing(markup), range: tag))
    }

    /// A tag waiting on the stack for its closing tag.
    private static func tagDelimiter(_ markup: InlineMarkup, _ range: Range<String.Index>) -> Delimiter {
        Delimiter(kind: .tag(markup), lower: range.lowerBound, upper: range.upperBound, count: 1, length: 1, canOpen: true, canClose: false)
    }

    /// CommonMark's "process emphasis" over the delimiters above `bottom`.
    ///
    /// Each closer, left to right, pairs with the nearest opener of its own
    /// character below it, taking two characters from each where both have
    /// two (strong, or a strike), else one (emphasis). What lay between the
    /// two can no longer pair with anything outside them, and is text unless
    /// it already paired.
    private static func processEmphasis(_ delimiters: inout [Delimiter], above bottom: Int, in text: String, into pieces: inout [Piece]) {
        var closerIndex = bottom + 1
        while closerIndex < delimiters.count {
            let closer = delimiters[closerIndex]
            guard closer.active, closer.canClose, closer.count > 0, case .run(let character) = closer.kind else {
                closerIndex += 1
                continue
            }

            var found: Int?
            var index = closerIndex - 1
            while index > bottom {
                let opener = delimiters[index]
                if opener.active, opener.canOpen, opener.count > 0, opener.kind == .run(character), canPair(opener, closer, character) {
                    found = index
                    break
                }
                index -= 1
            }

            guard let openerIndex = found else {
                // A closer that can't open is done with.
                if !closer.canOpen { delimiters[closerIndex].active = false }
                closerIndex += 1
                continue
            }

            let used = character == "~" || (delimiters[openerIndex].count >= 2 && closer.count >= 2) ? 2 : 1
            let markup: InlineMarkup = character == "~" ? .strikethrough : used == 2 ? .strong : .emphasis

            let openEnd = delimiters[openerIndex].upper
            let openStart = text.index(openEnd, offsetBy: -used)
            delimiters[openerIndex].upper = openStart
            delimiters[openerIndex].count -= used

            let closeStart = delimiters[closerIndex].lower
            let closeEnd = text.index(closeStart, offsetBy: used)
            delimiters[closerIndex].lower = closeEnd
            delimiters[closerIndex].count -= used

            pieces.append(Piece(kind: .opening(markup), range: openStart..<openEnd))
            pieces.append(Piece(kind: .closing(markup), range: closeStart..<closeEnd))

            for between in (openerIndex + 1)..<closerIndex {
                delimiters[between].active = false
            }
            if delimiters[openerIndex].count == 0 { delimiters[openerIndex].active = false }
            if delimiters[closerIndex].count == 0 {
                delimiters[closerIndex].active = false
                closerIndex += 1
            }
        }
    }

    /// Whether `opener` and `closer`, runs of `character`, may pair.
    ///
    /// Tildes pair two and two. Stars and underscores follow CommonMark's
    /// rule of three: where either run could both open and close, their
    /// lengths mustn't add up to a multiple of three unless both are one,
    /// which is what makes `*foo**bar**baz*` emphasis round strong rather
    /// than emphasis then text.
    private static func canPair(_ opener: Delimiter, _ closer: Delimiter, _ character: Character) -> Bool {
        if character == "~" { return opener.count >= 2 && closer.count >= 2 }
        if opener.canClose || closer.canOpen {
            let sum = opener.length + closer.length
            if sum % 3 == 0, !(opener.length % 3 == 0 && closer.length % 3 == 0) { return false }
        }
        return true
    }

    // MARK: Math

    /// A formula starting at the `$` at `open`, and where it ends.
    ///
    /// Pandoc's rule, which Obsidian's follows. Inline: the opening `$` has a
    /// non-space after it, the closing one a non-space before it and no digit
    /// after, so `costs $5 and $10` and `$5–$10` stay text. `$$`: a closing
    /// `$$`, and anything but blanks between, spaces allowed (`$$ x $$`).
    /// `\$` never closes either. A code span in between is skipped whole, so a
    /// `$` in one is not a closer; one that starts before a formula still wins
    /// over it, because it is found first, left to right.
    static func mathSpan(
        in text: String,
        at open: String.Index,
        limit: String.Index
    ) -> (style: MathStyle, opening: Range<String.Index>, closing: Range<String.Index>)? {
        let afterOpen = text.index(after: open)
        guard afterOpen < limit else { return nil }
        let isDisplay = text[afterOpen] == "$"
        let contentStart = isDisplay ? text.index(after: afterOpen) : afterOpen
        guard contentStart < limit else { return nil }
        if !isDisplay, text[contentStart].isWhitespace { return nil }

        var cursor = contentStart
        while cursor < limit {
            let character = text[cursor]
            if character == "\\" {
                // Whatever follows is not a closer; `\$` is the case that matters.
                cursor = text.index(after: cursor)
                if cursor < limit { cursor = text.index(after: cursor) }
                continue
            }
            if character == "`" {
                let next = text.index(after: cursor)
                if let closing = firstIndex(of: "`", in: text, from: next, limit: limit), closing > next {
                    cursor = text.index(after: closing)
                    continue
                }
            }
            if character == "$" {
                let after = text.index(after: cursor)
                if isDisplay {
                    if after < limit, text[after] == "$", cursor > contentStart,
                       text[contentStart..<cursor].contains(where: { !$0.isWhitespace }) {
                        return (.display, open..<contentStart, cursor..<text.index(after: after))
                    }
                } else if cursor > contentStart,
                          !text[text.index(before: cursor)].isWhitespace,
                          after >= limit || !text[after].isNumber {
                    return (.inline, open..<contentStart, cursor..<after)
                }
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    // MARK: Links

    /// `[text](address)` starting at `open`. The text can't be empty or blank
    /// and neither part crosses a bracket or a parenthesis, so `[ ] (x)` and
    /// `arr[i](j)` stay text only when they have nothing between the brackets;
    /// a note about `f[i](x)` does link, which is what Markdown does too.
    private static func markdownLink(
        in text: String,
        at open: String.Index,
        limit: String.Index
    ) -> (text: Range<String.Index>, destination: Range<String.Index>, end: String.Index)? {
        let contentStart = text.index(after: open)
        guard contentStart < limit else { return nil }

        var cursor = contentStart
        while cursor < limit, text[cursor] != "]", text[cursor] != "[" {
            cursor = text.index(after: cursor)
        }
        guard cursor < limit, text[cursor] == "]", cursor > contentStart else { return nil }
        guard text[contentStart..<cursor].contains(where: { !$0.isWhitespace }) else { return nil }

        let closeBracket = cursor
        let parenthesis = text.index(after: closeBracket)
        guard parenthesis < limit, text[parenthesis] == "(" else { return nil }

        let destinationStart = text.index(after: parenthesis)
        var end = destinationStart
        while end < limit, text[end] != ")", !text[end].isWhitespace {
            end = text.index(after: end)
        }
        guard end < limit, text[end] == ")", end > destinationStart else { return nil }

        return (contentStart..<closeBracket, destinationStart..<end, text.index(after: end))
    }

    /// A bare `http://` or `https://` address, shown exactly as typed, and
    /// where it ends. It runs to the next space or `<`, less the punctuation
    /// a sentence puts after it.
    private static func bareLink(
        in text: String,
        at start: String.Index,
        lower: String.Index,
        limit: String.Index,
        endsAtHighlight: () -> Bool
    ) -> String.Index? {
        // Not the tail of a longer word: `xhttp://` isn't an address.
        if start > lower {
            let previous = text[text.index(before: start)]
            if previous.isLetter || previous.isNumber { return nil }
        }

        let rest = text[start..<limit]
        let schemeLength: Int
        if rest.hasPrefix("https://") {
            schemeLength = 8
        } else if rest.hasPrefix("http://") {
            schemeLength = 7
        } else {
            return nil
        }

        var end = text.index(start, offsetBy: schemeLength)
        let hostStart = end
        // A `<` ends it, as in GitHub's autolinks: `</span>` after an address
        // in a run is the run's, not the address's.
        while end < limit, !text[end].isWhitespace, text[end] != "<" {
            end = text.index(after: end)
        }
        // A sentence's own punctuation, a closing bracket the address didn't
        // open, and the closing markers of a span around it: `*`, `_` or `~`
        // at its end, where the address holds none of that character before
        // them, so `**https://example.com**` is a bold address.
        while end > hostStart {
            let lastIndex = text.index(before: end)
            let last = text[lastIndex]
            if ".,;:!?'\"".contains(last) || (last == ")" && !text[hostStart..<end].contains("(")) {
                end = lastIndex
                continue
            }
            // A highlight's closing `==`, only inside one: outside, an
            // address ending in `==` (a padded base64 query) keeps it.
            if last == "=", end > text.index(after: hostStart), text[text.index(before: lastIndex)] == "=", endsAtHighlight() {
                end = text.index(before: lastIndex)
                continue
            }
            if "*_~".contains(last) {
                var runStart = lastIndex
                while runStart > hostStart, text[text.index(before: runStart)] == last {
                    runStart = text.index(before: runStart)
                }
                if !text[hostStart..<runStart].contains(last) {
                    end = runStart
                    continue
                }
            }
            break
        }
        guard end > hostStart else { return nil }
        return end
    }

    // MARK: Private

    private static func firstIndex(
        of character: Character,
        in text: String,
        from start: String.Index,
        limit: String.Index
    ) -> String.Index? {
        var cursor = start
        while cursor < limit {
            if text[cursor] == character { return cursor }
            cursor = text.index(after: cursor)
        }
        return nil
    }
}
