//
//  NoteTypographyController.swift
//  NoteCode
//
//  The note's text size and line spacing, and the block sizes made from them.
//

#if canImport(UIKit)

import Observation
import UIKit

/// The note's body size and line spacing: what the reader picked, what the
/// text is laid out with, and the undo steps between. `NoteEditor` forwards to
/// it (the hotbar and the page read and set them there).
@Observable
final class NoteTypographyController {

    @ObservationIgnored private unowned let editor: NoteEditor

    init(editor: NoteEditor) {
        self.editor = editor
    }

    // MARK: The note's text size

    /// The note's own body size as ••• › Text Size shows it: the reader's
    /// latest pick, which the note catches up to after `settleDelay` and,
    /// for a note with ink, a yes. Every size in the note is against it.
    private(set) var textSize = NoteTypography.defaultSize

    /// The size the note is laid out in now, from `Page.textSize`.
    private(set) var appliedTextSize = NoteTypography.defaultSize

    /// Writes the size into the note (`Page.textSize`). Set by the page.
    /// Not an edit: the page leaves `modifiedAt` and the undo stack alone.
    @ObservationIgnored var commitTextSize: ((Int?) -> Void)?

    @ObservationIgnored private(set) var settleTask: Task<Void, Never>?

    /// The note's typography as it is now, for a PDF made of it.
    var typography: NoteTypography { NoteTypography(bodySize: appliedTextSize, lineSpacing: appliedLineSpacing) }

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
        guard editor.mode == .text, !editor.isTextLocked else { return }
        let size = NoteTypography(bodySize: size).bodySize
        guard size != textSize else { return }
        textSize = size
        settleTask?.cancel()
        settleTask = Task { [weak self, settleDelay = editor.settleDelay, settleClock = editor.settleClock] in
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
        editor.textView?.undoManager?.registerUndo(withTarget: self) { $0.applyTextSize(before) }
        editor.textView?.undoManager?.setActionName("Text Size")
    }

    // MARK: The block sizes

    /// The note's block sizes as laid out, kept per text size: they come from
    /// the system's fonts, and the bar asks on every caret move.
    var blockSizes: MarkdownFormatting.BlockSizes {
        if let cached = blockSizesCache, cached.bodySize == appliedTextSize { return cached.sizes }
        let sizes = typography.blockSizes
        blockSizesCache = (appliedTextSize, sizes)
        return sizes
    }
    @ObservationIgnored private var blockSizesCache: (bodySize: Int, sizes: MarkdownFormatting.BlockSizes)?

    // MARK: The note's line spacing

    /// The points of line spacing the note is laid out with, from
    /// `Page.lineSpacing`, and as the text row's menu shows them. A pick is
    /// one action, so it applies at once (no `settleDelay`); a note with ink
    /// asks first, once each time it is opened, with the text size's answer.
    private(set) var lineSpacing = 0
    private(set) var appliedLineSpacing = 0

    /// Writes the spacing into the note (`Page.lineSpacing`). Not an edit.
    @ObservationIgnored var commitLineSpacing: ((Int?) -> Void)?

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
        guard editor.mode == .text, !editor.isTextLocked else { return }
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
        editor.textView?.undoManager?.registerUndo(withTarget: self) { $0.applyLineSpacing(before) }
        editor.textView?.undoManager?.setActionName("Line Spacing")
    }
}

#endif
