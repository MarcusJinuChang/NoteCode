//
//  MarkdownFormatting+Style.swift
//  NoteCode
//
//  The text options row's colour and size: wraps text in a styled run,
//  restyles a run, or takes a style off it (`SpanStyle`). Pure, like the
//  rest of `MarkdownFormatting`: it computes a `TextEdit`, and the editor
//  applies it through the text view, so it undoes like typing.
//

import Foundation

extension MarkdownFormatting {

    /// The point size of each kind of block's text, which a size chosen in
    /// points is written against (`SpanSize`): the note's, from its
    /// typography, since the same 24 is a different em in a heading.
    struct BlockSizes: Equatable, Sendable {
        var body: Double
        /// Heading levels 1 to 6.
        var headings: [Double]

        /// A heading's size, or the body's for level 0 and for a list item.
        func size(forHeadingLevel level: Int) -> Double {
            headings.indices.contains(level - 1) ? headings[level - 1] : body
        }
    }

    /// What a colour or size control changes: one of a run's two settings,
    /// to a value or to none. The other is kept.
    enum StyleChange: Equatable, Sendable {
        case colour(Int?)
        case size(SpanSize?)
        /// A size in points, written on each line against that line's own
        /// text (`BlockSizes`), so a selection from a heading into a
        /// paragraph comes out one size. `nil` is the text's own size.
        case points(Double?, BlockSizes)
        /// + and −: each character this many points bigger or smaller than
        /// it is, so text in several sizes keeps them apart. Stops at the
        /// control's ends (`SpanSize.stepped`).
        case steps(Int, BlockSizes)

        /// The change made to one character, in a block whose heading level
        /// is `headingLevel` (0 for body text).
        func apply(to style: inout StyledLine.Style, headingLevel: Int) {
            switch self {
            case .colour(let colour):
                style.colour = colour
            case .size(let size):
                style.size = size
            case .points(let points, let sizes):
                style.size = points.flatMap { SpanSize(points: $0, against: sizes.size(forHeadingLevel: headingLevel)) }
            case .steps(let steps, let sizes):
                let base = sizes.size(forHeadingLevel: headingLevel)
                guard let next = SpanSize.stepped(SpanSize.points(style.size, against: base), by: steps) else { return }
                style.size = SpanSize(points: next, against: base)
            }
        }
    }

    /// Sets `hex` on the selection, the run the caret is in or the word at
    /// the caret; `nil` takes colour off them instead. See `style`.
    static func colour(_ hex: Int?, selection: NSRange, in text: NSString, codeRanges: [CodeRange]) -> TextEdit? {
        style(.colour(hex), selection: selection, in: text, codeRanges: codeRanges)
    }

    /// Sets `size` on the selection, the run the caret is in or the word at
    /// the caret; `nil` makes them normal size again. See `style`.
    static func size(_ size: SpanSize?, selection: NSRange, in text: NSString, codeRanges: [CodeRange]) -> TextEdit? {
        style(.size(size), selection: selection, in: text, codeRanges: codeRanges)
    }

    /// Sets the selection, the run the caret is in or the word at the caret
    /// at `points`, against each line's own text; `nil`, or the text's own
    /// size, makes them normal size again. What the size control does.
    static func size(
        points: Double?,
        blockSizes: BlockSizes,
        selection: NSRange,
        in text: NSString,
        codeRanges: [CodeRange]
    ) -> TextEdit? {
        style(.points(points, blockSizes), selection: selection, in: text, codeRanges: codeRanges)
    }

    /// Makes each character of the selection, the run the caret is in or the
    /// word at the caret `steps` points bigger or smaller than it is, against
    /// each line's own text: + and −.
    static func size(
        steppedBy steps: Int,
        blockSizes: BlockSizes,
        selection: NSRange,
        in text: NSString,
        codeRanges: [CodeRange]
    ) -> TextEdit? {
        style(.steps(steps, blockSizes), selection: selection, in: text, codeRanges: codeRanges)
    }

