//
//  NoteEditor+SelectionSize.swift
//  NoteCode
//
//  The size of the text at the caret: what the size control reads, and the stepper's taps that wait to settle.
//

#if canImport(UIKit)

import Observation
import PaperKit
import SwiftUI
import UIKit

extension NoteEditor {

    // MARK: The size of the text at the caret

    /// What the size control reads: the text at the caret, or the
    /// selection, in points.
    struct SelectionTextSize: Equatable {
        /// The size, or `nil` for a selection of text in several sizes.
        var points: Double?
        /// The size of the text at the selection's start: where + and −
        /// start from on a selection of several.
        var startPoints: Double
        /// The size the text there has with no size of its own: what
        /// Default sets.
        var ownPoints: Double
        /// Whether there is anything to size: text mode, unlocked, not in
        /// code, and not a caret on no word and in no run.
        var canChange: Bool
    }

    /// A size for the selection in points (`nil`: the text's own), with the
    /// selection it was asked for: kept through the stepper's pause and the
    /// ink question, since the alert takes the keyboard and the text view's
    /// selection isn't something to read back afterwards.
    struct SizeRequest: Equatable {
        /// The size, `nil` for the text's own; for + and −, the size the
        /// text comes to, or `nil` for text in several sizes.
        var points: Double?
        var selection: NSRange
        /// For + and −: how many points each character moves from its own
        /// size, so text in several sizes keeps them apart. `nil` for a size
        /// picked or typed, which `points` says.
        var steps: Int? = nil
    }

    /// What the size control shows: the tap or the answer in flight, or the
    /// text as it is.
    var selectionTextSize: SelectionTextSize {
        var reading = textSize(reading: caretFormatting)
        if let request = pendingSelectionSize {
            reading.points = request.steps == nil ? request.points ?? reading.ownPoints : request.points
        } else {
            switch typing.typingStyle.points {
            case .set(let points)?: reading.points = points
            case .clear?:           reading.points = reading.ownPoints
            case nil:               break
            }
        }
        return reading
    }

    /// + and −, and ⌘+ and ⌘−. Off at the control's ends, 8 and 72 points.
    var canStepSelectionSize: (bigger: Bool, smaller: Bool) {
        let reading = selectionTextSize
        guard reading.canChange else { return (false, false) }
        let current = reading.points ?? reading.startPoints
        return (TextSizeMath.stepped(current, by: 1) != nil, TextSizeMath.stepped(current, by: -1) != nil)
    }

    /// + and −: a point bigger or smaller, for the selection, the run at the
    /// caret or the word there. Text in several sizes moves a point each,
    /// keeping them apart; each stops at the control's ends.
    func stepSelectionSize(by steps: Int) {
        guard let textView else { return }
        let reading = textSize(reading: currentFormatting(of: textView))
        guard mode == .text, !isTextLocked, reading.canChange else { return }
        // No word to resize: the next text typed gets the size, at once, since
        // nothing is laid out again.
        if typing.isTypingCaret(in: textView) {
            let shown = selectionTextSize
            if let next = TextSizeMath.stepped(shown.points ?? shown.startPoints, by: steps) {
                typing.set(typing.typingStyle.sizing(next))
            }
            return
        }
        // Where the control stands now, if the text is one size.
        let shown = pendingSelectionSize.map(\.points) ?? reading.points
        if let shown, TextSizeMath.stepped(shown, by: steps) == nil { return }
        let total = (pendingSelectionSize?.steps ?? 0) + steps
        if pendingSelectionSize == nil { pendingTextLength = textView.textStorage.length }
        pendingSelectionSize = SizeRequest(
            points: reading.points.flatMap { TextSizeMath.stepped($0, by: total) ?? $0 },
            selection: pendingSelectionSize?.selection ?? textView.selectedRange,
            steps: total
        )
        selectionSizeTask?.cancel()
        selectionSizeTask = Task { [weak self, settleDelay, settleClock] in
            try? await settleClock.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
            self?.settleSelectionSize()
        }
    }

    /// A size picked from the list, or `nil` for Default: at once, since a
    /// pick isn't one of a run of taps.
    func setSelectionSize(points: Double?) {
        guard let textView, mode == .text, !isTextLocked else { return }
        dropPendingSelectionSize()
        if typing.isTypingCaret(in: textView) {
            typing.set(typing.typingStyle.sizing(points.map { TextSizeMath.clampedPoints($0) }))
            return
        }
        requestSelectionSize(SizeRequest(points: points.map { TextSizeMath.clampedPoints($0) }, selection: textView.selectedRange))
    }

