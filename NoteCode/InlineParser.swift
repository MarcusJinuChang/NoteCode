//
//  InlineParser.swift
//  NoteCode
//
//  Splits a block's content into inline spans.
//

import Foundation

nonisolated enum InlineParser {

    /// Scans `range` within `text` for inline markdown spans.
    ///
    /// A deliberately small subset — inline code, strong, emphasis. Full
    /// CommonMark inline parsing (reference links, nested emphasis, HTML) is a
    /// famous tar pit and none of it is needed for class notes.
    ///
    /// Returned spans are contiguous and cover `range` exactly: the gaps
    /// between markup become `.text`, so callers can walk the list without
    /// checking for holes. An unmatched marker is just text.
    static func parse(_ text: String, in range: Range<String.Index>) -> [InlineNode] {
        var nodes: [InlineNode] = []
        var plainStart = range.lowerBound
        var cursor = range.lowerBound

        func flushPlainText(upTo end: String.Index) {
            guard plainStart < end else { return }
            nodes.append(InlineNode(kind: .text, range: plainStart..<end, contentRange: plainStart..<end))
        }

        while cursor < range.upperBound {
            let character = text[cursor]

            // Inline code wins over emphasis: `a *b* c` is code containing
            // asterisks, not code wrapped around emphasis.
            if character == "`" {
                let contentStart = text.index(after: cursor)
                if let closing = firstIndex(of: "`", in: text, from: contentStart, limit: range.upperBound),
                   closing > contentStart {
                    flushPlainText(upTo: cursor)
                    let end = text.index(after: closing)
                    nodes.append(InlineNode(kind: .inlineCode, range: cursor..<end, contentRange: contentStart..<closing))
                    cursor = end
                    plainStart = cursor
                    continue
                }
            } else if character == "*" || character == "_" {
                let second = text.index(after: cursor)

                // Doubled marker first, or `**bold**` would parse as emphasis
                // wrapping `*bold*`.
                if second < range.upperBound, text[second] == character {
                    let contentStart = text.index(after: second)
                    if let closing = firstDoubled(character, in: text, from: contentStart, limit: range.upperBound),
                       closing > contentStart {
                        flushPlainText(upTo: cursor)
                        let end = text.index(closing, offsetBy: 2)
                        nodes.append(InlineNode(kind: .strong, range: cursor..<end, contentRange: contentStart..<closing))
                        cursor = end
                        plainStart = cursor
                        continue
                    }
                } else if let closing = firstIndex(of: character, in: text, from: second, limit: range.upperBound),
                          closing > second {
                    flushPlainText(upTo: cursor)
                    let end = text.index(after: closing)
                    nodes.append(InlineNode(kind: .emphasis, range: cursor..<end, contentRange: second..<closing))
                    cursor = end
                    plainStart = cursor
                    continue
                }
            }

            cursor = text.index(after: cursor)
        }

        flushPlainText(upTo: range.upperBound)
        return nodes
    }

    // MARK: Private

    private static func firstIndex(
        of character: Character,
        in text: String,
        from start: String.Index,
        limit: String.Index
    ) -> String.Index? {
        var cursor = start
        while cursor < limit {
            if text[cursor] == character { return cursor }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    /// Finds the next pair of `character`, returning the index of the first of them.
    private static func firstDoubled(
        _ character: Character,
        in text: String,
        from start: String.Index,
        limit: String.Index
    ) -> String.Index? {
        var cursor = start
        while cursor < limit {
            let next = text.index(after: cursor)
            if text[cursor] == character, next < limit, text[next] == character {
                return cursor
            }
            cursor = next
        }
        return nil
    }
}
