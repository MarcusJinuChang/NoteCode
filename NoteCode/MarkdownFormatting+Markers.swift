//
//  MarkdownFormatting+Markers.swift
//  NoteCode
//
//  Editing text whose Markdown markers can't be seen: where the caret may
//  stop, and what Backspace does at the edge of a hidden marker.
//

import Foundation

/// A rendered note lays its markers out at zero width (`MarkdownLayout`), so
/// the characters are still there and take no room. Without these rules the
/// caret would stand still for the several presses it takes to cross `**`,
/// Backspace would delete a marker nobody can see, and the first press of
/// Backspace at the start of a heading would eat the space after its `#`.
///
/// Everything here works on the one line the caret is on, parsed with the
/// same parsers as the styling, so what counts as a marker is whatever the
/// note draws as one. A code block's lines are never touched.
extension MarkdownFormatting {

    /// A run of characters that take no room, as one place for the caret.
    ///
    /// Every offset in `range` (both ends included) is the same spot on the
    /// page. Which of them the caret is *at* decides what typing does there.
    struct HiddenStretch: Equatable, Sendable {
        /// `[a, b)`: from the first marker character to the first character
        /// after the last.
        var range: NSRange
        /// A heading's `# `, a quote's `> `, a rule's dashes or a checklist's
        /// `- [x] `. Text can't go before it, so the stop is after it. Inline markers stop at their left
        /// edge: the end of a bold word is inside it, the start isn't.
        var pinsAfter: Bool

        var start: Int { range.location }
        var end: Int { NSMaxRange(range) }

        /// The offset the caret stands at when it is anywhere in `range`.
        var stop: Int { pinsAfter ? end : start }
    }

    /// Whether a caret at `offset` is on a code block's lines.
    static func isCode(_ offset: Int, in codeRanges: [CodeRange]) -> Bool {
        codeRanges.contains { $0.contains(NSRange(location: offset, length: 0)) }
    }

    // MARK: Finding the stretches

    /// The hidden stretches on the line that holds `offset`, in order.
    static func hiddenStretches(around offset: Int, in text: NSString) -> (stretches: [HiddenStretch], line: NSRange) {
        let line = contentLine(containing: offset, in: text)
        return (hiddenStretches(inLine: line, of: text), line)
    }

    /// The line holding `offset`, without its terminator. An offset at the
    /// very start of a line belongs to that line, and one at its end too.
    static func contentLine(containing offset: Int, in text: NSString) -> NSRange {
        let offset = min(max(offset, 0), text.length)
        var line = text.lineRange(for: NSRange(location: offset, length: 0))
        while line.length > 0, [10, 13, 0x2028, 0x2029].contains(text.character(at: NSMaxRange(line) - 1)) {
            line.length -= 1
        }
        return line
    }

    static func hiddenStretches(inLine line: NSRange, of text: NSString) -> [HiddenStretch] {
        guard line.length > 0 else { return [] }
        let lineText = text.substring(with: line)
        guard let block = DocumentParser.parse(lineText).first, !block.isCode else { return [] }

        func absolute(_ range: Range<String.Index>) -> NSRange {
            shifted(NSRange(range, in: lineText), by: line.location)
        }

        var stretches: [HiddenStretch] = []
        switch block.kind {
        case .heading, .blockQuote, .rule:
            if let marker = block.markerRange {
                stretches.append(HiddenStretch(range: absolute(marker), pinsAfter: true))
            }
        case .listItem(_, .checkbox, _):
            if let marker = block.markerRange {
                var range = absolute(marker)
                let indent = indentation(of: lineText)
                range = NSRange(location: range.location + indent, length: range.length - indent)
                stretches.append(HiddenStretch(range: range, pinsAfter: true))
            }
        default:
            break
        }

        for inline in block.inlines where inline.kind.isMarker {
            stretches.append(HiddenStretch(range: absolute(inline.range), pinsAfter: false))
        }

        // Markers that touch are one stretch: `**a**[b](c)` has no place for
        // the caret between its `**` and its `[`.
        var merged: [HiddenStretch] = []
        for stretch in stretches {
            if var last = merged.last, stretch.start <= last.end, !last.pinsAfter, !stretch.pinsAfter {
                last.range = NSRange(location: last.start, length: max(last.end, stretch.end) - last.start)
                merged[merged.count - 1] = last
            } else {
                merged.append(stretch)
            }
        }
        return merged
    }

