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
    /// A deliberately small subset — inline code, strong, emphasis,
    /// strikethrough, and links. Spans don't nest. Full
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
            } else if character == "[" {
                if let link = markdownLink(in: text, at: cursor, limit: range.upperBound) {
                    flushPlainText(upTo: cursor)
                    nodes.append(link)
                    cursor = link.range.upperBound
                    plainStart = cursor
                    continue
                }
            } else if character == "h" {
                if let link = bareLink(in: text, at: cursor, limit: range.upperBound, plainStart: plainStart) {
                    flushPlainText(upTo: cursor)
                    nodes.append(link)
                    cursor = link.range.upperBound
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
            } else if character == "~" {
                // Doubled only. A single tilde is ordinary text in notes —
                // `~5ms`, `~/Developer` — and nothing renders it as markup.
                let second = text.index(after: cursor)
                if second < range.upperBound, text[second] == "~" {
                    let contentStart = text.index(after: second)
                    if let closing = firstDoubled("~", in: text, from: contentStart, limit: range.upperBound),
                       closing > contentStart {
                        flushPlainText(upTo: cursor)
                        let end = text.index(closing, offsetBy: 2)
                        nodes.append(InlineNode(kind: .strikethrough, range: cursor..<end, contentRange: contentStart..<closing))
                        cursor = end
                        plainStart = cursor
                        continue
                    }
                }
            }

            cursor = text.index(after: cursor)
        }

        flushPlainText(upTo: range.upperBound)
        return nodes
    }

    // MARK: Links

    /// `[text](address)` starting at `open`. The text can't be empty or blank
    /// and neither part crosses a bracket or a parenthesis, so `[ ] (x)` and
    /// `arr[i](j)` stay text only when they have nothing between the brackets;
    /// a note about `f[i](x)` does link, which is what Markdown does too.
    private static func markdownLink(
        in text: String,
        at open: String.Index,
        limit: String.Index
    ) -> InlineNode? {
        let contentStart = text.index(after: open)
        guard contentStart < limit else { return nil }

        var cursor = contentStart
        while cursor < limit, text[cursor] != "]", text[cursor] != "[" {
            cursor = text.index(after: cursor)
        }
        guard cursor < limit, text[cursor] == "]", cursor > contentStart else { return nil }
        guard text[contentStart..<cursor].contains(where: { !$0.isWhitespace }) else { return nil }

        let closeBracket = cursor
        let parenthesis = text.index(after: closeBracket)
        guard parenthesis < limit, text[parenthesis] == "(" else { return nil }

        let destinationStart = text.index(after: parenthesis)
        var end = destinationStart
        while end < limit, text[end] != ")", !text[end].isWhitespace {
            end = text.index(after: end)
        }
        guard end < limit, text[end] == ")", end > destinationStart else { return nil }

        return InlineNode(
            kind: .link,
            range: open..<text.index(after: end),
            contentRange: contentStart..<closeBracket,
            destination: destinationStart..<end
        )
    }

    /// A bare `http://` or `https://` address, shown exactly as typed. It runs
    /// to the next space, less the punctuation a sentence puts after it.
    private static func bareLink(
        in text: String,
        at start: String.Index,
        limit: String.Index,
        plainStart: String.Index
    ) -> InlineNode? {
        // Not the tail of a longer word: `xhttp://` isn't an address.
        if start > plainStart {
            let previous = text[text.index(before: start)]
            if previous.isLetter || previous.isNumber { return nil }
        }

        let rest = text[start..<limit]
        let schemeLength: Int
        if rest.hasPrefix("https://") {
            schemeLength = 8
        } else if rest.hasPrefix("http://") {
            schemeLength = 7
        } else {
            return nil
        }

        var end = text.index(start, offsetBy: schemeLength)
        let hostStart = end
        while end < limit, !text[end].isWhitespace {
            end = text.index(after: end)
        }
        // A sentence's own punctuation, and a closing bracket the address
        // didn't open.
        while end > hostStart {
            let last = text[text.index(before: end)]
            if ".,;:!?'\"".contains(last) || (last == ")" && !text[hostStart..<end].contains("(")) {
                end = text.index(before: end)
            } else {
                break
            }
        }
        guard end > hostStart else { return nil }
        return InlineNode(kind: .link, range: start..<end, contentRange: start..<end, destination: start..<end)
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
