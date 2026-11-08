//
//  PageView.swift
//  NoteCode
//
//  The page: a paged, fixed-width text view, drawn at whatever scale fits.
//

#if canImport(UIKit)

import PaperKit
import PencilKit
import SwiftUI
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
/// see docs/archive/phase-drawing-layer.md for the numbers.
final class PageView: UIScrollView, UIGestureRecognizerDelegate, PageInkHost, PageScrollIndicatorHost, PageZoomHost, PageKeyboardInsetHost, PageBandsHost, PageReadingHost {

    let textView: DocumentUITextView

    /// The ink layer. A subview of the text view's content, so it scrolls with
    /// the text and is scaled by the same transform, with no code to keep the
    /// two in step.
    let canvas: DrawingCanvas

    /// The Select tool: what is selected on the canvas, and the view that
    /// owns touches while it is the tool (docs/design/object-system.md).
    let selection: InkSelection
    let selectionOverlay: InkSelectionOverlay

    /// Sheets in print layout, break lines in compressed. Behind the text.
    let decorations = PageDecorationView()

    /// Over the ink, where seamless has no room — see `PageCoverView`.
    let covers = PageCoverView()

    /// What the page is painted, and what shows beside it. Dynamic colours:
    /// white on #F2F2F7 in light, black on #1C1C1E in dark.
    static let pageColor = UIColor.systemBackground
    static let surroundColor = UIColor.secondarySystemBackground

    /// The note's scroll indicator, at this view's edge.
    private lazy var scrollIndicator = PageScrollIndicator(host: self)
    private var lastPanTranslation = CGPoint.zero
    private let sidewaysFling = SidewaysFling()
    /// The page's edge: a hairline and a soft shadow behind the text view
    /// in the continuous modes (print layout's sheets have their own).
    private let pageEdge = PageEdgeView()

    /// The pages' orientation and how they are shown.
    ///
    /// Changing the mode keeps the reader's place and shows ink on its page.
    /// Changing the orientation re-wraps the text at a new width, so neither
    /// can be carried over exactly: the place is kept proportionally, and ink
    /// keeps its printed position, which no longer sits on the same words.
    var pageLayout = PageLayout() {
        didSet {
            guard pageLayout != oldValue else { return }
            bands.applyPageLayout(replacing: oldValue)
        }
    }

    /// The reader's zoom, relative to fitting the page's width to the area
    /// (`PageZoom`).
    private lazy var zoomControl = PageZoom(host: self)
    var zoom: CGFloat { zoomControl.zoom }

    /// The area's width when the page was last fitted to it, so a change of
    /// width re-centres a page fitted to its text column.
    private var fittedWidth: CGFloat = 0

    /// Told which page the reader is on whenever that changes, or the page
    /// count does: the device remembers it for next time. Held back until the
    /// note has been scrolled to where it is opening (`restore`), so opening
    /// at page 4 doesn't first report page 1.
    var onReadingPlaceChanged: ((NoteMemory.Place) -> Void)?

    /// Told whenever the note scrolls, with the page then at the top: the
    /// page badge shows while this keeps arriving and fades once it stops.
    /// Unlike the reading place this fires on every move, not only on a new
    /// page, since a scroll within a page still keeps the badge up.
    var onScrolled: ((NoteMemory.Place) -> Void)?

    /// Where the note opens, search and the outline scroll to, and the reading
    /// place and scroll are reported from (`PageReading`).
    private lazy var reading = PageReading(host: self)

    /// The page at the top of the view, and how many pages the note has.
    var readingPlace: NoteMemory.Place { reading.readingPlace }

    /// Opens the note at the top of page `index` (counted from 0) once it has
    /// laid out. A search's match wins if both are asked for.
    func restore(toPage index: Int) { reading.restore(toPage: index) }

    /// Shows a search result once the note is laid out: scrolled so the
    /// first match sits near the top, and every match highlighted.
    func reveal(_ first: NSRange, highlighting all: [NSRange]) {
        reading.reveal(first, highlighting: all)
    }

    /// Scrolls so the line holding `character` is the first the reader sees.
    func scroll(toLineAt character: Int) { reading.scroll(toLineAt: character) }