    // MARK: Caret stops

    /// Where a caret that has landed on `offset` should stand.
    ///
    /// - Parameters:
    ///   - direction: `+1` or `-1` for a caret that moved one place by an
    ///     arrow key; `0` for a tap, or anywhere it didn't walk to. Arrow
    ///     keys have to leave a stretch the way they came in, or the caret
    ///     would stand still for as many presses as the stretch has characters.
    ///   - codeRanges: the note's code blocks, whose lines have no markers.
    ///
    /// The stop is the stretch's left edge for an inline marker, so the end
    /// of a bold word is inside the bold and its start isn't; for a heading's
    /// marker it is after it. Moving right out of an inline stretch goes to
    /// the character after it (one visible place), except at the line's end,
    /// where there is nothing after it and the caret goes just past the
    /// markers: the one way to type plain text after a bold word that ends
    /// its line.
    static func caretStop(for offset: Int, direction: Int, in text: NSString, codeRanges: [CodeRange]) -> Int {
        guard offset >= 0, offset <= text.length, !isCode(offset, in: codeRanges) else { return offset }

        let (stretches, line) = hiddenStretches(around: offset, in: text)
        guard let stretch = stretches.first(where: { offset >= $0.start && offset <= $0.end }) else { return offset }

        let atLineEnd = stretch.end >= NSMaxRange(line)

        if stretch.pinsAfter {
            if offset == stretch.end { return offset }
            if direction < 0, line.location > 0 { return line.location - 1 }
            return stretch.end
        }

        if offset == stretch.start { return offset }
        if direction > 0 {
            if atLineEnd { return stretch.end }
            return min(stretch.end + 1, text.length)
        }
        return stretch.start
    }

    // MARK: Backspace

    /// What Backspace does with a collapsed caret at `caret`, when that isn't
    /// the default of deleting the character before it. `nil` for the default.
    ///
    /// - At the start of a heading's text, or of a list item's, it removes
    ///   the marker: the line becomes body text. (The default would delete
    ///   the space after the `#`, leaving `#Title` as text.)
    /// - At the end of a span, in front of, inside or just past its closing
    ///   markers, it deletes the last visible character of the span. A span
    ///   emptied that way loses its markers too, or `****` would be left on
    ///   the page, and so do the spans around it that it empties.
    static func backspace(at caret: Int, in text: NSString, codeRanges: [CodeRange]) -> TextEdit? {
        guard caret > 0, caret <= text.length, !isCode(caret, in: codeRanges) else { return nil }

        let line = contentLine(containing: caret, in: text)
        guard line.length > 0 else { return nil }
        let lineText = text.substring(with: line)
        guard let block = DocumentParser.parse(lineText).first, !block.isCode else { return nil }

        func absolute(_ range: Range<String.Index>) -> NSRange {
            shifted(NSRange(range, in: lineText), by: line.location)
        }

        // A block marker, from the start of the text after it.
        if let marker = block.markerRange {
            let contentStart = line.location + NSRange(marker, in: lineText).upperBound
            if caret == contentStart {
                let indent = block.listDepth == nil ? 0 : indentation(of: lineText)
                let removed = NSRange(location: line.location + indent, length: contentStart - line.location - indent)
                return TextEdit(range: removed, replacement: "", selection: NSRange(location: removed.location, length: 0))
            }
        }

        // A span, from the end of its text: in front of its closing markers,
        // inside them or just past them. Backspace deletes the last letter on
        // the page before the caret, never a hidden marker, and a span it
        // empties goes with its markers, or `****` or `<span …></span>` would
        // be left on the page as text. Spans nest, so that can be several,
        // all holding that one letter: the outermost goes, taking the rest.
        let spans = InlineSpan.spans(in: block.inlines).map { span in
            (whole: absolute(span.range), content: absolute(span.contentRange), isRun: span.markup.isTag)
        }
        let drawn = block.inlines.filter { !$0.kind.isMarker }.map { absolute($0.range) }

        // The last letter on the page before the caret.
        guard let holder = drawn.last(where: { $0.location < caret }) else { return nil }
        let letter = NSIntersectionRange(text.rangeOfComposedCharacterSequence(at: min(NSMaxRange(holder), caret) - 1), holder)

        // The spans holding that letter and nothing else on the page.
        func drawnLength(in range: NSRange) -> Int {
            drawn.reduce(0) { $0 + NSIntersectionRange($1, range).length }
        }
        let emptied = spans.filter { NSLocationInRange(letter.location, $0.content) && drawnLength(in: $0.content) == letter.length }

        // Only from the end of a span's text. In front of a run's `</span>`
        // the ordinary delete does the same, unless it empties the run.
        let atAnEnd = spans.contains { span in
            let end = NSMaxRange(span.content)
            let from = span.isRun && !emptied.contains { $0.whole == span.whole } ? end + 1 : end
            return caret >= from && caret <= NSMaxRange(span.whole)
        }
        guard atAnEnd else { return nil }

        if let outermost = emptied.max(by: { $0.whole.length < $1.whole.length }) {
            return TextEdit(range: outermost.whole, replacement: "", selection: NSRange(location: outermost.whole.location, length: 0))
        }
        return TextEdit(range: letter, replacement: "", selection: NSRange(location: letter.location, length: 0))
    }
}

