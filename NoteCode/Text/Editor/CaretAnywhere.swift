//
//  CaretAnywhere.swift
//  NoteCode
//
//  A tap in the empty space below a note's last line puts the caret there, by
//  adding the blank lines it takes to reach it (feedback item 7, "caret
//  anywhere").
//

import CoreGraphics

/// How many blank lines a tap below the note's end asks for.
nonisolated enum CaretAnywhere {

    /// No tap adds more than this, so a stray tap on a long blank page can't
    /// bury the note's end under a screen of newlines.
    static let maximumLines = 200

    /// The blank lines that bring the caret to the line `tapY` is on, when
    /// the note's last line ends at `lineBottom` and a blank line is
    /// `lineHeight` tall. None for a tap on or above the last line, which
    /// is the text view's own to place.
    static func newlines(tapY: CGFloat, lineBottom: CGFloat, lineHeight: CGFloat) -> Int {
        guard lineHeight > 0, tapY > lineBottom else { return 0 }
        return min(maximumLines, Int(((tapY - lineBottom) / lineHeight).rounded(.up)))
    }
}

#if canImport(UIKit)

import UIKit

extension DocumentUITextView {

    /// Whether TextKit has laid out down to the end of the note. A tap in
    /// the text is the common one, and asking where the note ends would lay
    /// out the whole of a long note for it; if the viewport stops short of
    /// the end, the tap can't be below the text.
    private var viewportReachesEnd: Bool {
        guard let manager = textLayoutManager,
              let viewport = manager.textViewportLayoutController.viewportRange
        else { return true }
        return viewport.endLocation.compare(manager.documentRange.endLocation) != .orderedAscending
    }

    /// Where the note's last line ends, in this view's coordinates, for a
    /// blank line `lineHeight` tall under it. `nil` when the end of the note
    /// isn't laid out (so no tap here can be below it).
    ///
    /// A note ending in a newline has an empty last line, which TextKit sets
    /// at 22pt with the caret at the end and about 14pt without (its extra
    /// line fragment takes the typing attributes only then), so that line is
    /// taken as a blank line's height, not measured.
    func lastLineBottom(blankLineHeight lineHeight: CGFloat) -> CGFloat? {
        guard viewportReachesEnd else { return nil }
        let text = textStorage.string as NSString
        let caret = lineCaretRect(for: endOfDocument)
        guard !caret.isNull, !caret.isInfinite else { return nil }
        let top = caret.minY + CaretHeight.above
        let endsInNewline = text.length > 0 && text.character(at: text.length - 1) == 0x0A
        return endsInNewline ? top + lineHeight : caret.maxY - CaretHeight.below
    }
}

extension DocumentTextView.Coordinator {

    /// The text of a blank line is one line of the note's body.
    private var blankLineHeight: CGFloat { typography.codeLineHeight }

    /// Whether a tap at `point` is in the empty space after the note's end,
    /// where it should add lines: in text mode, in a note that can be
    /// edited, and not on a code block's buttons.
    func isEmptySpace(at point: CGPoint, in textView: DocumentUITextView) -> Bool {
        guard emptySpaceIsTappable(in: textView),
              textView.overlay?.containsInteractiveElement(at: point) != true,
              let bottom = textView.lastLineBottom(blankLineHeight: blankLineHeight)
        else { return false }
        return point.y > bottom
    }

    private func emptySpaceIsTappable(in textView: UITextView) -> Bool {
        textView.isEditable && textView.markedTextRange == nil
            && editor?.mode == .text && editor?.isTextLocked != true
    }

    /// Adds the blank lines that put the caret on the line the tap was on,
    /// and the caret there. One undo step; the lines are the note's own
    /// newlines, so nothing is hidden or marked.
    ///
    /// The count comes from the geometry above, which a page break can
    /// outrun (a line that would cross one is pushed to the next page), so
    /// the caret's line is looked at after the edit and what is still
    /// missing is added.
    func extendNote(toReach point: CGPoint, in textView: DocumentUITextView) {
        guard isEmptySpace(at: point, in: textView) else { return }
        if !textView.isFirstResponder { textView.becomeFirstResponder() }

        for _ in 0..<4 {
            guard let bottom = textView.lastLineBottom(blankLineHeight: blankLineHeight) else { return }
            let count = CaretAnywhere.newlines(tapY: point.y, lineBottom: bottom, lineHeight: blankLineHeight)
            guard count > 0 else { return }
            let end = textView.textStorage.length
            apply(
                TextEdit(
                    range: NSRange(location: end, length: 0),
                    replacement: String(repeating: "\n", count: count),
                    selection: NSRange(location: end + count, length: 0)
                ),
                to: textView
            )
            textView.layoutIfNeeded()
        }
    }
}

#endif
