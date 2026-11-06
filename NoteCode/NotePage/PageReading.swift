#if canImport(UIKit)

import UIKit

/// What reopening, search and the outline read from, and report to, the page
/// they scroll.
@MainActor
protocol PageReadingHost: AnyObject {
    var textView: DocumentUITextView { get }
    var pageLayout: PageLayout { get }
    var pageCount: Int { get }
    var onReadingPlaceChanged: ((NoteMemory.Place) -> Void)? { get }
    var onScrolled: ((NoteMemory.Place) -> Void)? { get }
}

/// Where the note is read from (docs/refactor/2P-page.md, 2P2b): opening at
/// the page the reader left, scrolling to a search result or an outline
/// entry, the reading place and scroll the page reports, and the line
/// queries they share. Each waits for the note's first layout, which
/// `PageView` tells it about (`textViewDidLayout`).
@MainActor
final class PageReading {
    private unowned let host: PageReadingHost

    /// A search result's matches, waiting for the note's first layout: the
    /// first to scroll to, and all of them to highlight.
    private var pendingReveal: (first: NSRange, all: [NSRange])?

    /// The page to open the note at, waiting for its first layout.
    private var pendingRestore: Int?
    private var restoreScheduled = false

    private var lastReportedPlace: NoteMemory.Place?
    private var lastScrolledOffset: CGFloat = 0

    init(host: PageReadingHost) {
        self.host = host
    }

    private var textView: DocumentUITextView { host.textView }
    private var pageLayout: PageLayout { host.pageLayout }

    /// Runs after every layout pass of the text view: carries out what was
    /// waiting for the first layout, and reports where the note is.
    func textViewDidLayout() {
        if let reveal = pendingReveal, textView.bounds.height > 0 {
            pendingReveal = nil
            // After this layout pass rather than inside it.
            DispatchQueue.main.async { [weak self] in self?.show(reveal) }
        }
        if let index = pendingRestore, !restoreScheduled, pendingReveal == nil, textView.bounds.height > 0 {
            restoreScheduled = true
            DispatchQueue.main.async { [weak self] in self?.finishRestore(toPage: index) }
        }
        reportReadingPlace()
        reportScroll()
    }

    /// Tells `onScrolled` the note has moved. Not while it is opening at a
    /// place, which is the app positioning the note rather than the reader.
    private func reportScroll() {
        let offset = textView.contentOffset.y
        defer { lastScrolledOffset = offset }
        guard let onScrolled = host.onScrolled, abs(offset - lastScrolledOffset) > 0.5,
              pendingRestore == nil, pendingReveal == nil, textView.bounds.height > 0
        else { return }
        let place = readingPlace
        // After this layout pass: the callback changes SwiftUI state, and a
        // pass can be inside a SwiftUI update.
        DispatchQueue.main.async { onScrolled(place) }
    }


    /// Opens the note at the top of page `index` (counted from 0) once it has
    /// laid out, the way `reveal` waits for it. A search's match wins if
    /// both are asked for.
    func restore(toPage index: Int) {
        pendingRestore = index > 0 ? index : nil
    }

    private func finishRestore(toPage index: Int) {
        let layout = pageLayout
        // Lay the text out down to the page the way scrolling there by hand
        // would, so the page count is the note's rather than an estimate from
        // the little that is laid out, and the page's first line is placed
        // below every break above it. Not the whole note: what's below can
        // wait for the reader to get there.
        textView.textLayoutManager?.ensureLayout(for: CGRect(
            x: 0,
            y: 0,
            width: layout.textWidth,
            height: layout.scrollTop(forPage: index) + textView.bounds.height
        ))
        textView.setNeedsLayout()
        textView.layoutIfNeeded()
        // A note shortened since lands on its last page.
        let landing = min(index, max(host.pageCount - 1, 0))
        textView.contentOffset.y = clampedOffset(layout.scrollTop(forPage: landing))

        pendingRestore = nil
        restoreScheduled = false
        reportReadingPlace()
    }

    /// The page at the top of the view, and how many pages the note has.
    ///
    /// By the top edge, a point inside it: exactly on a page's scroll-top the
    /// edge is the middle of a band, and rounding there could name the page
    /// before.
    var readingPlace: NoteMemory.Place {
        let index = pageLayout.pageIndex(atY: textView.contentOffset.y + 1)
        return NoteMemory.Place(page: min(index, max(host.pageCount - 1, 0)), of: max(host.pageCount, 1))
    }

    private func reportReadingPlace() {
        guard let onReadingPlaceChanged = host.onReadingPlaceChanged, pendingRestore == nil, pendingReveal == nil,
              textView.bounds.height > 0
        else { return }
        let place = readingPlace
        guard place != lastReportedPlace else { return }
        lastReportedPlace = place
        onReadingPlaceChanged(place)
    }

    // MARK: Search