    /// Custom…: asks for a size (`PageDetailView`'s alert).
    func beginCustomSize() {
        guard let textView, mode == .text, !isTextLocked,
              textSize(reading: currentFormatting(of: textView)).canChange
        else { return }
        dropPendingSelectionSize()
        customSizeSelection = textView.selectedRange
    }

    /// Whether the size control would set the typing style: no word to resize.
    /// Nothing is laid out again then, so there is no ink question.
    private var sizesTypedText: Bool {
        guard let textView else { return false }
        return typing.isTypingCaret(in: textView)
    }

    func cancelCustomSize() {
        customSizeSelection = nil
    }

    /// The alert's Set: the typed size, clamped to 8 to 72 and to the half
    /// point. Anything that isn't a number sets nothing.
    func finishCustomSize(typed: String) {
        defer { customSizeSelection = nil }
        guard let selection = customSizeSelection, let points = TextSizeMath.points(typed: typed) else { return }
        if sizesTypedText {
            typing.set(typing.typingStyle.sizing(points))
            return
        }
        applySelectionSize(SizeRequest(points: points, selection: selection))
    }

    /// The caret's formatting read from the text view itself, for an action:
    /// `caretFormatting` is what the coordinator last reported, for the bar.
    private func currentFormatting(of textView: UITextView) -> MarkdownFormatting.CaretFormatting {
        MarkdownFormatting.formatting(at: textView.selectedRange, in: textView.textStorage.mutableString, codeRanges: textTarget?.codeRanges ?? [])
    }

    /// `formatting`'s sizes in points, in the note's fonts as laid out.
    private func textSize(reading formatting: MarkdownFormatting.CaretFormatting) -> SelectionTextSize {
        let typography = self.typography
        if case .code = formatting.block {
            let code = Double(typography.code.pointSize)
            return SelectionTextSize(points: code, startPoints: code, ownPoints: code, canChange: false)
        }
        let sizes = blockSizes
        let points = formatting.sizes.map { SpanSize.points($0.size, against: sizes.size(forHeadingLevel: $0.headingLevel)) }
        let own = formatting.sizes.first.map { sizes.size(forHeadingLevel: $0.headingLevel) } ?? sizes.body
        let start = points.first ?? own
        return SelectionTextSize(
            points: Set(points).count > 1 ? nil : start,
            startPoints: start,
            ownPoints: own,
            canChange: mode == .text && !isTextLocked && formatting.canResize
        )
    }

    private var blockSizes: MarkdownFormatting.BlockSizes { typographyController.blockSizes }

    /// The pending tap goes on. `keeping` is where the reader has just put
    /// the caret, which stays there rather than going back to the text sized.
    func settleSelectionSize(keeping selection: NSRange? = nil) {
        selectionSizeTask = nil
        guard let request = pendingSelectionSize else { return }
        pendingSelectionSize = nil
        guard textView?.textStorage.length == pendingTextLength else { return }
        requestSelectionSize(request, keeping: selection)
    }

    private func dropPendingSelectionSize() {
        selectionSizeTask?.cancel()
        selectionSizeTask = nil
        pendingSelectionSize = nil
    }

    private func requestSelectionSize(_ request: SizeRequest, keeping selection: NSRange? = nil) {
        guard let textView, sizeEdit(for: request, in: textView.textStorage.mutableString) != nil else { return }
        applySelectionSize(request, keeping: selection)
    }

    /// Sizes the text. The caret ends on what was sized, unless `keeping`
    /// says where else it was just put: there, moved past the tags if they
    /// went in before it.
    private func applySelectionSize(_ request: SizeRequest, keeping selection: NSRange? = nil) {
        guard let textView, let edit = sizeEdit(for: request, in: textView.textStorage.mutableString) else { return }
        let replaced = textView.textStorage.mutableString.substring(with: edit.range)
        perform { _, _ in edit }
        guard let kept = selection,
              let start = TextSizeMath.offset(kept.location, through: edit, replacing: replaced),
              let end = TextSizeMath.offset(NSMaxRange(kept), through: edit, replacing: replaced)
        else { return }
        textView.selectedRange = NSRange(location: start, length: end - start)
    }


    private func sizeEdit(for request: SizeRequest, in text: NSString) -> TextEdit? {
        if let steps = request.steps {
            return MarkdownFormatting.size(
                steppedBy: steps, blockSizes: blockSizes, selection: request.selection, in: text, codeRanges: codeRanges
            )
        }
        return MarkdownFormatting.size(
            points: request.points, blockSizes: blockSizes, selection: request.selection, in: text, codeRanges: codeRanges
        )
    }
}

#endif