    /// Changes the selection's colour or size, or the word the caret is
    /// inside, per character (text overhaul, phases 3 and 4; `StyledLine`).
    ///
    /// - Exactly the selected characters, less spaces at either end, and
    ///   each line's part of a selection over several, never the heading's
    ///   `#` or a list item's marker. Half a bold word can be red.
    /// - A caret strictly inside a word changes the word; anywhere else it
    ///   changes nothing here, and the control sets the typing style instead
    ///   (`caretTarget`, `TypingStyle`).
    /// - Each character keeps its other settings: a large red run made blue
    ///   stays large. One that loses its last setting leaves its run.
    /// - Code spans and links are taken whole.
    ///
    /// `nil` where there is nothing to do: in code, a caret not inside a
    /// word, taking off what nothing has, or a line that can't be written
    /// to read as asked.
    static func style(_ change: StyleChange, selection: NSRange, in text: NSString, codeRanges: [CodeRange]) -> TextEdit? {
        let selection = clamped(selection, to: text.length)
        guard !codeRanges.contains(where: { NSIntersectionRange($0.range, selection).length > 0 || $0.contains(selection) })
        else { return nil }

        var parts: [LinePart] = []
        for line in lines(touching: selection, in: text) {
            let lineText = text.substring(with: line)
            guard let runs = LineRuns(lineText), let styled = StyledLine(lineText) else { continue }
            // The selection's part of this line, in the line's offsets:
            // clipped first, since an NSRange can't start before 0.
            var glyphs: Range<Int>
            if selection.length == 0 {
                guard let word = styled.wordGlyphs(atCaret: selection.location - line.location) else { continue }
                glyphs = styled.wholeAtoms(word)
            } else {
                let start = max(selection.location, line.location)
                let end = min(NSMaxRange(selection), NSMaxRange(line))
                guard end > start,
                      let target = runs.target(of: NSRange(location: start - line.location, length: end - start))
                else { continue }
                glyphs = styled.wholeAtoms(
                    styled.glyphCount(endingBy: target.location)..<styled.glyphCount(startingBefore: NSMaxRange(target))
                )
            }
            guard !glyphs.isEmpty else { continue }
            parts.append(LinePart(line: line, styled: styled, glyphs: glyphs))
        }
        return restyle(parts, in: text, selection: selection) { glyph, part in
            change.apply(to: &glyph, headingLevel: part.styled.headingLevel)
        }
    }

    // MARK: Restyling lines

    /// One line's part in a change: the line read as glyphs, and the glyphs
    /// the change acts on.
    struct LinePart {
        var line: NSRange
        var styled: StyledLine
        var glyphs: Range<Int>
    }

    /// Each touched line's part of `selection` as glyphs, out to whole code
    /// spans and links: lines of code, blank lines and lines with nothing
    /// selected after their marker left out. `trimmingSpaces` leaves out
    /// spaces at either end of each part.
    static func lineParts(of selection: NSRange, in text: NSString, codeRanges: [CodeRange], trimmingSpaces: Bool) -> [LinePart] {
        lines(touching: selection, in: text).compactMap { line in
            guard !codeRanges.contains(where: { $0.contains(NSRange(location: line.location, length: 0)) }),
                  let styled = StyledLine(text.substring(with: line))
            else { return nil }
            let start = max(selection.location, line.location) - line.location
            let end = min(NSMaxRange(selection), NSMaxRange(line)) - line.location
            guard end > start else { return nil }
            var lower = styled.glyphCount(endingBy: start)
            var upper = styled.glyphCount(startingBefore: end)
            if trimmingSpaces {
                while lower < upper, styled.glyphs[lower].text.allSatisfy(\.isWhitespace) { lower += 1 }
                while upper > lower, styled.glyphs[upper - 1].text.allSatisfy(\.isWhitespace) { upper -= 1 }
            }
            guard lower < upper else { return nil }
            return LinePart(line: line, styled: styled, glyphs: styled.wholeAtoms(lower..<upper))
        }
    }

