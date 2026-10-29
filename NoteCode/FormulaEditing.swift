//
//  FormulaEditing.swift
//  NoteCode
//
//  LaTeX, step 5 (docs/design/latex.md › Drawing, "Editing"): the rules for a
//  formula the note draws as one object. Where the caret may stand, what
//  Backspace deletes, how a selection is widened, what a tap lands on and what
//  the editor writes back. Pure: it works on the parse and the text, so it is
//  tested without a text view in the loop.
//
//  Only a formula the layout swaps (`FormulaValidity`) is one object. One that
//  can't be drawn shows its source dimmed, and is edited as the text it is.
//

import Foundation

nonisolated enum FormulaEditing {

    /// A formula the note draws as an attachment.
    struct Span: Equatable, Sendable {
        /// The whole formula, dollars included. For a block, from its opening
        /// `$$` to the end of its closing line (no line break).
        var range: NSRange
        /// The TeX between the dollars, as typed.
        var texRange: NSRange
        var tex: String
        /// `$$ … $$` mid-line, or a block: set in display style.
        var display: Bool
        /// A `$$` block on lines of its own.
        var isBlock: Bool

        var start: Int { range.location }
        var end: Int { NSMaxRange(range) }
    }

    // MARK: Finding formulas

    /// The drawable formulas in `blocks` that touch `window` (all of them for
    /// `nil`), in order. `source` is what `blocks` were parsed from.
    static func spans(in blocks: [BlockNode], source: String, touching window: NSRange? = nil) -> [Span] {
        let text = source as NSString
        var found: [Span] = []
        for block in blocks {
            if let window {
                let whole = NSRange(block.range, in: source)
                // A block's range ends at the start of the next line, which
                // the caret at its very end belongs to.
                guard NSIntersectionRange(whole, window).length > 0
                        || (window.location >= whole.location && window.location <= NSMaxRange(whole))
                else { continue }
            }
            if let math = block.mathBlock {
                guard FormulaValidity.check(String(source[math.contentRange])).isValid else { continue }
                let start = NSRange(math.openingRange, in: source).location
                let closing = NSRange(math.closingRange, in: source)
                let line = MarkdownFormatting.contentLine(containing: closing.location, in: text)
                found.append(Span(
                    range: NSRange(location: start, length: NSMaxRange(line) - start),
                    texRange: NSRange(math.contentRange, in: source),
                    tex: String(source[math.contentRange]),
                    display: true,
                    isBlock: true
                ))
                continue
            }
            let inlines = block.inlines
            var index = 0
            while index + 2 < inlines.count {
                guard case .opening(.math(let style)) = inlines[index].kind,
                      inlines[index + 1].kind == .text,
                      case .closing(.math) = inlines[index + 2].kind,
                      FormulaValidity.check(String(source[inlines[index + 1].range])).isValid
                else { index += 1; continue }
                let opening = NSRange(inlines[index].range, in: source)
                let closing = NSRange(inlines[index + 2].range, in: source)
                found.append(Span(
                    range: NSRange(location: opening.location, length: NSMaxRange(closing) - opening.location),
                    texRange: NSRange(inlines[index + 1].range, in: source),
                    tex: String(source[inlines[index + 1].range]),
                    display: style == .display,
                    isBlock: false
                ))
                index += 3
            }
        }
        return found
    }

    // MARK: Caret

    /// Where a caret that has landed on `offset` should stand, given the
    /// formulas. A formula is one place: inside it the caret has no spot, so it
    /// goes to the edge it came from (an arrow key, `direction` ±1) or the
    /// nearer one (a tap, `0`). Past a block's closing line it goes to the
    /// start of the line after, when there is one.
    static func caretStop(for offset: Int, direction: Int, spans: [Span], in text: NSString) -> Int {
        guard let span = spans.first(where: { offset > $0.start && offset <= $0.end }) else { return offset }
        // After an inline formula is a real place; so is the end of a block.
        if offset == span.end, !span.isBlock { return offset }
        let after = afterStop(of: span, in: text)
        if direction > 0 { return after }
        if direction < 0 { return span.start }
        return offset - span.start < span.end - offset ? span.start : after
    }

    /// The place after a formula: for a block, the start of the line below it.
    static func afterStop(of span: Span, in text: NSString) -> Int {
        if span.isBlock, span.end < text.length { return span.end + 1 }
        return span.end
    }

    /// A selection with each edge that falls inside a formula moved outwards,
    /// so no formula is ever half selected.
    static func snapped(_ selection: NSRange, spans: [Span], in text: NSString) -> NSRange {
        guard selection.length > 0 else { return selection }
        var start = selection.location
        var end = NSMaxRange(selection)
        for span in spans {
            if start > span.start, start < span.end { start = span.start }
            if end > span.start, end < span.end { end = afterStop(of: span, in: text) }
        }
        // A selection that ends at a block's line break takes the formula whole.
        for span in spans where span.isBlock && end == span.end && start < span.start { end = afterStop(of: span, in: text) }
        return NSRange(location: start, length: end - start)
    }

    // MARK: Backspace

    /// What Backspace does with a caret at `caret` just after a formula, or
    /// inside one: it deletes the whole formula, as one edit. `nil` for any
    /// other place.
    static func backspace(at caret: Int, spans: [Span], in text: NSString) -> TextEdit? {
        for span in spans {
            if caret > span.start, caret <= span.end {
                return TextEdit(range: span.range, replacement: "", selection: NSRange(location: span.start, length: 0))
            }
            // From the start of the line after a block, which the formula
            // fills: the block goes with the line break that follows it.
            if span.isBlock, caret == span.end + 1, span.end < text.length {
                let removed = NSRange(location: span.start, length: span.end + 1 - span.start)
                return TextEdit(range: removed, replacement: "", selection: NSRange(location: span.start, length: 0))
            }
        }
        return nil
    }

    // MARK: The editor's write-back

    /// What the editor writes for the TeX it was given.
    ///
    /// An inline formula is one line with no space against its dollars, or it
    /// would no longer parse as a formula; a dollar inside it is escaped, as
    /// the parser would otherwise end the formula there. A block keeps its
    /// lines, with the blank ones dropped.
    static func cleaned(_ tex: String, isBlock: Bool) -> String {
        var text = tex.replacingOccurrences(of: "\r\n", with: "\n")
        text = escapeDollars(in: text)
        if isBlock {
            return text.split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func escapeDollars(in text: String) -> String {
        var result = ""
        var escaped = false
        for character in text {
            if character == "$", !escaped { result += "\\" }
            escaped = character == "\\" && !escaped
            result.append(character)
        }
        return result
    }

    /// The edit that replaces the TeX of `span` with `tex` (already
    /// `cleaned`), keeping the whitespace that padded it (`$$ x $$`, or the
    /// line breaks of a block). The caret lands after the formula.
    static func replacing(_ span: Span, with tex: String, in text: NSString) -> TextEdit {
        let old = text.substring(with: span.texRange) as NSString
        var lead = 0
        while lead < old.length, isSpace(old.character(at: lead)) { lead += 1 }
        var trail = 0
        while trail < old.length - lead, isSpace(old.character(at: old.length - 1 - trail)) { trail += 1 }
        let range = NSRange(location: span.texRange.location + lead, length: old.length - lead - trail)
        let length = (tex as NSString).length
        return TextEdit(
            range: range,
            replacement: tex,
            selection: NSRange(location: span.end - range.length + length, length: 0)
        )
    }

    private static func isSpace(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D
    }

    /// The edit that removes `span` altogether (a block with its line break).
    static func removing(_ span: Span, in text: NSString) -> TextEdit {
        var range = span.range
        if span.isBlock, span.end < text.length { range.length += 1 }
        return TextEdit(range: range, replacement: "", selection: NSRange(location: range.location, length: 0))
    }

    /// The edit that inserts a new formula for `tex` (already `cleaned`) over
    /// `selection`. A block takes lines of its own.
    static func inserting(_ tex: String, display: Bool, over selection: NSRange, in text: NSString) -> TextEdit {
        guard display else {
            let formula = "$" + tex + "$"
            return TextEdit(
                range: selection,
                replacement: formula,
                selection: NSRange(location: selection.location + (formula as NSString).length, length: 0)
            )
        }
        let beforeLine = MarkdownFormatting.contentLine(containing: selection.location, in: text)
        let atLineStart = selection.location == beforeLine.location
        let afterOffset = NSMaxRange(selection)
        let afterLine = MarkdownFormatting.contentLine(containing: afterOffset, in: text)
        let atLineEnd = afterOffset == NSMaxRange(afterLine)

        let formula = "$$\n" + tex + "\n$$"
        let replacement = (atLineStart ? "" : "\n") + formula + (atLineEnd ? "" : "\n")
        return TextEdit(
            range: selection,
            replacement: replacement,
            selection: NSRange(location: selection.location + (replacement as NSString).length, length: 0)
        )
    }
}
