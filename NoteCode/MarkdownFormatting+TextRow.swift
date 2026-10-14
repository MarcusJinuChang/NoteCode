//
//  MarkdownFormatting+TextRow.swift
//  NoteCode
//
//  The two edits the text options row makes that no menu made before: a link
//  around the selection, and an empty output block under a code block. Pure,
//  like the rest of `MarkdownFormatting`: a button computes a `TextEdit` and
//  the editor applies it through the text view, so it undoes like typing.
//

import Foundation

extension MarkdownFormatting {

    // MARK: Link

    /// What a Link wraps: the selection, or the word at the caret, or nothing
    /// (an empty range at the caret, for a link with placeholder text).
    ///
    /// `nil` where a link can't go: in code, across lines, or in a link that
    /// is already there (the button is lit then, and has nothing to add).
    static func linkTarget(in text: NSString, selection: NSRange, codeRanges: [CodeRange]) -> NSRange? {
        let selection = clamped(selection, to: text.length)
        guard !isCode(selection.location, in: codeRanges) else { return nil }

        if selection.length > 0 {
            guard !isCode(NSMaxRange(selection), in: codeRanges) else { return nil }
            let selected = text.substring(with: selection)
            guard !selected.contains("\n"), !selected.contains("[") , !selected.contains("]") else { return nil }
            guard !formatting(at: selection, in: text, codeRanges: codeRanges).link else { return nil }
            return selection
        }

        guard !formatting(at: selection, in: text, codeRanges: codeRanges).link else { return nil }

        // The word the caret is in or against: letters, digits and the
        // underscore of an identifier.
        func isWordCharacter(at index: Int) -> Bool {
            guard index >= 0, index < text.length else { return false }
            let unit = text.character(at: index)
            guard let scalar = Unicode.Scalar(unit) else { return unit >= 0xD800 }  // half of a pair
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }
        var start = selection.location
        var end = selection.location
        while isWordCharacter(at: start - 1) { start -= 1 }
        while isWordCharacter(at: end) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    /// An address as it is written into `(…)`: trimmed, with the characters
    /// that would end the address early or split it written as escapes.
    /// `nil` for nothing at all.
    static func linkAddress(from typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
    }

    /// `[text](address)` over `range`, the caret left after it. With nothing
    /// to wrap, the text is a placeholder, "link".
    static func link(address: String, over range: NSRange, in text: NSString) -> TextEdit {
        let range = clamped(range, to: text.length)
        let words = range.length > 0 ? text.substring(with: range) : "link"
        let replacement = "[\(words)](\(address))"
        return TextEdit(
            range: range,
            replacement: replacement,
            selection: NSRange(location: range.location + (replacement as NSString).length, length: 0)
        )
    }

    // MARK: Output

    /// An empty output block directly under the code block the caret is in,
    /// with the caret in it. `nil` when the caret isn't in a closed block: an
    /// unclosed block runs to the end of the note, with no place after it.
    static func insertOutputBlock(afterBlockAt caret: Int, in text: NSString, codeRanges: [CodeRange]) -> TextEdit? {
        guard let block = codeRanges.first(where: { $0.contains(NSRange(location: caret, length: 0)) }),
              block.isClosed
        else { return nil }

        let end = NSMaxRange(block.range)
        // A closing fence on the note's last line has no newline to end it.
        let needsNewline = end > 0 && end <= text.length && text.character(at: end - 1) != newline
        let opening = "```\(CodeBlockKind.outputTag)\n"
        let replacement = (needsNewline ? "\n" : "") + opening + "\n```\n"
        let caretAt = end + ((needsNewline ? "\n" : "") + opening as NSString).length
        // At the very end of a note that had no final newline, the one this
        // adds would leave an empty last line after the new fence; the note
        // doesn't need one.
        let trimmed = end >= text.length ? String(replacement.dropLast()) : replacement
        return TextEdit(range: NSRange(location: end, length: 0), replacement: trimmed, selection: NSRange(location: caretAt, length: 0))
    }
}