    /// The character that starts the first line reaching below the top of
    /// the view. Internal for `DebugStateReport`.
    func topLineCharacter() -> Int? { reading.topLineCharacter() }

    /// The top of the line holding `character`, in note coordinates.
    func lineTop(atCharacter character: Int) -> CGFloat? { reading.lineTop(atCharacter: character) }

    /// A vertical scroll offset kept within the note.
    func clampedOffset(_ y: CGFloat) -> CGFloat { reading.clampedOffset(y) }

    /// The scale the page is drawn at right now.
    private(set) var displayScale: CGFloat = 1

    /// The pages: the layout's margins and bands, and the page count
    /// (`PageBands`).
    private lazy var bands = PageBands(host: self)

    /// How many pages the text and ink fill. Worked out whenever TextKit sets
    /// the text's height — see `PageBands.noteHeight(forTextHeight:)`.
    var pageCount: Int { bands.pageCount }

    /// Puts every page break in place now, rather than at the next layout pass.
    /// For what has to know where lines are before then.
    func paginate() {
        bands.paginate()
    }

    /// The fewest pages the note has (`Page.minimumPageCount`): Add Page
    /// raises it, and so does ink reaching the last page in seamless.
    /// Setting it from outside only follows the note; it is told onward
    /// (`onMinimumPageCountChanged`) only when this view raises it.
    var minimumPageCount = 1 {
        didSet {
            guard minimumPageCount != oldValue else { return }
            textView.reapplyContentHeightAdjustment()
            textView.setNeedsLayout()
        }
    }

    /// Told the new minimum when this view raises it, so the note keeps it.
    var onMinimumPageCountChanged: ((Int) -> Void)?

    /// Whether a stroke the reader ends in the last page's foot adds a page
    /// (`InkPageGrowth`). Seamless keeps a blank page below ink regardless.
    var addsPagesWhileDrawing = InkPageGrowth.defaultEnabled

    /// The note's ink, in print layout's coordinates: where each stroke sits
    /// on its sheet, which is also where it prints.
    ///
    /// The canvas shows it converted to the current mode, and every mode
    /// change converts from this rather than from the canvas. Ink in a sheet's
    /// margin has no exact place in a mode with narrower breaks — see
    /// `PageLayout.convert` — so converting what's on screen back and forth
    /// would move it a page on every round trip.
    ///
    /// Strokes the reader made are taken in off the main thread
    /// (`captureInk`), so reading this first finishes any still on their way.
    var ink: PaperMarkup {
        commitInk()
        return inkPipeline.state.ink
    }

    /// The stored ink, the snapshot on its way in, the generation and the
    /// ink's lowest point (`PageInkPipeline`).
    /// Internal for `PageViewTests.redrawCost`.
    let inkPipeline: PageInkPipeline

    /// Called with the note's ink, in print coordinates, whenever the reader
    /// changes it: a stroke drawn, erased or moved.
    ///
    /// Not when ink is only shown — opened, or moved for a mode switch —
    /// since nothing needs saving then, and a save would bump the note up the
    /// list just for being looked at.
    var onInkChanged: ((PaperMarkup) -> Void)?

    /// Which touches scroll the note on the canvas, for the mode. Set by
    /// `NoteEditor`; off the canvas, `offCanvas` applies instead.
    var scrolling = PageScrolling.standard {
        didSet {
            guard scrolling != oldValue else { return }
            for pan in pans {
                scrolling.apply(to: pan)
            }
        }
    }

    /// The pans that scroll the note: the text view's, up and down, and this
    /// view's, sideways when zoomed in.
    private var pans: [UIPanGestureRecognizer] {
        [textView.panGestureRecognizer]
    }

