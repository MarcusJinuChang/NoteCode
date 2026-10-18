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

        func applied(to style: SpanStyle, headingLevel: Int) -> SpanStyle {
            var style = style
            switch self {
            case .colour(let colour): style.colour = colour
            case .size(let size):     style.size = size
            case .points(let points, let sizes):
                style.size = points.flatMap { SpanSize(points: $0, against: sizes.size(forHeadingLevel: headingLevel)) }
            }
            return style
        }

        /// Whether it takes its setting off rather than putting one on.
        var clears: Bool {
            switch self {
            case .colour(let colour):    colour == nil
            case .size(let size):        size == nil
            case .points(let points, _): points == nil
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

    /// Changes the selection's colour or size, or the run the caret is in,
    /// or the word at the caret.
    ///
    /// - A run per line: a selection over several lines styles each line's
    ///   part of it, never the heading's `#` or a list item's marker.
    /// - Runs aren't written nested. A run the text overlaps is taken off and
    ///   its text joins the rest, keeping its other setting: a large red run
    ///   made blue stays large. So restyling part of a run restyles it all.
    /// - A run never cuts a span in two: one the text runs into (half of a
    ///   bold word, say) is taken in whole, since a span can't cross a run's
    ///   edge and would show its markers.
    ///
    /// `nil` where there is nothing to do: in code, a caret on no word and in
    /// no run, or taking off what nothing has.
    static func style(_ change: StyleChange, selection: NSRange, in text: NSString, codeRanges: [CodeRange]) -> TextEdit? {
        let selection = clamped(selection, to: text.length)
        guard !codeRanges.contains(where: { NSIntersectionRange($0.range, selection).length > 0 || $0.contains(selection) })
        else { return nil }

        let lines = lines(touching: selection, in: text)
        guard let first = lines.first, let last = lines.last else { return nil }

        var rewritten: [String] = []
        var coloured: [NSRange?] = []      // per line, the styled text in the new line
        var caretAt: Int?                  // for a caret, its place in the new line
        for line in lines {
            let lineText = text.substring(with: line)
            // The selection's part of this line, in the line's offsets:
            // clipped first, since an NSRange can't start before 0.
            let local: NSRange
            if selection.length == 0 {
                local = NSRange(location: selection.location - line.location, length: 0)
            } else {
                let start = max(selection.location, line.location)
                let end = min(NSMaxRange(selection), NSMaxRange(line))
                guard end > start else {
                    rewritten.append(lineText)
                    coloured.append(nil)
                    continue
                }
                local = NSRange(location: start - line.location, length: end - start)
            }
            guard let result = styleLine(lineText, selection: local, change: change) else {
                rewritten.append(lineText)
                coloured.append(nil)
                continue
            }
            rewritten.append(result.text)
            coloured.append(result.coloured)
            caretAt = result.caret
        }

        let replacement = rewritten.joined(separator: "\n")
        let whole = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        guard replacement != text.substring(with: whole) else { return nil }

        // Where each new line starts, to place the selection afterwards.
        var starts: [Int] = []
        var position = first.location
        for line in rewritten {
            starts.append(position)
            position += (line as NSString).length + 1
        }

        let newSelection: NSRange
        if selection.length == 0, let caretAt {
            newSelection = NSRange(location: starts[0] + caretAt, length: 0)
        } else if let start = zip(starts, coloured).first(where: { $0.1 != nil }),
                  let end = Array(zip(starts, coloured)).last(where: { $0.1 != nil }) {
            let from = start.0 + start.1!.location
            newSelection = NSRange(location: from, length: end.0 + NSMaxRange(end.1!) - from)
        } else {
            newSelection = NSRange(location: first.location, length: 0)
        }
        return TextEdit(range: whole, replacement: replacement, selection: newSelection)
    }

    /// One line, restyled. `selection` is in the line's own offsets, and may
    /// run past either end of it.
    ///
    /// - Returns: the new line, where its styled text now is (the text
    ///   between its new tags, or where the text taken out of a run now is),
    ///   and for a caret its new place. `nil` for a line with nothing to do.
    static func styleLine(_ line: String, selection: NSRange, change: StyleChange) -> (text: String, coloured: NSRange, caret: Int?)? {
        guard let parsed = LineRuns(line) else { return nil }
        let (spans, runs) = (parsed.spans, parsed.runs)

        // What to colour.
        guard var target = parsed.target(of: selection) else { return nil }
        let caret: Int? = selection.length == 0 ? selection.location : nil

        // Runs it overlaps come off, their text joining it; spans it runs
        // into come in whole. Again, since taking a run in can reach another
        // span.
        var removed: [NSRange] = []
        var kept: SpanStyle?               // the first run's style, whose other setting stays
        var changed = true
        while changed {
            changed = false
            for run in runs where !removed.contains(run.open) {
                let whole = run.whole
                guard NSIntersectionRange(whole, target).length > 0 || NSLocationInRange(target.location, whole) else { continue }
                removed += [run.open, run.close]
                target = NSUnionRange(target, run.text)
                if kept == nil { kept = run.style }
                changed = true
            }
            for span in spans where NSIntersectionRange(span, target).length > 0 && NSUnionRange(span, target) != target {
                target = NSUnionRange(target, span)
                changed = true
            }
        }
        if change.clears, removed.isEmpty { return nil }

        // Rebuild the line: the old tags out, the new ones round the target,
        // none if nothing is left to set.
        let style = change.applied(to: kept ?? SpanStyle(), headingLevel: parsed.headingLevel)
        let opening = style.isEmpty ? "" : style.openTag
        let closing = style.isEmpty ? "" : SpanStyle.close
        var edits: [(range: NSRange, insert: String)] = removed.map { ($0, "") }
        edits.append((NSRange(location: target.location, length: 0), opening))
        edits.append((NSRange(location: NSMaxRange(target), length: 0), closing))
        // Back to front, and at one place the tag that is taken out before
        // the one put in.
        edits.sort { $0.range.location != $1.range.location ? $0.range.location > $1.range.location : $0.range.length > $1.range.length }

        let result = NSMutableString(string: line)
        for edit in edits {
            result.replaceCharacters(in: edit.range, with: edit.insert)
        }

        // A place in the old line, in the new one: shifted by everything put
        // in or taken out before it. The opening tag counts as before the
        // target's start, so the coloured text begins after it.
        func moved(_ offset: Int, afterInsertsAt equal: Bool) -> Int {
            var shift = 0
            for removal in removed where NSMaxRange(removal) <= offset { shift -= removal.length }
            if target.location < offset || (equal && target.location == offset) { shift += (opening as NSString).length }
            if NSMaxRange(target) < offset { shift += (closing as NSString).length }
            return offset + shift
        }
        let start = moved(target.location, afterInsertsAt: true)
        let end = moved(NSMaxRange(target), afterInsertsAt: true)
        let colouredRange = NSRange(location: start, length: max(0, end - start))
        return (result as String, colouredRange, caret.map { moved($0, afterInsertsAt: true) })
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
            guard let block = DocumentParser.parse(line).first, !block.isCode else { return nil }
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

        /// What a change acts on, before the runs and spans it reaches are
        /// taken in: for a caret, the run it is in or the word at it; for a
        /// selection, its part of the block's text less spaces at either
        /// end. `selection` is in the line's offsets and may run past either
        /// end. `nil` where there is nothing: a caret on no word and in no
        /// run, or a selection of spaces or markers alone.
        func target(of selection: NSRange) -> NSRange? {
            if selection.length == 0 {
                if let run = run(atCaret: selection.location) { return run.text }
                let word = MarkdownFormatting.word(at: selection.location, in: line)
                return word.length > 0 && NSLocationInRange(word.location, content) ? word : nil
            }
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
                local = NSRange(location: selection.location - line.location, length: 0)
                add(SizeSample(headingLevel: parsed.headingLevel, size: parsed.size(atCaret: local.location)))
            } else {
                let start = max(selection.location, line.location)
                let end = min(NSMaxRange(selection), NSMaxRange(line))
                guard end > start else { continue }
                local = NSRange(location: start - line.location, length: end - start)
            }
            guard let target = parsed.target(of: local) else { continue }
            hasTarget = true
            guard selection.length > 0 else { continue }

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
