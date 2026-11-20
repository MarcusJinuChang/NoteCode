#if canImport(UIKit)

import UIKit

/// What the bands and the page count read from, and set on, the page they
/// work for.
@MainActor
protocol PageBandsHost: UIView {
    var textView: DocumentUITextView { get }
    var canvas: DrawingCanvas { get }
    var selection: InkSelection { get }
    var selectionOverlay: InkSelectionOverlay { get }
    var decorations: PageDecorationView { get }
    var covers: PageCoverView { get }
    var pageLayout: PageLayout { get }
    var minimumPageCount: Int { get set }
    var onMinimumPageCountChanged: ((Int) -> Void)? { get }
    /// The ink's lowest point, which the page count has to leave room for.
    var inkBottom: CGFloat? { get }
    /// Shows the stored ink on the canvas in the current layout.
    func showInk()
    func paintPage()
    func pinLineWidth()
    func topLineCharacter() -> Int?
    func lineTop(atCharacter character: Int) -> CGFloat?
    func clampedOffset(_ y: CGFloat) -> CGFloat
}

/// The pages: a layout's margins and the bands text flows around, the page
/// count, and the canvas, sheets and breaks kept up to it (docs/refactor/
/// 2P-page.md, 2P2b). `PageView` still decides when to ask.
@MainActor
final class PageBands {
    private unowned let host: PageBandsHost

    /// How many pages the note fills; the bands and the furniture follow it.
    /// Worked out whenever TextKit sets the text's height (`noteHeight`).
    private(set) var pageCount = 1

    /// Keeps each paragraph on one page (`PagePaginator`).
    private lazy var paginator = PagePaginator(textView: host.textView)

    init(host: PageBandsHost) {
        self.host = host
    }

    private var textView: DocumentUITextView { host.textView }
    private var pageLayout: PageLayout { host.pageLayout }