    init(textView: DocumentUITextView) {
        let layout = PageLayout()
        self.textView = textView
        self.canvas = DrawingCanvas(pageSize: CGSize(
            width: layout.pageSize.width,
            height: layout.noteHeight(pageCount: 1)
        ))
        let selection = InkSelection()
        self.selection = selection
        self.selectionOverlay = InkSelectionOverlay(selection: selection)
        self.inkPipeline = PageInkPipeline(state: InkCapture.State(ink: PaperMarkup(bounds: CGRect(
            origin: .zero,
            size: CGSize(
                width: layout.pageSize.width,
                height: PageLayout(orientation: layout.orientation, mode: .print).noteHeight(pageCount: 1)
            )
        ))))
        super.init(frame: .zero)
        inkPipeline.host = self

        // Neither scroll view should invent insets of its own. SwiftUI keeps
        // this view clear of the safe area, but not of the keyboard: the page
        // area ignores that, so the page never resizes for it, and
        // `keyboardWillChangeFrame` insets the text view by what's covered.
        contentInsetAdjustmentBehavior = .never
        textView.contentInsetAdjustmentBehavior = .never

        isDirectionalLockEnabled = false
        alwaysBounceVertical = false
        showsVerticalScrollIndicator = false
        // The text view is what scrolls, and its own indicator sits inside the
        // page sheet. The note's indicator is `scrollIndicator`, at the
        // window's edge.
        textView.showsVerticalScrollIndicator = false
        addSubview(pageEdge)
        addSubview(textView)
        adoptTextViewPan()

        // A Duo folding or unfolding changes the size class, and with it
        // whether the page is fitted by its text column.
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (view: PageView, _) in
            view.setNeedsLayout()
        }

        // The line width is set here, never inferred. Left tracking the view,
        // a text view whose width is first set while it is scaled below 1x
        // sizes its container from the shrunken frame, and portrait and
        // landscape broke lines differently. Caught by
        // PageViewTests.identicalLineBreaks.
        textView.textContainer.widthTracksTextView = false

        // A note is always whole pages tall.
        textView.contentHeightAdjustment = { [weak self] height in
            self?.bands.noteHeight(forTextHeight: height) ?? height
        }

        decorations.isUserInteractionEnabled = false
        textView.insertSubview(decorations, at: 0)

        // Scrolling, transparency and who may draw are the canvas's own
        // business — see DrawingCanvas.
        canvas.onMarkupChanged = { [weak self] in self?.inkPipeline.capture() }
        canvas.takesTouch = { [weak self] point in
            guard let self else { return true }
            return pageLayout.takesInk(at: point, pageCount: pageCount)
        }
        textView.addSubview(canvas)
        textView.insertSubview(covers, aboveSubview: canvas)
        selection.canvas = canvas
        selectionOverlay.takesTouch = canvas.takesTouch
        textView.insertSubview(selectionOverlay, aboveSubview: covers)

        zoomControl.install()

        bands.applyPageLayout(replacing: nil)

        // The page breaks first: they decide the note's height, which UIKit
        // reads while it lays out.
        textView.addWillLayoutObserver { [weak self] in
            self?.bands.paginate()
        }
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
            guard let self, !zoomControl.isPinching else { return }
            matchRenderingScale()
        }

        keyboardInset.install()

#if DEBUG
        DebugSession.shared.attach(self)
