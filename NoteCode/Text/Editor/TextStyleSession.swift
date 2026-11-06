//
//  TextStyleSession.swift
//  NoteCode
//
//  What a text view needs to remember to style a note: the snapshot of the
//  text as the last edit left it, what the last styling pass wrote, and
//  the settings it styles with (size, collapsed markers, marker dimming,
//  Show Markdown). Pulled out of `DocumentTextView.Coordinator` (2T2); the
//  Coordinator keeps forwarding members for the call sites and tests that
//  already use them.
//

#if canImport(UIKit)

import UIKit

@MainActor
final class TextStyleSession {

    /// Settings › Writing › Show Markdown, as `DocumentTextView` last had it.
    var showMarkdown = ShowMarkdown.whileEditing

    /// Settings › Writing › Markers, as `DocumentTextView` last had it.
    var markerDimming = MarkerDimming.standard

    /// Whether the note lays its Markdown markers out at zero width.
    /// See `MarkdownLayout`.
    private(set) var rendersMarkdown = false

    /// The size the note is styled in. A value the session owns, not a
    /// global: a PDF or a thumbnail made while another note is open has a
    /// session of its own.
    private(set) var typography = NoteTypography.standard

    /// How many times the text's characters have been edited, so a
    /// selection change can tell typing from an arrow key.
    private(set) var editCount = 0

    /// How many snapshots were made. Exists so a test can see that a
    /// layout, or a caret move, made none.
    private(set) var snapshotCount = 0

    /// The note as the last edit left it, made the first time anything
    /// asks after an edit and dropped by the next one (`textDidEdit`).
    private var currentSnapshot: DocumentSnapshot?

    /// What the document looked like at the last styling pass, so only the
    /// blocks that actually changed get restyled.
    private var signatures: [DocumentStyler.BlockSignature] = []

    /// The note's characters were edited: the snapshot is stale.
    func textDidEdit() {
        currentSnapshot = nil
        editCount += 1
    }

    /// The note as it stands, made once per edit. `text` is read, and
    /// converted with `nativeUTF8`, only when no snapshot is held.
    func snapshot(of text: @autoclosure () -> String) -> DocumentSnapshot {
        if let currentSnapshot { return currentSnapshot }
        let snapshot = DocumentSnapshot(text: text(), editCount: editCount)
        currentSnapshot = snapshot
        snapshotCount += 1
        return snapshot
    }

    /// The runs to collapse in `storage`, worked out once per edit.
    func markerRuns(in storage: NSTextStorage) -> [MarkdownLayout.Run] {
        snapshot(of: storage.string).markerRuns
    }

    /// Returns whether the setting changed.
    func setRendersMarkdown(_ renders: Bool) -> Bool {
        guard renders != rendersMarkdown else { return false }
        rendersMarkdown = renders
        return true
    }

    /// Returns whether the size changed. The caller restyles from scratch
    /// (`invalidate`): a block's signature says nothing about its font.
    func setTypography(_ new: NoteTypography) -> Bool {
        guard new != typography else { return false }
        typography = new
        return true
    }

    /// Forgets what's on screen, forcing the next `style` to do everything.
    /// Needed whenever the storage is replaced wholesale.
    func invalidate() {
        signatures = []
    }

    /// Restyles the blocks that changed since the last pass, then sets the
    /// typing attributes. Returns the snapshot it styled.
    func style(_ textView: UITextView) -> DocumentSnapshot {
        // Read the text exactly once. Every range below indexes into this
        // instance, and mixing instances is ruinously slow — see the note
        // on DocumentStyler.applyStyling(to:source:blocks:previousSignatures:).
        let snapshot = snapshot(of: textView.text ?? "")
        signatures = DocumentStyler.applyStyling(
            to: textView,
            snapshot: snapshot,
            previousSignatures: signatures,
            rendered: rendersMarkdown,
            typography: typography,
            markers: markerDimming
        )
        applyTypingAttributes(to: textView, snapshot: snapshot)
        return snapshot
    }

    func applyTypingAttributes(to textView: UITextView, snapshot: DocumentSnapshot) {
        DocumentStyler.applyTypingAttributes(
            to: textView, source: snapshot.source, blocks: snapshot.blocks,
            rendered: rendersMarkdown, typography: typography
        )
    }
}

#endif
