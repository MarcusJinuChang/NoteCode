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

    // MARK: Search matches

    /// Whether a search result's matches are highlighted. Zeroed memory is
    /// `false` (see `layoutObservers`).
    private(set) var showsSearchMatches = false

    /// Highlights a search result's matches, `current` the most strongly.
    ///
    /// Drawn the way the find bar draws its matches, through this view's own
    /// find decorations, so they sit on the text at any zoom and in any view
    /// mode without laying anything out again.
    func highlightSearchMatches(_ ranges: [NSRange], current: NSRange) {
        for range in ranges {
            guard let start = position(from: beginningOfDocument, offset: range.location),
                  let end = position(from: start, offset: range.length),
                  let match = textRange(from: start, to: end)
            else { continue }
            decorate(foundTextRange: match, document: nil, usingStyle: range == current ? .highlighted : .found)
            showsSearchMatches = true
        }
    }

    /// Takes a search result's highlights away. Only those: while nothing
    /// has been highlighted, this leaves the find bar's own alone.
    func clearSearchHighlights() {
        guard showsSearchMatches else { return }
        showsSearchMatches = false
        clearAllDecoratedFoundText()
    }

    // MARK: Boxes, links and ⇧Tab

    /// The recognisers for taps on boxes and links. See `MarkerGestures`.
    var markerGestures: MarkerGestures?

    /// Whether a point is on a box or a link, so a touch there is this view's
    /// and not the text interaction's.
    var touchTarget: ((CGPoint) -> Bool)?

    /// ⇧Tab on a list item, and whether there is one to take back a level.
    var outdentHandler: (() -> Void)?
    var canOutdent: (() -> Bool)?

    /// ⇧Tab. A key command and not a menu button: a bare Tab in the menu bar
    /// would take it from every field in the app. It gives the key back
    /// (`canPerformAction`) whenever there is no list item to move.
    override var keyCommands: [UIKeyCommand]? {
        let outdent = UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(outdentListItem))
        outdent.wantsPriorityOverSystemBehavior = true
        return (super.keyCommands ?? []) + [outdent]
    }

    @objc func outdentListItem() {
        outdentHandler?()
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(outdentListItem) { return canOutdent?() ?? false }
        return super.canPerformAction(action, withSender: sender)
    }

    // MARK: Hidden markers

    /// Where a caret that lands on an offset should stand, for a rendered
    /// note whose markers take no room (`MarkdownFormatting.caretStop`).
    /// `nil` for a legacy note. Optional, like `layoutObservers`.
    var caretStopResolver: ((Int) -> Int)?

    /// Whether a finger touched this view a moment ago, which tells a tap
    /// that lands the caret from an arrow key that walks it.
    var wasTouchedRecently: Bool {
        CACurrentMediaTime() - lastPressTime < 0.5
    }

    /// Whether a touch at `point` is out beyond the end of the line whose end
    /// is `offset`. Such a tap means "the end", and a line that ends in a
    /// bold word or a link has two places there, either side of its hidden
    /// markers: the one inside the span, which a tap on its last letter
    /// wants, and the one after, which a tap in the empty space wants.
    func isBeyondLineEnd(_ point: CGPoint, at offset: Int) -> Bool {
        let text = textStorage.string as NSString
        guard offset >= 0, offset <= text.length else { return false }
        var lineEnd = 0, contentsEnd = 0
        text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: offset, length: 0))
        guard offset == contentsEnd,
              let position = position(from: beginningOfDocument, offset: offset)
        else { return false }
        // Past the glyph by more than a finger's sloppiness.
        return point.x > caretRect(for: position).midX + 8
    }

    /// `isBeyondLineEnd` for the touch that has just landed the caret, if one did.
    func lastTapIsBeyondLineEnd(at offset: Int) -> Bool {
        wasTouchedRecently && isBeyondLineEnd(lastPressPoint, at: offset)
    }

    private func resolvingCaretStop(_ position: UITextPosition?, tappedAt point: CGPoint? = nil) -> UITextPosition? {
        guard let position, let caretStopResolver else { return position }
        let offset = self.offset(from: beginningOfDocument, to: position)
        if let point, isBeyondLineEnd(point, at: offset) { return position }
        let stop = caretStopResolver(offset)
        guard stop != offset else { return position }
        return self.position(from: beginningOfDocument, offset: stop) ?? position
    }

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
            // A touch on a box or a link lands on this view itself, not the
            // view inside it that holds the text: UIKit asks the view a touch
            // lands on whether each recogniser may begin, so this is what
            // puts `gestureRecognizerShouldBegin` below in charge of it. Not
            // on an action bar, which is a button.
            if hit !== self, overlay?.containsInteractiveElement(at: point) != true, isOnMarker(point) {
                return self
            }
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
        return resolvingCaretStop(blankLine(before: position, tappedAt: point) ?? position, tappedAt: point)
    }

    override func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        guard let position = super.closestPosition(to: point, within: range) else { return nil }
        guard let blank = blankLine(before: position, tappedAt: point),
              compare(blank, to: range.start) != .orderedAscending
        else { return resolvingCaretStop(position, tappedAt: point) }
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

    /// Run after TextKit lays out the text on screen, and before it's drawn.
    ///
    /// Not the same as a layout pass of this view: an edit lays its paragraph
    /// out again, in a new fragment view, with no pass of this view at all.
    /// Optional for the same reason `layoutObservers` is.
    private var viewportLayoutObservers: [() -> Void]?

    func addViewportLayoutObserver(_ observer: @escaping () -> Void) {
        viewportLayoutObservers = (viewportLayoutObservers ?? []) + [observer]
    }

    override func textViewportLayoutControllerDidLayout(_ textViewportLayoutController: NSTextViewportLayoutController) {
        super.textViewportLayoutControllerDidLayout(textViewportLayoutController)
        for observer in viewportLayoutObservers ?? [] {
            observer()
        }
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

    /// A new accent redraws what is drawn from it without being asked for a
    /// tint: links (a dynamic colour read from the stored accent as it is
    /// drawn) and checked boxes. Drawing only; nothing is laid out or edited.
    override func tintColorDidChange() {
        super.tintColorDidChange()
        func redraw(_ view: UIView) {
            view.setNeedsDisplay()
            view.subviews.forEach(redraw)
        }
        subviews.forEach(redraw)
    }

    /// Keeps a tap on an action bar from reaching the text view's own gestures.
    ///
    /// A button inside a text view is not simply a button: when one of the text
    /// view's recognisers claims the touch — to place the caret, to start a
    /// selection — UIKit cancels the touch the button was tracking, and the
    /// button never fires. Refusing to let those recognisers start on a bar is
    /// what makes the tap land where it looks like it should.
    ///
    /// On a box or a link it refuses all but scrolling and the marker
    /// gestures, so a tap there doesn't also place the caret. Asked only for a
    /// touch that landed on this view, which is why `hitTest` answers with
    /// this view there.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let point = gestureRecognizer.location(in: self)
        if overlay?.containsInteractiveElement(at: point) == true {
            return false
        }
        // A box or a link is the marker gestures': see `MarkerGestures`.
        if !runsOnMarkers(gestureRecognizer), isOnMarker(point) {
            return false
        }

        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    /// Whether a touch at `point` is on a box or a link, and not on a
    /// selection's end, whose handle has to stay draggable over a link.
    private func isOnMarker(_ point: CGPoint) -> Bool {
        guard touchTarget?(point) == true else { return false }
        guard selectedRange.length > 0, let range = selectedTextRange else { return true }
        let reach: CGFloat = 22
        return ![range.start, range.end].contains { caretRect(for: $0).insetBy(dx: -reach, dy: -reach).contains(point) }
    }

    /// The recognisers that still run on a box or a link: scrolling, and the
    /// marker gestures themselves. Everything else on this view is the text
    /// interaction's — placing the caret, the loupe, selecting — and would
    /// treat the link as text.
    private func runsOnMarkers(_ recognizer: UIGestureRecognizer) -> Bool {
        recognizer === panGestureRecognizer
            || recognizer === pinchGestureRecognizer
            || recognizer === markerGestures?.tap
            || recognizer === markerGestures?.hold
    }
}

#endif
