//
//  MarkdownFormatting.swift
//  NoteCode
//
//  What the hotbar's formatting buttons do to the text.
//

import Foundation

/// One replacement in the document, and where the selection lands after it.
///
/// Offsets are UTF-16, because `UITextView.selectedRange` is.
nonisolated struct TextEdit: Equatable, Sendable {
    /// The span of the *original* text being replaced.
    var range: NSRange
    var replacement: String
    /// The selection afterwards, in the *edited* text.
    var selection: NSRange

    /// The text with this edit made. The editor goes through `UITextView`
    /// instead, so the change lands on its undo stack; this is for tests.
    func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}

/// Turns a formatting button into an edit of the markdown source.
///
/// Formatting is markdown written into the text, not attributes laid over it:
/// the source is the document, and the styler draws whatever it says. So a
/// button is a function from (text, selection) to an edit — pure, and testable
/// without a text view, the same split `DocumentParser` makes.
///
/// Every decision defers to `DocumentParser` and `InlineParser`. A button that
/// writes something the parser then reads differently leaves the student
/// looking at markers that never render.
nonisolated enum MarkdownFormatting {

    enum InlineStyle: CaseIterable, Sendable {
        case bold, italic, strikethrough, code

        var marker: String {
            switch self {
            case .bold:          "**"
            case .italic:        "*"
            case .strikethrough: "~~"
            case .code:          "`"
            }
        }

        var markup: InlineMarkup {
            switch self {
            case .bold:          .strong
            case .italic:        .emphasis
            case .strikethrough: .strikethrough
            case .code:          .inlineCode
            }
        }

        /// What it sets on each character.
        var attribute: WritableKeyPath<StyledLine.Style, Bool> {
            switch self {
            case .bold:          \.bold
            case .italic:        \.italic
            case .strikethrough: \.strikethrough
            case .code:          \.code
            }
        }
    }

    // MARK: Inline styles

    /// Adds or removes an inline style, per character (text overhaul, phase
    /// 3; `StyledLine`).
    ///
    /// - A selection gains the style on exactly its characters, or loses it
    ///   if every one already has it. Spaces don't count either way: at the
    ///   end of a bold stretch they can't be bold. Styles combine: Italic on
    ///   a bold word makes it bold italic, and Bold again leaves it italic.
    ///   Over several lines, each line's part, blank lines and code left
    ///   alone.
    /// - A caret inside a span of the style takes the style off the whole
    ///   span. Inside a span of another style (a bold word, a link, code),
    ///   that span gains it.
    /// - Otherwise an empty pair goes in with the caret between, and pressing
    ///   again takes it back out. (Phase 4 replaces it with a typing style.)
    /// - Code spans and links are taken whole: half a link would be two.
    ///
    /// `nil` where there is nothing to do, or where the line can't be written
    /// to read as asked (a `*` typed as text beside the new markers).
    static func toggle(_ style: InlineStyle, in text: String, selection: NSRange, codeRanges: [CodeRange] = []) -> TextEdit? {
        let ns = text as NSString
        let selection = clamped(selection, to: ns.length)
        guard selection.length > 0 else {
            return toggle(style, atCaret: selection.location, in: ns, codeRanges: codeRanges)
        }

        let parts = lineParts(of: selection, in: ns, codeRanges: codeRanges, trimmingSpaces: false)
        let drawn = parts.flatMap { part in part.glyphs.map { part.styled.glyphs[$0] } }.filter { !$0.isSpace }
        guard !drawn.isEmpty else { return nil }
        // Mixed text gains the style, the rule a selection that is only
        // partly bold follows in any editor.
        let removing = drawn.allSatisfy { $0.style[keyPath: style.attribute] }
        return restyle(parts, in: ns, selection: selection) { glyph, _ in
            glyph[keyPath: style.attribute] = !removing
        }
    }

    private static func toggle(_ style: InlineStyle, atCaret caret: Int, in ns: NSString, codeRanges: [CodeRange]) -> TextEdit? {
        guard !isCode(caret, in: codeRanges) else { return nil }
        let markerLength = (style.marker as NSString).length

        // The empty pair a previous press left behind. `****` is text to the
        // parser, so the span search below can't see it.
        if isEmptyPair(of: style.marker, at: caret, in: ns) {
            return TextEdit(
                range: NSRange(location: caret - markerLength, length: markerLength * 2),
                replacement: "",
                selection: NSRange(location: caret - markerLength, length: 0)
            )
        }

        let line = contentLine(containing: caret, in: ns)
        if let styled = StyledLine(ns.substring(with: line)) {
            let local = caret - line.location
            // The spans the caret is in, ends included, outer first. A run's
            // tags aren't a style this sets.
            let around = InlineSpan.spans(in: styled.inlines).filter { span in
                let content = NSRange(span.contentRange, in: styled.line)
                return !span.markup.isStyled && local >= content.location && local <= NSMaxRange(content)
            }
            if let span = around.first(where: { $0.markup == style.markup }) ?? around.first {
                let content = NSRange(span.contentRange, in: styled.line)
                let glyphs = styled.wholeAtoms(styled.glyphCount(endingBy: content.location)..<styled.glyphCount(startingBefore: NSMaxRange(content)))
                let removing = span.markup == style.markup
                return restyle([LinePart(line: line, styled: styled, glyphs: glyphs)], in: ns, selection: NSRange(location: caret, length: 0)) { glyph, _ in
                    glyph[keyPath: style.attribute] = !removing
                }
            }
        }

        return TextEdit(
            range: NSRange(location: caret, length: 0),
            replacement: style.marker + style.marker,
            selection: NSRange(location: caret + markerLength, length: 0)
        )
    }

    /// True for `**|**`, and false for `***|***`, where taking the inner two
    /// away would leave something that isn't empty.
    private static func isEmptyPair(of marker: String, at location: Int, in ns: NSString) -> Bool {
        let length = (marker as NSString).length
        guard location >= length, location + length <= ns.length,
              ns.substring(with: NSRange(location: location - length, length: length)) == marker,
              ns.substring(with: NSRange(location: location, length: length)) == marker
        else { return false }

        let markerCharacter = (marker as NSString).character(at: 0)
        let before = location - length - 1
        let after = location + length
        if before >= 0, ns.character(at: before) == markerCharacter { return false }
        if after < ns.length, ns.character(at: after) == markerCharacter { return false }
        return true
    }

    // MARK: Line markers

    /// Makes the touched lines a heading of `level`, or body text for `0`.
    ///
    /// Pressing the level a line already has turns it back into body text, so
    /// one button both applies and removes.
    static func setHeading(level: Int, in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let touched = lines(touching: selection, in: ns)

        let alreadyThere = level > 0 && candidates(touched, in: ns).allSatisfy {
            heading(ns.substring(with: $0))?.level == level
        }
        let target = alreadyThere ? 0 : min(level, 6)
        let marker = target > 0 ? String(repeating: "#", count: target) + " " : ""

        return replaceMarkers(on: touched, in: ns, selection: selection) { line in
            LineMarker(indent: 0, length: heading(line)?.length ?? 0, replacement: marker)
        }
    }

    enum ListStyle: CaseIterable, Sendable {
        case bullet, numbered, checklist

        var title: String {
            switch self {
            case .bullet:    "Bulleted List"
            case .numbered:  "Numbered List"
            case .checklist: "Checklist"
            }
        }

        var systemImage: String {
            switch self {
            case .bullet:    "list.bullet"
            case .numbered:  "list.number"
            case .checklist: "checklist"
            }
        }

        func matches(_ marker: ListMarker) -> Bool {
            switch (self, marker) {
            case (.bullet, .bullet), (.numbered, .ordered), (.checklist, .checkbox): true
            default: false
            }
        }
    }

    /// Bullets the touched lines, or un-bullets them if every one already is.
    ///
    /// A numbered item becomes a bullet, rather than gaining one in front of
    /// its number. Indentation is kept, since it is what sets a list's depth.
    static func toggleBullet(in text: String, selection: NSRange) -> TextEdit {
        toggleList(.bullet, in: text, selection: selection)
    }

    /// Makes the touched lines a list of `style`, or takes the list off them
    /// if every one already is one. A line in another kind of list changes
    /// kind; numbers count the written lines from 1.
    static func toggleList(_ style: ListStyle, in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let touched = lines(touching: selection, in: ns)

        let allThere = candidates(touched, in: ns).allSatisfy {
            listItem(ns.substring(with: $0)).map { style.matches($0.kind) } == true
        }

        var number = 0
        return replaceMarkers(on: touched, in: ns, selection: selection) { line in
            let item = listItem(line)
            var marker = ""
            if !allThere {
                if !isBlank(line) { number += 1 }
                marker = switch style {
                case .bullet:    "- "
                case .numbered:  "\(number). "
                case .checklist: "- [ ] "
                }
            }
            return LineMarker(
                indent: item?.indent ?? indentation(of: line),
                length: item?.length ?? 0,
                replacement: marker
            )
        }
    }

    // MARK: Return, Tab, and checkboxes

    /// What Return does at a collapsed caret, when that isn't a plain newline.
    ///
    /// - In a list item with text, a new item follows: the same bullet, the
    ///   next number, or an empty box. Whatever follows the caret moves to it.
    /// - In an empty item, the list ends: the marker goes and the line is
    ///   left empty.
    /// - In a rendered note, at the end of a line whose last characters are a
    ///   closing marker, the newline goes after the marker. The caret stands
    ///   in front of it (inside the bold) and the page can't show that, so a
    ///   plain newline would have split `**` from its word.
    ///
    /// `nil` means a plain newline.
    static func returnEdit(
        in text: NSString,
        caret: Int,
        rendered: Bool,
        codeRanges: [CodeRange]
    ) -> TextEdit? {
        guard caret >= 0, caret <= text.length, !isCode(caret, in: codeRanges) else { return nil }

        let line = contentLine(containing: caret, in: text)
        let original = caret
        var caret = caret
        if rendered,
           let stretch = hiddenStretches(inLine: line, of: text).first(where: { !$0.pinsAfter && caret >= $0.start && caret <= $0.end }),
           stretch.end >= NSMaxRange(line) {
            caret = NSMaxRange(line)
        }

        let lineText = text.substring(with: line)
        if let block = DocumentParser.parse(lineText).first, let marker = block.listMarker, let markerRange = block.markerRange {
            let markerEnd = line.location + NSRange(markerRange, in: lineText).upperBound
            guard caret >= markerEnd else { return nil }

            let indent = String(lineText.prefix { $0 == " " || $0 == "\t" })
            let after = text.substring(with: NSRange(location: markerEnd, length: NSMaxRange(line) - markerEnd))

            if after.allSatisfy({ $0 == " " || $0 == "\t" }) {
                // Nothing after the marker: end the list.
                return TextEdit(range: line, replacement: "", selection: NSRange(location: line.location, length: 0))
            }

            let written = String(lineText[markerRange].dropFirst(indent.count))
            let next = nextMarker(after: marker, written: written)
            let insertion = "\n" + indent + next
            return TextEdit(
                range: NSRange(location: caret, length: 0),
                replacement: insertion,
                selection: NSRange(location: caret + (insertion as NSString).length, length: 0)
            )
        }

        // Not a list. Only a caret moved past closing markers needs an edit.
        guard caret != original else { return nil }
        return TextEdit(
            range: NSRange(location: caret, length: 0),
            replacement: "\n",
            selection: NSRange(location: caret + 1, length: 0)
        )
    }

    /// The marker the next item gets, given the one the line has as typed.
    private static func nextMarker(after marker: ListMarker, written: String) -> String {
        switch marker {
        case .bullet:
            return written
        case .ordered(let number):
            let digits = written.prefix { $0.isNumber }
            return "\(number + 1)" + written.dropFirst(digits.count)
        case .checkbox:
            return "\(written.first ?? "-") [ ] "
        }
    }

    /// The lines whose state decides a toggle: the written ones, unless the
    /// selection is only blank lines — then those, so a heading button on an
    /// empty line still has somewhere to go.
    private static func candidates(_ lines: [NSRange], in ns: NSString) -> [NSRange] {
        let written = lines.filter { !isBlank(ns.substring(with: $0)) }
        return written.isEmpty ? lines : written
    }

    private struct LineMarker {
        /// Leading whitespace to keep, in UTF-16 units.
        var indent: Int
        /// The marker already there after the indent, space included.
        var length: Int
        /// What replaces it. Empty removes it.
        var replacement: String
    }

    /// Rewrites the start of each line, and carries the selection across.
    ///
    /// Blank lines in a selection of several are left alone: bulleting three
    /// paragraphs shouldn't also bullet the gaps between them.
    private static func replaceMarkers(
        on lines: [NSRange],
        in ns: NSString,
        selection: NSRange,
        marker: (String) -> LineMarker
    ) -> TextEdit {
        let skipsBlankLines = lines.count > 1
        let blockStart = lines[0].location
        let blockEnd = NSMaxRange(lines[lines.count - 1])

        var rewritten: [String] = []
        var placements: [(old: Int, new: Int, change: LineMarker)] = []
        var newStart = blockStart

        for line in lines {
            let text = ns.substring(with: line) as NSString
            var change = marker(text as String)
            if skipsBlankLines, isBlank(text as String) {
                change = LineMarker(indent: 0, length: 0, replacement: "")
            }

            let result = text.substring(to: change.indent)
                + change.replacement
                + text.substring(from: change.indent + change.length)

            rewritten.append(result)
            placements.append((line.location, newStart, change))
            newStart += (result as NSString).length + 1
        }

        /// Where a position in the old text ends up. A caret inside the old
        /// marker lands just after the new one, at the start of the words.
        ///
        /// - Parameter keepsLineStart: for the start of a real selection. A
        ///   selection that began at the start of a line should still take
        ///   in the whole line, marker included.
        func map(_ position: Int, keepsLineStart: Bool = false) -> Int {
            guard let placement = placements.last(where: { $0.old <= position }) else { return position }
            let offset = position - placement.old
            let change = placement.change

            if offset < change.indent || (keepsLineStart && offset == 0) {
                return placement.new + offset
            }
            let past = max(offset - change.indent - change.length, 0)
            return placement.new + change.indent + (change.replacement as NSString).length + past
        }

        let start = map(selection.location, keepsLineStart: selection.length > 0)
        let end = map(NSMaxRange(selection))

        return TextEdit(
            range: NSRange(location: blockStart, length: blockEnd - blockStart),
            replacement: rewritten.joined(separator: "\n"),
            selection: NSRange(location: start, length: max(end - start, 0))
        )
    }

    /// A line's heading level and the length of its `## ` marker, as the
    /// parser reads it.
    private static func heading(_ line: String) -> (level: Int, length: Int)? {
        guard let block = DocumentParser.parse(line).first,
              let level = block.headingLevel,
              let marker = block.markerRange
        else { return nil }
        return (level, line[marker].utf16.count)
    }

    /// A list item's indentation and marker lengths, as the parser reads it.
    private static func listItem(_ line: String) -> (indent: Int, length: Int, kind: ListMarker)? {
        guard let block = DocumentParser.parse(line).first,
              let kind = block.listMarker,
              let marker = block.markerRange
        else { return nil }
        let indent = indentation(of: line)
        return (indent, line[marker].utf16.count - indent, kind)
    }

    static func indentation(of line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.utf16.count
    }

    // MARK: Code blocks

    /// Fences the selection as a code block, or opens an empty one at the caret.
    ///
    /// Fences only count at the start of a line, so the block gets a line of
    /// its own whatever was either side of it.
    static func insertCodeBlock(language: CodeLanguage?, in text: String, selection: NSRange) -> TextEdit {
        insertCodeBlock(tag: language?.rawValue, in: text, selection: selection)
    }

    /// `insertCodeBlock(language:in:selection:)` for any kind of block,
    /// Output and Plain Text included.
    static func insertCodeBlock(kind: CodeBlockKind, in text: String, selection: NSRange) -> TextEdit {
        insertCodeBlock(tag: kind.tag, in: text, selection: selection)
    }

    private static func insertCodeBlock(tag: String?, in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let selection = clamped(selection, to: ns.length)

        var body = ns.substring(with: selection)
        if body.hasSuffix("\n") { body.removeLast() }

        let before = selection.location > 0 && ns.character(at: selection.location - 1) != newline ? "\n" : ""
        let end = NSMaxRange(selection)
        let endsOnNewline = selection.length > 0 && ns.character(at: end - 1) == newline
        let after = end < ns.length && ns.character(at: end) != newline && !endsOnNewline ? "\n" : ""
        let trailing = endsOnNewline ? "\n" : after

        let opening = before + "```" + (tag ?? "") + "\n"
        let bodyStart = selection.location + (opening as NSString).length

        return TextEdit(
            range: selection,
            replacement: opening + body + "\n```" + trailing,
            selection: NSRange(location: bodyStart, length: (body as NSString).length)
        )
    }

    // MARK: Lines

    /// The lines `selection` touches, split the way `DocumentParser` splits
    /// them — on `\n` only — without their terminators.
    ///
    /// A selection that ends just past a newline stops at the line before it.
    /// Triple-clicking a line selects its newline too, and that shouldn't pull
    /// the next line in.
    static func lines(touching selection: NSRange, in ns: NSString) -> [NSRange] {
        let selection = clamped(selection, to: ns.length)

        var end = NSMaxRange(selection)
        if selection.length > 0, ns.character(at: end - 1) == newline {
            end -= 1
        }

        let previousBreak = ns.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: selection.location))
        let start = previousBreak.location == NSNotFound ? 0 : NSMaxRange(previousBreak)

        let nextBreak = ns.range(of: "\n", range: NSRange(location: end, length: ns.length - end))
        let stop = nextBreak.location == NSNotFound ? ns.length : nextBreak.location

        var ranges: [NSRange] = []
        var lineStart = start
        while true {
            let lineBreak = ns.range(of: "\n", range: NSRange(location: lineStart, length: stop - lineStart))
            guard lineBreak.location != NSNotFound else {
                ranges.append(NSRange(location: lineStart, length: stop - lineStart))
                return ranges
            }
            ranges.append(NSRange(location: lineStart, length: lineBreak.location - lineStart))
            lineStart = NSMaxRange(lineBreak)
        }
    }

    // MARK: Helpers

    static let newline = unichar(0x0A)

    static func isBlank(_ line: String) -> Bool {
        line.allSatisfy { $0 == " " || $0 == "\t" }
    }

    static func clamped(_ range: NSRange, to length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        return NSRange(location: location, length: min(max(range.length, 0), length - location))
    }

    static func shifted(_ range: NSRange, by offset: Int) -> NSRange {
        NSRange(location: range.location + offset, length: range.length)
    }
}

private extension NSRange {
    /// Whether `other` lies within this range, touching either end included —
    /// a caret right after `**bold` is still inside the bold.
    nonisolated func contains(_ other: NSRange) -> Bool {
        other.location >= location && NSMaxRange(other) <= NSMaxRange(self)
    }
}
