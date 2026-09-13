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

        var kind: InlineNode.Kind {
            switch self {
            case .bold:          .strong
            case .italic:        .emphasis
            case .strikethrough: .strikethrough
            case .code:          .inlineCode
            }
        }
    }

    // MARK: Inline styles

    /// Adds or removes an inline style.
    ///
    /// - Inside a span of this style, the span's markers come off.
    /// - Inside a span of a different style, its markers are swapped for this
    ///   one's. `InlineParser` doesn't nest spans, so bold-inside-italic would
    ///   render as neither; replacing is the version that shows what it says.
    /// - Otherwise the selection is wrapped. With nothing selected an empty pair
    ///   goes in with the caret between, and pressing again takes it back out.
    /// - A selection across lines is styled a line at a time. A span can't
    ///   cross a line, so wrapping the whole selection would leave two markers
    ///   that never pair up.
    static func toggle(_ style: InlineStyle, in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let selection = clamped(selection, to: ns.length)

        if ns.substring(with: selection).contains("\n") {
            return toggleAcrossLines(style, in: ns, selection: selection)
        }

        let markerLength = (style.marker as NSString).length

        // The empty pair a previous press left behind. `****` is text to the
        // parser, so the span search below can't see it.
        if selection.length == 0, isEmptyPair(of: style.marker, at: selection.location, in: ns) {
            return TextEdit(
                range: NSRange(location: selection.location - markerLength, length: markerLength * 2),
                replacement: "",
                selection: NSRange(location: selection.location - markerLength, length: 0)
            )
        }

        let line = lines(touching: selection, in: ns)[0]
        let lineText = ns.substring(with: line)

        for node in InlineParser.parse(lineText, in: lineText.startIndex..<lineText.endIndex) where node.kind != .text {
            let whole = shifted(NSRange(node.range, in: lineText), by: line.location)
            let content = shifted(NSRange(node.contentRange, in: lineText), by: line.location)
            let selectsWhole = selection == whole
            guard selectsWhole || content.contains(selection) else { continue }

            let marker = node.kind == style.kind ? "" : style.marker
            let newMarkerLength = (marker as NSString).length
            let oldMarkerLength = content.location - whole.location

            return TextEdit(
                range: whole,
                replacement: marker + ns.substring(with: content) + marker,
                selection: selectsWhole
                    ? NSRange(location: whole.location + newMarkerLength, length: content.length)
                    : NSRange(location: selection.location - oldMarkerLength + newMarkerLength, length: selection.length)
            )
        }

        return TextEdit(
            range: selection,
            replacement: style.marker + ns.substring(with: selection) + style.marker,
            selection: NSRange(location: selection.location + markerLength, length: selection.length)
        )
    }

    private static func toggleAcrossLines(_ style: InlineStyle, in ns: NSString, selection: NSRange) -> TextEdit {
        let segments = ns.substring(with: selection).components(separatedBy: "\n")
        let written = segments.filter { !isBlank($0) }

        // Mixed lines get the style added, not removed — the same rule a
        // selection that is only partly bold follows in any editor.
        let removing = !written.isEmpty && written.allSatisfy { soleSpan(in: $0)?.kind == style.kind }

        let rewritten = segments.map { segment -> String in
            guard !isBlank(segment) else { return segment }

            guard let span = soleSpan(in: segment) else {
                return style.marker + segment + style.marker
            }

            let inner = String(segment[span.contentRange])
            if removing { return inner }
            if span.kind == style.kind { return segment }
            return style.marker + inner + style.marker
        }

        let replacement = rewritten.joined(separator: "\n")
        return TextEdit(
            range: selection,
            replacement: replacement,
            selection: NSRange(location: selection.location, length: (replacement as NSString).length)
        )
    }

    /// The single span that makes up all of `segment`, if it is exactly one.
    private static func soleSpan(in segment: String) -> InlineNode? {
        let nodes = InlineParser.parse(segment, in: segment.startIndex..<segment.endIndex)
        guard nodes.count == 1, let node = nodes.first, node.kind != .text else { return nil }
        return node
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

    /// Bullets the touched lines, or un-bullets them if every one already is.
    ///
    /// A numbered item becomes a bullet, rather than gaining one in front of
    /// its number. Indentation is kept, since it is what sets a list's depth.
    static func toggleBullet(in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let touched = lines(touching: selection, in: ns)

        let allBulleted = candidates(touched, in: ns).allSatisfy {
            listItem(ns.substring(with: $0))?.isBullet == true
        }
        let marker = allBulleted ? "" : "- "

        return replaceMarkers(on: touched, in: ns, selection: selection) { line in
            let item = listItem(line)
            return LineMarker(
                indent: item?.indent ?? indentation(of: line),
                length: item?.length ?? 0,
                replacement: marker
            )
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
    private static func listItem(_ line: String) -> (indent: Int, length: Int, isBullet: Bool)? {
        guard let block = DocumentParser.parse(line).first,
              let kind = block.listMarker,
              let marker = block.markerRange
        else { return nil }
        let indent = indentation(of: line)
        return (indent, line[marker].utf16.count - indent, kind == .bullet)
    }

    private static func indentation(of line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.utf16.count
    }

    // MARK: Code blocks

    /// Fences the selection as a code block, or opens an empty one at the caret.
    ///
    /// Fences only count at the start of a line, so the block gets a line of
    /// its own whatever was either side of it.
    static func insertCodeBlock(language: CodeLanguage?, in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let selection = clamped(selection, to: ns.length)

        var body = ns.substring(with: selection)
        if body.hasSuffix("\n") { body.removeLast() }

        let before = selection.location > 0 && ns.character(at: selection.location - 1) != newline ? "\n" : ""
        let end = NSMaxRange(selection)
        let endsOnNewline = selection.length > 0 && ns.character(at: end - 1) == newline
        let after = end < ns.length && ns.character(at: end) != newline && !endsOnNewline ? "\n" : ""
        let trailing = endsOnNewline ? "\n" : after

        let opening = before + "```" + (language?.rawValue ?? "") + "\n"
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

    private static let newline = unichar(0x0A)

    private static func isBlank(_ line: String) -> Bool {
        line.allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func clamped(_ range: NSRange, to length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        return NSRange(location: location, length: min(max(range.length, 0), length - location))
    }

    private static func shifted(_ range: NSRange, by offset: Int) -> NSRange {
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
