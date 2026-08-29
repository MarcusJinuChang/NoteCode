//
//  DocumentParser.swift
//  NoteCode
//
//  Pure document parsing. No UIKit, no SwiftUI, no TextKit — this file turns a
//  string into a list of block nodes and nothing else, so it stays cheap to
//  unit-test (see AGENTS.md, "Conventions").
//

import Foundation

enum DocumentParser {

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
                        range: open.start..<lineEnd
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
                blocks.append(paragraph(from: lineStart, to: lineEnd))
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
                    range: open.start..<text.endIndex
                )
            )
        }

        return blocks
    }

    // MARK: Private

    /// A paragraph covering one source line.
    ///
    /// Its inline content is a single `.text` span for now. Splitting that into
    /// bold, emphasis and inline-code spans is the next step, and is confined
    /// to this function plus `InlineNode`.
    private static func paragraph(from start: String.Index, to end: String.Index) -> BlockNode {
        BlockNode(
            kind: .paragraph(inlines: [InlineNode(kind: .text, range: start..<end)]),
            range: start..<end
        )
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
