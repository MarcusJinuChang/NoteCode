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

    /// Run after every layout pass, which for a scroll view includes every
    /// scroll. `CodeBlockOverlay` repositions from here, and `PageView` sizes
    /// the canvas.
    ///
    /// Optional, and it has to be. This view is made with
    /// `init(usingTextLayoutManager:)`, which goes through UIKit and never runs
    /// this class's Swift property initialisers, so every stored property here
    /// starts as zeroed memory. Zero is a valid `nil`; it is not a valid `[]`,
    /// and appending to one crashed.
    private var layoutObservers: [() -> Void]?

    /// Weak on purpose: the coordinator owns the overlay, and the overlay
    /// already points back at this view.
    weak var overlay: CodeBlockOverlay?

    func addLayoutObserver(_ observer: @escaping () -> Void) {
        layoutObservers = (layoutObservers ?? []) + [observer]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for observer in layoutObservers ?? [] {
            observer()
        }
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