// MARK: - Nesting, boxes, links, and the state at the caret

extension MarkdownFormatting {

    /// Tab and ⇧Tab on list items: one level in or out, two spaces.
    ///
    /// Every line the selection touches has to be a list item or blank,
    /// or the key means something else (a tab character, or nothing).
    /// `nil` also when there's nothing to do, so ⇧Tab on an item that isn't
    /// nested gives the key back.
    static func indent(
        in text: NSString,
        selection: NSRange,
        outdent: Bool,
        codeRanges: [CodeRange]
    ) -> TextEdit? {
        guard !isCode(selection.location, in: codeRanges) else { return nil }
        let touched = lines(touching: selection, in: text)
        guard let first = touched.first else { return nil }

        var rewritten: [String] = []
        var deltas: [Int] = []
        var sawItem = false
        for line in touched {
            let lineText = text.substring(with: line)
            if isBlank(lineText) {
                rewritten.append(lineText)
                deltas.append(0)
                continue
            }
            guard DocumentParser.parse(lineText).first?.listMarker != nil else { return nil }
            sawItem = true

            if outdent {
                let removed = lineText.hasPrefix("\t") ? 1 : lineText.prefix(2).prefix { $0 == " " }.count
                rewritten.append(String(lineText.dropFirst(removed)))
                deltas.append(-removed)
            } else {
                rewritten.append("  " + lineText)
                deltas.append(2)
            }
        }
        guard sawItem, deltas.contains(where: { $0 != 0 }) else { return nil }

        let blockEnd = NSMaxRange(touched[touched.count - 1])
        // A selection that began at a line's start still takes in the whole line.
        let start = selection.length > 0 && selection.location == first.location
            ? first.location
            : max(first.location, selection.location + deltas[0])
        let end = max(start, NSMaxRange(selection) + deltas.reduce(0, +))
        return TextEdit(
            range: NSRange(location: first.location, length: blockEnd - first.location),
            replacement: rewritten.joined(separator: "\n"),
            selection: NSRange(location: start, length: end - start)
        )
    }

    /// Ticks or unticks the checkbox on the line holding `offset`. `nil` if
    /// the line has none. The selection is whatever the caller says it is
    /// afterwards: a tap on a box doesn't move the caret.
    static func toggleCheckbox(onLineAt offset: Int, in text: NSString, keeping selection: NSRange) -> TextEdit? {
        let line = contentLine(containing: offset, in: text)
        guard line.length >= 5 else { return nil }
        let lineText = text.substring(with: line)
        guard let block = DocumentParser.parse(lineText).first, case .checkbox(let checked)? = block.listMarker else { return nil }

        // `- [` then the mark.
        let mark = line.location + indentation(of: lineText) + 3
        return TextEdit(
            range: NSRange(location: mark, length: 1),
            replacement: checked ? " " : "x",
            selection: selection
        )
    }

