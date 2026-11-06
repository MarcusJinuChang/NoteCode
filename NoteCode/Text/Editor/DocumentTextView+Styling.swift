//
//  DocumentTextView+Styling.swift
//  NoteCode
//
//  The coordinator's styling: the note's size, the pass that restyles it
//  after an edit, and forgetting what was styled.
//

#if canImport(UIKit)

import UIKit

extension DocumentTextView.Coordinator {

    /// Sets the note's text size, restyling the whole note in it.
    ///
    /// Restyled from scratch (`invalidateStyling`): a block's signature
    /// says nothing about its font. The styler writes only where the
    /// result differs, so this is one edit of the storage's attributes and
    /// one layout. `UITextView.font` is deliberately not set: that
    /// replaces every run's font with one, which the restyle would then
    /// undo with a second layout.
    func setTypography(_ new: NoteTypography, in textView: UITextView) {
        guard new != typography else { return }
        typography = new
        invalidateStyling()
        if textView.textStorage.length > 0 {
            restyle(textView)
        } else {
            let snapshot = self.snapshot(of: textView)
            DocumentStyler.applyTypingAttributes(
                to: textView, source: snapshot.source, blocks: snapshot.blocks,
                rendered: rendersMarkdown, typography: typography
            )
        }
    }

    /// The runs to collapse in `storage`, worked out once per edit.
    func markerRuns(in storage: NSTextStorage) -> [MarkdownLayout.Run] {
        snapshot(of: storage.string).markerRuns
    }

    /// Re-parses and re-applies styling. Everything goes through the shared
    /// cache, so an edit parses the document exactly once no matter how many
    /// delegate callbacks it triggers.
    func restyle(_ textView: UITextView) {
        // Read the text exactly once. Every range below indexes into this
        // instance, and mixing instances is ruinously slow — see the note
        // on DocumentStyler.applyStyling(to:source:blocks:previousSignatures:).
        let snapshot = self.snapshot(of: textView)
        let source = snapshot.source
        let blocks = snapshot.blocks

        styleSignatures = DocumentStyler.applyStyling(
            to: textView,
            snapshot: snapshot,
            previousSignatures: styleSignatures,
            rendered: rendersMarkdown,
            typography: typography,
            markers: markerDimming
        )
        DocumentStyler.applyTypingAttributes(
            to: textView, source: source, blocks: blocks, rendered: rendersMarkdown, typography: typography
        )
        // Before the overlay places its buttons: an edit can add a block or
        // move the one the caret is in.
        refreshFenceVisibility(in: textView, repositioning: false)
        refreshHeadingMarkers(in: textView)
        refreshCaretFormatting(in: textView)
        let targets = snapshot.targets
        overlay?.update(targets: targets)
        editor?.blocksDidChange(targets)
        scheduleHighlighting(for: textView, source: source, blocks: blocks)
    }

    /// Forgets what's on screen, forcing the next restyle to do everything.
    /// Needed whenever the storage is replaced wholesale.
    func invalidateStyling() {
        styleSignatures = []
        // Replacing the storage wipes the colours too.
        highlightedBlocks = []
    }

}

#endif