    /// Puts a layout's margins, bands and decorations in place.
    ///
    /// - Parameter old: the layout being replaced, or `nil` when first set.
    func applyPageLayout(replacing old: PageLayout?) {
        // Where the reader is, taken before anything moves. Within one
        // orientation every mode paginates the same, so this converts by
        // page. A new orientation re-wraps the text and no position converts,
        // so there the line at the top is kept instead.
        let offset = textView.contentOffset.y
        let anchor = old.map { $0.orientation != pageLayout.orientation } == true ? host.topLineCharacter() : nil
        let oldTextBottom = textView.textContentHeight - textView.textContainerInset.bottom

        if old != nil {
            host.showInk()
        }

        // The bottom inset is the space after the last page's body. The note's
        // height is rounded to whole pages separately, in the content height,
        // so this never has to be worked out from the text.
        textView.textContainerInset = UIEdgeInsets(
            top: pageLayout.firstBodyTop,
            left: PageLayout.margin,
            bottom: pageLayout.trailingSpace,
            right: PageLayout.margin
        )
        host.pinLineWidth()

        // The page count, before the bands that depend on it.
        //
        // The text's height is still the old layout's until TextKit lays it
        // out again, and read against the new layout it gave the wrong count:
        // switching a nine-page note from print layout to seamless counted
        // eleven pages, then nine, ten, nine, as the text reflowed. Every
        // change reassigned the bands, which relays out the whole note, and
        // TextKit shifted the scroll offset each time — the reader landed a
        // line and a half into the page. Within one orientation every mode
        // puts the same lines on the same pages, so the old text bottom
        // converts exactly, and the count is right the first time.
        let newLayout = pageLayout
        textView.reapplyContentHeightAdjustment(converting: { [textView] height in
            guard let old, let bottom = old.convert(y: oldTextBottom, to: newLayout) else { return height }
            return bottom + textView.textContainerInset.bottom
        })
        restartPagination()
        host.paintPage()

        guard old != nil else { return }

        // Re-anchor TextKit at the top of the note before going back to the
        // reader's place.
        //
        // TextKit 2 lays text out relative to what the viewport showed last.
        // After the bands change under a viewport deep in a note, it kept that
        // anchor: every line on screen sat 167pt below its true position —
        // exactly print layout's 168pt break less seamless's 1pt, one stale
        // break's worth — and lines ran across seamless's page breaks. The
        // reader saw the previous page's last lines where the page began.
        // Invalidating the layout, a full ensureLayout, and relaying out the
        // viewport all left it there; only scrolling to the top and back
        // cleared it (ZZ probe, 13 Sep). At the top of a note nothing is above
        // the viewport to be stale, so the jump back lays out fresh. It all
        // happens before the next frame is drawn, so nothing flickers.
        textView.contentOffset.y = 0

        // The text reflows against new bands, so lay it out before restoring
        // the reader's place in it.
        host.setNeedsLayout()
        host.layoutIfNeeded()
        textView.layoutIfNeeded()

        let target: CGFloat
        if let old, old.orientation == pageLayout.orientation {
            let index = old.pageIndex(atY: offset)
            let intoBody = offset - old.bodyTop(ofPage: index)
            // At or above a page's first line — in its margin, or the break
            // before it — means the page itself: show it from its top edge,
            // and the note from its very top.
            target = intoBody <= 0.5
                ? pageLayout.scrollTop(forPage: index)
                : pageLayout.bodyTop(ofPage: index) + min(intoBody, pageLayout.bodyHeight)
        } else if let anchor, let top = host.lineTop(atCharacter: anchor) {
            // A page's first line means the page itself, the same rule as a
            // mode switch — and the note's first line means its very top.
            // Keeping the line itself at the top instead opened every note
            // with landscape pages 36pt down, its top margin out of view:
            // PageView starts with default portrait pages, so taking the
            // note's own on opening runs through here.
            let index = pageLayout.pageIndex(atY: top)
            let startsPage = top - pageLayout.bodyTop(ofPage: index) < 1
            target = startsPage ? pageLayout.scrollTop(forPage: index) : top
        } else {
            textView.contentOffset.y = host.clampedOffset(textView.contentOffset.y)
            return
        }

        // Within one orientation the page count is right from the start, so
        // nothing reassigns the bands after this and the first set sticks.
        // Across orientations the text re-wraps and the count can still move
        // while it settles, which relays out the note and shifts the offset,
        // so set it again if a pass moved it.
        for _ in 0..<3 {
            let clamped = host.clampedOffset(target)
            if abs(textView.contentOffset.y - clamped) < 0.5 { break }
            textView.contentOffset.y = clamped
            textView.layoutIfNeeded()
        }
    }

    /// Starts the page breaks again, for a new layout: every paragraph is
    /// laid out afresh and the pushes worked out for it as it is reached.
    ///
    /// A page break is the paragraph below it pushed down (`PagePaginator`),
    /// and a new layout moves them all, so none carries over.
    func restartPagination() {
        let storage = textView.textStorage
        if let table = textView.blankLineLayout?.pushes {
            table.reset()
            if storage.length > 0 {
                // Regenerates every paragraph the text view has laid out,
                // without the pushes it had.
                table.isApplying = true
                storage.edited(.editedAttributes, range: NSRange(location: 0, length: storage.length), changeInLength: 0)
                table.isApplying = false
            }
        }
        if !textView.textContainer.exclusionPaths.isEmpty {
            textView.textContainer.exclusionPaths = []
        }
    }

    /// Puts every page break in place: passes over the note until none moves a
    /// paragraph. Also what the layout pass does, and what anything that has
    /// to know where lines are before the next pass calls (opening at a page,
    /// a search result).
    func paginate() {
        var changed = false
        for _ in 0..<(PagePaginator.passLimit + 2) {
            guard paginator.paginate(layout: pageLayout) else { break }
            changed = true
        }
        if changed { textView.setNeedsLayout() }
    }

    /// The note's height for text TextKit says is `height` tall: enough whole
    /// pages for the text and the ink.
    ///
    /// Idempotent. Fed its own answer back — as happens if anything sets the
    /// content size from the content size — the text's bottom lands at the end
    /// of the last page's body, which gives the same page count again.
    func noteHeight(forTextHeight height: CGFloat) -> CGFloat {
        let height = settledTextHeight() ?? height
        let textBottom = height - textView.textContainerInset.bottom
        pageCount = pageLayout.pageCount(textBottom: textBottom, inkBottom: host.inkBottom, minimum: host.minimumPageCount)
        return pageLayout.noteHeight(pageCount: pageCount)
    }

