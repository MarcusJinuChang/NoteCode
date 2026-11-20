//
//  CodeBlockAction.swift
//  NoteCode
//
//  Getting a code block out of the app.
//

import Foundation

/// Finding the code block a run or copy acts on. Run itself is Pro and goes
/// to the run service, or to an online compiler when a run can't happen
/// (AGENTS.md › Project overview).
nonisolated enum CodeBlockAction {

    /// The code block the caret is in, fence lines included, for run and copy
    /// from the keyboard and the edit menu.
    ///
    /// A caret at the very end of the note counts as in the block that ends
    /// there, which is the unclosed block still being typed.
    static func target(atCaret offset: Int, in targets: [CodeBlockTarget], sourceLength: Int) -> CodeBlockTarget? {
        targets.first { NSLocationInRange(offset, $0.range) }
            ?? targets.last { offset == sourceLength && NSMaxRange($0.range) == sourceLength }
    }
}
