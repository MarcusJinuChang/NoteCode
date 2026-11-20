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
        guard styleSession.setTypography(new) else { return }
        invalidateStyling()
        if textView.textStorage.length > 0 {
            restyle(textView)
        } else {
            styleSession.applyTypingAttributes(to: textView, snapshot: snapshot(of: textView))
        }
    }

    /// The runs to collapse in `storage`, worked out once per edit.
    func markerRuns(in storage: NSTextStorage) -> [MarkdownLayout.Run] {
        styleSession.markerRuns(in: storage)
    }

    /// Re-parses and re-applies styling. Everything goes through the shared
    /// cache, so an edit parses the document exactly once no matter how many
    /// delegate callbacks it triggers.
    func restyle(_ textView: UITextView) {
        let snapshot = styleSession.style(textView)
        let source = snapshot.source
        let blocks = snapshot.blocks
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
        styleSession.invalidate()
        // Replacing the storage wipes the colours too.
        syntaxColouring.forget()
    }

}

#endif
