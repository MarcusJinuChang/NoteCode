//
//  EditRouter.swift
//  NoteCode
//
//  What a text view does with an edit before it lands: whether a keystroke
//  is the reader's or the app's own, the edit a Backspace at a hidden
//  marker or a Return in a list should make instead of its own, and
//  applying an edit of the app's. Pulled out of `DocumentTextView.Coordinator`
//  (2T4); the Coordinator keeps the delegate methods, which forward here.
//
//  The flags that say "the app is making this edit" live in `EditGuard`.
//  The router owns the one the Coordinator uses; a Coordinator that serves a
//  `NoteEditor` shares the editor's, so a formatting button's edit is seen
//  from both sides.
//

#if canImport(UIKit)

import UIKit

@MainActor
final class EditRouter {

    /// The re-entrancy flags (`EditGuard`).
    var editGuard = EditGuard()

    /// What a decision about an edit reads from the Coordinator, as closures
    /// so only what a path needs is worked out.
    struct Context {
        var rendersMarkdown: Bool
        var indentWidth: Int
        var codeRanges: () -> [CodeRange]
        var formulaSpans: (NSRange) -> [FormulaEditing.Span]
    }

    /// Whether the text view is putting text back for undo or redo, which
    /// looks exactly like a keyboard correction.
    private func isUndoingOrRedoing(_ textView: UITextView) -> Bool {
        let undoManager = textView.undoManager
        return undoManager?.isUndoing == true || undoManager?.isRedoing == true
    }

    /// Whether a change that just happened was the reader's typing, not an
    /// edit the app made.
    func isTyping(in textView: UITextView) -> Bool {
        !editGuard.isAppEdit && !isUndoingOrRedoing(textView)
    }

    /// Turns away the keyboard's rewrites of code behind the caret, and
    /// answers a keystroke with an edit of the app's own where one is due.
    ///
    /// The keyboard's own corrections are the edits that replace text
    /// other than the selection. Typing and pasting replace the
    /// selection, deleting leaves nothing, composition replaces its own
    /// marked text, and a formatting button knows what it's changing, so
    /// all of those go through untouched.
    func shouldChange(
        in textView: UITextView,
        range: NSRange,
        replacementText text: String,
        editor: NoteEditor?,
        context: Context,
        apply: (TextEdit) -> Void,
        rewriteChangesCode: () -> Bool
    ) -> Bool {
        if !editGuard.isReplacingForTheReader { editor?.typingTextWillChange(range: range) }

        // A formatting edit's text is what its button meant (and so is a
        // paste or marker edit the coordinator makes: a window in a scene
        // showed their quotes going curly too). UIKit runs
        // smart punctuation over it as if it had been typed, as edits of
        // their own inside the replace, and turned a colour tag's quotes
        // curly, so it was a tag no longer and showed as text (seen 17
        // Oct, two one-character edits while the colour was applied).
        if editGuard.isReplacingForTheReader, range.length > 0, NSMaxRange(range) <= (textView.text as NSString).length,
           TextRewritingPolicy.isSmartPunctuation(replacing: (textView.text as NSString).substring(with: range), with: text) {
            return false
        }

        // A typed --- is a rule, not "—-": at a line's start the keyboard's
        // dash is kept as the hyphens typed (F-fixes, Dashes).
        if text == "\u{2013}" || text == "\u{2014}", isTyping(in: textView), textView.markedTextRange == nil,
           range.length > 0,
           NSMaxRange(range) <= (textView.text as NSString).length,
           let edit = TextRewritingPolicy.hyphensKept(replacing: range, with: text, in: textView.text as NSString) {
            apply(edit)
            return false
        }

        // Undo and redo put text back by replacing it, which looks exactly
        // like a keyboard correction: undoing a language pick, whose tag
        // was replaced inside a fence, was turned away, and used up the
        // undo step without changing the text.
        if isTyping(in: textView),
           let edit = markerEdit(for: range, replacement: text, in: textView, context: context) {
            apply(edit)
            return false
        }

        guard range.length > 0, !text.isEmpty, range != textView.selectedRange,
              textView.markedTextRange == nil, isTyping(in: textView)
        else { return true }

        return !rewriteChangesCode()
    }

