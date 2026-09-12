//
//  DocumentUITextView.swift
//  NoteCode
//
//  The editor's UITextView, with the two hooks the action bars need.
//

#if canImport(UIKit)

import UIKit

/// A `UITextView` that reports its layout passes and keeps its own gestures off
/// the action bars floating above it.
///
/// Careful, as everywhere else in this editor: reading the legacy
/// `.layoutManager` property on this view silently downgrades it to TextKit 1
/// and leaves `textLayoutManager` nil. Nothing here touches it.
final class DocumentUITextView: UITextView {

    /// Fires after every layout pass, which for a scroll view includes every
    /// scroll. `CodeBlockOverlay` repositions from here.
    var onLayout: (() -> Void)?

    /// Weak on purpose: the coordinator owns the overlay, and the overlay
    /// already points back at this view.
    weak var overlay: CodeBlockOverlay?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }

    /// Keeps a tap on an action bar from reaching the text view's own gestures.
    ///
    /// A button inside a text view is not simply a button: when one of the text
    /// view's recognisers claims the touch — to place the caret, to start a
    /// selection — UIKit cancels the touch the button was tracking, and the
    /// button never fires. Refusing to let those recognisers start on a bar is
    /// what makes the tap land where it looks like it should.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if overlay?.containsInteractiveElement(at: gestureRecognizer.location(in: self)) == true {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

#endif
