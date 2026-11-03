//
//  AIInsertion.swift
//  NoteCode
//
//  "Insert below": where an answer goes in the note and what is written.
//  Pure; the editor makes the edit through the text view, so it undoes.
//

import Foundation

nonisolated enum AIInsertion {

    /// Where an answer goes: the end of the code block the caret is in, else
    /// the end of the line the caret is on. UTF-16, past the line's newline.
    static func anchor(caret: Int, in text: NSString, codeRanges: [CodeRange]) -> Int {
        let caret = min(max(caret, 0), text.length)
        if let block = codeRanges.first(where: { NSLocationInRange(caret, $0.range) || (caret == text.length && NSMaxRange($0.range) == text.length) }) {
            return min(NSMaxRange(block.range), text.length)
        }
        return NSMaxRange(text.lineRange(for: NSRange(location: caret, length: 0)))
    }

    /// The edit that writes `answer` at `anchor` as a quote or an output
    /// block, set off from the text on both sides by a blank line. `nil` for
    /// an answer with nothing in it.
    static func edit(inserting answer: String, style: AIInsertStyle, at anchor: Int, in text: NSString) -> TextEdit? {
        let answer = cleaned(answer)
        guard !answer.isEmpty else { return nil }

        let at = min(max(anchor, 0), text.length)
        let newline = unichar(UInt8(ascii: "\n"))
        let lead = at == 0 ? "" : (text.character(at: at - 1) == newline ? "\n" : "\n\n")
        let trail = at < text.length && text.character(at: at) != newline ? "\n" : ""

        let body: String
        switch style {
        case .quote:
            body = answer.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.isEmpty ? ">" : "> \($0)" }
                .joined(separator: "\n") + "\n"
        case .output:
            let fence = String(repeating: "`", count: max(3, longestBacktickRun(in: answer) + 1))
            body = "\(fence)\(CodeBlockKind.outputTag)\n\(answer)\n\(fence)\n"
        }

        let replacement = lead + body + trail
        let end = at + (replacement as NSString).length - trail.utf16.count
        return TextEdit(range: NSRange(location: at, length: 0), replacement: replacement, selection: NSRange(location: end, length: 0))
    }

    /// The model's text made safe to write: line ends as `\n`, no trailing
    /// space, no more than one blank line in a row, nothing at the ends.
    static func cleaned(_ answer: String) -> String {
        var lines: [String] = []
        for raw in answer.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.replacingOccurrences(of: "\r", with: "")
            let trimmed = String(line.reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed())
            if trimmed.isEmpty && (lines.last?.isEmpty ?? true) { continue }
            lines.append(trimmed)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    private static func longestBacktickRun(in text: String) -> Int {
        var longest = 0, run = 0
        for character in text {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        return longest
    }
}