    /// An edit of the coordinator's own, through `replace(_:withText:)`
    /// like typing: undoable, restyled, written back to the page.
    func apply(_ edit: TextEdit, to textView: UITextView, editor: NoteEditor?) {
        guard let range = textView.textRange(for: edit.range) else { return }
        // A Return the app makes (a list's next item) ends the typing style
        // as one the keyboard types does.
        if edit.replacement.contains("\n") { editor?.clearTypingStyle() }
        editGuard.perform(as: .markerEdit) {
            textView.replace(range, withText: edit.replacement)
        }
        textView.selectedRange = edit.selection
        editor?.undoRouter.refresh()
    }

    /// The edit a keystroke should make instead of its own, or `nil` to
    /// let it through: Backspace at a hidden marker, Return in a list or
    /// at the end of a bold word, and Tab on a list item.
    ///
    /// Never during marked text, where a keystroke belongs to the
    /// composition. Return and Tab work in legacy notes too; Backspace's
    /// rule is about markers nobody can see.
    func markerEdit(for range: NSRange, replacement: String, in textView: UITextView, context: Context) -> TextEdit? {
        guard textView.markedTextRange == nil else { return nil }
        let text = textView.textStorage.mutableString

        // In code, Return keeps the line's indent and Tab indents the
        // lines. Checked first: code isn't a list, and these answer nil
        // anywhere but in a block's own lines.
        if replacement == "\n", range == textView.selectedRange,
           let edit = CodeIndent.returnEdit(
               in: text, selection: range, codeRanges: context.codeRanges(), width: context.indentWidth
           ) {
            return edit
        }
        if replacement == "\t", range == textView.selectedRange,
           let edit = CodeIndent.indentEdit(
               in: text, selection: range, outdent: false, codeRanges: context.codeRanges(), width: context.indentWidth
           ) {
            return edit
        }
        if replacement == "\n", range == textView.selectedRange, range.length == 0 {
            return MarkdownFormatting.returnEdit(
                in: text, caret: range.location, rendered: context.rendersMarkdown, codeRanges: context.codeRanges()
            )
        }
        if replacement == "\t", range == textView.selectedRange {
            return MarkdownFormatting.indent(
                in: text, selection: range, outdent: false, codeRanges: context.codeRanges()
            )
        }
        // In code, Backspace in a line's indent takes back a whole level.
        if replacement.isEmpty, range.length == 1, textView.selectedRange.length == 0,
           NSMaxRange(range) == textView.selectedRange.location,
           let edit = CodeIndent.backspaceEdit(
               in: text, caret: NSMaxRange(range), codeRanges: context.codeRanges(), width: context.indentWidth
           ) {
            return edit
        }
        // Typing or deleting over a selection that takes a hidden marker of
        // a span it doesn't take whole keeps the marker, or the span's other
        // marker would show as text (⇧← steps through `**` one at a time).
        if context.rendersMarkdown, range.length > 0, range == textView.selectedRange, !replacement.contains("\n"),
           let edit = MarkdownFormatting.replacing(
               range, with: replacement, in: text, codeRanges: context.codeRanges()
           ) {
            return edit
        }
        guard context.rendersMarkdown, textView.selectedRange.length == 0,
              replacement.isEmpty, range.length >= 1,
              NSMaxRange(range) == textView.selectedRange.location
        else { return nil }
        // Backspace after a formula deletes all of it: one undo step.
        let caret = NSMaxRange(range)
        if let edit = FormulaEditing.backspace(
            at: caret, spans: context.formulaSpans(NSRange(location: caret, length: 0)), in: text
        ) {
            return edit
        }
        return MarkdownFormatting.backspace(
            at: caret, in: text, codeRanges: context.codeRanges()
        )
    }
}

#endif
