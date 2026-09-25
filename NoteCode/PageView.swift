//
//  PageView.swift
//  NoteCode
//
//  The page: a paged, fixed-width text view, drawn at whatever scale fits.
//

#if canImport(UIKit)

import PaperKit
import UIKit

/// Hosts the editor at its pages' width, breaks its text into pages, and
/// draws it at the scale the area and the reader's zoom call for.
///
/// **Scale.** The text view still scrolls itself, and the scale is a transform
/// on it. A non-scrolling text view inside an outer zoom scroll view makes
/// TextKit 2's viewport the entire document: measured on 12 September 2026, a
/// 500-line note cost 477ms per keystroke against 11ms. This view scrolls only
/// sideways, when zoom makes the page wider than the area.
///
/// **Pages.** Text flows around a band after each page's body, set as the
/// text container's exclusion paths; `PageLayout` has the geometry and why
/// every mode paginates identically. The bands make typing cost more, because
/// TextKit lays out everything below an edit once any exclusion path exists —
/// see docs/phase-drawing-layer.md for the numbers.
final class PageView: UIScrollView, UIGestureRecognizerDelegate {

    let textView: DocumentUITextView

    /// The ink layer. A subview of the text view's content, so it scrolls with
    /// the text and is scaled by the same transform, with no code to keep the
    /// two in step.
    let canvas: DrawingCanvas

    /// Sheets in print layout, break lines in compressed. Behind the text.
    let decorations = PageDecorationView()

    /// The line around the page in the continuous modes, on its edges at
    /// whatever scale it's drawn. Print layout's sheets carry their own.
    let outline = UIView()

    /// The outline's corners, on screen.
    static let outlineCornerRadius: CGFloat = 16

    /// The pages' orientation and how they are shown.
    ///
    /// Changing the mode keeps the reader's place and shows ink on its page.
    /// Changing the orientation re-wraps the text at a new width, so neither
    /// can be carried over exactly: the place is kept proportionally, and ink
    /// keeps its printed position, which no longer sits on the same words.
    var pageLayout = PageLayout() {
        didSet {
            guard pageLayout != oldValue else { return }
            applyPageLayout(replacing: oldValue)
        }
    }

    /// The reader's zoom, relative to fitting the page's width to the area.
    private(set) var zoom: CGFloat = 1

    /// The scale the page is drawn at right now.
    private(set) var displayScale: CGFloat = 1

    /// How many pages the text and ink fill. Worked out whenever TextKit sets
    /// the text's height — see `noteHeight(forTextHeight:)`.
    private(set) var pageCount = 1

    /// How many pages the text currently has bands for.
    private var bandedPageCount = 0

    /// The note's ink, in print layout's coordinates: where each stroke sits
    /// on its sheet, which is also where it prints.
    ///
    /// The canvas shows it converted to the current mode, and every mode
    /// change converts from this rather than from the canvas. Ink in a sheet's
    /// margin has no exact place in a mode with narrower breaks — see
    /// `PageLayout.convert` — so converting what's on screen back and forth
    /// would move it a page on every round trip.
    private(set) var ink: PaperMarkup

    /// The lowest point of the ink as shown, cached so working out the page
    /// count — which every layout pass does — doesn't walk the strokes.
    private var inkBottom: CGFloat?

    /// Where each element sat when the canvas was last shown or read.
    ///
    /// What the reader draws, erases or moves is whatever differs from this.
    /// Everything else keeps the stored copy it already has, so ink that was
    /// never touched is never converted back from the screen — the round trip
    /// `ink` exists to avoid.
    private var shownElements: [MarkupOrderedSet.ElementID: CGRect] = [:]

    /// Called with the note's ink, in print coordinates, whenever the reader
    /// changes it: a stroke drawn, erased or moved.
    ///
    /// Not when ink is only shown — opened, or moved for a mode switch —
    /// since nothing needs saving then, and a save would bump the note up the
    /// list just for being looked at.
    var onInkChanged: ((PaperMarkup) -> Void)?

    private let pinch = UIPinchGestureRecognizer()
    private var zoomAtPinchStart: CGFloat = 1

