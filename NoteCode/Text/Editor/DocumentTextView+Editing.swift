//
//  DocumentTextView+Editing.swift
//  NoteCode
//
//  The coordinator's edits: what a keystroke or a change does, and the edits
//  the coordinator makes of its own (a Backspace at a hidden marker, a
//  list's Return).
//

#if canImport(UIKit)

import SwiftUI
import UIKit

extension DocumentTextView.Coordinator {

    func textViewDidChange(_ textView: UITextView) {
        // Text just typed under a typing style is written with it, before
        // the restyle below, which then sees the note as it will be.
        editor?.typingTextDidChange(in: textView, isTyping: editRouter.isTyping(in: textView))
        // A search result's highlights are for finding the place, and go
        // once the reader starts working there.
        (textView as? DocumentUITextView)?.clearSearchHighlights()
        restyle(textView)
        text.wrappedValue = textView.text
        editor?.refreshUndoState()
    }

    /// Turns away the keyboard's rewrites of code behind the caret
    /// (`EditRouter.shouldChange`).
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        editRouter.shouldChange(
            in: textView, range: range, replacementText: text, editor: editor, context: editContext(in: textView),
            apply: { [weak self] edit in self?.apply(edit, to: textView) },
            rewriteChangesCode: { [weak self] in
                guard let self else { return false }
                let snapshot = snapshot(of: textView)
                return TextRewritingPolicy.rewriteChangesCode(
                    range, with: text, in: snapshot.source, blocks: snapshot.blocks
                )
            }
        )
    }

    /// An edit of the coordinator's own, through `replace(_:withText:)`
    /// like typing: undoable, restyled, written back to the page.
    func apply(_ edit: TextEdit, to textView: UITextView) {
        editRouter.apply(edit, to: textView, editor: editor)
    }

    /// What the router reads about the note to decide an edit.
    func editContext(in textView: UITextView) -> EditRouter.Context {
        EditRouter.Context(
            rendersMarkdown: rendersMarkdown,
            indentWidth: indentWidth,
            codeRanges: { [unowned self] in codeRanges(in: textView.textStorage) },
            formulaSpans: { [unowned self] window in formulaSpans(in: textView, touching: window) }
        )
    }

}

#endif
