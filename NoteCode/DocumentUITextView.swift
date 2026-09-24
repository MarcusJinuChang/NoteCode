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

    /// Held here because the content storage's delegate is weak. Optional for
    /// the same reason `layoutObservers` is.
    var blankLineLayout: BlankLineLayout?

    // MARK: Blank lines

    /// Where and when the last touch landed on this view, for
    /// `placeCaretOnTappedBlankLine`. Taken from hit testing: the recogniser
    /// that places the caret sits on a view inside this one, so it never asks
    /// `gestureRecognizerShouldBegin` here (simulator, 23 September). Plain values rather than an optional
    /// tuple: this class's initialisers don't run (see `layoutObservers`), and
    /// zeroed memory is a valid "never" here — time 0 is always too long ago.
    private var lastPressPoint: CGPoint = .zero
    private var lastPressTime: CFTimeInterval = 0

    /// Puts the caret back on the blank line a tap was on.
    ///
    /// A blank line is laid out as a zero-width space (see `BlankLineLayout`).
    /// UIKit places a tap's caret at a word boundary, and to it a run of blank
    /// lines is one word of zero-width spaces: a tap anywhere on the run put
    /// the caret after it, on the next line of text (simulator, 23 September).
    /// Called when the selection changes. A caret just after blank lines, below
    /// where a tap began a moment ago, goes back up to the blank line under the
    /// finger.
    func placeCaretOnTappedBlankLine() {
        guard CACurrentMediaTime() - lastPressTime < 0.5, selectedRange.length == 0 else { return }
        lastPressTime = 0

        let text = textStorage.string as NSString
        var offset = selectedRange.location
        guard BlankLineLayout.isBlankLine(at: offset - 1, in: text),
              let caret = position(from: beginningOfDocument, offset: offset),
              // A little slack, so a tap on the top edge of the line itself
              // isn't taken for the blank line above it.
              lastPressPoint.y < caretRect(for: caret).minY - 2
        else { return }

        while BlankLineLayout.isBlankLine(at: offset - 1, in: text) {
            offset -= 1
            guard let line = position(from: beginningOfDocument, offset: offset) else { break }
            if lastPressPoint.y >= caretRect(for: line).minY { break }
        }
        selectedRange = NSRange(location: offset, length: 0)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if event?.type == .touches, hit != nil {
            lastPressPoint = point
            lastPressTime = CACurrentMediaTime()
        }
        return hit
    }

    /// Takes a point on a blank line back to that line, for anything that
    /// asks the text input where a point is.
    ///
    /// The zero-width space gives a blank line a second caret stop, after the
    /// space, and that offset is the start of the next line. UIKit's own tap
    /// doesn't come through here — see `placeCaretOnTappedBlankLine` — but
    /// the answer should be right for whatever does.
    override func closestPosition(to point: CGPoint) -> UITextPosition? {
        guard let position = super.closestPosition(to: point) else { return nil }
        return blankLine(before: position, tappedAt: point) ?? position
    }

    override func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        guard let position = super.closestPosition(to: point, within: range) else { return nil }
        guard let blank = blankLine(before: position, tappedAt: point),
              compare(blank, to: range.start) != .orderedAscending
        else { return position }
        return blank
    }

    /// The blank line just before `position`, if the point is on it rather
    /// than on the line `position` starts.
    private func blankLine(before position: UITextPosition, tappedAt point: CGPoint) -> UITextPosition? {
        let offset = self.offset(from: beginningOfDocument, to: position)
        guard BlankLineLayout.isBlankLine(at: offset - 1, in: textStorage.string as NSString),
              point.y < caretRect(for: position).minY
        else { return nil }
        return self.position(from: position, offset: -1)
    }

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