    /// The edit that makes `change` to each part's glyphs, written back
    /// line by line (`StyledLine.restyled`).
    ///
    /// The selection afterwards runs from the first changed character to the
    /// last, after the markers in front and before the ones behind; a caret
    /// stays in front of the character it was in front of, before any
    /// markers there, which is where the caret stops anyway. `nil` where no
    /// line changes. A line that can't be written to read as asked is left
    /// as it was.
    static func restyle(
        _ parts: [LinePart],
        in text: NSString,
        selection: NSRange,
        change: (inout StyledLine.Style, LinePart) -> Void
    ) -> TextEdit? {
        var rewritten: [(part: LinePart, read: StyledLine?)] = []
        for part in parts {
            var styles = part.styled.glyphs.map(\.style)
            for index in part.glyphs { change(&styles[index], part) }
            rewritten.append((part, part.styled.restyled(styles)))
        }
        guard let first = rewritten.first, let last = rewritten.last, rewritten.contains(where: { $0.read != nil })
        else { return nil }

        // The lines, rewritten, and the text between them as it was.
        let whole = NSRange(location: first.part.line.location, length: NSMaxRange(last.part.line) - first.part.line.location)
        var replacement = ""
        var starts: [Int] = []          // where each part's line starts in the new text
        var cursor = whole.location
        for (part, read) in rewritten {
            replacement += text.substring(with: NSRange(location: cursor, length: part.line.location - cursor))
            starts.append(whole.location + (replacement as NSString).length)
            replacement += read?.line ?? text.substring(with: part.line)
            cursor = NSMaxRange(part.line)
        }

        /// A place in front of glyph `index` of a part's line, in the new
        /// text: after any markers there, or before them.
        func position(_ item: Int, glyph index: Int, afterMarkers: Bool) -> Int {
            let styled = rewritten[item].read ?? rewritten[item].part.styled
            return starts[item] + (afterMarkers ? styled.latestPosition(at: index) : styled.earliestPosition(at: index))
        }

        let newSelection: NSRange
        if selection.length == 0 {
            let local = selection.location - first.part.line.location
            newSelection = NSRange(location: position(0, glyph: first.part.styled.glyphCount(endingBy: local), afterMarkers: false), length: 0)
        } else {
            let start = position(0, glyph: first.part.glyphs.lowerBound, afterMarkers: true)
            let end = position(rewritten.count - 1, glyph: last.part.glyphs.upperBound, afterMarkers: false)
            newSelection = NSRange(location: start, length: max(0, end - start))
        }

        let edit = minimalEdit(replacing: whole, with: replacement, in: text)
        return TextEdit(range: edit.range, replacement: edit.replacement, selection: newSelection)
    }