    init(textView: DocumentUITextView) {
        let layout = PageLayout()
        self.textView = textView
        self.canvas = DrawingCanvas(pageSize: CGSize(
            width: layout.pageSize.width,
            height: layout.noteHeight(pageCount: 1)
        ))
        self.ink = PaperMarkup(bounds: CGRect(
            origin: .zero,
            size: CGSize(
                width: layout.pageSize.width,
                height: PageLayout(orientation: layout.orientation, mode: .print).noteHeight(pageCount: 1)
            )
        ))
        super.init(frame: .zero)

        // Neither scroll view should invent insets of its own. SwiftUI already
        // keeps this view clear of the keyboard and the safe area.
        contentInsetAdjustmentBehavior = .never
        textView.contentInsetAdjustmentBehavior = .never

        isDirectionalLockEnabled = true
        alwaysBounceVertical = false
        showsVerticalScrollIndicator = false
        addSubview(textView)

        // The line width is set here, never inferred. Left tracking the view,
        // a text view whose width is first set while it is scaled below 1x
        // sizes its container from the shrunken frame, and portrait and
        // landscape broke lines differently. Caught by
        // PageViewTests.identicalLineBreaks.
        textView.textContainer.widthTracksTextView = false

        // A note is always whole pages tall.
        textView.contentHeightAdjustment = { [weak self] height in
            self?.noteHeight(forTextHeight: height) ?? height
        }

        decorations.isUserInteractionEnabled = false
        textView.insertSubview(decorations, at: 0)

        // Over the text view rather than on it: the text view is scaled, and
        // a border of its own would thicken and thin with the zoom.
        outline.isUserInteractionEnabled = false
        outline.backgroundColor = .clear
        outline.layer.borderWidth = 1
        outline.layer.cornerRadius = Self.outlineCornerRadius
        outline.layer.cornerCurve = .continuous
        addSubview(outline)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (page: PageView, _) in
            page.resolveOutlineColor()
        }
        resolveOutlineColor()

        // Scrolling, transparency and who may draw are the canvas's own
        // business — see DrawingCanvas.
        canvas.onMarkupChanged = { [weak self] in self?.captureInk() }
        textView.addSubview(canvas)

        pinch.addTarget(self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        applyPageLayout(replacing: nil)

        textView.addLayoutObserver { [weak self] in
            self?.textViewDidLayout()
        }

        // An edit lays its paragraph out again in a new view, at the screen's
        // density, with no layout pass of the text view to raise it: the line
        // being typed stayed soft until the caret moved to another line (on
        // the iPad, and measured on the simulator, 25 September). TextKit's
        // own layout of what's on screen covers edits too, and comes before
        // the frame is drawn.
        textView.addViewportLayoutObserver { [weak self] in
            guard let self, pinch.state != .changed else { return }
            matchRenderingScale()
        }

#if DEBUG
        DebugSession.shared.attach(self)
#endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        let area = bounds.size
        guard area.width > 0, area.height > 0 else { return }

        apply(scale: CanvasGeometry.displayScale(
            areaWidth: area.width,
            pageWidth: pageLayout.pageSize.width,
            zoom: zoom,
            gutter: CanvasGeometry.gutter(for: pageLayout.mode)
        ))
    }

