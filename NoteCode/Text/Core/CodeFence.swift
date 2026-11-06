//
//  CodeFence.swift
//  NoteCode
//
//  Writing a fenced block around text, once. Pure: Foundation only.
//

import Foundation

nonisolated enum CodeFence {
    /// `text` in a fence tagged `tag`, with no newline after the closing fence.
    /// The fence is longer than any run of backticks in the text, so text that
    /// holds a fence doesn't close its own block.
    static func wrapping(_ text: String, tag: String) -> String {
        var longest = 0, run = 0
        for character in text {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        let fence = String(repeating: "`", count: max(3, longest + 1))
        return fence + tag + "\n" + text + "\n" + fence
    }
}