    // MARK: Links

    /// The links on the line holding `offset`: the text that is the link, and
    /// where it goes, as written.
    static func links(onLineAt offset: Int, in text: NSString, codeRanges: [CodeRange]) -> [(text: NSRange, destination: String)] {
        guard !isCode(offset, in: codeRanges) else { return [] }
        let line = contentLine(containing: offset, in: text)
        guard line.length > 0 else { return [] }
        let lineText = text.substring(with: line)
        guard let block = DocumentParser.parse(lineText).first, !block.isCode else { return [] }

        return InlineSpan.spans(in: block.inlines).compactMap { span in
            guard span.markup == .link, let destination = span.destination else { return nil }
            return (shifted(NSRange(span.contentRange, in: lineText), by: line.location), String(lineText[destination]))
        }
    }

    // MARK: State at the caret

    /// What the hotbar shows lit: the formatting the next typed letter would
    /// have, or the whole selection has.
    struct CaretFormatting: Equatable, Sendable {
        var bold = false
        var italic = false
        var code = false
        var strikethrough = false
        var underline = false
        var link = false
        /// The colour of the run the caret is in (`TextColour`), or `nil`
        /// for none.
        var colour: Int?
        /// The colour of the highlight the caret is in, or `nil` for none.
        var highlight: HighlightColour?
        /// The size of the run the caret is in (`SpanSize`), or `nil` for
        /// normal size.
        var size: SpanSize?
        /// The sizes of the text the size control acts on, each once
        /// (`MarkdownFormatting.sizes`): one for a caret, more for a
        /// selection of text in several sizes. Empty in code.
        var sizes: [SizeSample] = []
        /// Whether the size control has anything to act on: not in code,
        /// and not a caret on no word and in no run.
        var canResize = false
        /// 1 to 6, or 0 for body text.
        var headingLevel = 0
        /// How many `>`s the line has, 0 for a line that isn't a quote.
        var quoteDepth = 0
        var list: ListStyle?
        /// What the caret is in, which decides what the text options row
        /// offers after the size stepper.
        var block = Block.paragraph

        /// The kinds of place the row has its own controls for.
        enum Block: Equatable, Sendable {
            /// A paragraph or a heading: Body, H1 to H3, Link.
            case paragraph
            /// A list item: the list kinds, outdent and indent.
            case listItem
            /// A code block. `kind` is `nil` for a tag the app doesn't know
            /// (it keeps its tag in the menu, ticking nothing). An unclosed
            /// block runs to the end of the note, so nothing can follow it.
            case code(label: String, kind: CodeBlockKind?, isClosed: Bool)
        }
    }

