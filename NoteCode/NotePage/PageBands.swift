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

    /// How many pages the text currently has bands for.
    private var bandedPageCount = 0

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
        applyBands()
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

    /// Sets the bands text flows around, one after each page.
    func applyBands() {
        bandedPageCount = pageCount
        textView.textContainer.exclusionPaths = pageLayout
            .exclusionBands(pageCount: pageCount, containerTop: textView.textContainerInset.top)
            .map { UIBezierPath(rect: $0) }
    }

    /// The note's height for text TextKit says is `height` tall: enough whole
    /// pages for the text and the ink.
    ///
    /// Idempotent. Fed its own answer back — as happens if anything sets the
    /// content size from the content size — the text's bottom lands at the end
    /// of the last page's body, which gives the same page count again.
    func noteHeight(forTextHeight height: CGFloat) -> CGFloat {
        let textBottom = height - textView.textContainerInset.bottom
        pageCount = pageLayout.pageCount(textBottom: textBottom, inkBottom: host.inkBottom, minimum: host.minimumPageCount)
        return pageLayout.noteHeight(pageCount: pageCount)
    }

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

    /// Brings the bands, canvas and decorations up to the page count.
    ///
    /// A line pushed past the last page's band makes one more page; its band
    /// only affects text below it, so this converges. Reassigning exclusion
    /// paths relays out the text, so only when the count has changed.
    func updatePageFurniture() {
        if bandedPageCount != pageCount {
            applyBands()
        }

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
