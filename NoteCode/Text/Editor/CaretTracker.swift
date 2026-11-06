//
//  CaretTracker.swift
//  NoteCode
//
//  Where the caret was at the last selection change, and moving it off the
//  inside of a hidden marker. Pulled out of `DocumentTextView.Coordinator`
//  (2T4); the Coordinator keeps `textViewDidChangeSelection` and
//  `caretStop(for:direction:in:)`, which forward here.
//

#if canImport(UIKit)

import UIKit

@MainActor
final class CaretTracker {

    /// Where the caret was at the last selection change, for the direction
    /// an arrow key walked it.
    private(set) var lastCaret = 0

    /// The edit count at the last selection change, so a selection change
    /// can tell typing (the count moved) from an arrow key (it didn't).
    private(set) var editCountAtLastSelection = 0

    /// Whether the text was edited since the last selection change.
    func isAfterEdit(editCount: Int) -> Bool {
        editCount != editCountAtLastSelection
    }

    /// The selection change has been dealt with.
    func settle(at textView: UITextView, editCount: Int) {
        lastCaret = textView.selectedRange.location
        editCountAtLastSelection = editCount
    }

    /// The offset a caret landing on `offset` should stand at.
    static func caretStop(
        for offset: Int, direction: Int, in text: NSString, formulaSpans: [FormulaEditing.Span], codeRanges: [CodeRange]
    ) -> Int {
        let inFormula = FormulaEditing.caretStop(for: offset, direction: direction, spans: formulaSpans, in: text)
        if inFormula != offset { return inFormula }
        return MarkdownFormatting.caretStop(for: offset, direction: direction, in: text, codeRanges: codeRanges)
    }

    /// Moves a collapsed caret off the inside of a hidden marker.
    ///
    /// Not after an edit: the caret typing leaves is where typing put it,
    /// and moving it would put the next letter on the other side of the
    /// marker just typed. An arrow key is told by its caret having moved
    /// one place with no finger down; a tap, or anything else, lands on
    /// the stretch's stop.
    ///
    /// `caretStop` answers for an offset and a direction; `formulaSpans`
    /// for the formulas near a range.
    func normalize(
        in textView: UITextView,
        editCount: Int,
        rendersMarkdown: Bool,
        editGuard: EditGuard,
        formulaSpans: (NSRange) -> [FormulaEditing.Span],
        caretStop: (Int, Int) -> Int
    ) {
        let isNormalizing = editGuard.isActive(.normalizingCaret)
        // A selection with an edge inside a formula takes the formula whole.
        if rendersMarkdown, !isNormalizing, editCount == editCountAtLastSelection,
           textView.selectedRange.length > 0, textView.markedTextRange == nil {
            let selection = textView.selectedRange
            let snapped = FormulaEditing.snapped(
                selection,
                spans: formulaSpans(selection),
                in: textView.textStorage.mutableString
            )
            if snapped != selection {
                editGuard.perform(as: .normalizingCaret) { textView.selectedRange = snapped }
            }
            return
        }
        guard rendersMarkdown, !isNormalizing,
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
        let stop = caretStop(offset, arrow ? step : 0)
        guard stop != offset else { return }

        editGuard.perform(as: .normalizingCaret) {
            textView.selectedRange = NSRange(location: stop, length: 0)
        }
    }
}

#endif
