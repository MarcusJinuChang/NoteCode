//
//  NoteEditor+Assistant.swift
//  NoteCode
//
//  The on-device assistant's side of the editor: Explain Code, Summarise
//  Note, and Insert Below.
//

#if canImport(UIKit)

import UIKit

extension NoteEditor {

    /// Explain Code: opens the assistant's sheet on a block.
    func explain(_ target: CodeBlockTarget) {
        guard !target.isOutput, !target.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        ai.begin(AIPrompts.explainJob(
            code: target.code,
            languageName: target.language?.displayName,
            insertionOffset: min(NSMaxRange(target.range), textView?.textStorage.length ?? NSMaxRange(target.range)),
            contextTokens: ai.contextTokens,
            length: ai.settings.length
        ))
    }

    /// Summarise Note: opens the assistant's sheet on the note's text.
    func summariseNote(title: String) {
        guard let textView else { return }
        let text = textView.text ?? ""
        ai.begin(AIPrompts.summariseJob(
            text: text,
            title: title,
            insertionOffset: AIInsertion.anchor(caret: textView.selectedRange.location, in: text as NSString, codeRanges: codeRanges?() ?? []),
            contextTokens: ai.contextTokens,
            length: ai.settings.length
        ))
    }

    /// Whether Insert Below can write: text mode, and not a locked note.
    var canInsertAnswer: Bool {
        mode == .text && !isTextLocked && textView != nil
    }

    /// Insert Below: the answer as a quote or an output block under the
    /// block or line it was asked about. One edit through the text view, so
    /// one undo step. Returns whether it wrote anything.
    @discardableResult
    func insertAnswer(_ answer: String, style: AIInsertStyle, at anchor: Int) -> Bool {
        guard canInsertAnswer else { return false }
        var wrote = false
        perform { text, _ in
            let edit = AIInsertion.edit(inserting: answer, style: style, at: anchor, in: text as NSString)
            wrote = edit != nil
            return edit
        }
        return wrote
    }
}

#endif
