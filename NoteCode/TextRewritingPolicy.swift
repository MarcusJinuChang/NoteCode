//
//  TextRewritingPolicy.swift
//  NoteCode
//
//  The single place the keyboard's text-rewriting features get configured.
//

#if canImport(UIKit)

import UIKit

/// Whether the keyboard may rewrite what the user typed.
///
/// Five separate UIKit traits all edit text after the fact, and every one of
/// them corrupts code silently:
///
///     autocorrection       `int lo`  ->  `In too`
///     autocapitalization   `back`    ->  `Back`
///     smart quotes         `"`       ->  `“`
///     smart dashes         `--`      ->  `—`
///     smart insert/delete  adjusts spacing around pasted words
///
/// They're grouped here rather than set individually at the call site so that
/// switching them per region later is one call, not five scattered
/// assignments that can drift apart. See the roadmap's deferred-work section:
/// the plan is `.prose` everywhere except inside a fenced code block.
enum TextRewritingPolicy {
    /// Everything on — correct for prose, ruinous for code.
    case prose
    /// Everything off — correct inside a fenced code block.
    case code

    /// What the editor uses today, before per-region switching exists.
    ///
    /// `.code` is the safe default: it costs prose its autocorrect, but the
    /// alternative corrupts source the user can't see being changed.
    static let current: TextRewritingPolicy = .code

    /// Applies this policy's five traits to `textView`.
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

        if reloadingInputViews {
            textView.reloadInputViews()
        }
    }
}

#endif
