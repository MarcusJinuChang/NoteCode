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

    // MARK: Content height

    /// Turns the height TextKit works out for the text into the height the
    /// view scrolls through. `PageView` rounds it up to whole pages.
    ///
    /// Applied in the setter, as TextKit sets the height, rather than
    /// corrected afterwards. TextKit can set it after the layout pass that
    /// would have corrected it, and then nothing does: a five-page note sat
    /// 500pt short after a mode switch, and extra layout passes didn't fix it.
    var contentHeightAdjustment: ((CGFloat) -> CGFloat)?

    /// The height TextKit last set, before adjustment. Zeroed memory is a
    /// valid 0 here, so the missing initialiser (see `layoutObservers`) is
    /// harmless.
    private(set) var textContentHeight: CGFloat = 0

    override var contentSize: CGSize {
        get { super.contentSize }
        set {
            textContentHeight = newValue.height
            var adjusted = newValue
            if let contentHeightAdjustment {
                adjusted.height = contentHeightAdjustment(newValue.height)
            }
            super.contentSize = adjusted
        }
    }

    /// Applies the adjustment again to TextKit's last height, for when what
    /// it depends on changes without the text being laid out — ink, say.
    ///
    /// - Parameter convert: turns that height into what it will be once the
    ///   text is laid out again, when the caller knows — a page layout change
    ///   that moves every line by a known amount. Without it, the stale
    ///   height is read against the new layout.
    func reapplyContentHeightAdjustment(converting convert: ((CGFloat) -> CGFloat)? = nil) {
        let height = convert?(textContentHeight) ?? textContentHeight
        contentSize = CGSize(width: super.contentSize.width, height: height)
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