    /// `range` replaced with `replacement`, less what the two share at either
    /// end, so the edit touches only what changes. Never between the two
    /// halves of a surrogate pair.
    static func minimalEdit(replacing range: NSRange, with replacement: String, in text: NSString) -> (range: NSRange, replacement: String) {
        let old = Array(text.substring(with: range).utf16)
        let new = Array(replacement.utf16)
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        if prefix > 0, UTF16.isLeadSurrogate(old[prefix - 1]) { prefix -= 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        if suffix > 0, UTF16.isTrailSurrogate(old[old.count - suffix]) { suffix -= 1 }
        let kept = String(decoding: new[prefix..<(new.count - suffix)], as: UTF16.self)
        return (NSRange(location: range.location + prefix, length: old.count - suffix - prefix), kept)
    }

    // MARK: A line's runs

    /// A styled run on a line: its two tags and its style, in the line's
    /// offsets.
    struct StyledRun: Equatable {
        var open: NSRange
        var close: NSRange
        var style: SpanStyle

        /// The text between the tags.
        var text: NSRange { NSRange(location: NSMaxRange(open), length: close.location - NSMaxRange(open)) }
        /// The tags and the text.
        var whole: NSRange { NSRange(location: open.location, length: NSMaxRange(close) - open.location) }
    }

    /// One line read for colour and size: its block's text, its spans and
    /// its styled runs, in the line's own offsets. `nil` for a line of code
    /// or nothing.
    struct LineRuns {
        var line: NSString
        var headingLevel: Int
        var content: NSRange
        /// Every span but a run, markers included: bold, code, links.
        var spans: [NSRange] = []
        /// The runs, an outer one before those inside it.
        var runs: [StyledRun] = []
        /// The text that is drawn, each piece with its size against the
        /// block's.
        var text: [(range: NSRange, size: SpanSize?)] = []

        init?(_ line: String) {
            // A blank line has no block, and is a line of nothing to size where
            // the typing style goes.
            let parsed = DocumentParser.parse(line).first
            guard !(parsed?.isCode ?? false), parsed != nil || line.isEmpty else { return nil }
            let block = parsed ?? BlockNode(kind: .paragraph(inlines: []), range: line.startIndex..<line.endIndex, contentRange: line.startIndex..<line.endIndex)
            self.line = line as NSString
            headingLevel = block.headingLevel ?? 0
            content = NSRange(block.contentRange, in: line)
            for span in InlineSpan.spans(in: block.inlines) {
                guard case .styled(let style) = span.markup else {
                    spans.append(NSRange(span.range, in: line))
                    continue
                }
                let open = NSRange(span.range.lowerBound..<span.contentRange.lowerBound, in: line)
                let close = NSRange(span.contentRange.upperBound..<span.range.upperBound, in: line)
                runs.append(StyledRun(open: open, close: close, style: style))
            }
            text = block.inlines.filter { !$0.kind.isMarker }.map { (NSRange($0.range, in: line), $0.attributes.size) }
        }

        /// The run a caret at `offset` is in: from just after its opening
        /// tag's first character to the start of its closing tag. The
        /// outermost, where runs nest.
        func run(atCaret offset: Int) -> StyledRun? {
            runs.first { offset > $0.open.location && offset <= $0.close.location }
        }

        /// The size of the text a caret at `offset` is in, by the same rule:
        /// every run it is in, multiplied.
        func size(atCaret offset: Int) -> SpanSize? {
            runs.filter { offset > $0.open.location && offset <= $0.close.location }
                .reduce(InlineAttributes.plain) { $0.inside(.styled($1.style)) }
                .size
        }

        /// What a change acts on a selection, before the runs and spans it
        /// reaches are taken in: its part of the block's text less spaces at
        /// either end. `selection` is in the line's offsets and may run past
        /// either end. `nil` for a selection of spaces or markers alone. (A
        /// caret acts on the word it is inside, `StyledLine.wordGlyphs`, or
        /// sets the typing style.)
        func target(of selection: NSRange) -> NSRange? {
            guard selection.length > 0 else { return nil }
            var target = NSIntersectionRange(selection, content)
            guard target.length > 0 else { return nil }
            while target.length > 0, line.character(at: target.location) == 32 {
                target = NSRange(location: target.location + 1, length: target.length - 1)
            }
            while target.length > 0, line.character(at: NSMaxRange(target) - 1) == 32 {
                target.length -= 1
            }
            return target.length > 0 ? target : nil
        }

        /// Whether `range` holds anything but white space.
        func hasText(in range: NSRange) -> Bool {
            range.length > 0 && line.substring(with: range).contains { !$0.isWhitespace }
        }
    }

    // MARK: Reading sizes

    /// The size of some of the text a size control acts on: the block it
    /// is in (a heading's level, 0 for body text and list items) and its
    /// run's size. The control turns it into points with the note's fonts.
    struct SizeSample: Hashable, Sendable {
        var headingLevel: Int
        var size: SpanSize?
    }

    /// The sizes of the text the size control would act on, in the order
    /// they come, each once; and whether there is anything for it to act on.
    ///
    /// A caret has one: the size of the run it is in, or its block's, even
    /// where nothing would change (so the control can say what size the
    /// text there is). A selection has one for each size its text is in, by
    /// line, spaces and tags not counted. Nothing in or across code, where
    /// sizes don't go.
    static func sizes(at selection: NSRange, in text: NSString, codeRanges: [CodeRange]) -> (samples: [SizeSample], hasTarget: Bool) {
        let selection = clamped(selection, to: text.length)
        guard !codeRanges.contains(where: { NSIntersectionRange($0.range, selection).length > 0 || $0.contains(selection) })
        else { return ([], false) }

        var samples: [SizeSample] = []
        var hasTarget = false
        func add(_ sample: SizeSample) {
            if !samples.contains(sample) { samples.append(sample) }
        }

        for line in lines(touching: selection, in: text) {
            guard let parsed = LineRuns(text.substring(with: line)) else { continue }
            let local: NSRange
            if selection.length == 0 {
                // A caret has something to size anywhere in prose: the word
                // it is inside, or the typing style.
                local = NSRange(location: selection.location - line.location, length: 0)
                add(SizeSample(headingLevel: parsed.headingLevel, size: parsed.size(atCaret: local.location)))
                hasTarget = true
                continue
            }
            let start = max(selection.location, line.location)
            let end = min(NSMaxRange(selection), NSMaxRange(line))
            guard end > start else { continue }
            local = NSRange(location: start - line.location, length: end - start)
            guard let target = parsed.target(of: local) else { continue }
            hasTarget = true

            // The selected text that is drawn, markers and tags left out, in
            // the order it comes on the line.
            for piece in parsed.text where parsed.hasText(in: NSIntersectionRange(target, piece.range)) {
                add(SizeSample(headingLevel: parsed.headingLevel, size: piece.size))
            }
        }
        return (samples, hasTarget)
    }

    /// The word `offset` is in or against: letters, digits and the
    /// underscore of an identifier, as Link takes it.
    fileprivate static func word(at offset: Int, in text: NSString) -> NSRange {
        func isWordCharacter(at index: Int) -> Bool {
            guard index >= 0, index < text.length else { return false }
            let unit = text.character(at: index)
            guard let scalar = Unicode.Scalar(unit) else { return unit >= 0xD800 }  // half of a pair
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }
        var start = offset
        var end = offset
        while isWordCharacter(at: start - 1) { start -= 1 }
        while isWordCharacter(at: end) { end += 1 }
        return NSRange(location: start, length: end - start)
    }
}
