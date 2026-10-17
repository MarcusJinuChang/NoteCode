//
//  MarkdownFormatting+Colour.swift
//  NoteCode
//
//  The text options row's colour: wraps text in `<span style="color:…">`,
//  recolours a run, or takes colour off (`TextColour`). Pure, like the rest
//  of `MarkdownFormatting`: it computes a `TextEdit`, and the editor applies
//  it through the text view, so it undoes like typing.
//

import Foundation

extension MarkdownFormatting {

    /// Sets `hex` on the selection, or on the coloured run the caret is in,
    /// or on the word at the caret; `nil` takes colour off them instead.
    ///
    /// - A run per line: a selection over several lines colours each line's
    ///   part of it, never the heading's `#` or a list item's marker.
    /// - Colours don't nest. A run the text overlaps is taken off and its
    ///   text coloured with the rest, so recolouring part of a run recolours
    ///   it all.
    /// - A colour never cuts a span in two: one the text runs into (half of a
    ///   bold word, say) is taken in whole, since a span can't cross a run's
    ///   edge and would show its markers.
    ///
    /// `nil` where there is nothing to do: in code, a caret on no word and in
    /// no run, or Default where nothing is coloured.
    static func colour(_ hex: Int?, selection: NSRange, in text: NSString, codeRanges: [CodeRange]) -> TextEdit? {
        let selection = clamped(selection, to: text.length)
        guard !codeRanges.contains(where: { NSIntersectionRange($0.range, selection).length > 0 || $0.contains(selection) })
        else { return nil }

        let lines = lines(touching: selection, in: text)
        guard let first = lines.first, let last = lines.last else { return nil }

        var rewritten: [String] = []
        var coloured: [NSRange?] = []      // per line, the coloured text in the new line
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
            guard let result = colourLine(lineText, selection: local, hex: hex) else {
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

    /// One line, coloured or uncoloured. `selection` is in the line's own
    /// offsets, and may run past either end of it.
    ///
    /// - Returns: the new line, where its coloured text now is (the text
    ///   between its new tags, or where the text taken out of a run now is),
    ///   and for a caret its new place. `nil` for a line with nothing to do.
    static func colourLine(_ line: String, selection: NSRange, hex: Int?) -> (text: String, coloured: NSRange, caret: Int?)? {
        guard let block = DocumentParser.parse(line).first, !block.isCode else { return nil }
        let ns = line as NSString
        let content = NSRange(block.contentRange, in: line)

        // The spans and runs on the line, in its offsets.
        var spans: [NSRange] = []
        var runs: [(open: NSRange, close: NSRange)] = []
        var open: NSRange?
        for inline in block.inlines {
            let whole = NSRange(inline.range, in: line)
            switch inline.kind {
            case .text: break
            case .colourOpen: open = whole
            case .colourClose:
                if let tag = open { runs.append((tag, whole)) }
                open = nil
            default: spans.append(whole)
            }
        }
        func text(of run: (open: NSRange, close: NSRange)) -> NSRange {
            NSRange(location: NSMaxRange(run.open), length: run.close.location - NSMaxRange(run.open))
        }

        // What to colour.
        var target: NSRange
        var caret: Int?
        if selection.length == 0 {
            let at = selection.location
            caret = at
            if let run = runs.first(where: { at > $0.open.location && at <= $0.close.location }) {
                target = text(of: run)
            } else {
                target = word(at: at, in: ns)
                guard target.length > 0, NSLocationInRange(target.location, content) else { return nil }
            }
        } else {
            target = NSIntersectionRange(selection, content)
            guard target.length > 0 else { return nil }
            // Not the spaces at either end.
            while target.length > 0, ns.character(at: target.location) == 32 {
                target = NSRange(location: target.location + 1, length: target.length - 1)
            }
            while target.length > 0, ns.character(at: NSMaxRange(target) - 1) == 32 {
                target.length -= 1
            }
            guard target.length > 0 else { return nil }
        }

        // Runs it overlaps come off, their text joining it; spans it runs
        // into come in whole. Again, since taking a run in can reach another
        // span.
        var removed: [NSRange] = []
        var changed = true
        while changed {
            changed = false
            for run in runs where !removed.contains(run.open) {
                let whole = NSRange(location: run.open.location, length: NSMaxRange(run.close) - run.open.location)
                guard NSIntersectionRange(whole, target).length > 0 || NSLocationInRange(target.location, whole) else { continue }
                removed += [run.open, run.close]
                target = NSUnionRange(target, text(of: run))
                changed = true
            }
            for span in spans where NSIntersectionRange(span, target).length > 0 && NSUnionRange(span, target) != target {
                target = NSUnionRange(target, span)
                changed = true
            }
        }
        if hex == nil, removed.isEmpty { return nil }

        // Rebuild the line: the old tags out, the new ones round the target.
        let opening = hex.map(TextColour.openTag(hex:)) ?? ""
        let closing = hex == nil ? "" : TextColour.close
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

    /// The word `offset` is in or against: letters, digits and the
    /// underscore of an identifier, as Link takes it.
    private static func word(at offset: Int, in text: NSString) -> NSRange {
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
