//
//  NoteEditor+Typography.swift
//  NoteCode
//
//  The note's text size and line spacing, and the block sizes made from them.
//

#if canImport(UIKit)

import Observation
import PaperKit
import SwiftUI
import UIKit

extension NoteEditor {

    // MARK: The note's text size

    /// The note's typography as it is now, for a PDF made of it.
    var typography: NoteTypography { NoteTypography(bodySize: appliedTextSize, lineSpacing: appliedLineSpacing) }

    /// Returns once the sizes waiting for `settleDelay`, the note's and the
    /// selection's, have been applied, or were dropped. For tests.
    func sizeSettled() async {
        await settleTask?.value
        await selectionSizeTask?.value
    }

    /// Follows the note's stored size (`Page.textSize`), as the page opens
    /// and whenever something else changes it. A tap in flight wins until it
    /// settles.
    func syncTextSize(to stored: Int?) {
        let size = NoteTypography(bodySize: stored).bodySize
        appliedTextSize = size
        if settleTask == nil, textSize != size { textSize = size }
    }

    /// A size picked from ••• › Text Size. Text mode only, and not for a
    /// locked note, whose text is read and not changed.
    func setTextSize(_ size: Int) {
        guard mode == .text, !isTextLocked else { return }
        let size = NoteTypography(bodySize: size).bodySize
        guard size != textSize else { return }
        textSize = size
        settleTask?.cancel()
        settleTask = Task { [weak self, settleDelay, settleClock] in
            try? await settleClock.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
            self?.settleTextSize()
        }
    }

    private func settleTextSize() {
        settleTask = nil
        guard textSize != appliedTextSize else { return }
        applyTextSize(textSize)
    }

    /// Lays the note out in `size`, as one undo step: undo goes back to the
    /// size it had, and redo to this one.
    private func applyTextSize(_ size: Int) {
        let before = appliedTextSize
        commitTextSize?(NoteTypography(bodySize: size).storedSize)
        appliedTextSize = size
        textSize = size
        textView?.undoManager?.registerUndo(withTarget: self) { $0.applyTextSize(before) }
        textView?.undoManager?.setActionName("Text Size")
    }

    // MARK: The note's line spacing

    /// Follows the note's stored spacing, as the page opens and whenever
    /// something else changes it.
    func syncLineSpacing(to stored: Int?) {
        let spacing = NoteTypography(lineSpacing: stored).lineSpacing
        appliedLineSpacing = spacing
        lineSpacing = spacing
    }

    /// A spacing picked from the text row. Text mode only, and not for a
    /// locked note.
    func setLineSpacing(_ points: Int) {
        guard mode == .text, !isTextLocked else { return }
        let spacing = NoteTypography(lineSpacing: points).lineSpacing
        guard spacing != appliedLineSpacing else { return }
        applyLineSpacing(spacing)
    }

    /// Lays the note out with `spacing`, as one undo step.
    private func applyLineSpacing(_ spacing: Int) {
        let before = appliedLineSpacing
        commitLineSpacing?(NoteTypography(lineSpacing: spacing).storedLineSpacing)
        appliedLineSpacing = spacing
        lineSpacing = spacing
        textView?.undoManager?.registerUndo(withTarget: self) { $0.applyLineSpacing(before) }
        textView?.undoManager?.setActionName("Line Spacing")
    }
}

#endif
