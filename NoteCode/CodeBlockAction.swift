//
//  CodeBlockAction.swift
//  NoteCode
//
//  Getting a code block out of the app.
//

import Foundation

/// Running code in-app is deliberately out of scope — see AGENTS.md. What a
/// student actually needs is the block in the toolchain they already use, so
/// the editor offers copy and share instead.
nonisolated enum CodeBlockAction {

    /// The code a copy or share action should act on, given where the caret is.
    ///
    /// Returns `nil` when the caret isn't inside a fenced block, which is what
    /// keeps the actions out of the edit menu in prose. The fence lines are
    /// excluded — pasting ```` ```cpp ```` into a compiler helps nobody.
    static func code(atCaret utf16Offset: Int, in source: String, blocks: [BlockNode]) -> String? {
        guard let index = Range(NSRange(location: utf16Offset, length: 0), in: source)?.lowerBound else {
            return nil
        }

        let block = blocks.first { $0.range.contains(index) }
            ?? (index == source.endIndex ? blocks.last : nil)

        guard let code = block?.codeBlock else { return nil }
        return String(source[code.contentRange])
    }
}
