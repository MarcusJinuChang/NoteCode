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
        let undoManager = textView.undoManager
        editor?.typingTextDidChange(
            in: textView,
            isTyping: !isApplyingMarkerEdit && editor?.isFormatting != true && !isRetagging
                && undoManager?.isUndoing != true && undoManager?.isRedoing != true
        )
        // A search result's highlights are for finding the place, and go
        // once the reader starts working there.
        (textView as? DocumentUITextView)?.clearSearchHighlights()
        restyle(textView)
        text.wrappedValue = textView.text
        editor?.refreshUndoState()
    }

    /// Turns away the keyboard's rewrites of code behind the caret.
    ///
    /// The keyboard's own corrections are the edits that replace text
    /// other than the selection. Typing and pasting replace the
    /// selection, deleting leaves nothing, composition replaces its own
    /// marked text, and a formatting button knows what it's changing, so
    /// all of those go through untouched.
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if editor?.isFormatting != true, !isApplyingMarkerEdit { editor?.typingTextWillChange(range: range) }

        // A formatting edit's text is what its button meant (and so is a
        // paste or marker edit the coordinator makes: a window in a scene
        // showed their quotes going curly too). UIKit runs
        // smart punctuation over it as if it had been typed, as edits of
        // their own inside the replace, and turned a colour tag's quotes
        // curly, so it was a tag no longer and showed as text (seen 17
        // Oct, two one-character edits while the colour was applied).
        if editor?.isFormatting == true || isApplyingMarkerEdit, range.length > 0, NSMaxRange(range) <= (textView.text as NSString).length,
           TextRewritingPolicy.isSmartPunctuation(replacing: (textView.text as NSString).substring(with: range), with: text) {
            return false
        }

        // Undo and redo put text back by replacing it, which looks exactly
        // like a keyboard correction: undoing a language pick, whose tag
        // was replaced inside a fence, was turned away, and used up the
        // undo step without changing the text.
        let undoManager = textView.undoManager
        if !isApplyingMarkerEdit, editor?.isFormatting != true, !isRetagging,
           undoManager?.isUndoing != true, undoManager?.isRedoing != true,
           let edit = markerEdit(for: range, replacement: text, in: textView) {
            apply(edit, to: textView)
            return false
        }

        guard range.length > 0, !text.isEmpty, range != textView.selectedRange,
              textView.markedTextRange == nil, editor?.isFormatting != true, !isRetagging,
              !isApplyingMarkerEdit, undoManager?.isUndoing != true, undoManager?.isRedoing != true
        else { return true }

        let snapshot = self.snapshot(of: textView)
        return !TextRewritingPolicy.rewriteChangesCode(
            range, with: text, in: snapshot.source, blocks: snapshot.blocks
        )
    }

    /// An edit of the coordinator's own, through `replace(_:withText:)`
    /// like typing: undoable, restyled, written back to the page.
    func apply(_ edit: TextEdit, to textView: UITextView) {
        guard let start = textView.position(from: textView.beginningOfDocument, offset: edit.range.location),
              let end = textView.position(from: start, offset: edit.range.length),
              let range = textView.textRange(from: start, to: end)
        else { return }
        // A Return the app makes (a list's next item) ends the typing style
        // as one the keyboard types does.
        if edit.replacement.contains("\n") { editor?.clearTypingStyle() }
        isApplyingMarkerEdit = true
        textView.replace(range, withText: edit.replacement)
        isApplyingMarkerEdit = false
        textView.selectedRange = edit.selection
        editor?.refreshUndoState()
    }

    /// The edit a keystroke should make instead of its own, or `nil` to
    /// let it through: Backspace at a hidden marker, Return in a list or
    /// at the end of a bold word, and Tab on a list item.
    ///
    /// Never during marked text, where a keystroke belongs to the
    /// composition. Return and Tab work in legacy notes too; Backspace's
    /// rule is about markers nobody can see.
    private func markerEdit(for range: NSRange, replacement: String, in textView: UITextView) -> TextEdit? {
        guard textView.markedTextRange == nil else { return nil }
        let storage = textView.textStorage
        let text = storage.mutableString

        // In code, Return keeps the line's indent and Tab indents the
        // lines. Checked first: code isn't a list, and these answer nil
        // anywhere but in a block's own lines.
        if replacement == "\n", range == textView.selectedRange,
           let edit = CodeIndent.returnEdit(
               in: text, selection: range, codeRanges: codeRanges(in: storage), width: indentWidth
           ) {
            return edit
        }
        if replacement == "\t", range == textView.selectedRange,
           let edit = CodeIndent.indentEdit(
               in: text, selection: range, outdent: false, codeRanges: codeRanges(in: storage), width: indentWidth
           ) {
            return edit
        }
        if replacement == "\n", range == textView.selectedRange, range.length == 0 {
            return MarkdownFormatting.returnEdit(
                in: text, caret: range.location, rendered: rendersMarkdown, codeRanges: codeRanges(in: storage)
            )
        }
        if replacement == "\t", range == textView.selectedRange {
            return MarkdownFormatting.indent(
                in: text, selection: range, outdent: false, codeRanges: codeRanges(in: storage)
            )
        }
        // In code, Backspace in a line's indent takes back a whole level.
        if replacement.isEmpty, range.length == 1, textView.selectedRange.length == 0,
           NSMaxRange(range) == textView.selectedRange.location,
           let edit = CodeIndent.backspaceEdit(
               in: text, caret: NSMaxRange(range), codeRanges: codeRanges(in: storage), width: indentWidth
           ) {
            return edit
        }
        guard rendersMarkdown, textView.selectedRange.length == 0,
              replacement.isEmpty, range.length >= 1,
              NSMaxRange(range) == textView.selectedRange.location
        else { return nil }
        // Backspace after a formula deletes all of it: one undo step.
        let caret = NSMaxRange(range)
        if let edit = FormulaEditing.backspace(
            at: caret, spans: formulaSpans(in: textView, touching: NSRange(location: caret, length: 0)), in: text
        ) {
            return edit
        }
        return MarkdownFormatting.backspace(
            at: caret, in: text, codeRanges: codeRanges(in: storage)
        )
    }

}

#endif
