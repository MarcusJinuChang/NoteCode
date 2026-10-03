//
//  TextRewritingPolicy.swift
//  NoteCode
//
//  The single place the keyboard's text-rewriting features get configured,
//  and where in a note each set applies.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Whether the keyboard may rewrite what the user typed.
///
/// Six separate UIKit traits all edit text after the fact, and every one of
/// them corrupts code silently:
///
///     autocorrection       `int lo`  ->  `In too`
///     autocapitalization   `back`    ->  `Back`
///     smart quotes         `"`       ->  `“`
///     smart dashes         `--`      ->  `—`
///     smart insert/delete  adjusts spacing around pasted words
///     inline predictions   the space bar accepts a suggested word
///
/// They're grouped here rather than set individually at the call site so that
/// switching them is one call, not six scattered assignments that can drift
/// apart. Prose gets them and code doesn't: `at(_:in:blocks:)` says which
/// applies where the caret is, and `DocumentTextView` switches as the caret
/// moves.
nonisolated enum TextRewritingPolicy: Equatable, Sendable {
    /// Everything on — correct for prose, ruinous for code.
    case prose
    /// Everything off — correct inside a fenced code block.
    case code

    /// What a new editor starts with, before the caret has been placed.
    ///
    /// Nothing rewrites until the editor knows where typing will go: the
    /// coordinator picks the policy for the caret as editing begins, and
    /// again as it moves.
    static let initial: TextRewritingPolicy = .code

    /// The policy for typing at a UTF-16 offset in `source`, whose blocks are
    /// `blocks`.
    ///
    /// Code is a fenced block's lines, its fences included, and inline code
    /// in a line of prose. An unclosed fence or backtick counts too, since the
    /// closing one is typed last: `int lo` would be corrected before it came.
    /// So does the word just after a closing backtick, until a space ends it.
    static func at(_ utf16Offset: Int, in source: String, blocks: [BlockNode]) -> TextRewritingPolicy {
        guard let caret = Range(NSRange(location: utf16Offset, length: 0), in: source)?.lowerBound else {
            return .code
        }

        let block: BlockNode?
        if caret == source.endIndex {
            // The note's last line is the last block's, unless a line break
            // ends that block: then the caret is on a new, empty line. An
            // unclosed code block runs to the end of the note, so the new
            // line is still code.
            if let last = blocks.last,
               last.range.upperBound == source.endIndex,
               source.last?.isNewline != true || last.codeBlock?.isClosed == false {
                block = last
            } else {
                block = nil
            }
        } else {
            // Half-open, so a caret at the start of the line after a closing
            // fence is in that line, not the block above it.
            block = blocks.first { $0.range.contains(caret) }
        }

        guard let block else { return .prose }
        if block.isCode { return .code }
        if endsWordTouchingBacktick(caret, in: source) { return .code }
        return isInInlineCode(caret, block: block, source: source) ? .code : .prose
    }

    /// Whether the word that ends at `caret` has a backtick in it.
    ///
    /// The keyboard corrects the word before the caret when a space ends it,
    /// and its word runs straight through a backtick: right after inline
    /// code, "use `int lo` " became "use `int lot ", the backtick eaten
    /// (measured 3 Oct). So the word stays code until a space ends it, and
    /// the space is typed with nothing on to correct it.
    private static func endsWordTouchingBacktick(_ caret: String.Index, in source: String) -> Bool {
        source[..<caret].reversed().prefix { !$0.isWhitespace }.contains("`")
    }

    /// Whether `caret` is in inline code within a line of prose: between a
    /// span's backticks, or after a backtick nothing closes yet.
    private static func isInInlineCode(_ caret: String.Index, block: BlockNode, source: String) -> Bool {
        for inline in block.inlines {
            guard inline.range.lowerBound < caret else { break }
            switch inline.kind {
            case .inlineCode:
                // Right after the opening backtick to right before the
                // closing one. After the closing one is prose again.
                if caret <= inline.contentRange.upperBound { return true }
            case .text:
                // The parser leaves a backtick as text when nothing on the
                // line closes it, which is what one being typed looks like.
                let before = inline.range.lowerBound..<min(inline.range.upperBound, caret)
                if source[before].contains("`") { return true }
            default:
                break
            }
        }
        return false
    }
}

#if canImport(UIKit)

@MainActor
extension TextRewritingPolicy {
    /// Applies this policy's traits to `textView`.
    ///
    /// Spell checking stays off for both. Its underlines aren't confined to
    /// the part the caret is in: on in prose, it marks every word typed this
    /// session anywhere in the note, so an identifier typed in a code block
    /// turned red as soon as the caret moved back to prose (measured 3 Oct).
    ///
    /// - Parameter reloadingInputViews: pass `true` when switching policy while
    ///   the keyboard is already on screen. UIKit reads these traits when it
    ///   builds the keyboard, so without the reload the change appears to do
    ///   nothing until the keyboard is dismissed and shown again.
    func apply(to textView: UITextView, reloadingInputViews: Bool = false) {
        let rewritingAllowed = (self == .prose)

        textView.autocorrectionType = rewritingAllowed ? .yes : .no
        textView.autocapitalizationType = rewritingAllowed ? .sentences : .none
        textView.smartQuotesType = rewritingAllowed ? .yes : .no
        textView.smartDashesType = rewritingAllowed ? .yes : .no
        textView.smartInsertDeleteType = rewritingAllowed ? .yes : .no
        // The reader's keyboard setting decides in prose, as it does in Notes.
        textView.inlinePredictionType = rewritingAllowed ? .default : .no
        textView.spellCheckingType = .no

        if reloadingInputViews {
            textView.reloadInputViews()
        }
    }
}

#endif