#endif
    }

    // MARK: Keyboard and the hotbar

    /// The room the page keeps for the keyboard and the hotbar, and its move
    /// with the hotbar (`PageKeyboardInset`).
    private lazy var keyboardInset = PageKeyboardInset(host: self)

    var windowFrameForScreenFrame: (CGRect, UIWindow) -> CGRect {
        get { keyboardInset.windowFrameForScreenFrame }
        set { keyboardInset.windowFrameForScreenFrame = newValue }
    }

    /// Room to leave above the keyboard, in screen points: the hotbar's, when
    /// it is docked at the bottom.
    var keyboardClearance: CGFloat {
        get { keyboardInset.keyboardClearance }
        set { keyboardInset.keyboardClearance = newValue }
    }

    /// Room the bottom of the text keeps from the area's edge, in screen
    /// points, for a hotbar floating over the bottom of the page.
    var restingClearance: CGFloat {
        get { keyboardInset.restingClearance }
        set { keyboardInset.restingClearance = newValue }
    }

    /// The space SwiftUI gives the page, as the edges it leaves.
    var areaInsets: UIEdgeInsets { keyboardInset.areaInsets }

    /// The page's area is about to become `insets` less than the window, and
    /// the page should get there with `animation`.
    func areaWillChange(to insets: UIEdgeInsets, animation: Animation?) {
        keyboardInset.areaWillChange(to: insets, animation: animation)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        keyboardInset.pageDidMoveToWindow()
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

        let motion = keyboardInset.takeAreaMotion()
        let before = keyboardInset.lastPlaceOnScreen

        let scale = CanvasGeometry.displayScale(
            areaWidth: area.width,
            pageWidth: pageLayout.pageSize.width,
            columnWidth: columnWidth,
            zoom: zoom,
            gutter: CanvasGeometry.gutter(for: pageLayout.mode)
        )
        let refitted = scale != displayScale || area.width != fittedWidth
        apply(scale: scale)

        // Fitted to its text column, the page is wider than the area: show
        // the column, with the margins cut evenly either side, rather than
        // the left margin and the column's start. Only when the fit itself
        // changes (opening, rotating, a narrower window), never under a
        // reader who has panned or zoomed.
        if refitted, zoom == 1 {
            fittedWidth = area.width
            contentOffset.x = CanvasGeometry.centredOffset(
                areaWidth: area.width, pageWidth: pageLayout.pageSize.width, scale: scale
            )
        }

        if let motion, let before {
            keyboardInset.movePage(from: before, with: motion)
        }
        if window != nil {
            keyboardInset.lastPlaceOnScreen = (convert(textView.center, to: nil), displayScale, textView.bounds.size)
        }
    }

    /// The text column, offered for fitting in a compact width only: an
    /// iPhone, a folded Duo, a narrow Split View (`CanvasGeometry.fitScale`).
    var columnWidth: CGFloat? {
        guard traitCollection.horizontalSizeClass == .compact else { return nil }
        return CanvasGeometry.columnWidth(textWidth: pageLayout.textWidth)
    }

    /// Draws the page at `scale` in the current area.
    func apply(scale: CGFloat) {
        let area = bounds.size
        let pageWidth = pageLayout.pageSize.width
        let frame = CanvasGeometry.pageFrame(in: area, pageWidth: pageWidth, scale: scale)
        let pageSize = CanvasGeometry.pageBounds(in: area, pageWidth: pageWidth, scale: scale)

        let scaleChanged = displayScale != scale
        displayScale = scale
        if scaleChanged {
            keyboardInset.displayScaleChanged()
        }
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
        paintPage()
        pageEdge.isHidden = pageLayout.mode == .print
        if pageEdge.frame != textView.frame {
            pageEdge.frame = textView.frame
        }

        let content = CGSize(width: max(area.width, frame.width), height: area.height)
        if contentSize != content {
            contentSize = content
        }

        // Re-rendering every line on every frame of a pinch would stutter.
        // The pinch's end catches up.
        if !zoomControl.isPinching {
            matchRenderingScale()
        }
    }

    /// Paints the page against its surround.
    ///
    /// The page has no border and square corners (16 Oct, roadmap step 5): it
    /// fills its window, and the colours alone say where it ends.
    func paintPage() {
        let continuous = pageLayout.mode != .print

        // The page against its surround, in every mode. The view itself is
        // the surround: it shows beside the page, and in print layout between
        // the sheets. The continuous modes' page is a column the text view's
        // width, so the text view paints it — under the text, the break
        // decorations and the canvas, which are all its subviews. Print
        // layout's text view stays clear, since its sheets carry
        // the page colour and the surround must show between them. Set by
        // mode, not once, so a switch can't leave the column behind.
        backgroundColor = Self.surroundColor
        let fill = continuous ? Self.pageColor : UIColor.clear
        if textView.backgroundColor != fill {
            textView.backgroundColor = fill
        }
    }

    /// Sets the text container to the pages' text width.
    func pinLineWidth() {
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
        bands.updatePageFurniture()
        if !zoomControl.isPinching {
            matchRenderingScale()
        }
        reading.textViewDidLayout()
    }

    // MARK: Re-wrapping

    /// Runs a change that re-wraps the text (a new text size), and puts the
    /// reader back on the line they were reading.
    ///
    /// A re-wrap moves every line, and no scroll offset converts across it,
    /// so the line at the top is kept instead, as for a new orientation (see
    /// `applyPageLayout`). The same two precautions: the page count comes out
    /// right before the bands it sets (the count is worked out from the text
    /// as TextKit sets its height, here the new layout's), and TextKit is
    /// re-anchored at the top of the note before going back, or it keeps
    /// the old layout's viewport and the lines on screen sit a stale
    /// break's worth off.
    func reflow(_ change: () -> Void) {
        let anchor = reading.topLineCharacter()
        change()

        setNeedsLayout()
        layoutIfNeeded()
        textView.layoutIfNeeded()
        textView.contentOffset.y = 0
        setNeedsLayout()
        layoutIfNeeded()
        textView.layoutIfNeeded()

        guard let anchor, anchor > 0 else {
            textView.contentOffset.y = clampedOffset(0)
            return
        }
        reading.layOut(downTo: anchor)
        reading.settleOffset(onLineAt: anchor)
    }

    // MARK: Pages

    /// One more page at the end of the note, for ink or text to go on.
    func addPage() {
        bands.addPage()
    }

    // MARK: Ink

    var inkBottom: CGFloat? { inkPipeline.bottom }

    func showInk() {
        inkPipeline.show()
    }

    /// Replaces the note's ink.
    ///
    /// - Parameter drawing: strokes in print layout's coordinates, for this
    ///   note's orientation — the form ink is stored and printed in.
    func setInk(_ markup: PaperMarkup) {
        // Whatever was on its way in belonged to the ink this replaces.
        inkPipeline.replace(with: markup)
        inkPipeline.show()
    }

    /// Runs one of PaperKit's inserts so what it adds lands on the page the
    /// reader is looking at: see `InkInsertion.centre`.
    ///
    /// The insert tells the canvas's delegate, so it is captured, saved and
    /// undone like any other change the reader makes.
    func insertIntoInk(extent: CGSize, _ insert: () -> Void) {
        let centre = InkInsertion.centre(
            in: canvas.coveredPart,
            regions: pageLayout.inkRegions(pageCount: pageCount),
            extent: extent
        )
        canvas.inserting(around: centre, insert)
    }

    /// The tallest a photo is first shown: a share of what is on screen, and
    /// of a page's body, so it fits one page.
    var insertionMaxHeight: CGFloat {
        min(canvas.coveredPart.height, pageLayout.bodyHeight) * InkInsertion.photoWidthShare
    }

    /// Hands touches to the Select tool's overlay, or back to the canvas.
    func setSelecting(_ selecting: Bool, allowsFingers: Bool) {
        selectionOverlay.allowsFingers = allowsFingers
        selectionOverlay.isActive = selecting
    }

    /// Takes in, now and on the main thread, whatever the reader drew that is
    /// still on its way: before ink is shown again, read, printed or saved
    /// for the app leaving the screen (`PageInkPipeline.commit`).
    func commitInk() {
        inkPipeline.commit()
    }

    // MARK: PageInkHost

    func inkChanged(_ ink: PaperMarkup) {
        onInkChanged?(ink)
    }

    func inkChangedPageCount() {
        textView.reapplyContentHeightAdjustment()
        textView.setNeedsLayout()
    }

    func inkWasTakenIn(drawnEnds: [CGPoint]) {
        bands.keepPageBelowInk()
        growPageForStroke(endingAt: drawnEnds)
    }

    /// A stroke the reader just drew that ends in the last page's foot adds a
    /// page, as Add Page does (`PageBands.raiseMinimum`), so they can go on writing.
    ///
    /// Only strokes drawn now count (`InkCapture.Result.drawnEnds`): not ink
    /// that was loaded, moved by the lasso or shown again for a mode switch.
    /// It runs after the stroke has been taken in and told onward, and the
    /// page it adds is the note's minimum, not ink: nothing here calls
    /// `onInkChanged`, so growing never saves ink of its own. Seamless adds
    /// its page from `PageBands.keepPageBelowInk` as soon as ink reaches the last page.
    private func growPageForStroke(endingAt ends: [CGPoint]) {
        guard addsPagesWhileDrawing, pageLayout.mode != .seamless else { return }
        let last = pageCount
        guard ends.contains(where: { pageLayout.endsInGrowthBand(y: $0.y, pageCount: last) }) else { return }
        bands.raiseMinimum(to: last + 1)
    }

    // MARK: Zoom

    /// Zooms to `newZoom`, keeping what's under `focus` under it.
    ///
    /// - Parameter focus: a point in this view's visible area, in screen
    ///   points from its top left.
    func setZoom(_ newZoom: CGFloat, about focus: CGPoint) {
        zoomControl.setZoom(newZoom, about: focus)
    }

    // MARK: Touches

    /// Sends a touch beside the page to the text view, and sets how many
    /// fingers a scroll from there needs.
    ///
    /// Beside the page is this view's own space, and this view scrolls only
    /// sideways, so a drag there moved nothing — in either mode. Handed to
    /// the text view, it scrolls the note; the pinch, on this view, still
    /// sees it.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let found = super.hitTest(point, with: event)
        guard event?.type != .hover else { return found }
        let hit = found === self ? textView : found
        if event?.type == .touches {
            touchWillLand(on: hit)
        }
        return hit
    }

    /// Picks the scroll rule for a touch that lands on `view`.
    ///
    /// One finger scrolls wherever the canvas takes no touch, and the mode's
    /// rule applies on it. Decided as the first finger lands, before any pan
    /// has a touch: a second finger joins whatever gesture the first began.
    func touchWillLand(on view: UIView?) {
        guard pans.allSatisfy({ $0.numberOfTouches == 0 }) else { return }
        let onCanvas = (view?.isDescendant(of: canvas) ?? false) || (view?.isDescendant(of: selectionOverlay) ?? false)
        let rule = onCanvas ? scrolling : scrolling.offCanvas
        for pan in pans {
            rule.apply(to: pan)
        }
    }

    // MARK: One pan for the page (W2)

    /// The text view's pan lives on this view, so a drag anywhere on it,
    /// beside the page included, scrolls the note, and the same pan drives
    /// the sideways offset: zoomed in, one drag moves the page diagonally.
    /// This view's own pan is switched off for good; the text view still
    /// scrolls itself, so the viewport, the transform and the canvas geometry
    /// are as they were (docs/design/who-owns-scrolling.md › W2).
    private func adoptTextViewPan() {
        let pan = textView.panGestureRecognizer
        pan.view?.removeGestureRecognizer(pan)
        addGestureRecognizer(pan)
        pan.addTarget(self, action: #selector(textViewPanChanged(_:)))
        // Its own pan is off for good: scrolling disabled does that and, unlike
        // the recogniser's isEnabled, UIKit doesn't switch it back on.
        isScrollEnabled = false
        panGestureRecognizer.isEnabled = false

        scrollIndicator.install()
    }

    @objc private func textViewPanChanged(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            sidewaysFling.stop()
            lastPanTranslation = .zero
        case .changed:
            let t = pan.translation(in: self)
            let dx = t.x - lastPanTranslation.x
            lastPanTranslation = t
            scrollSideways(by: -dx)
        case .ended:
            // The text view decelerates itself; the sideways axis is ours.
            let velocity = pan.velocity(in: self).x
            sidewaysFling.start(velocity: -velocity) { [weak self] delta in
                self?.scrollSideways(by: delta) ?? false
            }
        default:
            break
        }
    }

    /// Moves the sideways offset, clamped. Returns whether it moved.
    @discardableResult
    private func scrollSideways(by delta: CGFloat) -> Bool {
        let maxX = max(contentSize.width - bounds.width, 0)
        let next = min(max(contentOffset.x + delta, 0), maxX)
        guard next != contentOffset.x else { return false }
        contentOffset.x = next
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // A scroll already under way mustn't keep the pinch from starting.
        gestureRecognizer === zoomControl.pinch && (other === panGestureRecognizer || other === textView.panGestureRecognizer)
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
    func matchRenderingScale() {
        let value = CanvasGeometry.renderingScale(
            displayScale: displayScale,
            screenScale: traitCollection.displayScale
        )
        Self.setRenderingScale(value, in: textView, skipping: canvas)
        canvas.renderScale = CanvasGeometry.inkRenderScale(displayScale: displayScale)
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

#endif
