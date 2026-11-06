//
//  DocumentTextView+Caret.swift
//  NoteCode
//
//  The coordinator's caret: what a selection change does, and keeping the
//  caret off the inside of a hidden marker.
//

#if canImport(UIKit)

import UIKit

extension DocumentTextView.Coordinator {

    func textViewDidChangeSelection(_ textView: UITextView) {
        editor?.typingSelectionDidChange(afterEdit: caretTracker.isAfterEdit(editCount: editCount))
        (textView as? DocumentUITextView)?.placeCaretOnTappedBlankLine()
        caretTracker.normalize(
            in: textView,
            editCount: editCount,
            rendersMarkdown: rendersMarkdown,
            editGuard: editGuard,
            formulaSpans: { [unowned self] selection in formulaSpans(in: textView, touching: selection) },
            caretStop: { [unowned self] offset, direction in caretStop(for: offset, direction: direction, in: textView) }
        )
        defer { caretTracker.settle(at: textView, editCount: editCount) }

        // Moving the caret across a fence boundary changes what the next
        // character should look like, even though no text changed. This
        // fires on every keystroke too, so it reads through the cache
        // rather than re-parsing.
        let snapshot = self.snapshot(of: textView)
        let source = snapshot.source
        let blocks = snapshot.blocks
        DocumentStyler.applyTypingAttributes(
            to: textView, source: source, blocks: blocks, rendered: rendersMarkdown, typography: typography
        )
        applyRewritingPolicy(to: textView, source: source, blocks: blocks)
        updateCodeSelectionHighlight(in: textView)
        refreshFenceVisibility(in: textView)
        refreshHeadingMarkers(in: textView)
        refreshCaretFormatting(in: textView)
    }

    // MARK: Hidden markers

    /// The offset a caret landing on `offset` should stand at.
    func caretStop(for offset: Int, direction: Int, in textView: UITextView) -> Int {
        CaretTracker.caretStop(
            for: offset,
            direction: direction,
            in: textView.textStorage.mutableString,
            formulaSpans: formulaSpans(in: textView, touching: NSRange(location: offset, length: 0)),
            codeRanges: codeRanges(in: textView.textStorage)
        )
    }

    /// The formulas the note draws as attachments near `window` (LaTeX,
    /// step 5). Nothing when the note is not rendered, or has no `$`.
    func formulaSpans(in textView: UITextView, touching window: NSRange? = nil) -> [FormulaEditing.Span] {
        guard rendersMarkdown else { return [] }
        let storage = textView.textStorage
        guard storage.mutableString.range(of: "$").location != NSNotFound else { return [] }
        let snapshot = self.snapshot(of: storage.string)
        return FormulaEditing.spans(in: snapshot.blocks, source: snapshot.source, touching: window)
    }

}

#endif
