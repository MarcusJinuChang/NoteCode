//
//  NoteInfo.swift
//  NoteCode
//
//  What a note holds, worked out from its text.
//

import Foundation

/// A note's words, and its code blocks by language.
///
/// Worked out from the text when someone asks, never stored: nothing to keep
/// in step with every keystroke, nothing to go stale, and no model change.
/// Pure, so it's tested without SwiftUI, and it reads the note the way the
/// editor does, through `DocumentParser`.
nonisolated struct NoteInfo: Equatable, Sendable {

    /// The code blocks in one language.
    struct Code: Equatable, Sendable, Identifiable {
        /// `nil` for blocks with no language after the fence, or one the app
        /// doesn't know.
        var language: CodeLanguage?
        var blocks: Int
        /// Every line between the fences, blank ones included.
        var lines: Int

        var id: String { language?.rawValue ?? "other" }
        var name: String { language?.displayName ?? "Other" }
    }

    /// Words of prose. Code doesn't count, since `i++` isn't a word, and
    /// neither do the markdown markers around prose: `**bold**` is one word.
    var words: Int

    /// The languages the note has code in, in the order the hotbar lists
    /// them, then blocks in no known language.
    var code: [Code]

    var codeBlocks: Int {
        code.reduce(0) { $0 + $1.blocks }
    }

    init(content: String) {
        var words = 0
        var blocksByLanguage: [CodeLanguage?: (blocks: Int, lines: Int)] = [:]

        for block in DocumentParser.parse(content) {
            if let code = block.codeBlock {
                let lines = Self.lineCount(content[code.contentRange])
                let counted = blocksByLanguage[code.language] ?? (0, 0)
                blocksByLanguage[code.language] = (counted.blocks + 1, counted.lines + lines)
            } else {
                // The content range leaves out a heading's #s and a list
                // item's marker, and word enumeration skips punctuation, so
                // inline markers drop out on their own.
                content.enumerateSubstrings(
                    in: block.contentRange,
                    options: [.byWords, .substringNotRequired]
                ) { _, _, _, _ in
                    words += 1
                }
            }
        }

        let order: [CodeLanguage?] = CodeLanguage.allCases.map(Optional.some) + [nil]
        self.words = words
        self.code = order.compactMap { language in
            blocksByLanguage[language].map { Code(language: language, blocks: $0.blocks, lines: $0.lines) }
        }
    }

    /// Lines in a block's code: one per line break, plus a last line with no
    /// break after it, which an unclosed block at the end of a note has.
    private static func lineCount(_ code: Substring) -> Int {
        var lines = code.reduce(0) { $1.isNewline ? $0 + 1 : $0 }
        if let last = code.last, !last.isNewline {
            lines += 1
        }
        return lines
    }
}
