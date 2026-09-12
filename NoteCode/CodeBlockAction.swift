//
//  CodeBlockAction.swift
//  NoteCode
//
//  Getting a code block out of the app.
//

import Foundation

/// One code block, located in UTF-16 and carrying everything an action needs.
///
/// UTF-16 because both consumers speak it: TextKit wants an offset to find the
/// block's first line, and `NSTextStorage` wants an `NSRange`. Converting a
/// `Range<String.Index>` costs O(offset) per call, so the ranges here are
/// accumulated in one pass instead — the same reason `DocumentStyler` does it.
nonisolated struct CodeBlockTarget: Equatable, Sendable {
    var id: CodeBlockID
    /// The whole block, fence lines included. Its start is the first line, and
    /// that is where the action buttons go.
    var range: NSRange
    /// `nil` when the fence carried no tag, or one the app doesn't know. Those
    /// blocks get no run button, because there is nowhere honest to send them.
    var language: CodeLanguage?
    /// Just the code between the fences.
    var code: String
}

/// Running code in-app is deliberately out of scope — see AGENTS.md. What a
/// student actually needs is the block in the toolchain they already use, so
/// the editor copies it out or hands it to an online compiler instead.
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

    /// Every code block in the document, in order, with UTF-16 ranges.
    ///
    /// One forward pass over *all* blocks, not just the code ones: a block's
    /// offset is the sum of the lengths before it, so the prose in between has
    /// to be measured even though it produces nothing.
    static func targets(in source: String, blocks: [BlockNode]) -> [CodeBlockTarget] {
        var targets: [CodeBlockTarget] = []
        var offset = 0

        for block in blocks {
            let length = source[block.range].utf16.count

            if let code = block.codeBlock {
                targets.append(
                    CodeBlockTarget(
                        id: code.id,
                        range: NSRange(location: offset, length: length),
                        language: code.language,
                        code: String(source[code.contentRange])
                    )
                )
            }

            offset += length
        }

        return targets
    }
}