    /// Shows a search result once the note is laid out: scrolled so the
    /// first match sits near the top, and every match highlighted until the
    /// text changes.
    func reveal(_ first: NSRange, highlighting all: [NSRange]) {
        pendingReveal = (first, all)
    }

    /// Lays the text out down to `character`, the way scrolling there by hand
    /// would, so its line is placed below every page break above it. Not the
    /// whole note: what's below can wait for the reader to get there.
    /// Whether there was anywhere to lay out to.
    @discardableResult
    func layOut(downTo character: Int) -> Bool {
        guard let manager = textView.textLayoutManager,
              let content = manager.textContentManager,
              let target = content.location(content.documentRange.location, offsetBy: character),
              let above = NSTextRange(location: content.documentRange.location, end: target)
        else { return false }
        manager.ensureLayout(for: above)
        textView.setNeedsLayout()
        textView.layoutIfNeeded()
        return true
    }

    private func show(_ reveal: (first: NSRange, all: [NSRange])) {
        guard layOut(downTo: reveal.first.location) else { return }

        if let top = lineTop(atCharacter: reveal.first.location) {
            // A quarter of the way down, so the lines leading up to the match
            // show too.
            textView.contentOffset.y = clampedOffset(top - textView.bounds.height / 4)
        }
        textView.highlightSearchMatches(reveal.all, current: reveal.first)
    }

    // MARK: Outline

    /// Scrolls so the line holding `character` is the first the reader sees:
    /// the outline's tap, which goes where a search result does (lay out
    /// down to it, then scroll) but puts the line at the top rather than a
    /// quarter of the way down. A page's first line shows that page from its
    /// top edge, the rule a mode switch keeps; and a line too near the end
    /// to reach the top lands as far up as the note scrolls.
    func scroll(toLineAt character: Int) {
        guard layOut(downTo: character) else { return }
        settleOffset(onLineAt: character)
    }

    /// Puts the offset where `character`'s line starts the view, set again
    /// while it moves: the page count, and so the bands, can still change as
    /// the text settles, which shifts everything below them.
    func settleOffset(onLineAt character: Int) {
        for _ in 0..<4 {
            guard let top = lineTop(atCharacter: character) else { return }
            let index = pageLayout.pageIndex(atY: top)
            let startsPage = top - pageLayout.bodyTop(ofPage: index) < 1
            let target = clampedOffset(startsPage ? pageLayout.scrollTop(forPage: index) : pixelCeiling(top))
            if abs(textView.contentOffset.y - target) < 0.5 { return }
            textView.contentOffset.y = target
            textView.layoutIfNeeded()
        }
    }

    /// `y` rounded up to a whole pixel. A scroll offset snaps to the screen's
    /// pixels, and one that snaps down from a line's top leaves the line above
    /// showing by a fraction of a point, which is then the first line the
    /// reader sees (a size change landed one line early, and a test of the
    /// line at the top caught it).
    private func pixelCeiling(_ y: CGFloat) -> CGFloat {
        let scale = max(textView.traitCollection.displayScale, 1)
        return (y * scale).rounded(.up) / scale
    }

    /// A vertical scroll offset kept within the note.
    func clampedOffset(_ y: CGFloat) -> CGFloat {
        min(max(y, 0), max(textView.contentSize.height - textView.bounds.height, 0))
    }

    /// The character that starts the first line reaching below the top of
    /// the view — the line the reader is looking at.
    ///
    /// With the top edge in a margin or a page break, that's the next page's
    /// first line, which is what someone scrolled to a sheet's top is reading.
    /// Internal rather than private for `DebugStateReport`.
    func topLineCharacter() -> Int? {
        guard let manager = textView.textLayoutManager,
              let content = manager.textContentManager
        else { return nil }

        let edge = textView.contentOffset.y - textView.textContainerInset.top
        let documentStart = content.documentRange.location
        let from = manager.textViewportLayoutController.viewportRange?.location ?? documentStart

        var found: Int?
        manager.enumerateTextLayoutFragments(from: from, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            guard let line = fragment.textLineFragments.first(where: { frame.minY + $0.typographicBounds.maxY > edge }) else {
                return true
            }
            found = content.offset(from: documentStart, to: fragment.rangeInElement.location) + line.characterRange.location
            return false
        }
        return found
    }

    /// The top of the line holding `character`, in note coordinates.
    func lineTop(atCharacter character: Int) -> CGFloat? {
        guard let manager = textView.textLayoutManager,
              let content = manager.textContentManager,
              let location = content.location(content.documentRange.location, offsetBy: character),
              let fragment = manager.textLayoutFragment(for: location)
        else { return nil }

        let within = character - content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        let line = fragment.textLineFragments.first { NSLocationInRange(within, $0.characterRange) }
            ?? fragment.textLineFragments.first
        guard let line else { return nil }
        return fragment.layoutFragmentFrame.minY + line.typographicBounds.minY + textView.textContainerInset.top
    }
}

#endif