    /// The text's height with every page break in place, when an edit has left
    /// some unchecked; `nil` when none is, and TextKit's own height stands.
    ///
    /// UIKit sets the height as the text changes, before any layout pass, and
    /// after an edit that invalidated much of the note (the syntax colours
    /// arriving, a paste) TextKit's height for what it hasn't laid out again
    /// leaves out the pushes. A 10-page note read 9 pages for a moment, and
    /// UIKit pulled the reader's offset up to fit, 400pt, and back. So the
    /// breaks are worked out here, which lays the invalidated paragraphs out,
    /// and the height is the laid-out note's. It costs what the pass that
    /// would have run next costs, and is not run for the paragraph being typed
    /// in beyond that.
    private func settledTextHeight() -> CGFloat? {
        guard !isSettling,
              let table = textView.blankLineLayout?.pushes, table.through != Int.max,
              let manager = textView.textLayoutManager
        else { return nil }
        isSettling = true
        defer { isSettling = false }

        var moved = false
        for _ in 0..<(PagePaginator.passLimit + 2) {
            guard paginator.paginate(layout: pageLayout) else { break }
            moved = true
        }
        manager.ensureLayout(for: manager.documentRange)
        if moved { textView.setNeedsLayout() }
        let inset = textView.textContainerInset
        return manager.usageBoundsForTextContainer.maxY + inset.top + inset.bottom
    }

    /// Whether `settledTextHeight` is running, since it edits the storage and
    /// UIKit answers with another height.
    private var isSettling = false

    /// One more page at the end of the note, for ink or text to go on.
    func addPage() {
        raiseMinimum(to: pageCount + 1)
    }

    /// Seamless has no page ends to see, so a note keeps a blank page below
    /// its ink: when ink reaches the last page, there is one more. Compressed
    /// and print layout show their pages, and have Add Page.
    func keepPageBelowInk() {
        guard pageLayout.mode == .seamless, let inkBottom = host.inkBottom,
              pageLayout.pageIndex(atY: inkBottom) >= pageCount - 1
        else { return }
        raiseMinimum(to: pageCount + 1)
    }

    func raiseMinimum(to count: Int) {
        guard count > host.minimumPageCount else { return }
        host.minimumPageCount = count
        host.onMinimumPageCountChanged?(count)
    }

    /// Brings the page breaks, canvas and decorations up to the page count.
    ///
    /// A paragraph pushed to a new page makes one more page; the push only
    /// affects text below it, so this converges.
    func updatePageFurniture() {
        paginate()

        let noteHeight = pageLayout.noteHeight(pageCount: pageCount)
        host.canvas.noteSize = CGSize(width: pageLayout.pageSize.width, height: noteHeight)
        let visible = Self.visiblePart(
            ofNoteHeight: noteHeight,
            width: pageLayout.pageSize.width,
            scrolledTo: textView.contentOffset.y,
            viewHeight: textView.bounds.height
        )
        host.canvas.cover(visible)
        host.selectionOverlay.cover(visible)
        host.selection.regions = pageLayout.inkRegions(pageCount: pageCount)
        host.decorations.update(layout: pageLayout, pageCount: pageCount, height: noteHeight)
        host.covers.update(layout: pageLayout, pageCount: pageCount, height: noteHeight)
    }

    /// The part of the note on screen, which is all the canvas covers.
    ///
    /// Kept within the note, so a bounce past either end doesn't carry the
    /// canvas off it: the ink there has nothing to draw anyway.
    static func visiblePart(ofNoteHeight noteHeight: CGFloat, width: CGFloat, scrolledTo offset: CGFloat, viewHeight: CGFloat) -> CGRect {
        let height = min(max(viewHeight, 0), noteHeight)
        let top = min(max(offset, 0), noteHeight - height)
        return CGRect(x: 0, y: top, width: width, height: height)
    }
}

#endif
