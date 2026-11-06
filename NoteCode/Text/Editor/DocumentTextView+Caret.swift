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
        editor?.typingSelectionDidChange(afterEdit: editCount != editCountAtLastSelection)
        (textView as? DocumentUITextView)?.placeCaretOnTappedBlankLine()
        normalizeCaret(in: textView)
        defer {
            lastCaret = textView.selectedRange.location
            editCountAtLastSelection = editCount
        }

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
        let spans = formulaSpans(in: textView, touching: NSRange(location: offset, length: 0))
        let inFormula = FormulaEditing.caretStop(
            for: offset, direction: direction, spans: spans, in: textView.textStorage.mutableString
        )
        if inFormula != offset { return inFormula }
        return MarkdownFormatting.caretStop(
            for: offset,
            direction: direction,
            in: textView.textStorage.mutableString,
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

    /// Moves a collapsed caret off the inside of a hidden marker.
    ///
    /// Not after an edit: the caret typing leaves is where typing put it,
    /// and moving it would put the next letter on the other side of the
    /// marker just typed. An arrow key is told by its caret having moved
    /// one place with no finger down; a tap, or anything else, lands on
    /// the stretch's stop.
    ///
    private func normalizeCaret(in textView: UITextView) {
        // A selection with an edge inside a formula takes the formula whole.
        if rendersMarkdown, !isNormalizingCaret, editCount == editCountAtLastSelection,
           textView.selectedRange.length > 0, textView.markedTextRange == nil {
            let selection = textView.selectedRange
            let snapped = FormulaEditing.snapped(
                selection,
                spans: formulaSpans(in: textView, touching: selection),
                in: textView.textStorage.mutableString
            )
            if snapped != selection {
                isNormalizingCaret = true
                textView.selectedRange = snapped
                isNormalizingCaret = false
            }
            return
        }
        guard rendersMarkdown, !isNormalizingCaret,
              editCount == editCountAtLastSelection,
              textView.selectedRange.length == 0,
              textView.markedTextRange == nil
        else { return }

        let offset = textView.selectedRange.location
        let step = offset - lastCaret
        let arrow = abs(step) == 1 && (textView as? DocumentUITextView)?.wasTouchedRecently != true
        // A tap in the empty space after a line's last markers means the
        // end of the line, after them.
        if !arrow, (textView as? DocumentUITextView)?.lastTapIsBeyondLineEnd(at: offset) == true { return }
        let stop = caretStop(for: offset, direction: arrow ? step : 0, in: textView)
        guard stop != offset else { return }

        isNormalizingCaret = true
        textView.selectedRange = NSRange(location: stop, length: 0)
        isNormalizingCaret = false
    }

}

#endif
