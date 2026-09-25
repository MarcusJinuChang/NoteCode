//
//  CodeBlockOverlay.swift
//  NoteCode
//
//  Keeps one action bar pinned to each code block as the document changes.
//

#if canImport(UIKit)

import UIKit

/// Positions a `CodeBlockActionBar` over every code block on screen.
///
/// The bars are subviews of the text view itself, which is a scroll view — so
/// they are placed once in content coordinates and scroll with the text for
/// free, rather than being chased on every frame.
///
/// Only blocks inside TextKit 2's laid-out viewport get a position. Asking for
/// the frame of a block further down the document would force layout all the
/// way to it, which is exactly the lazy layout the editor is built on.
@MainActor
final class CodeBlockOverlay {

    /// Called when the student taps run. The overlay decides nothing about
    /// where the code goes — see `CodeDestination`.
    var onRun: ((CodeBlockTarget) -> Void)?
    var onCopy: ((CodeBlockTarget) -> Void)?

    private weak var textView: UITextView?

    /// One bar per code block, in document order.
    ///
    /// Positional rather than keyed by `CodeBlockID`, and that matters: an ID
    /// carries a hash of the code, so it changes on every keystroke inside a
    /// block. Keying by it would tear down and rebuild a view per character.
    private var bars: [CodeBlockActionBar] = []

    private var targets: [CodeBlockTarget] = []

    /// A view the bars stay beneath: the ink layer.
    ///
    /// In draw mode the canvas takes every touch on the page. Bars for blocks
    /// that existed when a note opened were added before the canvas and sat
    /// under it, but bars added later landed on top: they caught the Pencil
    /// on a block's top-right corner, and in draw mode some blocks' buttons
    /// worked and others didn't. Inserted beneath this, every bar is under
    /// the ink, and in text mode the canvas lets their taps through.
    weak var ceiling: UIView?

    init(textView: UITextView) {
        self.textView = textView
    }

    // MARK: Updating

    /// Takes a new set of code blocks, after an edit.
    func update(targets: [CodeBlockTarget]) {
        self.targets = targets
        matchBarCount(to: targets.count)
        reposition()
    }

    /// Recomputes every visible bar's frame. Cheap enough for `layoutSubviews`:
    /// it walks the viewport's fragments, not the document's.
    ///
    /// - Parameter laysOutViewport: whether it may lay the viewport out when
    ///   TextKit hasn't. Not when called from TextKit's own viewport layout:
    ///   with no viewport to show, laying it out calls straight back here,
    ///   and a mode switch in a test recursed until the stack ran out.
    func reposition(laysOutViewport: Bool = true) {
        guard let textView,
              let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return }

        for bar in bars {
            bar.isHidden = true
        }

        guard !targets.isEmpty else { return }

        // The text view's own layout pass can reach this before TextKit has
        // laid out the viewport, and then no bar gets a position until some
        // later pass happens along. Inside PageView none reliably does, so a
        // freshly opened note showed no run or copy buttons at all. Laying the
        // viewport out here, only when it isn't ready, keeps this independent
        // of how many passes the host happens to run.
        let viewportController = layoutManager.textViewportLayoutController
        if viewportController.viewportRange == nil, laysOutViewport {
            viewportController.layoutViewport()
        }

        guard let viewport = viewportController.viewportRange else { return }

        // A code block's first layout fragment starts exactly where the block
        // does, so an offset match is enough to recognise one.
        var indexByOffset: [Int: Int] = [:]
        for (index, target) in targets.enumerated() {
            indexByOffset[target.range.location] = index
        }

        let inset = textView.textContainerInset
        // The panel spans the text container rather than the glyphs, so its
        // right edge comes from the view, not from the fragment.
        let panelRight = textView.bounds.width - inset.right
        let documentStart = contentManager.documentRange.location

        layoutManager.enumerateTextLayoutFragments(
            from: viewport.location,
            options: [.ensuresLayout]
        ) { fragment in
            let start = fragment.rangeInElement.location
            guard start.compare(viewport.endLocation) != .orderedDescending else { return false }

            let offset = contentManager.offset(from: documentStart, to: start)
            if let index = indexByOffset[offset], index < bars.count {
                // The first line, not the whole fragment. A block that starts
                // a new page keeps a fragment frame beginning above the page
                // break, with its line pushed down inside it, and centring on
                // the frame put the buttons in the gap between two sheets.
                let frame = fragment.layoutFragmentFrame
                let firstLine = fragment.textLineFragments.first.map {
                    $0.typographicBounds.offsetBy(dx: frame.minX, dy: frame.minY)
                } ?? frame
                place(
                    bars[index],
                    target: targets[index],
                    lineFrame: firstLine.offsetBy(dx: inset.left, dy: inset.top),
                    panelRight: panelRight
                )
            }
            return true
        }
    }

    private func place(
        _ bar: CodeBlockActionBar,
        target: CodeBlockTarget,
        lineFrame: CGRect,
        panelRight: CGFloat
    ) {
        let showsRun = target.language != nil
        bar.configure(showsRun: showsRun)

        let size = showsRun ? CodeBlockActionBar.size : CodeBlockActionBar.copyOnlySize
        bar.frame = CodeBlockActionBar.frame(size: size, panelRight: panelRight, lineFrame: lineFrame)
        bar.isHidden = false
    }

    // MARK: The pool

    private func matchBarCount(to count: Int) {
        guard let textView else { return }

        while bars.count < count {
            let index = bars.count
            let bar = CodeBlockActionBar(frame: .zero)
            // The index is stable for the life of the bar because `targets` is
            // rebuilt in document order on every edit, so bar *i* is always
            // block *i*. The target itself is read at tap time, not captured,
            // since the code may have changed since the bar was made.
            bar.onRun = { [weak self] in self?.run(at: index) }
            bar.onCopy = { [weak self] in self?.copy(at: index) }
            if let ceiling, ceiling.superview === textView {
                textView.insertSubview(bar, belowSubview: ceiling)
            } else {
                textView.addSubview(bar)
            }
            bars.append(bar)
        }

        while bars.count > count {
            bars.removeLast().removeFromSuperview()
        }
    }

    private func run(at index: Int) {
        guard targets.indices.contains(index) else { return }
        onRun?(targets[index])
    }

    private func copy(at index: Int) {
        guard targets.indices.contains(index) else { return }
        onCopy?(targets[index])
        bars[index].acknowledgeCopy()
    }

    /// True when the point, in the text view's coordinates, lands on a bar.
    ///
    /// The text view's own gesture recognisers would otherwise claim the touch
    /// and cancel the button's — see `DocumentUITextView`.
    func containsInteractiveElement(at point: CGPoint) -> Bool {
        bars.contains { !$0.isHidden && $0.frame.contains(point) }
    }
}

#endif
