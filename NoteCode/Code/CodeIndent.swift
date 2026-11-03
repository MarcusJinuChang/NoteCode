//
//  CodeIndent.swift
//  NoteCode
//
//  What Return, Tab and ⇧Tab do inside a code block. Pure: text and a
//  selection in, an edit out, so the rules are tables in a test.
//

import Foundation

/// Indentation in code, the counterpart of `MarkdownFormatting`'s list rules.
///
/// The same shape on purpose: a function from (text, selection) to a
/// `TextEdit` that the coordinator applies through `replace(_:withText:)`,
/// so it is undoable and restyles like typed text.
nonisolated enum CodeIndent {

    // MARK: The setting

    /// Settings › Code › Indent Width. Per device.
    static let widthKey = "indentWidth"

    static let widths = [2, 4]
    static let defaultWidth = 4

    /// A stored width, or 4 for one the picker can't have made.
    static func validWidth(_ stored: Int?) -> Int {
        guard let stored, widths.contains(stored) else { return defaultWidth }
        return stored
    }

    static func width(from defaults: UserDefaults = .standard) -> Int {
        validWidth(defaults.object(forKey: widthKey) as? Int)
    }

    /// One level of indentation. A line already indented with a tab gets
    /// another tab and the rest get spaces, so a student's file that uses
    /// tabs isn't mixed.
    static func unit(width: Int, for indent: String) -> String {
        indent.hasPrefix("\t") ? "\t" : String(repeating: " ", count: width)
    }

    // MARK: Where code is

    /// The part of a block between its fences: the lines Return and Tab
    /// treat as code.
    ///
    /// From the line after the opening fence to the start of the closing
    /// fence's line, or the end of the note for a block still being typed.
    /// A caret on either fence line isn't in it.
    static func contentRange(of block: CodeRange, in text: NSString) -> NSRange? {
        guard block.range.location < text.length else { return nil }

        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: block.range.location, length: 0))
        let start = lineEnd

        var end = min(NSMaxRange(block.range), text.length)
        if block.isClosed {
            let caret = min(block.lastCaret, text.length)
            text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: caret, length: 0))
            end = lineStart
        }
        guard end >= start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    /// The block whose code lines hold every one of `lines`, with its content.
    private static func block(
        holding lines: ClosedRange<Int>,
        in text: NSString,
        codeRanges: [CodeRange]
    ) -> (block: CodeRange, content: NSRange)? {
        for block in codeRanges where !block.isOutput {
            guard let content = contentRange(of: block, in: text) else { continue }
            // A closed block's content stops at its closing fence's line, so
            // a line starting there is the fence. An open one runs to the end.
            let limit = block.isClosed ? content.location + content.length - 1 : content.location + content.length
            if lines.lowerBound >= content.location, lines.upperBound <= limit { return (block, content) }
        }
        return nil
    }

    // MARK: Return

    /// What Return does at the selection, or `nil` for a plain newline.
    ///
    /// - The new line keeps the line's indent, as far as the caret is in it.
    /// - After `{`, `(` or `[` (and a colon, in Python) it goes one level
    ///   deeper.
    /// - Between a bracket and its closer, the closer moves to a line of its
    ///   own at the original indent and the caret lands on the empty line
    ///   between them.
    /// - Whitespace the old line would be left with, when the caret is in its
    ///   indent, goes: a blank line stays blank.
    ///
    /// Not in output blocks, which hold what a program printed and not code,
    /// and not on a fence line.
    static func returnEdit(
        in text: NSString,
        selection: NSRange,
        codeRanges: [CodeRange],
        width: Int
    ) -> TextEdit? {
        guard selection.location >= 0, NSMaxRange(selection) <= text.length,
              let (block, _) = block(holding: selection.location...NSMaxRange(selection), in: text, codeRanges: codeRanges)
        else { return nil }

        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: selection.location, length: 0))
        // A caret past the end of the line's text, in its terminator, is
        // before the newline for our purposes.
        let caret = min(selection.location, contentsEnd)

        let before = text.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        let indent = String(before.prefix { $0 == " " || $0 == "\t" })
        let beforeIsBlank = indent.count == before.count

        // What follows the selection on its own line.
        var afterLineStart = 0, afterLineEnd = 0, afterContentsEnd = 0
        text.getLineStart(&afterLineStart, end: &afterLineEnd, contentsEnd: &afterContentsEnd, for: NSRange(location: NSMaxRange(selection), length: 0))
        let afterStart = NSMaxRange(selection)
        let after = text.substring(with: NSRange(location: afterStart, length: max(afterContentsEnd - afterStart, 0)))

        let last = before.last { $0 != " " && $0 != "\t" }
        let opens = last.map { "{([".contains($0) } ?? false
        let colon = last == ":" && block.language == .python
            && !before.drop { $0 == " " || $0 == "\t" }.hasPrefix("#")
        let deeper = opens || colon
        let unit = Self.unit(width: width, for: indent)

        // `{█}`: the closer goes down to its own line.
        let skipped = after.prefix { $0 == " " || $0 == "\t" }
        let next = after.dropFirst(skipped.count).first
        if opens, let last, let next, closer(of: last) == next {
            let start = selection.location
            let removed = NSRange(location: start, length: afterStart + skipped.count - start)
            let inner = "\n" + indent + unit
            return TextEdit(
                range: removed,
                replacement: inner + "\n" + indent,
                selection: NSRange(location: start + (inner as NSString).length, length: 0)
            )
        }

        // A blank line keeps no whitespace of its own: it is replaced along
        // with what the caret has passed.
        let start = beforeIsBlank ? lineStart : selection.location
        let replacement = "\n" + indent + (deeper ? unit : "")
        let range = NSRange(location: start, length: NSMaxRange(selection) - start)
        // An edit that is a plain newline is no edit.
        if replacement == "\n", range == selection { return nil }
        return TextEdit(
            range: range,
            replacement: replacement,
            selection: NSRange(location: start + (replacement as NSString).length, length: 0)
        )
    }

    private static func closer(of opener: Character) -> Character? {
        switch opener {
        case "{": "}"
        case "(": ")"
        case "[": "]"
        default:  nil
        }
    }

    // MARK: Backspace

    /// What Backspace does with a collapsed caret in a code line's indent: it
    /// takes the indent back one level, to the previous multiple of the
    /// width, rather than one space. Four spaces typed by ⇥ then go with one
    /// press, and an indent of six goes to four.
    ///
    /// `nil` for anything else, which is the ordinary delete: a caret that
    /// isn't in a code block's lines, one with text before it on its line, an
    /// indent of tabs (one tab is one level already) and the line's first
    /// column.
    static func backspaceEdit(
        in text: NSString,
        caret: Int,
        codeRanges: [CodeRange],
        width: Int
    ) -> TextEdit? {
        guard caret > 0, caret <= text.length,
              block(holding: caret...caret, in: text, codeRanges: codeRanges) != nil
        else { return nil }

        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: caret, length: 0))
        guard caret > lineStart, caret <= contentsEnd else { return nil }

        let before = text.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        guard before.allSatisfy({ $0 == " " }) else { return nil }

        let remainder = before.count % width
        let removed = min(remainder == 0 ? width : remainder, before.count)
        // One space is the ordinary delete.
        guard removed > 1 else { return nil }
        let range = NSRange(location: caret - removed, length: removed)
        return TextEdit(range: range, replacement: "", selection: NSRange(location: range.location, length: 0))
    }

    // MARK: Tab and ⇧Tab

    /// ⇥ and ⇧⇥: one level in or out on every line the selection touches.
    ///
    /// Only when all of them are code lines of one block. With a caret and
    /// no selection, the line the caret is on. On a selection of several
    /// lines blank ones are left alone, but a single blank line, which is
    /// what a caret on an empty line is, takes the indent: otherwise ⇥ there
    /// would do nothing.
    ///
    /// `nil` when there is nothing to change, so ⇧Tab on a line with no
    /// indent hands the key back.
    static func indentEdit(
        in text: NSString,
        selection: NSRange,
        outdent: Bool,
        codeRanges: [CodeRange],
        width: Int
    ) -> TextEdit? {
        guard selection.location >= 0, NSMaxRange(selection) <= text.length else { return nil }
        let touched = MarkdownFormatting.lines(touching: selection, in: text)
        guard let first = touched.first, let last = touched.last,
              block(holding: first.location...last.location, in: text, codeRanges: codeRanges) != nil
        else { return nil }

        let allBlank = touched.allSatisfy { MarkdownFormatting.isBlank(text.substring(with: $0)) }
        var rewritten: [String] = []
        var deltas: [Int] = []
        for line in touched {
            let lineText = text.substring(with: line)
            if outdent {
                let removed = lineText.hasPrefix("\t") ? 1 : lineText.prefix(width).prefix { $0 == " " }.count
                rewritten.append(String(lineText.dropFirst(removed)))
                deltas.append(-removed)
            } else if MarkdownFormatting.isBlank(lineText) && !allBlank {
                rewritten.append(lineText)
                deltas.append(0)
            } else {
                let added = unit(width: width, for: lineText)
                rewritten.append(added + lineText)
                deltas.append((added as NSString).length)
            }
        }
        guard deltas.contains(where: { $0 != 0 }) else { return nil }

        let blockEnd = NSMaxRange(last)
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
}
