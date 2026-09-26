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
/// what is shown. Scrolling belongs to neither — in ink mode the page still
/// scrolls, or a lecture turns into toggling modes every few lines. See
/// `scrolling(fingerDraws:)` for which touches do it.
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
    /// eventually gets missed at a call site. The tool picker's settings never
    /// join it — the hotbar replaces `PKToolPicker`, see
    /// docs/phase-drawing-layer.md.
    ///
    /// The canvas brings one knob, not the two the plan expected. Which input
    /// may draw turned out to be a property of the canvas rather than of the
    /// mode: PaperKit has no `drawingPolicy`, and its Pencil-only drawing
    /// recognisers are set up once, in `DrawingCanvas`. What moves per mode is
    /// who accepts touches at all.
    ///
    /// - Parameter saved: what the previous call returned.
    /// - Returns: what to pass next time. Entering ink captures a session and
    ///   returning to text spends it.
    @discardableResult
    func apply(to textView: UITextView, canvas: DrawingCanvas? = nil, saved: TextSession?) -> TextSession? {
        // Not `isHidden`: both layers stay visible in both modes, and only
        // one of them accepts touches.
        canvas?.isUserInteractionEnabled = self == .ink

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

// MARK: - Scrolling

/// Which touches scroll the page.
///
/// A scroll view's pan takes one touch, from a finger, the Pencil or a
/// pointer. In ink mode the Pencil and, unless the canvas is locked to it, a
/// finger belong to the canvas, and the text view's pan raced PaperKit's own
/// gestures for them. Drawing won, since PencilKit's recogniser starts at
/// touch-down. Dragging a lasso selection didn't: the selection stayed put
/// and the page scrolled instead (simulator, 25 September; with the pan
/// needing two fingers, the same drag moved it).
struct PageScrolling: Equatable {
    /// Fingers a scroll needs.
    var minimumTouches: Int

    /// Which kinds of touch scroll at all.
    var touchTypes: [UITouch.TouchType]

    /// A scroll view's own: one touch, from a finger, the Pencil or a
    /// pointer (read from the app, 25 September).
    static let standard = PageScrolling(minimumTouches: 1, touchTypes: [.direct, .pencil, .indirectPointer])

    func apply(to pan: UIPanGestureRecognizer) {
        pan.minimumNumberOfTouches = minimumTouches
        pan.allowedTouchTypes = touchTypes.map { NSNumber(value: $0.rawValue) }
    }
}

extension EditorMode {

    /// Which touches scroll the page in this mode.
    ///
    /// In ink mode the Pencil never scrolls: it's drawing, erasing, or moving
    /// what the lasso caught. Nor does one finger while a finger draws; two
    /// fingers scroll then. Locked to the Pencil, one finger scrolls again.
    ///
    /// - Parameter fingerDraws: whether a finger draws on the canvas.
    func scrolling(fingerDraws: Bool) -> PageScrolling {
        switch self {
        case .text:
            .standard
        case .ink:
            PageScrolling(minimumTouches: fingerDraws ? 2 : 1, touchTypes: [.direct, .indirectPointer])
        }
    }
}

#endif
