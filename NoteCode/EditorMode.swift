//
//  EditorMode.swift
//  NoteCode
//
//  The text/ink toggle, as one set of settings that move together.
//

#if canImport(UIKit)

import UIKit

/// Which layer of the page takes input.
///
/// Both layers stay visible in either mode: this switches who *edits*, not
/// what is shown. Scrolling belongs to neither — in ink mode a finger still
/// scrolls, or a lecture turns into toggling modes every few lines.
enum EditorMode: String, CaseIterable, Sendable {
    case text
    case ink
}

/// What the text layer was doing when ink took over.
///
/// The selection isn't in here, and doesn't need to be. Measured on
/// 12 September 2026 with the text view in a window and mid-edit: UIKit keeps
/// `selectedRange` through resigning and through `isEditable` and
/// `isSelectable` going off and on again. `EditorModeTests.roundTrip` holds it
/// to that, and is where a restore goes back in if the canvas changes it.
struct TextSession: Equatable {
    /// Whether the keyboard was up. It only comes back if it was.
    var wasEditing: Bool
}

extension EditorMode {

    /// Moves every setting this toggle owns, together.
    ///
    /// The same shape as `TextRewritingPolicy.apply(to:)`, for the same
    /// reason: settings that have to agree live in one call, or one of them
    /// eventually gets missed at a call site. The canvas's
    /// `isUserInteractionEnabled` and `drawingPolicy` join this when the
    /// canvas exists. The tool picker's settings never will — the hotbar
    /// replaces `PKToolPicker`, see docs/phase-drawing-layer.md.
    ///
    /// - Parameter saved: what the previous call returned.
    /// - Returns: what to pass next time. Entering ink captures a session and
    ///   returning to text spends it.
    @discardableResult
    func apply(to textView: UITextView, saved: TextSession?) -> TextSession? {
        switch self {
        case .ink:
            // Applying ink twice must not capture twice. By the second call
            // the keyboard is already down, and "was editing" would be lost.
            let session = saved ?? TextSession(wasEditing: textView.isFirstResponder)

            // Resign first, so the keyboard leaves the normal way rather than
            // having editing pulled out from under it.
            textView.resignFirstResponder()
            textView.isEditable = false
            // Not selectable either. A resting finger or a long press would
            // otherwise start a text selection underneath the pen.
            textView.isSelectable = false
            return session

        case .text:
            textView.isSelectable = true
            textView.isEditable = true

            // Someone who was reading, not typing, shouldn't be handed a
            // keyboard for having drawn something.
            if saved?.wasEditing == true {
                textView.becomeFirstResponder()
            }
            return nil
        }
    }
}

#endif