    /// The caret's formatting. Inline markers are never drawn in place, so
    /// this is where their state shows.
    ///
    /// A caret is in a span from just after its opening markers' first
    /// character to the end of its text, so the end of a bold word is bold
    /// and the start of one isn't, which is what typing there would produce.
    /// A selection has bold, italic, code or strikethrough when every
    /// character in it but spaces does, over every line, which is when the
    /// button takes it off (`toggle`); a link or a colour when it lies
    /// wholly inside one.
    static func formatting(at selection: NSRange, in text: NSString, codeRanges: [CodeRange]) -> CaretFormatting {
        var state = CaretFormatting()
        if let code = codeRanges.first(where: { $0.contains(NSRange(location: selection.location, length: 0)) }) {
            let kind: CodeBlockKind? = if let language = code.language {
                .language(language)
            } else if code.isOutput {
                .output
            } else {
                code.tag.isEmpty ? .plain : nil
            }
            state.block = .code(label: FenceTag.label(language: code.language, tag: code.tag), kind: kind, isClosed: code.isClosed)
            return state
        }
        guard selection.location <= text.length else { return state }
        (state.sizes, state.canResize) = sizes(at: selection, in: text, codeRanges: codeRanges)

        let line = contentLine(containing: selection.location, in: text)
        guard line.length > 0 else { return state }
        let lineText = text.substring(with: line)
        guard let block = DocumentParser.parse(lineText).first, !block.isCode else { return state }

        state.headingLevel = block.headingLevel ?? 0
        state.quoteDepth = block.quoteDepth ?? 0
        switch block.listMarker {
        case .bullet?:   state.list = .bullet
        case .ordered?:  state.list = .numbered
        case .checkbox?: state.list = .checklist
        case nil:        break
        }
        if state.list != nil { state.block = .listItem }

        // Spans nest, so the caret can be in several: bold and italic both
        // light up in `***x***`. A styled run is read by the same rule, and
        // runs inside runs as the styler draws them: the inner colour, the
        // sizes multiplied.
        var runs = InlineAttributes.plain
        for span in InlineSpan.spans(in: block.inlines) {
            let whole = shifted(NSRange(span.range, in: lineText), by: line.location)
            let content = shifted(NSRange(span.contentRange, in: lineText), by: line.location)
            let inside = selection.length == 0
                ? selection.location > whole.location && selection.location <= NSMaxRange(content)
                : selection.location >= content.location && NSMaxRange(selection) <= NSMaxRange(content)
            guard inside else { continue }

            switch span.markup {
            case .strong:        state.bold = true
            case .emphasis:      state.italic = true
            case .inlineCode:    state.code = true
            case .strikethrough: state.strikethrough = true
            case .underline:     state.underline = true
            case .link:          state.link = true
            case .styled, .highlight: runs = runs.inside(span.markup)
            }
        }
        state.colour = runs.colour
        state.size = runs.size
        state.highlight = runs.highlight

        if selection.length > 0, let styles = selectionStyles(selection, in: text, codeRanges: codeRanges) {
            state.bold = styles.bold
            state.italic = styles.italic
            state.code = styles.code
            state.strikethrough = styles.strikethrough
            state.underline = styles.underline
        }
        return state
    }

    /// Which of bold, italic, code, strikethrough and underline every glyph
    /// of the selection but spaces has, `nil` for a selection of none. Stops at the
    /// first line that settles it, since this runs on every selection change:
    /// reading a 500-line note as glyphs is about 6ms.
    private static func selectionStyles(_ selection: NSRange, in text: NSString, codeRanges: [CodeRange]) -> StyledLine.Style? {
        var all = StyledLine.Style(bold: true, italic: true, strikethrough: true, code: true, underline: true)
        var any = false
        for line in lines(touching: selection, in: text) {
            guard let part = lineParts(of: NSIntersectionRange(selection, NSRange(location: line.location, length: line.length + 1)), in: text, codeRanges: codeRanges, trimmingSpaces: false).first
            else { continue }
            for index in part.glyphs where !part.styled.glyphs[index].isSpace {
                let style = part.styled.glyphs[index].style
                any = true
                all.bold = all.bold && style.bold
                all.italic = all.italic && style.italic
                all.code = all.code && style.code
                all.strikethrough = all.strikethrough && style.strikethrough
                all.underline = all.underline && style.underline
            }
            if any, !all.bold, !all.italic, !all.code, !all.strikethrough, !all.underline { break }
        }
        return any ? all : nil
    }
}

// MARK: - Where a link goes

/// What a tap on a link opens.
nonisolated enum LinkTarget {

    /// The URL for a link's address as typed, or `nil` if it isn't one to
    /// open. Web addresses and mail only: a note someone shared mustn't be
    /// able to point a tap at `file:` or `javascript:`. An address with no
    /// scheme is taken for a web one (`example.com/notes`).
    static func url(for destination: String) -> URL? {
        let address = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }

        if let colon = address.firstIndex(of: ":") {
            let scheme = address[..<colon]
            let after = address[address.index(after: colon)...]
            let looksLikeScheme = scheme.first?.isLetter == true
                && scheme.allSatisfy { $0.isLetter || $0.isNumber || "+.-".contains($0) }
                && !(after.first?.isNumber ?? false)
            if looksLikeScheme {
                guard ["http", "https", "mailto"].contains(scheme.lowercased()) else { return nil }
                return URL(string: address)
            }
        }
        return URL(string: "https://" + address)
    }
}
