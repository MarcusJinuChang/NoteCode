//
//  DocumentParser.swift
//  NoteCode
//
//  Pure document parsing. No UIKit, no SwiftUI, no TextKit — this file turns a
//  string into a list of block nodes and nothing else, so it stays cheap to
//  unit-test (see AGENTS.md, "Conventions").
//

import Foundation

nonisolated enum DocumentParser {

    /// Splits `text` into block nodes.
    ///
    /// Prose becomes one paragraph block per source line; a fenced region
    /// becomes a single code block spanning all of its lines. An unterminated
    /// fence deliberately produces a code block running to the end of the
    /// document — otherwise nothing would highlight until the user typed the
    /// closing fence, which AGENTS.md rules out.
    static func parse(_ text: String) -> [BlockNode] {
        var blocks: [BlockNode] = []

        // `split` hands back Substrings whose indices point back into `text`,
        // so line boundaries double as document offsets for free.
        //
        // Splitting on `\.isNewline` rather than the literal "\n" matters: Swift
        // stores CRLF as a *single* Character (one grapheme cluster), so
        // `split(separator: "\n")` silently fails to break CRLF documents apart
        // and the whole file parses as one line.
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)

        // Set while we're inside a code block.
        var openFence: (start: String.Index, contentStart: String.Index, info: String, backticks: Int)?
        // Position of the next code block among code blocks, in document order.
        var ordinal = 0

        for (offset, line) in lines.enumerated() {
            let lineStart = line.startIndex
            // Start of the next line, i.e. this line including its terminator.
            let lineEnd = offset + 1 < lines.count ? lines[offset + 1].startIndex : text.endIndex

            let fence = fenceInfo(line)

            if let open = openFence {
                // Inside a block: only a bare fence of at least the opening
                // width closes it. A tagged fence is just code content.
                guard let fence, fence.info.isEmpty, fence.backticks >= open.backticks else { continue }

                let contentRange = open.contentStart..<lineStart
                blocks.append(
                    BlockNode(
                        kind: .code(
                            CodeBlock(
                                id: CodeBlockID(ordinal: ordinal, code: String(text[contentRange])),
                                language: language(from: open.info),
                                infoString: open.info,
                                isClosed: true,
                                contentRange: contentRange
                            )
                        ),
                        range: open.start..<lineEnd,
                        contentRange: contentRange
                    )
                )
                ordinal += 1
                openFence = nil
            } else if let fence {
                openFence = (start: lineStart, contentStart: lineEnd, info: fence.info, backticks: fence.backticks)
            } else {
                // A trailing empty line sits at the very end of the string and
                // spans nothing. Emitting it would add a zero-length block.
                guard lineStart < lineEnd else { continue }
                blocks.append(proseBlock(text, line: line, from: lineStart, to: lineEnd))
            }
        }

        // An unterminated fence runs to the end of the document.
        if let open = openFence {
            let contentRange = open.contentStart..<text.endIndex
            blocks.append(
                BlockNode(
                    kind: .code(
                        CodeBlock(
                            id: CodeBlockID(ordinal: ordinal, code: String(text[contentRange])),
                            language: language(from: open.info),
                            infoString: open.info,
                            isClosed: false,
                            contentRange: contentRange
                        )
                    ),
                    range: open.start..<text.endIndex,
                    contentRange: contentRange
                )
            )
        }

        return blocks
    }

    // MARK: Private

    /// One source line of prose: a heading if it starts with `#`, otherwise a
    /// paragraph. Either way its content is scanned for inline spans.
    private static func proseBlock(
        _ text: String,
        line: Substring,
        from start: String.Index,
        to end: String.Index
    ) -> BlockNode {
        if let list = listInfo(line) {
            let contentRange = list.contentStart..<end
            return BlockNode(
                kind: .listItem(
                    depth: list.depth,
                    marker: list.marker,
                    inlines: InlineParser.parse(text, in: contentRange)
                ),
                range: start..<end,
                contentRange: contentRange
            )
        }

        if let heading = headingInfo(line) {
            let contentRange = heading.contentStart..<end
            return BlockNode(
                kind: .heading(level: heading.level, inlines: InlineParser.parse(text, in: contentRange)),
                range: start..<end,
                contentRange: contentRange
            )
        }

        let contentRange = start..<end
        return BlockNode(
            kind: .paragraph(inlines: InlineParser.parse(text, in: contentRange)),
            range: contentRange,
            contentRange: contentRange
        )
    }

    /// Recognizes a list item: optional indentation, a marker, then a space.
    ///
    /// The space is what separates `- item` from `-1`, and `* item` from the
    /// `*emphasis*` that would otherwise start a line.
    ///
    /// Depth is indentation columns / 2, with a tab counting as two columns —
    /// so both the two-space and four-space nesting conventions work, the
    /// latter simply advancing two levels at a time.
    private static func listInfo(_ line: Substring) -> (depth: Int, marker: ListMarker, contentStart: String.Index)? {
        var cursor = line.startIndex
        var columns = 0

        while cursor < line.endIndex, line[cursor] == " " || line[cursor] == "\t" {
            columns += line[cursor] == "\t" ? 2 : 1
            cursor = line.index(after: cursor)
        }
        guard cursor < line.endIndex else { return nil }

        let depth = columns / 2

        if line[cursor] == "-" || line[cursor] == "*" || line[cursor] == "+" {
            let afterMarker = line.index(after: cursor)
            guard afterMarker < line.endIndex, line[afterMarker] == " " else { return nil }
            return (depth, .bullet, line.index(after: afterMarker))
        }

        if line[cursor].isNumber {
            var digits = cursor
            var value = 0
            while digits < line.endIndex, let digit = line[digits].wholeNumberValue, line[digits].isNumber {
                value = value * 10 + digit
                digits = line.index(after: digits)
            }
            guard digits < line.endIndex, line[digits] == "." || line[digits] == ")" else { return nil }
            let afterPunctuation = line.index(after: digits)
            guard afterPunctuation < line.endIndex, line[afterPunctuation] == " " else { return nil }
            return (depth, .ordered(value), line.index(after: afterPunctuation))
        }

        return nil
    }

    /// Recognizes `#` through `######` followed by a space.
    ///
    /// The space is required, so a C preprocessor line like `#include` inside
    /// prose isn't mistaken for a heading.
    private static func headingInfo(_ line: Substring) -> (level: Int, contentStart: String.Index)? {
        var cursor = line.startIndex
        var hashes = 0

        while cursor < line.endIndex, line[cursor] == "#", hashes < 7 {
            hashes += 1
            cursor = line.index(after: cursor)
        }

        guard (1...6).contains(hashes), cursor < line.endIndex, line[cursor] == " " else { return nil }
        return (hashes, line.index(after: cursor))
    }

    private struct Fence {
        var backticks: Int
        var info: String
    }

    /// Recognizes a fence line: up to three spaces of indent, then three or
    /// more backticks, then an optional info string.
    ///
    /// Returns `nil` for ordinary prose — including lines containing inline
    /// code spans, since those don't *begin* with three backticks.
    private static func fenceInfo(_ line: Substring) -> Fence? {
        var cursor = line.startIndex

        var indent = 0
        while cursor < line.endIndex, line[cursor] == " ", indent < 4 {
            indent += 1
            cursor = line.index(after: cursor)
        }
        guard indent <= 3 else { return nil }

        var backticks = 0
        while cursor < line.endIndex, line[cursor] == "`" {
            backticks += 1
            cursor = line.index(after: cursor)
        }
        guard backticks >= 3 else { return nil }

        let info = line[cursor...].trimmingCharacters(in: .whitespaces)
        // A backtick in the info string means this is an inline code span on a
        // line of its own, not a fence.
        guard !info.contains("`") else { return nil }

        return Fence(backticks: backticks, info: info)
    }

    /// First whitespace-separated word of the info string, mapped to a language.
    private static func language(from infoString: String) -> CodeLanguage? {
        guard let tag = infoString.split(separator: " ").first else { return nil }
        return CodeLanguage(tag: String(tag))
    }
}