    /// Draws the page at `scale` in the current area.
    private func apply(scale: CGFloat) {
        let area = bounds.size
        let pageWidth = pageLayout.pageSize.width
        let frame = CanvasGeometry.pageFrame(in: area, pageWidth: pageWidth, scale: scale)
        let pageSize = CanvasGeometry.pageBounds(in: area, pageWidth: pageWidth, scale: scale)

        displayScale = scale
        if textView.transform.a != scale {
            textView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }

        // Size only, never origin: a scroll view's bounds origin is its scroll
        // position, and that is in page points, so it survives a scale change
        // untouched. The line at the top stays at the top through a rotation.
        if textView.bounds.size != pageSize {
            textView.bounds.size = pageSize
            pinLineWidth()
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        if textView.center != center {
            textView.center = center
        }
        placeOutline()

        let content = CGSize(width: max(area.width, frame.width), height: area.height)
        if contentSize != content {
            contentSize = content
        }

        // Re-rendering every line on every frame of a pinch would stutter.
        // The pinch's end catches up.
        if pinch.state != .changed {
            matchRenderingScale()
        }
    }

    /// Puts the outline on the page's edges, and rounds the page's corners to
    /// match — in page points, since the text view is scaled.
    ///
    /// Print layout has none: each sheet has an edge of its own, and a line
    /// around the column would run down the sheets' sides and across the
    /// surround between them.
    private func placeOutline() {
        let continuous = pageLayout.mode != .print
        outline.isHidden = !continuous
        if outline.frame != textView.frame {
            outline.frame = textView.frame
        }
        let radius = continuous && displayScale > 0 ? Self.outlineCornerRadius / displayScale : 0
        if textView.layer.cornerRadius != radius {
            textView.layer.cornerRadius = radius
            textView.layer.cornerCurve = .continuous
        }
    }

    private func resolveOutlineColor() {
        outline.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    }

    /// Sets the text container to the pages' text width.
    private func pinLineWidth() {
        let width = pageLayout.textWidth
        if textView.textContainer.size.width != width {
            textView.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        }
    }

    /// Runs after every layout pass of the text view, which includes every
    /// scroll, but not every edit.
    private func textViewDidLayout() {
#if DEBUG
        defer { DebugSession.shared.pageDidLayout(self) }
#endif
        updatePageFurniture()
        if pinch.state != .changed {
            matchRenderingScale()
        }
    }

    // MARK: Pages

    /// Puts a layout's margins, bands and decorations in place.
    ///
    /// - Parameter old: the layout being replaced, or `nil` when first set.
    private func applyPageLayout(replacing old: PageLayout?) {
        // Where the reader is, taken before anything moves. Within one
        // orientation every mode paginates the same, so this converts by
        // page. A new orientation re-wraps the text and no position converts,
        // so there the line at the top is kept instead.
        let offset = textView.contentOffset.y
        let anchor = old.map { $0.orientation != pageLayout.orientation } == true ? topLineCharacter() : nil
        let oldTextBottom = textView.textContentHeight - textView.textContainerInset.bottom

        if old != nil {
            showInk()
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
        pinLineWidth()

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
        backgroundColor = pageLayout.mode == .print ? .secondarySystemBackground : .clear
        placeOutline()

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
        setNeedsLayout()
        layoutIfNeeded()
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
        } else if let anchor, let top = lineTop(atCharacter: anchor) {
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
            textView.contentOffset.y = clampedOffset(textView.contentOffset.y)
            return
        }

        // Within one orientation the page count is right from the start, so
        // nothing reassigns the bands after this and the first set sticks.
        // Across orientations the text re-wraps and the count can still move
        // while it settles, which relays out the note and shifts the offset,
        // so set it again if a pass moved it.
        for _ in 0..<3 {
            let clamped = clampedOffset(target)
            if abs(textView.contentOffset.y - clamped) < 0.5 { break }
            textView.contentOffset.y = clamped
            textView.layoutIfNeeded()
        }
    }

    /// A vertical scroll offset kept within the note.
    private func clampedOffset(_ y: CGFloat) -> CGFloat {
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

    /// Sets the bands text flows around, one after each page.
    private func applyBands() {
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
    private func noteHeight(forTextHeight height: CGFloat) -> CGFloat {
        let textBottom = height - textView.textContainerInset.bottom
        pageCount = pageLayout.pageCount(textBottom: textBottom, inkBottom: inkBottom)
        return pageLayout.noteHeight(pageCount: pageCount)
    }

    /// Brings the bands, canvas and decorations up to the page count.
    ///
    /// A line pushed past the last page's band makes one more page; its band
    /// only affects text below it, so this converges. Reassigning exclusion
    /// paths relays out the text, so only when the count has changed.
    private func updatePageFurniture() {
        if bandedPageCount != pageCount {
            applyBands()
        }

        let noteHeight = pageLayout.noteHeight(pageCount: pageCount)
        canvas.noteSize = CGSize(width: pageLayout.pageSize.width, height: noteHeight)
        canvas.cover(Self.visiblePart(
            ofNoteHeight: noteHeight,
            width: pageLayout.pageSize.width,
            scrolledTo: textView.contentOffset.y,
            viewHeight: textView.bounds.height
        ))
        decorations.update(layout: pageLayout, pageCount: pageCount, height: noteHeight)
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

    // MARK: Ink

    /// Replaces the note's ink.
    ///
    /// - Parameter drawing: strokes in print layout's coordinates, for this
    ///   note's orientation — the form ink is stored and printed in.
    func setInk(_ markup: PaperMarkup) {
        ink = markup
        showInk()
    }

    /// Puts the ink on the canvas, converted to the current mode.
    ///
    /// Strokes drawn on the canvas are converted the other way as they arrive,
    /// each on its own page, rather than by converting the whole canvas back —
    /// that round trip is what `ink` exists to avoid.
    private func showInk() {
        let print = PageLayout(orientation: pageLayout.orientation, mode: .print)
        var shown = canvas.markup

        if shown.subelements.isEmpty {
            // Nothing on the canvas to reconcile with: hand it the stored ink,
            // converted, in one go.
            canvas.markup = PageView.convert(ink, from: print, to: pageLayout) ?? ink
        } else {
            // The canvas has its own copy of these elements, and a markup
            // *merges* what it is given rather than replacing it. A copy made
            // from `ink` branched before the canvas's own edits, so assigning
            // it changes nothing — measured on 19 September, when ink stayed
            // where it was drawn through every mode. Moving the canvas's own
            // elements, by the distance its stored copy says, is what takes.
            let stored = Dictionary(
                ink.subelements.map { ($0.elementID, $0) },
                uniquingKeysWith: { _, last in last }
            )

            for id in Set(shown.subelements.ids) where stored[id] == nil {
                shown.subelements.removeElement(for: id)
            }
            let onCanvas = Set(shown.subelements.ids)
            for (id, element) in stored where !onCanvas.contains(id) {
                shown.subelements.updateOrAppend(element)
            }

            var placed = MarkupOrderedSet()
            for element in shown.subelements {
                guard let original = stored[element.elementID] else { continue }
                let target = print.convert(y: original.renderFrame.midY, to: pageLayout)
                    ?? original.renderFrame.midY
                var element = element
                let delta = target - element.renderFrame.midY
                if abs(delta) > 0.001 {
                    element.applyTransform(CGAffineTransform(translationX: 0, y: delta))
                }
                placed.append(element)
            }
            shown.subelements = placed
            canvas.markup = shown
        }

        // Ink just moved under whatever the undo stack was holding: its
        // actions restore strokes to the mode they were drawn in.
        canvas.forgetUndo()

        shownElements = PageView.frames(of: canvas.markup)
        inkBottom = canvas.markup.subelements.isEmpty ? nil : canvas.markup.contentsRenderFrame.maxY
        // The page count depends on the ink, and nothing about the text changed.
        textView.reapplyContentHeightAdjustment()
        textView.setNeedsLayout()
    }

    /// Takes what the reader just drew, erased or moved into `ink`.
    ///
    /// Only what changed is converted into print coordinates. An element
    /// that hasn't moved keeps the stored copy it came from, because
    /// converting out of a mode with narrow breaks isn't exact: ink in a
    /// sheet's margin has no place in seamless, so a round trip there and
    /// back would walk it onto the next page.
    private func captureInk() {
        let shown = canvas.markup
        let print = PageLayout(orientation: pageLayout.orientation, mode: .print)
        let shownIDs = Set(shown.subelements.ids)
        let storedIDs = Set(ink.subelements.ids)

        var updated = ink
        var changed = false

        // Erased. A markup merges rather than replaces, so leaving an element
        // out of a new set keeps it; taking it out is a call of its own.
        for id in storedIDs where !shownIDs.contains(id) {
            updated.subelements.removeElement(for: id)
            changed = true
        }

        // Drawn, or moved by the lasso. Everything else keeps the copy it
        // already has, so ink nobody touched is never converted back from the
        // screen — the round trip `ink` exists to avoid.
        for element in shown.subelements {
            let id = element.elementID
            guard !storedIDs.contains(id) || shownElements[id] != element.renderFrame else { continue }
            updated.subelements.updateOrAppend(PageView.moved(element, from: pageLayout, to: print))
            changed = true
        }

        guard changed else { return }
        ink = updated
        onInkChanged?(updated)

        shownElements = PageView.frames(of: shown)
        inkBottom = shown.subelements.isEmpty ? nil : shown.contentsRenderFrame.maxY
        // Ink below the last line makes the note longer, and nothing about the
        // text changed to trigger that on its own.
        textView.reapplyContentHeightAdjustment()
        textView.setNeedsLayout()
    }

    /// Where each element sits, by id.
    private static func frames(of markup: PaperMarkup) -> [MarkupOrderedSet.ElementID: CGRect] {
        Dictionary(
            markup.subelements.map { ($0.elementID, $0.renderFrame) },
            uniquingKeysWith: { _, last in last }
        )
    }

    /// One element at the same place on its page in another layout.
    ///
    /// An element belongs to the page its middle is on, so a stroke drawn
    /// across a page break travels whole rather than being torn in two.
    private static func moved(_ element: any Markup, from old: PageLayout, to new: PageLayout) -> any Markup {
        var element = element
        let middle = element.renderFrame.midY
        if let target = old.convert(y: middle, to: new), target != middle {
            element.applyTransform(CGAffineTransform(translationX: 0, y: target - middle))
        }
        return element
    }

    /// The ink with every element moved to the same place on its page in
    /// another layout, or `nil` when there's no such place — a different
    /// orientation wraps text at another width.
    ///
    /// Built in one pass and assigned once. Moving elements one at a time
    /// through `updateOrAppend` costs more the more there are: 3.3s for a
    /// thousand strokes against 56ms this way, measured on 19 September.
    static func convert(_ markup: PaperMarkup, from old: PageLayout, to new: PageLayout) -> PaperMarkup? {
        guard old.orientation == new.orientation else { return nil }
        guard old != new else { return markup }

        var moved = MarkupOrderedSet()
        for element in markup.subelements {
            moved.append(PageView.moved(element, from: old, to: new))
        }

        var result = markup
        result.subelements = moved
        return result
    }

    // MARK: Zoom

    /// Zooms to `newZoom`, keeping what's under `focus` under it.
    ///
    /// - Parameter focus: a point in this view's visible area, in screen
    ///   points from its top left.
    func setZoom(_ newZoom: CGFloat, about focus: CGPoint) {
        let area = bounds.size
        guard area.width > 0, area.height > 0 else { return }

        let clamped = CanvasGeometry.clampedZoom(newZoom)
        let pageWidth = pageLayout.pageSize.width
        let next = CanvasGeometry.zoom(
            CanvasGeometry.Viewport(
                scale: displayScale,
                horizontalOffset: contentOffset.x,
                verticalOffset: textView.contentOffset.y
            ),
            to: CanvasGeometry.displayScale(
                areaWidth: area.width,
                pageWidth: pageWidth,
                zoom: clamped,
                gutter: CanvasGeometry.gutter(for: pageLayout.mode)
            ),
            about: focus,
            area: area,
            pageWidth: pageWidth,
            noteHeight: textView.contentSize.height
        )

        zoom = clamped
        apply(scale: next.scale)
        contentOffset.x = next.horizontalOffset
        textView.contentOffset.y = next.verticalOffset
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            zoomAtPinchStart = zoom
            // Two fingers moving apart also look like a scroll. Stop both
            // scroll views taking a share of the gesture while it zooms.
            setPanning(enabled: false)
        case .changed:
            let location = gesture.location(in: self)
            let focus = CGPoint(x: location.x - contentOffset.x, y: location.y - contentOffset.y)
            setZoom(zoomAtPinchStart * gesture.scale, about: focus)
        case .ended, .cancelled, .failed:
            setPanning(enabled: true)
            matchRenderingScale()
        default:
            break
        }
    }

    private func setPanning(enabled: Bool) {
        panGestureRecognizer.isEnabled = enabled
        textView.panGestureRecognizer.isEnabled = enabled
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // A scroll already under way mustn't keep the pinch from starting.
        gestureRecognizer === pinch && (other === panGestureRecognizer || other === textView.panGestureRecognizer)
    }

    // MARK: Rendering

    /// Renders text at the density it is actually shown at, up to a cap.
    ///
    /// A transform scales pixels that were drawn at the screen's own density,
    /// so text drawn at 1x and shown at 1.25x is soft. Raising the content
    /// scale makes TextKit draw it at the density it lands on. Newly created
    /// fragment views arrive at the default, which is why this also runs after
    /// every text view layout and every layout of the text on screen; it only
    /// touches a view whose value is wrong.
    ///
    /// The canvas is left out: PaperKit keeps its own views' scale, and draws
    /// ink at the density it's shown at by zooming instead — see
    /// `DrawingCanvas.renderScale`.
    private func matchRenderingScale() {
        let value = CanvasGeometry.renderingScale(
            displayScale: displayScale,
            screenScale: traitCollection.displayScale
        )
        Self.setRenderingScale(value, in: textView, skipping: canvas)
        canvas.renderScale = min(displayScale, CanvasGeometry.maximumRenderingScale)
    }

    private static func setRenderingScale(_ value: CGFloat, in view: UIView, skipping excluded: UIView) {
        guard view !== excluded else { return }
        if view.contentScaleFactor != value {
            view.contentScaleFactor = value
        }
        for subview in view.subviews {
            setRenderingScale(value, in: subview, skipping: excluded)
        }
    }
}

// MARK: - Decorations

/// What a view mode draws behind the text: nothing for seamless, a dashed
/// line at each break for compressed, a sheet of paper per page for print.
///
/// One small view or layer per page rather than one tall drawing. A drawn
/// view as tall as a forty-page note would need a backing store to match.
final class PageDecorationView: UIView {

    private var sheets: [UIView] = []
    private var breaks: [CAShapeLayer] = []
    private var layout: PageLayout?
    private var pageCount = 0

    /// Sheet frames in note coordinates, for tests.
    var sheetFrames: [CGRect] { sheets.map(\.frame) }

    /// Each sheet's border width, for tests.
    var sheetBorderWidths: [CGFloat] { sheets.map(\.layer.borderWidth) }

    /// Break line heights in note coordinates, for tests.
    var breakLineYs: [CGFloat] { breaks.map { $0.frame.midY } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: PageDecorationView, _) in
            view.resolveColors()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(layout: PageLayout, pageCount: Int, height: CGFloat) {
        let frame = CGRect(x: 0, y: 0, width: layout.pageSize.width, height: height)
        if self.frame != frame {
            self.frame = frame
        }
        guard layout != self.layout || pageCount != self.pageCount else { return }
        self.layout = layout
        self.pageCount = pageCount

        let sheetCount = layout.mode == .print ? pageCount : 0
        while sheets.count < sheetCount {
            let sheet = UIView()
            sheet.backgroundColor = .systemBackground
            sheet.layer.shadowColor = UIColor.black.cgColor
            sheet.layer.shadowOpacity = 0.12
            sheet.layer.shadowRadius = 6
            sheet.layer.shadowOffset = CGSize(width: 0, height: 2)
            // The page's border, in both appearances. The shadow lifts the
            // sheet off the surround in light mode; dark mode swallows it.
            sheet.layer.borderWidth = 1
            addSubview(sheet)
            sheets.append(sheet)
        }
        while sheets.count > sheetCount {
            sheets.removeLast().removeFromSuperview()
        }
        for (index, sheet) in sheets.enumerated() {
            sheet.frame = layout.sheet(ofPage: index)
            sheet.layer.shadowPath = UIBezierPath(rect: sheet.bounds).cgPath
        }

        let breakCount = layout.mode == .compressed ? max(pageCount - 1, 0) : 0
        while breaks.count < breakCount {
            let line = CAShapeLayer()
            line.lineWidth = 1
            line.lineDashPattern = [6, 5]
            line.fillColor = nil
            layer.addSublayer(line)
            breaks.append(line)
        }
        while breaks.count > breakCount {
            breaks.removeLast().removeFromSuperlayer()
        }
        for (index, line) in breaks.enumerated() {
            line.frame = CGRect(x: 0, y: layout.breakLineY(afterPage: index) - 0.5, width: frame.width, height: 1)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: PageLayout.margin / 2, y: 0.5))
            path.addLine(to: CGPoint(x: frame.width - PageLayout.margin / 2, y: 0.5))
            line.path = path.cgPath
        }

        resolveColors()
    }

    /// CALayer colours are plain CGColors and don't follow dark mode on their
    /// own, so they're re-resolved whenever the appearance changes.
    private func resolveColors() {
        let separator = UIColor.separator.resolvedColor(with: traitCollection).cgColor
        for sheet in sheets {
            sheet.layer.borderColor = separator
        }
        for line in breaks {
            line.strokeColor = separator
        }
    }
}

#endif
