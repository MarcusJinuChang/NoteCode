//
//  NoteEditor+TypingStyle.swift
//  NoteCode
//
//  The typing style: what the next text typed is drawn with, set by a button that has no word to act on.
//

#if canImport(UIKit)

import Observation
import PaperKit
import SwiftUI
import UIKit

extension NoteEditor {

    // MARK: The typing style

    /// Whether a press with the selection as it is sets the typing style: a
    /// caret that isn't inside a word (`MarkdownFormatting.caretTarget`).
    func isTypingCaret(in textView: UITextView) -> Bool {
        let selection = textView.selectedRange
        return selection.length == 0 && MarkdownFormatting.caretTarget(
            at: selection.location, in: textView.textStorage.mutableString, codeRanges: codeRanges
        ) == .typing
    }

    /// Sets the typing style, with the keyboard up for it as a formatting
    /// button brings it, and starts watching for the text typed.
    func setTypingStyle(_ style: TypingStyle) {
        guard let textView else { return }
        if !textView.isFirstResponder { textView.becomeFirstResponder() }
        typingStyle = style
        let caret = textView.selectedRange.location
        typingAnchor = style.isEmpty ? nil : TypingAnchor(from: caret, suffix: textView.textStorage.length - caret, caret: caret)
        typingAnchorIsStale = false
    }

    /// A caret move, a mode switch, a locked note, a keyboard going away.
    func clearTypingStyle() {
        if !typingStyle.isEmpty { typingStyle = .none }
        typingAnchor = nil
        typingAnchorIsStale = false
    }

    /// The text view is about to change `range`. Only a hint, since what the
    /// keyboard says it is doing isn't always what it does (the iPad's Korean
    /// keyboard reports a jamo inserted where it replaces one): an edit that
    /// starts in front of the typing style's place is an autocorrect or
    /// something else, never the text typed there.
    func typingTextWillChange(range: NSRange) {
        guard !editGuard.isActive(.writingTypedText), let anchor = typingAnchor, range.location < anchor.from else { return }
        typingAnchorIsStale = true
    }

    /// The text changed. If it is text just typed where the typing style
    /// was set, the same text is written again with the style on, in the same
    /// turn of the run loop and so the same undo step as the typing.
    ///
    /// Written after the fact, from here, and never in `shouldChangeTextIn`:
    /// that is told what the keyboard thinks it is doing, which for Korean
    /// on the iPad is a jamo inserted at the caret where the text view really
    /// replaces the one before it, with no marked text. What is typed is
    /// found from the note's length instead. `suffix`, the length less the
    /// caret's place, doesn't change while text is typed or replaced at the
    /// caret, so the caret's place now says where the typed text ends,
    /// whatever the keyboard did to get there.
    ///
    /// Not while a composition is open (`markedTextRange`): that is the
    /// keyboard's text until it commits it, and the commit is where the style
    /// goes on. `isTyping` is false for the app's own edits (a heading, a
    /// list's Return, an undo), which only move the place.
    func typingTextDidChange(in textView: UITextView, isTyping: Bool) {
        guard var anchor = typingAnchor, !typingStyle.isEmpty, !editGuard.isActive(.writingTypedText), mode == .text else { return }
        let selection = textView.selectedRange
        // The caret moves as the composition does; it hasn't gone anywhere.
        guard textView.markedTextRange == nil else {
            typingAnchor?.caret = selection.location
            return
        }
        guard selection.length == 0 else { return clearTypingStyle() }

        let storage = textView.textStorage
        let end = storage.length - anchor.suffix
        defer { if typingAnchor != nil { typingAnchor?.caret = textView.selectedRange.location } }

        guard isTyping, !typingAnchorIsStale, end == selection.location, end >= anchor.from else {
            // Something else changed the text: start again from the caret.
            typingAnchorIsStale = false
            typingAnchor = TypingAnchor(from: selection.location, suffix: storage.length - selection.location, caret: selection.location)
            return
        }
        guard end > anchor.from else { return }

        let run = NSRange(location: anchor.from, length: end - anchor.from)
        anchor.from = end
        typingAnchor = anchor
        let text = storage.mutableString
        // A new line ends it, as a caret move does; a long paste is left as it is.
        guard text.rangeOfCharacter(from: .newlines, options: [], range: run).location == NSNotFound else {
            return clearTypingStyle()
        }
        guard run.length <= 2_000,
              let edit = MarkdownFormatting.typed(
                  typingStyle, run: run, in: text, blockSizes: blockSizes, codeRanges: codeRanges
              ),
              let start = textView.position(from: textView.beginningOfDocument, offset: edit.range.location),
              let finish = textView.position(from: start, offset: edit.range.length),
              let range = textView.textRange(from: start, to: finish)
        else { return }

        editGuard.perform(as: .writingTypedText) {
            editGuard.perform(as: .formatting) {
                textView.replace(range, withText: edit.replacement)
            }
            textView.selectedRange = edit.selection
        }
        typingAnchor = TypingAnchor(
            from: edit.selection.location, suffix: storage.length - edit.selection.location, caret: edit.selection.location
        )
        undoRouter.refresh()
    }

    /// The selection changed. A caret that went somewhere the typing didn't
    /// take it has moved, and the typing style goes. A change that came with
    /// an edit is typing (or the keyboard's composition) moving it.
    func typingSelectionDidChange(afterEdit: Bool) {
        guard let anchor = typingAnchor, !editGuard.isActive(.writingTypedText), !afterEdit, let textView else { return }
        let selection = textView.selectedRange
        // Within a composition the keyboard moves the caret as it likes.
        if textView.markedTextRange != nil {
            typingAnchor?.caret = selection.location
        } else if selection.length != 0 || selection.location != anchor.caret {
            clearTypingStyle()
        }
    }
}

#endif
